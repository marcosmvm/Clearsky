import SwiftUI
import ClearskyCore

/// App-layer *presentation* mappings for `ClearskyCore` types — display strings,
/// icons and colours. Deliberately kept out of `ClearskyCore` itself: the domain
/// package has no UIKit/SwiftUI dependency by design (see `ios/ClearskyCore/README.md`),
/// and this task must not add files under `ios/ClearskyCore/Sources`. Everything below
/// only *reads* the closed enums ClearskyCore already exports; it adds no new states.

extension Outcome {
    /// The exact word the product uses for this state everywhere — brief copy,
    /// analytics, the Triage completion tally. Source: `CLAUDE_CODE_AUDIT.md`
    /// §"Triage decision and state machine" / root README "Interactions and behaviour".
    var displayName: String {
        switch self {
        case .needsAttention: return "Needs attention"
        case .responded: return "Responded"
        case .planned: return "Planned"
        case .snoozed: return "Snoozed"
        case .waitingOnThem: return "Waiting on them"
        case .needsANewPlan: return "Needs a new plan"
        case .kept: return "Kept"
        case .released: return "Released"
        }
    }

    /// Status colour, honouring the audit's explicit rule: "define an explicit
    /// status-to-presentation map so 'Needs a new plan' cannot inherit red/error
    /// treatment" (`CLAUDE_CODE_AUDIT.md` §"Promise ownership"). Terracotta is
    /// reserved and unused by this map on purpose — nothing here is styled as an error.
    var statusColor: Color {
        switch self {
        case .needsAttention: return ClearskyColor.secondaryInk
        case .responded: return ClearskyColor.skyStart
        case .planned: return ClearskyColor.skyStart
        case .snoozed: return ClearskyColor.muted
        case .waitingOnThem: return ClearskyColor.muted
        case .needsANewPlan: return ClearskyColor.amberLabelInk
        case .kept: return ClearskyColor.keptGreen
        case .released: return ClearskyColor.muted
        }
    }
}

extension TriageExplanation.Signal {
    /// Short chip copy for the WHY NOW signal row, e.g. "Inner circle" · "Direct
    /// question". Wording follows the example in `TriageExplanation.whyNow`'s doc
    /// comment: "Inner circle · asked you a direct question · waiting 3 days".
    var chipLabel: String {
        switch self {
        case .innerCircle: return "Inner circle"
        case .directQuestion: return "Direct question"
        case .promiseDue: return "Promise due"
        case .waitingDuration: return "Waiting a while"
        case .recentChange: return "Recently changed"
        case .snoozeReturn: return "Snooze returned"
        }
    }
}

extension TriageExplanation.RecommendedAction {
    /// Button copy for this action, written from the card's point of view — matches
    /// the vocabulary table in `TriagePresentation.triageAction(for:from:)`.
    var actionLabel: String {
        switch self {
        case .respond: return "Respond"
        case .plan: return "Confirm a plan"
        case .snooze: return "Snooze"
        case .wait: return "Mark waiting on them"
        case .letGo: return "Let it go"
        }
    }

    var symbolName: String {
        switch self {
        case .respond: return "arrowshape.turn.up.left.fill"
        case .plan: return "calendar.badge.checkmark"
        case .snooze: return "clock.arrow.circlepath"
        case .wait: return "hourglass"
        case .letGo: return "hand.raised.slash"
        }
    }
}
