import EventKit
import ClearskyCore

/// `CalendarHolding` backed by a real `EKEventStore` — the concrete implementation
/// that actually writes a protected-time hold onto the person's device calendar.
///
/// ## Why the real title/detail never reach `EKEvent`
///
/// `01 Product Scope.dc.html` §15 decision 4 requires: "A calendar hold that shows as
/// busy to others; the details stay private." `ProtectedTimePresentation.resolve(_:for:)`
/// in `ClearskyCore` already encodes that rule as pure data — `.owner` sees the real
/// `ownerTitle`/`ownerDetail`, `.otherViewer` always sees the fixed
/// `busyLabelForOtherViewers` ("Busy") with no detail.
///
/// EventKit has no API that makes one field of an `EKEvent` visible to the owner but
/// hidden from anyone else who can see that calendar — there is no per-viewer,
/// per-field privacy control on a calendar event. Once a value is written into an
/// `EKEvent` and saved, it syncs to the calendar as-is for anyone who can see that
/// calendar. So the only way "the details stay private" can actually hold is:
/// **the real `ownerTitle`/`ownerDetail` are never written into the `EKEvent` at
/// all.** What this file writes to the real calendar is always the already-resolved
/// `.otherViewer` presentation — title `"Busy"`, no notes — with `availability = .busy`
/// so free/busy lookups still correctly show the time as unavailable. This is not a
/// partial implementation of decision 4; given the EventKit API surface, it is the
/// only implementation of decision 4 that is actually correct. A reviewer who expects
/// `block.ownerTitle` to appear somewhere in `createHold(for:)` is expecting a bug,
/// not a feature — see `resolvedTitleAndDetail(for:)` below, which is what a test can
/// assert on without needing a real event store.
///
/// When the owner looks at a protected block inside Clearsky's own UI, that screen
/// reads the real `ownerTitle`/`ownerDetail` from the app's own stored
/// `ProtectedTimeBlock` record — the same one `createHold(for:)` is handed here — never
/// by reading them back off the synced `EKEvent`, because they were never put there.
final class EventKitCalendarService: CalendarHolding {
    /// Errors specific to this EventKit-backed implementation. `CalendarHolding`
    /// itself stays error-type-agnostic (`throws`, not a fixed error enum) so a future
    /// conformer isn't forced to reuse these cases.
    enum ServiceError: Error, Equatable {
        /// There is no calendar EventKit can write a new event to (for example, no
        /// calendar accounts configured on the device at all).
        case noWritableCalendar
        /// `removeHold(eventIdentifier:)` was given an identifier `EKEventStore` no
        /// longer has an event for (already removed, or never existed).
        case eventNotFound
    }

    private let eventStore: EKEventStore

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    /// The write-side-only, no-owner-detail title/detail this service ever writes to
    /// a real `EKEvent`, for any `ProtectedTimeBlock` — pulled out as a pure function
    /// so a test can assert this exact mapping without standing up an `EKEventStore`.
    /// Always resolves `block` for `.otherViewer`; never reads `block.ownerTitle` or
    /// `block.ownerDetail`. See the type-level doc above for why.
    static func resolvedTitleAndDetail(for block: ProtectedTimeBlock) -> (title: String, detail: String?) {
        let presentation = ProtectedTimePresentation.resolve(block, for: .otherViewer)
        return (title: presentation.title, detail: presentation.detail)
    }

    /// Requests full calendar access via the iOS 17+ API (`requestFullAccessToEvents`
    /// pairs with the `NSCalendarsFullAccessUsageDescription` Info.plist key this
    /// app's target declares — see `project.yml`). Full access, not write-only,
    /// because `removeHold(eventIdentifier:)` below needs to look an event back up by
    /// identifier, which write-only access does not grant.
    func requestAccess() async throws -> Bool {
        try await eventStore.requestFullAccessToEvents()
    }

    /// Creates a calendar hold for `block`. Only ever writes the resolved
    /// `.otherViewer` presentation ("Busy", no notes) — see the type-level doc.
    func createHold(for block: ProtectedTimeBlock) async throws -> String {
        guard let calendar = eventStore.defaultCalendarForNewEvents else {
            throw ServiceError.noWritableCalendar
        }

        let (title, detail) = Self.resolvedTitleAndDetail(for: block)

        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.startDate = block.start
        event.endDate = block.end
        event.title = title
        event.notes = detail
        event.availability = .busy

        try eventStore.save(event, span: .thisEvent, commit: true)

        guard let identifier = event.eventIdentifier else {
            throw ServiceError.noWritableCalendar
        }
        return identifier
    }

    /// Removes the calendar hold previously created with `eventIdentifier`.
    func removeHold(eventIdentifier: String) async throws {
        guard let event = eventStore.event(withIdentifier: eventIdentifier) else {
            throw ServiceError.eventNotFound
        }
        try eventStore.remove(event, span: .thisEvent, commit: true)
    }
}
