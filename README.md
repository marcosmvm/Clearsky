# Handoff: Clearsky

## Overview
Clearsky is a relationship and commitment operating system for iPhone. It sorts the noise out of a
person's day, turns the messages that matter into plans they actually keep, and protects the time
those plans need. This bundle contains the complete design of record: the written product spec, an
interactive 19-screen app prototype, seven marketing pages, and the design system.

## About the design files
The files in this bundle are **design references created in HTML** — prototypes showing intended
look and behaviour, not production code to copy directly. The task is to **recreate these designs
in the target codebase's existing environment** (React, SwiftUI, native, whatever is established)
using its own patterns and libraries. If no environment exists yet, choose the framework that fits
the product — iPhone-first, iOS 17+ — and implement the designs there.

Two of these files are documents rather than screens: `01 Product Scope` is the written spec and
the source of truth for behaviour; `00 Clearsky Index` is the file register.

## Fidelity
**High fidelity.** Colours, typography, spacing, hit targets, motion timings and copy are final and
should be recreated faithfully. Exact values are listed under Design tokens below and are readable
from the source of each file.

## Read this first
`CLAUDE_CODE_AUDIT.md` in this folder is the operating procedure for using Claude Code against an
existing Clearsky codebase: audit prompts, the canonical state machine, the product invariants that
must hold, the priority framework, the test list and the manual QA script. **Protect the model
before the UI.** The product's trust depends on explainable prioritisation, explicit user control,
calm state transitions, ownership-aware commitments, and the guarantee that it never sends on the
user's behalf.

## Screens
Nineteen app screens, grouped by flow. `01 Product Scope` §6 carries the full inventory with each
screen's purpose, states and actions; `02 App Prototype` is the interactive version — open it and
use the side panel to jump to any screen.

**First run (4):** Sign in · Connect accounts · Inner circle · Notifications
**Daily loop (5):** Today · Triage · Thread · Composer · Sent
**Commitments (4):** Promises · Promise detail · New promise · Calendar
**Moments, money, account (6):** Weekly recap · Digest · Paywall · Plans · You · Privacy

The two screens that carry the product's logic are **Today** and **Triage**. Both render, per item:
a WHY NOW rationale drawn from real signals, an IF YOU DO NOTHING / IF NOT consequence, one
recommended action selected from the item's own context, and quieter alternatives. Do not
reduce either screen to a menu of equal-weight cards; that was the defect this design corrects.

## Interactions and behaviour
- **Triage** advances one card at a time. Every action maps to exactly one named outcome:
  Responded, Planned, Snoozed, Waiting on them, Let go. The completion screen tallies in those words.
- **Return path.** The app records the entry source (`from`) and the person (`who`) when a decision
  navigates away, so New promise, Thread and Calendar all return to where the user came from with the
  triage run intact. Never rely on browser history alone.
- **Promises** group by ownership, not status: *Yours to keep* (I'll reach out / We made plans),
  *Not your move* (Waiting on them — dashed circle, not tickable), then Kept and Released.
- **No "overdue" anywhere.** The state is **Needs a new plan**, and it offers three honest exits:
  keep it, give it a new time, let it go.
- **Nothing sends itself.** Clearsky drafts, suggests and reminds. Every outbound word is tapped by
  the user on the final message content.
- **One nudge a day** is a hard product constraint, not a setting: a morning summary, plus a reminder
  only when a dated promise is due, plus the Sunday recap. There is no fourth category in V1.
- **Motion** is slow: splash patterns loop over 24–56s with a breathing bloom; marketing uses
  scroll-driven parallax. Nothing faster than a breath. Honour reduce-motion.

## State management
The prototype holds state in one logic class; a real implementation should centralise the same model
in one domain layer rather than spreading conditionals through screens. Prefer a single
`deriveTriagePresentation()` that returns whyNow, ifNoAction, recommendedAction, alternatives and
nextReviewAt. The canonical transition table is in `CLAUDE_CODE_AUDIT.md`.

State the prototype tracks: current screen, triage index, the outcome tally, per-item outcomes,
entry source and person, promise done/released maps, protected-time flag, plan choice, notification
permission, connected accounts, inner circle, and the live draft.

## Design tokens
**Type** — Anton for display headlines, uppercase, letter-spacing 0.015em · Source Serif 4 (600) for
editorial and emotional moments · Instrument Sans for all UI and body.

**Colour**
- Ink navy `#1B2B4B` · body `#22314F` · muted `#5B6F8E` · secondary ink `#4C5F7D`
- Sky `#7FA5CE` → `#D5E8F9` · surfaces `#FDFEFF`, `#F3F8FD`, `#F7FBFE` · hairline `#E9F1F9`, `#E0EBF7`
- Amber action `#F2B84B` (gradient `#FFDD9A`→`#F2B84B`, ink `#4A3410`) · amber label ink `#8A6420`
- Kept green `#3F6339` · urgent terracotta `#C0492B`
- Never use `#8FA2BD` for text under 18px — it fails AA on every surface in this system.

**Radius** 11 · 13 · 14 · 16 · 18 · 20 · 22 · 999px pills. **Spacing** 4 · 7 · 9 · 11 · 14 · 16 · 18 · 22.

**Hard rules** 44px minimum hit target, everywhere, no exceptions · no emoji · no badges, streaks or
guilt mechanics · the daydreamer character is marketing-only and must never appear in the app · the
six painted sky plates DO stay in the app as splash backgrounds under their CSS patterns.

## Assets
Eight background plates: two marketing hero skies (M01, M02) and six app splash plates (dawn,
golden morning, high clear air, mint relief, golden hour, dusk cloud sea). Twenty-one transparent
character embeds and six cloud cutouts — **all marketing only**. Every URL is listed in
`11 Illustration Index`, which also documents, per marketing page, the exact hero, wording,
components and images that page ships.

The plates are hotlinked from a CDN in these prototypes. Download and re-host them in the target
codebase; do not depend on the CDN URLs.

## Files
| File | What it is |
|---|---|
| `00 Clearsky Index.dc.html` | The file register and the working rules |
| `01 Product Scope.dc.html` | The written spec, 16 sections — read §3, §4, §6, §16 |
| `02 App Prototype.dc.html` | The app: 19 interactive screens, every route wired |
| `03 M01 Landing.dc.html` | Marketing: the story in five beats, 3D scroll |
| `04 M02 How It Works.dc.html` | Marketing: the five loops |
| `05 M03 Why We Show Up.dc.html` | Marketing: the manifesto |
| `06 M04 Pricing.dc.html` | Marketing: plans, trial timeline, FAQ |
| `07 M05 Get Clearsky.dc.html` | Marketing: download and setup |
| `08 M06 Private By Design.dc.html` | Marketing: privacy principles and data flow |
| `09 404.dc.html` | Marketing: recovery |
| `10 UI Kit.dc.html` | Logo, wordmark, app icon, palette, type scale |
| `11 Illustration Index.dc.html` | Per-page asset spec and the full library |
| `CLAUDE_CODE_AUDIT.md` | How to review a codebase against this model |

`support.js` and `doc-page.js` are runtime files for the prototypes; they are not part of the design.

## Open product decisions
`01 Product Scope` §15 lists five questions the design does not answer — triage cadence, queued-item
expiry, undated promises, whether protected time writes a visible calendar event, and the
zero-accounts empty state. §16 lists the seven scenarios to user-test next. Neither should be
resolved by an implementer alone.
