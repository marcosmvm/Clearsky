import SwiftUI
import ClearskyCore

/// The three fixed due-date choices `01 Product Scope.dc.html` §6 Screen inventory
/// calls for on "New promise" ("three time presets plus a picker"), each resolved to
/// a concrete `Date` at the moment it is tapped — not a static value captured once
/// when the screen loads — so a promise saved late at night still lands on a sensible
/// time. The spec names only the labels, not the times; the concrete choices made
/// here, documented since nothing pins them elsewhere:
/// - `.today` -> today at 6:00 PM. An evening check-in time that is still
///   unambiguously "today" no matter what time of day the promise is saved.
/// - `.tomorrow` -> tomorrow at 9:00 AM. The start of the next working day.
/// - `.thisWeek` -> the coming Friday at 5:00 PM, end of the current work week. If
///   today is already Friday, this rolls to *next* Friday — `.thisWeek` always means
///   a date strictly after today, never today itself (that's what `.today` is for).
enum DatePreset: String, CaseIterable, Identifiable, Equatable {
    case today
    case tomorrow
    case thisWeek

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: return "Today"
        case .tomorrow: return "Tomorrow"
        case .thisWeek: return "This week"
        }
    }

    /// Resolves this preset to a concrete `Date`, relative to `now`. `calendar` and
    /// `now` are parameters (not hardcoded to `.current`/`Date()`) purely so this is
    /// unit-testable; every call site in `NewPromiseView` uses the defaults.
    func date(from now: Date = Date(), calendar: Calendar = .current) -> Date {
        switch self {
        case .today:
            return calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now) ?? now
        case .tomorrow:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        case .thisWeek:
            // Gregorian weekday numbering is fixed regardless of locale: 1 = Sunday
            // ... 6 = Friday. `nextDate(after:matching:)` finds the next Friday
            // strictly after `now`, so a promise saved on Friday itself rolls to next
            // Friday rather than "presetting" a date already in the past relative to
            // that evening's cutoff.
            var components = DateComponents()
            components.weekday = 6
            let friday = calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime) ?? now
            return calendar.date(bySettingHour: 17, minute: 0, second: 0, of: friday) ?? friday
        }
    }
}

/// The "New promise" screen: capture a commitment by hand.
///
/// Per `01 Product Scope.dc.html` §6 Screen inventory, "New promise" — Purpose:
/// "Capture a commitment by hand". Key states/actions: "What was said, three time
/// presets plus a picker, protect-the-time toggle." This view renders exactly those
/// inputs (who it's for, what was said, a due date via preset or custom picker, and
/// the protect-the-time toggle) plus a Save action.
///
/// Two entry points, one screen: opened with a `CapturedPromiseDraft` (text captured
/// via the iOS Share Sheet, see `CapturedPromiseDraft.swift`) this prefills
/// `whatWasPromised` from `draft.sharedText` and carries that same text through as the
/// saved promise's `sourceText`; opened with `nil` this is a purely hand-entered
/// promise and `sourceText` stays `nil`, per `Promise.swift`'s doc comment on that
/// field.
///
/// This view never talks to `PromiseStore` directly. `onSave` is injected at init so
/// the caller decides where a saved promise goes — a later integration task wires
/// that caller up to a real store and to navigation; this task only needs the view to
/// compile and be previewable/testable standalone (see the `#Preview`s below).
struct NewPromiseView: View {
    private let draft: CapturedPromiseDraft?
    private let onSave: (Promise) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var personName: String = ""
    @State private var whatWasPromised: String
    @State private var dueDate: Date
    @State private var protectedTime: Bool = false
    @State private var selectedPreset: DatePreset?

    /// - Parameters:
    ///   - draft: The Share Sheet capture this screen was opened from, if any. `nil`
    ///     for a hand-entered promise started from the Promises list's "+" button.
    ///   - onSave: Called once with the newly-built `Promise` when Save is tapped.
    ///     The caller decides where it goes (typically `PromiseStore.add(_:)`).
    init(draft: CapturedPromiseDraft?, onSave: @escaping (Promise) -> Void) {
        self.draft = draft
        self.onSave = onSave
        _whatWasPromised = State(initialValue: draft?.sharedText ?? "")
        // A New promise always has a date at creation (§6: "three time presets plus
        // a picker" — never an empty/optional date), so a preset is pre-selected
        // rather than leaving `dueDate` at an arbitrary "now".
        _dueDate = State(initialValue: DatePreset.today.date())
        _selectedPreset = State(initialValue: .today)
    }

    private var isSaveEnabled: Bool {
        !personName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !whatWasPromised.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ClearskySpacing.xl) {
                Text("New promise")
                    .font(ClearskyFont.display(28))
                    .foregroundStyle(ClearskyColor.inkNavy)
                    .displayHeadlineStyle()
                    .padding(.top, ClearskySpacing.m)

                fieldSection(label: "WHO IT'S FOR") {
                    TextField("Name", text: $personName)
                        .font(ClearskyFont.ui(16))
                        .foregroundStyle(ClearskyColor.inkNavy)
                        .padding(.horizontal, ClearskySpacing.m)
                        .frame(minHeight: ClearskyMetric.minHitTarget)
                        .background(fieldBackground)
                }

                fieldSection(label: "WHAT WAS SAID") {
                    VStack(alignment: .leading, spacing: ClearskySpacing.xxs) {
                        TextEditor(text: $whatWasPromised)
                            .font(ClearskyFont.editorial(16))
                            .foregroundStyle(ClearskyColor.body)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 96)
                            .padding(ClearskySpacing.s)
                            .background(fieldBackground)

                        if draft != nil {
                            Text("Carried over from what was shared")
                                .font(ClearskyFont.ui(12, weight: .medium))
                                .foregroundStyle(ClearskyColor.muted)
                        }
                    }
                }

                fieldSection(label: "WHEN") {
                    VStack(alignment: .leading, spacing: ClearskySpacing.sm) {
                        presetRow

                        DatePicker(
                            "Custom date",
                            selection: $dueDate,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .font(ClearskyFont.ui(15))
                        .foregroundStyle(ClearskyColor.inkNavy)
                        .tint(ClearskyColor.inkNavy)
                        .onChange(of: dueDate) { _, _ in selectedPreset = nil }
                        .padding(.horizontal, ClearskySpacing.m)
                        .frame(minHeight: ClearskyMetric.minHitTarget)
                        .background(fieldBackground)
                    }
                }

                protectToggle

                saveButton
            }
            .padding(.horizontal, ClearskySpacing.l)
            .padding(.bottom, ClearskySpacing.xl)
        }
        .background(ClearskyColor.surfaceTertiary.ignoresSafeArea())
    }

    private var presetRow: some View {
        HStack(spacing: ClearskySpacing.xs) {
            ForEach(DatePreset.allCases) { preset in
                let isSelected = selectedPreset == preset

                Button {
                    selectedPreset = preset
                    dueDate = preset.date()
                } label: {
                    Text(preset.label)
                        .font(ClearskyFont.ui(13, weight: .medium))
                        .foregroundStyle(isSelected ? ClearskyColor.amberInk : ClearskyColor.secondaryInk)
                        .padding(.horizontal, ClearskySpacing.m)
                        .frame(minHeight: ClearskyMetric.minHitTarget)
                        .background(
                            Group {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: ClearskyRadius.sm, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [ClearskyColor.amberGradientStart, ClearskyColor.amberGradientEnd],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                } else {
                                    RoundedRectangle(cornerRadius: ClearskyRadius.sm, style: .continuous)
                                        .fill(ClearskyColor.surfaceSecondary)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: ClearskyRadius.sm, style: .continuous)
                                                .stroke(ClearskyColor.hairlineStrong, lineWidth: 1)
                                        )
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private var protectToggle: some View {
        Toggle(isOn: $protectedTime) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Protect this time")
                    .font(ClearskyFont.ui(15, weight: .semibold))
                    .foregroundStyle(ClearskyColor.inkNavy)
                Text("Nothing else can be booked over it")
                    .font(ClearskyFont.ui(12))
                    .foregroundStyle(ClearskyColor.muted)
            }
        }
        .tint(ClearskyColor.inkNavy)
        .padding(ClearskySpacing.m)
        .background(
            RoundedRectangle(cornerRadius: ClearskyRadius.md, style: .continuous)
                .fill(ClearskyColor.surfacePrimary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ClearskyRadius.md, style: .continuous)
                .stroke(ClearskyColor.hairline, lineWidth: 1)
        )
    }

    private var saveButton: some View {
        Button {
            save()
        } label: {
            Text("Save")
                .font(ClearskyFont.ui(16, weight: .semibold))
                .foregroundStyle(ClearskyColor.amberInk)
                .frame(maxWidth: .infinity)
                .frame(minHeight: ClearskyMetric.minHitTarget)
                .background(
                    LinearGradient(
                        colors: [ClearskyColor.amberGradientStart, ClearskyColor.amberGradientEnd],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: ClearskyRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isSaveEnabled)
        .opacity(isSaveEnabled ? 1 : 0.5)
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: ClearskyRadius.sm, style: .continuous)
            .fill(ClearskyColor.surfacePrimary)
            .overlay(
                RoundedRectangle(cornerRadius: ClearskyRadius.sm, style: .continuous)
                    .stroke(ClearskyColor.hairlineStrong, lineWidth: 1)
            )
    }

    @ViewBuilder
    private func fieldSection<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: ClearskySpacing.xs) {
            Text(label)
                .font(ClearskyFont.ui(11, weight: .semibold))
                .tracking(0.08 * 11)
                .foregroundStyle(ClearskyColor.muted)
            content()
        }
    }

    private func save() {
        let promise = Promise(
            id: UUID().uuidString,
            personName: personName.trimmingCharacters(in: .whitespacesAndNewlines),
            whatWasPromised: whatWasPromised.trimmingCharacters(in: .whitespacesAndNewlines),
            dueDate: dueDate,
            sourceText: draft?.sharedText,
            protectedTime: protectedTime,
            state: .planned
        )
        onSave(promise)
        dismiss()
    }
}

#Preview("Hand-entered") {
    NewPromiseView(draft: nil) { promise in
        print("Saved: \(promise)")
    }
}

#Preview("From a share") {
    NewPromiseView(
        draft: CapturedPromiseDraft(
            id: "draft-preview",
            sharedText: "Can you send the invoice by Friday?",
            capturedAt: Date(),
            source: .text
        )
    ) { promise in
        print("Saved: \(promise)")
    }
}
