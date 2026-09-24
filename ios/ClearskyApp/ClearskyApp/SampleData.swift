import Foundation
import ClearskyCore

/// One person/thread wrapper around a `TriagePresentation`.
///
/// `ClearskyCore` intentionally has no Person/Message/Thread model yet — it is a
/// domain layer for the triage state machine and explanation/resolution logic only
/// (see `ios/ClearskyCore/README.md`). Today and Triage still need *something* to
/// identify who an item is about and what the source message said, so `TriageItem` is
/// the small app-layer wrapper for that: a name, a preview and the real
/// `TriagePresentation` the card renders from. This is not a domain type and is not a
/// substitute for one — if/when ClearskyCore grows a real Person/Thread model, this
/// type should be replaced, not extended.
struct TriageItem: Identifiable {
    let id = UUID()
    let personName: String
    let initials: String
    let isInnerCircle: Bool
    let messagePreview: String
    let presentation: TriagePresentation
}

/// Sample data driving Today and Triage in this app shell. There is no backend yet, so
/// these are hand-built `TriageExplanation` values — but every field the screens read
/// (`whyNow`, `ifNoAction`, `recommended`, `alternatives`) is produced by running that
/// explanation through `TriagePresentation.build(state:explanation:)`, the same real
/// resolver a live data source would call. No screen reads a hardcoded action label or
/// outcome name outside of what `TriagePresentation` resolved.
enum SampleData {
    static let triageItems: [TriageItem] = [
        TriageItem(
            personName: "Maya Chen",
            initials: "MC",
            isInnerCircle: true,
            messagePreview: "\u{201C}Are you still free for dinner on the 12th, or should I just book for two of us and hope?\u{201D}",
            presentation: TriagePresentation.build(
                state: .needsAttention,
                explanation: TriageExplanation(
                    whyNow: "Inner circle \u{B7} asked you a direct question",
                    signals: [.innerCircle, .directQuestion],
                    ifNoAction: "She reads the silence as a no and books the table for one by tonight.",
                    recommendedAction: .respond,
                    alternativeActions: [.plan, .snooze]
                )
            )
        ),
        TriageItem(
            personName: "James Okafor",
            initials: "JO",
            isInnerCircle: false,
            messagePreview: "\u{201C}Hey \u{2014} following up on the intro doc from last week, any read on it?\u{201D}",
            presentation: TriagePresentation.build(
                state: .needsAttention,
                explanation: TriageExplanation(
                    whyNow: "Waiting on you for 3 days",
                    signals: [.waitingDuration],
                    ifNoAction: "The thread goes quiet and drops off Today by the weekend.",
                    recommendedAction: .respond,
                    alternativeActions: [.wait, .letGo]
                )
            )
        ),
        TriageItem(
            personName: "Priya Patel",
            initials: "PP",
            isInnerCircle: true,
            messagePreview: "\u{201C}Let's lock in Saturday for the hike \u{2014} what time works?\u{201D}",
            presentation: TriagePresentation.build(
                state: .needsAttention,
                explanation: TriageExplanation(
                    whyNow: "Inner circle \u{B7} a plan is due to be confirmed",
                    signals: [.innerCircle, .promiseDue],
                    ifNoAction: "Saturday arrives with no time set and the hike quietly doesn't happen.",
                    recommendedAction: .plan,
                    alternativeActions: [.snooze, .letGo]
                )
            )
        ),
        TriageItem(
            personName: "Diego Ruiz",
            initials: "DR",
            isInnerCircle: false,
            messagePreview: "\u{201C}Sent you the venue options — sent my reply, just need your pick.\u{201D}",
            presentation: TriagePresentation.build(
                state: .responded,
                explanation: TriageExplanation(
                    whyNow: "You already replied \u{B7} the next move is his",
                    signals: [.recentChange],
                    ifNoAction: "Nothing breaks if you wait — this just sits until he answers.",
                    recommendedAction: .wait,
                    alternativeActions: []
                )
            )
        )
    ]
}
