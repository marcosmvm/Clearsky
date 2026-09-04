# Using Claude Code on the Clearsky codebase

Use Claude Code as a **repository auditor first, then a constrained implementation partner**. Ask it
to prove what the code currently does against the Clearsky product model, produce a prioritized
discrepancy list with file-level evidence, and only then make narrowly scoped changes you approve.

The most important review target is whether the implementation actually reflects the corrected
interaction model: explained prioritization, one decision per card, five named outcomes,
ownership-based promises, one triage surface, and the marketing-only character / app-plate visual rule.

---

## 1. Baseline audit prompt

Paste this at the repository root before asking it to edit anything.

```text
You are reviewing the Clearsky codebase against the attached product requirements.

Do not modify files yet.

First:
1. Inspect the repository structure, package scripts, routes, components, state/data model, assets, design tokens, and tests.
2. Identify the current stack and how to run typecheck, lint, tests, build, and any visual/storybook checks.
3. Compare the implementation against the product rules below.
4. Return an audit in a Markdown table with:
   - Requirement
   - Current implementation evidence
   - Exact files and relevant symbols/lines
   - Status: implemented / partial / missing / contradictory / cannot verify
   - User impact
   - Recommended smallest safe change
   - Priority: P0, P1, P2, or P3
5. Do not infer implementation from filenames or comments alone. Trace the actual rendered path and state transitions where possible.
6. Do not make changes until I approve a scoped implementation plan.

Canonical Clearsky rules to verify:
- The product is single-player and never sends messages on the user's behalf.
- There is one primary triage surface for the prototype; avoid duplicate Sky/Queue navigation.
- Every Today and Triage item has a WHY NOW explanation.
- Every Today and Triage item has an IF YOU DO NOTHING / IF NOT consequence.
- Each triage card presents one recommended action selected from item context, with quieter alternatives.
- Every action maps to exactly one named outcome:
  Responded, Planned, Snoozed, Waiting on them, or Let go.
- Snoozed must include a known return date or time.
- Waiting on them must not appear as an incomplete task or tickable obligation.
- Promises are grouped by ownership/kind:
  Yours to keep: "I'll reach out" and "We made plans"
  Not your move: "Waiting on them"
  Also support Kept and Released.
- Do not use "overdue"; use "Needs a new plan."
- Promise detail must provide three honest exits:
  keep it, give it a new time, or let it go.
- One nudge per day is a hard product constraint, plus a reminder only when a dated promise is due.
- No badges, streaks, guilt mechanics, or emoji.
- The Clearsky character/daydreamer is marketing-only and must never appear in the app.
- The app may use six painted sky plates as splash backgrounds beneath CSS patterns.
- Weekly Recap uses the golden-hour sky plate beneath the light-column pattern.
- All outbound message sending must require explicit user action and clear confirmation of the message content.

End with:
A. A ranked top-10 discrepancy list
B. A list of unknowns that require product decisions rather than code changes
C. The smallest recommended implementation batch
D. The commands I should run to validate the current baseline before edits
```

This forces Claude Code to separate facts it can demonstrate from assumptions it cannot, and keeps
it from "fixing" product decisions — reintroducing a separate Queue tab, moving the paywall —
because it believes those are conventional. The one-surface triage model and the state vocabulary
are deliberate.

---

## 2. Focused reviews

Run each as its own prompt, after the baseline. Smaller reviews produce more actionable findings.

### Navigation and flow

```text
Trace every user route into and out of Today, Triage, Thread, Plan, Promises, Promise Detail, Calendar, Weekly Recap, and Paywall.

For each route, answer:
1. What user intent begins the flow?
2. What state/context is passed forward?
3. What action changes state?
4. What screen appears next?
5. Can the user return without losing the originating item, draft, date selection, scroll position, or state?
6. Are there duplicate destinations or competing tabs for the same intent?
7. Are any deep links or notification routes landing on a tab root rather than the exact item?

Return a route/state-transition map with file references. Do not edit files.
```

Act on it: collapse duplicate routes for one intent to a canonical one; introduce an explicit
`returnTo`/origin object rather than leaning on history; route notification taps to the exact
object with a fallback for already-handled items; give every disappearing item a deterministic
completion view.

### Triage decision and state machine — highest priority

```text
Review the full triage decision model as a state machine.

Find:
- All item states stored in code, API schemas, database models, mocks, reducers, stores, server actions, and UI conditionals
- Every action that changes an item's state
- Any action names or states that overlap semantically, including keep, queue, wait, release, dismiss, archive, defer, snooze, resolve, complete, overdue, or pending
- Any UI action that does not have a deterministic resulting state
- Any resulting state that is not rendered consistently in Today, Triage, Promises, Calendar, notifications, completion, and recap surfaces

Propose a canonical transition table using only:
Needs attention, Responded, Planned, Snoozed, Waiting on them, Needs a new plan, Kept, Released.

Do not change code. Flag migrations and backward-compatibility risks separately.
```

The interaction model only stays ergonomic if the database model, UI labels, analytics events and
notifications share one vocabulary. Adopt this table before touching components:

| From state | User action | To state | Required metadata |
|---|---|---|---|
| Needs attention | Send reply | Responded | Message/thread ID, sent timestamp |
| Needs attention | Confirm plan | Planned | Person, date/time, event/thread reference |
| Needs attention | Choose revisit time | Snoozed | Exact return timestamp |
| Needs attention or Responded | Mark awaiting reply | Waiting on them | Awaited person, initial action/time |
| Needs attention / Planned / Needs a new plan | Let go | Released | Reason optional, timestamp |
| Planned | Complete commitment | Kept | Completion timestamp, optional moment |
| Planned | Date no longer works | Needs a new plan | Prior date, reason optional |
| Snoozed | Return date arrives | Needs attention | Return reason and current priority rationale |

Then ask for a migration plan — not an execution:

```text
Based on the state-machine audit, propose a migration plan only.

Include:
- Canonical enum/type definitions
- Legacy state-to-new-state mapping
- Database/API migration order
- UI transition changes
- Analytics event migration
- Test fixture updates
- Rollback strategy
- Files affected
- Risks where legacy data cannot be mapped without a product decision

Do not modify files.
```

Do not accept a migration that silently maps ambiguous legacy states. A legacy `queued` may mean
"needs attention later", "snoozed", or "waiting on them" — require the missing information to be
identified and preserved with a safe default.

### Why now and consequence

```text
Audit all Today and Triage card render paths.

For every active item, verify whether the UI renders:
- WHY NOW
- A human-readable explanation based on real item signals
- IF YOU DO NOTHING or IF NOT
- A specific predicted reappearance/escalation behavior
- One context-selected recommended action
- Quieter alternatives
- The exact resulting state for each action

Identify all cases where these fields are missing, generic, hard-coded, contradictory, or not computable from available data.

For each gap, state whether it needs:
A. a data-model field
B. a prioritization-rule function
C. a UI component change
D. a copy/content rule
E. a product decision

Do not edit files.
```

Build these as first-class fields, not copy strings sprinkled through components:

```ts
type TriageExplanation = {
  whyNow: string;
  signals: Array<
    | "inner_circle"
    | "direct_question"
    | "promise_due"
    | "waiting_duration"
    | "recent_change"
    | "snooze_return"
  >;
  ifNoAction: string;
  nextReviewAt?: string;
  recommendedAction: "respond" | "plan" | "snooze" | "wait" | "let_go";
  alternativeActions: Array<"respond" | "plan" | "snooze" | "wait" | "let_go">;
};
```

The visible copy stays natural — "Inner circle · asked you a direct question · waiting 3 days" — but
storing structured signals and a next review time makes the logic testable, localizable and
consistent across surfaces.

### Promise ownership

```text
Review the Promises list, Promise Detail, Calendar, recap, and all promise-related notifications.

Verify that:
- Promises are grouped by ownership/kind rather than only by status
- "I'll reach out" and "We made plans" appear under Yours to keep
- "Waiting on them" appears under Not your move
- Waiting on them cannot be completed using a checkbox/tap-to-complete interaction
- No user-facing copy says overdue
- "Needs a new plan" has clear, non-shaming recovery actions
- Promise detail offers keep it, give it a new time, and let it go
- Calendar representations distinguish promises, external events, and protected blocks

Return evidence, gaps, edge cases, and the smallest component/data changes needed. Do not edit.
```

Act on it: strip completion affordances from Waiting on them; make grouping a domain decision rather
than a sort order buried in a component; replace every legacy `overdue` string, badge, icon,
event name, empty state and analytics label; define an explicit status-to-presentation map so
"Needs a new plan" cannot inherit red/error treatment; make "give it a new time" preserve the source
thread, original wording, person and prior date.

### Notification budget

```text
Audit every notification creation path, scheduler, cron job, server action, background worker, local-notification API call, and notification preference.

Determine:
- All notification categories currently possible
- Maximum notifications a user can receive per day under every combination of triggers
- Whether deduplication, quiet hours, timezone handling, and idempotency exist
- Whether the exact target item is opened on notification tap
- What happens if the target is already handled
- Whether due-promise notifications can coexist with the morning summary without violating product policy

Evaluate against this rule:
One morning summary per day, plus a reminder only when a dated promise is due. Any exception must be explicit and documented.

Provide a trigger matrix and failure cases. Do not edit.
```

Build a notification policy layer as the single gateway rather than letting features send directly.
Require timezone awareness, one idempotency key per type/user/object/date, a daily budget check,
quiet-hour suppression, a stale-target fallback ("You're all caught up here", never a dead route),
and analytics that separate sent, delivered, opened, suppressed and acted-on. V1 has exactly three
categories: morning summary, due-promise reminder, Sunday recap.

### Messaging safety

```text
Audit all message drafting and sending paths, including UI buttons, keyboard submit handlers, API routes, background jobs, integrations, retries, webhooks, and AI-assist code.

Verify the invariant:
Clearsky may draft, suggest, or prepare text, but it must never send a message without a deliberate user action on the final message content.

Find any violation or ambiguous path, including:
- Automatic sends
- Scheduled sends
- Auto-retries that could duplicate a send
- Send triggered by navigation, modal dismissal, or a background process
- Unclear final-send affordances
- Content changes after user confirmation
- Missing failure or retry handling

Provide file-level evidence and a severity-ranked remediation plan. Do not edit.
```

**Any actual or possible auto-send is a P0 blocker.** Stop feature work and correct it first. Require
a final explicit send tap on visible, editable content; idempotent sending keyed to that action;
clear sent/failed/pending states; no automatic resend under delivery uncertainty; a parked draft or
retry path after failure. "Nothing sends itself" is a core product promise, not a feature detail.

### Visual asset boundary

```text
Audit routes, components, CSS, image assets, design tokens, CMS/content sources, and build output for visual-asset usage.

Verify:
- The Clearsky daydreamer / character art appears only on marketing routes
- No character asset is rendered, imported, or bundled into the app experience
- The app uses only painted sky plates as splash backgrounds under CSS patterns
- The app has six splash plates: dawn, golden morning, high clear air, mint relief, golden hour, and dusk cloud sea
- Weekly Recap uses the golden-hour plate beneath the light-column pattern
- The total plate library is eight: two marketing hero skies plus six app splash plates

Return:
1. Exact usage map
2. Unused/orphaned assets
3. Incorrect route imports
4. Build-size implications
5. Recommended changes, but do not edit files.
```

Act on it: move character imports into marketing-only entry points; keep app bundles from importing
or preloading character images; add a route-level asset test or dependency boundary; rename
ambiguous assets (`marketing-character-*`, `app-splash-golden-hour`, `marketing-hero-dawn`).

### Accessibility and mobile ergonomics

```text
Review Clearsky as an iPhone-first product for accessibility and mobile ergonomics.

Audit:
- Touch target sizes, including close buttons, chips, icon-only controls, tab items, checkboxes, and destructive actions
- Dynamic Type / text scaling
- Screen-reader labels, roles, grouping, reading order, and state announcements
- Color contrast and whether color is the only state indicator
- Keyboard focus behavior where applicable
- Modal/sheet dismissal, back navigation, and unsaved draft protection
- Loading, empty, offline, sync-failure, permission-denied, and send-failure states
- Reachability of primary actions and accidental destructive taps
- Motion-reduction support for sky plates, parallax, slow loops, and breathing bloom

Return a prioritized accessibility and ergonomics backlog with exact files/components. Do not edit.
```

Prioritize: anything blocking completion or causing accidental destructive action; missing labels and
state announcements on primary flows; small tap targets and unclear icon-only controls; lost
drafts/context on navigation or sheet dismissal; colour-only state signalling; motion settings.
44px minimum hit targets, no emoji, no badges or streaks and calm motion are measurable test
conditions in this product, not aspirations.

---

## 3. Turning answers into work

Never say "fix all of this." Convert the audit into a decision log and small batches.

| Priority | Meaning | What you do |
|---|---|---|
| P0 | Breaks a core promise, privacy/safety constraint, data integrity, or basic completion path | Stop and fix before further build or demo work |
| P1 | Breaks the product model or makes a core flow misleading | Fix in the next implementation batch |
| P2 | Causes friction, inconsistency, or incomplete edge-state handling | Add to the next UX hardening sprint |
| P3 | Polish, refactor, non-blocking enhancement | Log it; do not let it expand scope |

Typical Clearsky **P0s**: automatic sending, destructive behaviour without confirmation, a
notification system that can spam, missing privacy or deletion safeguards.
Typical **P1s**: missing WHY NOW copy, unclear action outcomes, reintroduced `overdue` language,
a tickable "Waiting on them", a character asset in an app route.

### Ask for a plan

```text
Create an implementation plan for only the following approved findings:

[PASTE THE FINDING IDs OR EXACT ROWS HERE]

Constraints:
- Do not widen scope beyond these findings.
- Preserve existing working behavior unless a change is required by an approved finding.
- Prefer the smallest composable change that centralizes product logic.
- Separate data-model changes, API changes, UI changes, migration work, tests, and documentation.
- State every file to create, modify, or delete and why.
- Include acceptance criteria for each finding.
- Include validation commands and manual test scenarios.
- Identify anything that still needs my product decision before implementation.

Do not edit files yet.
```

The question to ask of the plan: **does it fix the model in one place, or spread duplicate
conditionals through screens?** Good — one `deriveTriagePresentation()` returning WHY NOW, IF NOT,
recommended action, alternatives and next-review behaviour. Weak — repeated `if/else` inside Today,
the triage card, the notification formatter and the completion screen.

### Approve a batch

```text
Implement only the approved plan items below.

Approved items:
- [ID]: [Short description]
- [ID]: [Short description]

Required constraints:
- Do not change navigation, pricing/paywall timing, or product scope unless explicitly listed above.
- Do not rename user-facing outcome vocabulary:
  Responded, Planned, Snoozed, Waiting on them, Let go, Needs a new plan.
- Do not introduce automatic sending.
- Do not add new notifications beyond the approved policy.
- Do not use character art in app routes.

Before editing:
1. Restate the files you will change.
2. State the acceptance criteria you will validate.

After editing:
1. Run typecheck, lint, tests, and production build.
2. Report every file changed and why.
3. Report the exact commands and results.
4. Report any failures, skipped checks, assumptions, or unresolved edge cases.
5. Provide a short manual QA checklist.
```

Commit after each successful batch, narrowly:
`feat(triage): add explicit explanation and outcome model` ·
`feat(promises): group commitments by ownership` ·
`fix(notifications): enforce daily notification policy` ·
`fix(assets): restrict character art to marketing routes` ·
`test(core-model): cover triage state transitions`

---

## 4. Require tests

```text
For the approved implementation, add or update tests for product invariants, not only component snapshots.

At minimum test:
- Every active triage card renders WHY NOW and IF YOU DO NOTHING / IF NOT.
- A recommended action is exactly one of the allowed outcomes.
- Every action produces the correct named state.
- Snooze cannot be saved without a return date/time.
- Waiting on them cannot render as a tickable/completable task.
- "Overdue" does not appear in user-facing product copy.
- Needs a new plan presents keep, reschedule, and let-go exits.
- Sending requires explicit user confirmation/tap.
- The notification policy cannot issue more than the allowed number for a user/day.
- App routes do not render/import character assets.
- Weekly Recap uses the golden-hour plate and the light-column layer.

Use the project's existing test conventions. Report what remains best suited to manual QA.
```

---

## 5. Manual QA script

Run this by hand after each batch, even when automated tests pass.

1. **Direct-question triage card.** WHY NOW identifies the real reason, the recommended action makes
   sense, and the consequence explains when and how it returns.
2. **Respond path.** Open the thread, edit the draft, send only through an explicit final action,
   confirm the result becomes **Responded**.
3. **Plan path.** Choose "Plan a time", accept or alter a slot, confirm the message, verify the
   result becomes **Planned** with a linked promise and calendar result.
4. **Snooze path.** Select a return date/time; the item must not be vague or deferred indefinitely,
   and must come back at the intended time.
5. **Waiting-on-them path.** Appears under **Not your move**, has no completion checkbox, receives
   no task-like pressure.
6. **Needs-a-new-plan path.** No "overdue" wording. Test all three exits: keep it, give it a new
   time, let it go.
7. **No-action consequence.** Do nothing on a relevant item; reappearance must match the stated
   IF NOT message.
8. **Notification policy.** Trigger competing conditions and verify the one-daily-summary plus
   dated-promise exception holds.
9. **Visual boundary.** Visit every product route; no character art anywhere. Weekly Recap uses the
   golden-hour plate under the light-column pattern.
10. **Failure and recovery.** No connected accounts, permission denied, offline, sync failure, send
    failure, stale notification, empty triage, and a very large triage day.

---

## 6. The operating rhythm

1. Audit, no edits.
2. Review findings and make the product decisions yourself.
3. Approve a small implementation plan.
4. Implement one coherent batch.
5. Run automated validation.
6. Run the manual QA script.
7. Commit a focused change.
8. Re-audit the affected area.

That keeps Claude Code valuable without letting it become an ungoverned product manager. Protect the
model before the UI: Clearsky's trust depends on explainable prioritization, explicit user control,
calm state transitions, ownership-aware commitments, and the guarantee that it never sends on the
user's behalf.
