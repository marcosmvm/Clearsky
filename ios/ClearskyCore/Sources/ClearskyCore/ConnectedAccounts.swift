import Foundation

/// The account kinds Clearsky can connect, matching the prototype's `accounts`
/// state (`02 App Prototype.dc.html`: `mail`, `cal`, `msg`) and the root
/// `README.md` "State management" section, which lists "connected accounts" among
/// the state the prototype tracks alongside "protected-time flag" and
/// "inner circle" (see `ProtectedTime.swift` for the protected-time domain model).
public enum ConnectedAccountKind: String, CaseIterable, Equatable, Hashable, Sendable, Codable {
    case mail
    case calendar
    case messaging
}

/// Whether a data-driven surface (Today, Triage, Calendar) should render sample
/// data or the user's real data.
///
/// `01 Product Scope.dc.html` §15, decision 5, answers "What is the empty state for
/// a user with no inner circle and no connected accounts — a demo day, or a prompt
/// to connect?" with: "A demo day with sample data, and one tap to connect." This
/// enum is the closed, named result of that decision, so a screen asks this model
/// which experience to render instead of re-deriving the rule from raw connection
/// counts itself.
///
/// `.demoDay` is also the correct resolution for the "No connected accounts"
/// failure/recovery case in `CLAUDE_CODE_AUDIT.md` §"Manual QA script", item 10
/// ("Failure and recovery": "No connected accounts, permission denied, offline,
/// sync failure, send failure, stale notification, empty triage, and a very large
/// triage day.") — whether zero accounts is a new user who has never connected
/// anything, or a previously-connected user whose last account was disconnected or
/// revoked, `ConnectedAccountsState.presentationState` below derives the same
/// answer from the same state, so there is no separate "failure" branch to drift
/// out of sync with decision 5's empty state.
public enum DataPresentationState: Equatable, Hashable, Sendable {
    /// No connected accounts and no inner circle: render sample data plus the
    /// one-tap-connect affordance (`ConnectedAccountsAction.connectAccount`).
    case demoDay
    /// At least one connected account or at least one inner-circle person: render
    /// the user's real data.
    case live
}

/// The user's current connection state: which account kinds are connected, and how
/// many people are in their inner circle.
///
/// A plain data snapshot, not a live observer — a caller reads `presentationState`
/// off whatever snapshot it currently has (from local state, a sync result, or a
/// permission-denied/offline fallback) to decide what to render, per
/// `CLAUDE_CODE_AUDIT.md` §"Manual QA script" item 10.
public struct ConnectedAccountsState: Equatable, Hashable, Sendable, Codable {
    public let connectedAccountKinds: Set<ConnectedAccountKind>
    public let innerCircleCount: Int

    public init(connectedAccountKinds: Set<ConnectedAccountKind> = [], innerCircleCount: Int = 0) {
        self.connectedAccountKinds = connectedAccountKinds
        self.innerCircleCount = innerCircleCount
    }

    /// The state a brand-new, never-onboarded (or fully disconnected) user is in:
    /// no accounts, no inner circle.
    public static let empty = ConnectedAccountsState()

    public var hasAnyConnectedAccount: Bool { !connectedAccountKinds.isEmpty }
    public var hasInnerCircle: Bool { innerCircleCount > 0 }

    /// §15 decision 5's empty-state condition is "no inner circle *and* no
    /// connected accounts" — having either one alone is enough to leave demo day.
    /// The decision text only names the both-empty case, and a user who has
    /// connected an account but not yet added anyone to their inner circle (or the
    /// reverse) has already taken the "one tap to connect" step decision 5 asks
    /// for, so this is `.live` rather than a third, undocumented in-between state.
    public var presentationState: DataPresentationState {
        (hasAnyConnectedAccount || hasInnerCircle) ? .live : .demoDay
    }
}

/// The one-tap-connect affordance §15 decision 5 requires ("...and one tap to
/// connect"), modelled as a real, named action rather than a UI button string or
/// callback closure.
public enum ConnectedAccountsAction: Equatable, Hashable, Sendable {
    /// The user tapped the one-tap-connect affordance (shown on demo day) and
    /// connected a specific account kind.
    case connectAccount(ConnectedAccountKind)
    /// The user disconnected a previously connected account kind — the reverse
    /// transition, and how a live user can arrive back at the "No connected
    /// accounts" failure/recovery case from `CLAUDE_CODE_AUDIT.md` §"Manual QA
    /// script" item 10.
    case disconnectAccount(ConnectedAccountKind)
}

/// Applies a `ConnectedAccountsAction` to a `ConnectedAccountsState` and returns the
/// resulting state.
///
/// Pure and total: every action has a defined effect on every state, so a caller
/// never has to guess at an intermediate or undefined result. Kept separate from
/// `ConnectedAccountsState` itself the same way `TriageStateMachine` is kept
/// separate from `Outcome` — a transition is a decision about *how state changes*,
/// not part of the state's own shape.
public enum ConnectedAccountsTransition {

    /// - `.connectAccount(kind)` inserts `kind` into `connectedAccountKinds`.
    ///   Applying it to `ConnectedAccountsState.empty` is, by itself, sufficient to
    ///   move `presentationState` from `.demoDay` to `.live` — this is the concrete
    ///   transition decision 5's one-tap-connect affordance performs.
    /// - `.disconnectAccount(kind)` removes `kind` from `connectedAccountKinds`.
    ///   Applying it until no kinds remain (and with no inner circle either) moves
    ///   `presentationState` back to `.demoDay`.
    /// - `innerCircleCount` is carried through unchanged; neither action here
    ///   affects it.
    public static func apply(
        _ action: ConnectedAccountsAction,
        to state: ConnectedAccountsState
    ) -> ConnectedAccountsState {
        switch action {
        case .connectAccount(let kind):
            var kinds = state.connectedAccountKinds
            kinds.insert(kind)
            return ConnectedAccountsState(
                connectedAccountKinds: kinds,
                innerCircleCount: state.innerCircleCount
            )
        case .disconnectAccount(let kind):
            var kinds = state.connectedAccountKinds
            kinds.remove(kind)
            return ConnectedAccountsState(
                connectedAccountKinds: kinds,
                innerCircleCount: state.innerCircleCount
            )
        }
    }
}
