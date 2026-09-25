import SwiftUI
import ClearskyCore

/// The app shell: three tabs — Today, Promises, Triage — sharing one injected
/// `PromiseStore`, `SharedDraftStoreObserver` and `CalendarHolding`.
///
/// Everything is passed in through `init` rather than reached via a global singleton
/// (`ClearskyApp.swift` owns the real, on-disk/App-Group/EventKit-backed instances),
/// so a preview or a test can substitute fakes — see `MockCalendarService` and the
/// disposable-file/disposable-`UserDefaults`-suite pattern `PromisesView.swift` and
/// the test targets already use.
///
/// Triage is unchanged from the original app shell and still renders
/// `SampleData.triageItems` — out of scope for this task ("Do not build Triage in
/// this round"). Today and Promises both read real data through `promiseStore` and
/// `draftsObserver` (a `SharedDraftStoreObserver`, not a raw `SharedDraftStore` — see
/// that type's doc comment for why a plain `.loadAll()` call here was the actual bug
/// this task fixes: it never observed the underlying `UserDefaults`, so a draft the
/// Share Extension appended while this app was already open didn't reliably show up
/// until something unrelated forced a re-render).
struct RootView: View {
    @ObservedObject var promiseStore: PromiseStore
    @ObservedObject var draftsObserver: SharedDraftStoreObserver
    let calendarService: CalendarHolding

    @State private var selectedTab: Tab = .today
    @State private var isPresentingNewPromise = false
    @State private var isPresentingPendingDrafts = false

    private enum Tab: Hashable {
        case today, promises, triage
    }

    init(promiseStore: PromiseStore, draftsObserver: SharedDraftStoreObserver, calendarService: CalendarHolding) {
        self.promiseStore = promiseStore
        self.draftsObserver = draftsObserver
        self.calendarService = calendarService
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                TodayView(
                    items: SampleData.triageItems,
                    promiseStore: promiseStore,
                    draftsObserver: draftsObserver,
                    onSaveNewPromise: handleSavedPromise,
                    onGoToPromises: { selectedTab = .promises }
                )
                .toolbar { toolbarContent }
            }
            .tabItem { Label("Today", systemImage: "sun.max") }
            .tag(Tab.today)

            NavigationStack {
                PromisesView(store: promiseStore, calendarService: calendarService)
                    .toolbar { toolbarContent }
            }
            .tabItem { Label("Promises", systemImage: "checklist") }
            .tag(Tab.promises)

            TriageView(items: SampleData.triageItems)
                .tabItem { Label("Triage", systemImage: "tray.full") }
                .tag(Tab.triage)
        }
        .tint(ClearskyColor.inkNavy)
        .sheet(isPresented: $isPresentingNewPromise) {
            NewPromiseView(draft: nil, onSave: handleSavedPromise)
        }
        .sheet(isPresented: $isPresentingPendingDrafts) {
            PendingDraftsView(draftsObserver: draftsObserver, onSaveNewPromise: handleSavedPromise)
        }
        .task {
            // Moves any `.planned` promise whose due date has already passed to
            // `.needsANewPlan` once, before Today/Promises render, so a stale due
            // date never reads as still-on-track.
            promiseStore.refreshOverdueStates()
        }
    }

    // MARK: - Toolbar

    /// Shared by both the Today and Promises tabs: a captured-drafts entry point
    /// (badged with the pending count, read live off `draftsObserver` — this is what
    /// makes the Share Extension's captured drafts actually reachable by a person; see
    /// `PendingDraftsView`) and the "+" that opens a hand-entered `NewPromiseView`
    /// (anticipated by that view's own doc comment: "a hand-entered promise started
    /// from the Promises list's '+' button").
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                isPresentingPendingDrafts = true
            } label: {
                Image(systemName: "tray.and.arrow.down")
            }
            .overlay(alignment: .topTrailing) {
                if pendingDraftsCount > 0 {
                    Text("\(pendingDraftsCount)")
                        .font(ClearskyFont.ui(10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Circle().fill(ClearskyColor.urgentTerracotta))
                        .offset(x: 10, y: -8)
                }
            }
            .accessibilityLabel("Captured, \(pendingDraftsCount) waiting")
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                isPresentingNewPromise = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("New promise")
        }
    }

    private var pendingDraftsCount: Int {
        draftsObserver.count
    }

    // MARK: - Saving a promise (shared by the "+" button and a resolved pending draft)

    /// The one place `NewPromiseView`'s `onSave` is wired — used both from the "+"
    /// button (a hand-entered promise, `draft: nil`) and from resolving a pending
    /// `CapturedPromiseDraft` (in `PendingDraftsView` and Today's real primary card),
    /// so the save-then-protect logic exists exactly once.
    ///
    /// Saves the promise, then — only if `protectedTime` is on — asks for calendar
    /// access and creates a hold, storing the resulting event identifier back onto
    /// the saved promise via `PromiseStore.update(_:)`.
    private func handleSavedPromise(_ promise: Promise) {
        promiseStore.add(promise)
        guard promise.protectedTime else { return }
        Task {
            await createCalendarHold(for: promise)
        }
    }

    /// Creates a protected-time calendar hold for a just-saved promise.
    ///
    /// Hold duration: a fixed 30 minutes starting at `promise.dueDate`. Nothing in
    /// `01 Product Scope.dc.html` pins an exact duration for a protected-time hold —
    /// the New promise screen's "protect this time" toggle only promises "nothing
    /// else can be booked over it" — so 30 minutes is this task's documented default:
    /// long enough to genuinely claim a calendar slot around the due date, short
    /// enough not to silently block out the rest of someone's day for what may be a
    /// quick call or errand. A future screen that lets a person pick their own
    /// duration can override this; nothing else in the app assumes 30 minutes.
    private func createCalendarHold(for promise: Promise) async {
        do {
            guard try await calendarService.requestAccess() else { return }
            let block = ProtectedTimeBlock(
                id: promise.id,
                start: promise.dueDate,
                end: promise.dueDate.addingTimeInterval(30 * 60),
                ownerTitle: promise.whatWasPromised,
                ownerDetail: "With \(promise.personName)"
            )
            let identifier = try await calendarService.createHold(for: block)
            var updated = promise
            updated.calendarEventIdentifier = identifier
            promiseStore.update(updated)
        } catch {
            // Access denied, no writable calendar, or the write itself failed. The
            // promise is already saved either way — the hold is simply skipped
            // rather than surfaced as a blocking error on save.
        }
    }
}

// MARK: - Previews

/// A no-op `CalendarHolding` for previews only — never grants access, so a preview
/// run never attempts a real EventKit call.
private struct PreviewCalendarService: CalendarHolding {
    func requestAccess() async throws -> Bool { false }
    func createHold(for block: ProtectedTimeBlock) async throws -> String { "preview-event" }
    func removeHold(eventIdentifier: String) async throws {}
}

/// Builds a disposable, file-backed `PromiseStore` and a `SharedDraftStoreObserver`
/// over a disposable `UserDefaults` suite — same isolation pattern
/// `PromisesView.swift`'s `makePreviewStore()` uses — so this preview never touches a
/// real device's Documents directory or App Group container.
@MainActor
private func makeRootPreviewDependencies() -> (PromiseStore, SharedDraftStoreObserver) {
    let promiseStoreURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("root-view-preview-\(UUID().uuidString)")
        .appendingPathExtension("json")
    let draftsSuiteName = "root-view-preview-\(UUID().uuidString)"
    let draftsDefaults = UserDefaults(suiteName: draftsSuiteName)!
    return (
        PromiseStore(fileURL: promiseStoreURL),
        SharedDraftStoreObserver(store: SharedDraftStore(defaults: draftsDefaults), defaults: draftsDefaults)
    )
}

#Preview {
    let (promiseStore, draftsObserver) = makeRootPreviewDependencies()
    return RootView(
        promiseStore: promiseStore,
        draftsObserver: draftsObserver,
        calendarService: PreviewCalendarService()
    )
}
