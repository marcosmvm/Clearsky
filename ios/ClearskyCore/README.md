# ClearskyCore

This is the domain layer only — no UI. It gives the app one place to hold the triage
outcome vocabulary (`Outcome`), the canonical state-machine transitions
(`TriageAction`, `TriageStateMachine`), and the structured why-now/consequence model
(`TriageExplanation`), so no screen has to re-derive or duplicate this logic in
conditionals of its own.

The source of truth for all of it is `CLAUDE_CODE_AUDIT.md` at the repository root,
§"Triage decision and state machine" — read that section before changing anything
here. This package intentionally has no dependency on UIKit or SwiftUI so it builds
and tests on any platform; the app that will eventually consume it is SwiftUI,
iOS 17+.
