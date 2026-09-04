# Clearsky — project notes (updated 2026-09-04)

## Read first
`00 Clearsky Index.dc.html` is the project index — twelve pages, each with exactly one job.
`01 Product Scope.dc.html` is the written spec. `02 App Prototype.dc.html` is the app.
Files are numbered so the project reads in order: 00 index · 01 spec · 02 app · 03–09 marketing · 10–11 design system.
Five superseded working docs (flow index, mobile screens, marketing map, style board, illustration kit)
were retired on 2026-09-04; their content lives in Product Scope §6, the Illustration Index and these notes.

## HARD RULE — the CHARACTER is marketing only
The daydreamer avatar appears on the marketing site ONLY — never in the app.
The painted sky plates DO stay in the app: each of the six splash screens keeps its own
generated background plate (`PLATE` map in the prototype logic), with a unique CSS pattern
loop layered over it at 62% opacity:
dawn = rising arcs · morning = sunburst · clearing = dot sweep · relief = ripples · golden = light columns · dusk = diagonal weave.
Never reintroduce an `<img>` of a character into the prototype.

## UI Kit is the token authority
`10 UI Kit.dc.html` v2.0 — 26 sections. 01–08 are foundations (logo system, construction/clear space,
backgrounds/monochrome, misuse, app icon, colour ramps + measured contrast, type scale, tokens);
09–26 are components. No page may introduce a colour, size, radius, shadow or duration absent from it.
RETIRED: `#8FA2BD` as type at any size (2.58:1 on white) — use `#5B6F8E`. Hairlines and icon fills only.

## Today dashboard
Rebuilt as a sequence, not a menu: sort-progress ring, ONE primary next action driven by day state
(stack → due today → next up → all clear), the day's shape, then promises due today only.
It must not duplicate the tab bar. Weekly recap lives in You and arrives Sunday.

Use when any screen needs imagery (clouds, skies, avatar, props).

## Generation (primary, style-matched painterly clouds/avatars)
- Higgsfield MCP: `higgsfield__generate_image` — Nano Banana Pro `nano_banana_pro` (2 credits/img, 4K/detail), `soul_2` (portraits/character), Seedream. Batch via `generate_image_batch`.
- Cutout pipeline: generate on flat contrasting bg → `higgsfield__remove_background` (media_id = job_id) → transparent PNG URL → hotlink as layer.
- `higgsfield__media_import_url` imports any https image for editing/bg-removal.
- STATUS: style LOCKED 2026-09-04 — S3 glossy mascot ("toy-vinyl" recipe). Anchor approved. Reference element "Clearsky Daydreamer" id 0d579d05-0695-494d-99ed-5b9f734c0d93 — embed <<<id>>> in every prompt for character consistency. 13 illustrations + 6 transparent cloud cutouts (C1-C6, LAYERS section) generated; URLs live in Clearsky Illustration Index.dc.html. Page skies stay CSS gradients. M01 landing built with 3D scroll layers.
- Reusable character: `show_reference_elements` (instant, multi-ref) vs Soul training (5-20 photos). For the Clearsky avatar use Elements once key art exists.

## Free real photography (works today)
- Wikimedia Commons, hotlink via `https://commons.wikimedia.org/wiki/Special:FilePath/<File name>?width=1200`.
  - `Cloud PNG Image.png` — transparent cumulus cutout, CC BY-SA 4.0 (attribution required).
  - `Clouds background.jpg` — cumulus humilis on blue sky, public domain. Use `mix-blend-mode: screen` over sky gradients to drop the blue.
  - Categories: Cumulus clouds, Cloud studies (Constable/Eckersberg paintings, PD — painterly!).

## Free soft-3D props (emoji style — accents only, NOT for painterly scene art)
- `assetmcp__search_3d_assets`: Fluent Emoji 3D (MIT), 3dicons (CC0, 120), Khagwal 3D (CC0, 45). Direct jsDelivr/CDN URLs. Has Cloud, Sun behind cloud, Rainbow.

## User's Canva library
- `canva__list-folder-items` — currently only Wryko social assets, no sky imagery. Canva can't produce transparent cutouts.

## Other
- Mobbin MCP — UI reference screenshots only, not an asset source.
- GitHub free packs: only pixel-art game clouds found; wrong style.
- `uploads/` + image-slot.js — user drag-and-drop for purchased stock.

## Layer treatment (3D scroll)
Transparent PNG (or screen-blend photo) → absolutely positioned layer → scroll-driven `rotate()` + parallax translate, as in Clearsky Landing hero. Demo: Illustration Kit section 06.
