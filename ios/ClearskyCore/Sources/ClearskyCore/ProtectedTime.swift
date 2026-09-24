import Foundation

/// The closed set of calendar representations a calendar surface must be able to
/// distinguish.
///
/// Mirrors `CLAUDE_CODE_AUDIT.md` §"Promise ownership", which requires: "Calendar
/// representations distinguish promises, external events, and protected blocks."
/// This is the minimal closed vocabulary that makes that distinction real in code —
/// nothing outside this file infers what "kind" a calendar item is by inspecting its
/// title, colour or source ad hoc, and no fourth kind can be added without a change
/// here.
///
/// This file does not touch `TriageStateMachine`, `TriageAction` or `Outcome`: a
/// protected block and an external event are not triage items and never enter that
/// state machine. Full promise-list domain modelling (grouping, ownership, exits)
/// already lives in `PromiseOwnership.swift`; `.promise` here only identifies the
/// calendar-representation kind a kept/planned promise's calendar result reports as,
/// so a calendar screen can tell it apart from a protected block or an event
/// Clearsky did not create.
public enum CalendarItemKind: String, CaseIterable, Equatable, Hashable, Sendable, Codable {
    /// The calendar result linked to a promise (for example the entry a "Planned"
    /// outcome creates). Represents a commitment to another person.
    case promise
    /// An event that originated outside Clearsky on a connected calendar account —
    /// Clearsky did not create it and does not own or alter its details.
    case externalEvent
    /// A protected-time hold Clearsky created at the user's own request. See
    /// `ProtectedTimeBlock` below.
    case protectedBlock
}

/// Who is looking at a protected-time block on the calendar.
///
/// `01 Product Scope.dc.html` §15, decision 4, answers "Does protected time write a
/// real calendar event that others can see as busy, or a private hold?" with: "A
/// calendar hold that shows as busy to others; the details stay private." That
/// answer only makes sense as a function of *who is looking* — the owner still needs
/// to see their own real details — so "viewer" is a first-class, closed type here
/// rather than an inferred boolean sprinkled through view code.
public enum ProtectedTimeViewer: Equatable, Hashable, Sendable {
    /// The person who created the protected-time block.
    case owner
    /// Anyone else who can see the owner's calendar (a shared calendar, a
    /// free/busy lookup, an invite that overlaps the block, etc.).
    case otherViewer
}

/// A calendar hold the user created to keep a span of time free, per
/// `01 Product Scope.dc.html` §15, decision 4.
///
/// This is data, not a UI concern: `ProtectedTimePresentation.resolve(_:for:)` is
/// the single place that decides what a given viewer may see, so a screen never has
/// to re-derive the busy-to-others/private-details rule for itself. Modelled as its
/// own type — separate from a promise or an external event, and reporting its own
/// distinct `CalendarItemKind` — because a protected block represents time the user
/// is withholding, not a commitment to anyone or an event Clearsky did not create.
public struct ProtectedTimeBlock: Equatable, Hashable, Sendable, Codable {
    public let id: String
    public let start: Date
    public let end: Date
    /// The real title only the owner sees, e.g. "Protected evening" or a more
    /// specific label the user typed themselves.
    public let ownerTitle: String
    /// The real detail/note only the owner sees, e.g. "Nothing can land here".
    public let ownerDetail: String

    public init(id: String, start: Date, end: Date, ownerTitle: String, ownerDetail: String) {
        self.id = id
        self.start = start
        self.end = end
        self.ownerTitle = ownerTitle
        self.ownerDetail = ownerDetail
    }

    /// The `CalendarItemKind` a protected block always reports as. Always
    /// `.protectedBlock` — never `.promise` or `.externalEvent` — which is what
    /// makes it distinguishable from those two per `CLAUDE_CODE_AUDIT.md`
    /// §"Promise ownership".
    public var kind: CalendarItemKind { .protectedBlock }
}

/// What a calendar surface renders for a `ProtectedTimeBlock`, resolved per viewer.
///
/// Directly encodes `01 Product Scope.dc.html` §15 decision 4: to `.otherViewer` the
/// block "shows as busy" — `title` is always the fixed, generic
/// `busyLabelForOtherViewers` and `detail` is always `nil`, never the block's real
/// `ownerTitle`/`ownerDetail` — while `.owner` always sees the real values ("the
/// details stay private" only describes what *other* viewers see). Building this as
/// a pure resolver over data, rather than a view-layer `if isOwner` branch, is what
/// keeps a real title or note from ever leaking into an "other viewer" render by
/// accident.
public struct ProtectedTimePresentation: Equatable, Sendable {
    public let title: String
    public let detail: String?
    /// Whether this presentation reveals the block's real owner-authored
    /// title/detail. `true` only for `.owner`.
    public let revealsOwnerDetails: Bool

    public init(title: String, detail: String?, revealsOwnerDetails: Bool) {
        self.title = title
        self.detail = detail
        self.revealsOwnerDetails = revealsOwnerDetails
    }

    /// The fixed label decision 4's "shows as busy to others" resolves to for
    /// `.otherViewer`. Not a quote from the source docs (decision 4 does not pin an
    /// exact string) — a single named constant here, rather than a literal repeated
    /// at each call site, is what keeps every "other viewer" render using the same
    /// word.
    public static let busyLabelForOtherViewers = "Busy"

    /// Resolves what `viewer` may see of `block`.
    ///
    /// - `.owner` → the real `ownerTitle`/`ownerDetail`, `revealsOwnerDetails: true`.
    /// - `.otherViewer` → `busyLabelForOtherViewers`, `detail: nil`,
    ///   `revealsOwnerDetails: false`. This branch never reads `block.ownerDetail`
    ///   and never reads `block.ownerTitle` beyond confirming it is a
    ///   `ProtectedTimeBlock` at all — there is no code path here that could forward
    ///   the real value.
    public static func resolve(
        _ block: ProtectedTimeBlock,
        for viewer: ProtectedTimeViewer
    ) -> ProtectedTimePresentation {
        switch viewer {
        case .owner:
            return ProtectedTimePresentation(
                title: block.ownerTitle,
                detail: block.ownerDetail,
                revealsOwnerDetails: true
            )
        case .otherViewer:
            return ProtectedTimePresentation(
                title: busyLabelForOtherViewers,
                detail: nil,
                revealsOwnerDetails: false
            )
        }
    }
}
