#!/usr/bin/env node
// Generates clearsky.tokens.css from clearsky.tokens.json.
// The JSON is the source of truth. Never hand-edit the CSS.
//   node tokens/build.mjs

import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const T = JSON.parse(readFileSync(join(here, "clearsky.tokens.json"), "utf8"));

const out = [];
const p = (s = "") => out.push(s);

p("/* Clearsky design tokens " + T.$version + " — GENERATED FILE, DO NOT EDIT.");
p("   Source: tokens/clearsky.tokens.json  ·  Regenerate: node tokens/build.mjs");
p("   " + T.$rule);
p("*/");
p();
p(":root {");

p("  /* ── Colour ramps — 6 × 10 steps ─────────────────────────────── */");
for (const [ramp, steps] of Object.entries(T.ramps)) {
  for (const [step, hex] of Object.entries(steps)) p(`  --${ramp}-${step}: ${hex};`);
  p();
}

p("  /* ── Semantic colour — always prefer these over a raw ramp ───── */");
for (const [name, t] of Object.entries(T.semantic)) {
  p(`  --${name}: ${t.value};${" ".repeat(Math.max(1, 12 - t.value.length))}/* ${t.use} */`);
}
p();

p("  /* ── Type faces ──────────────────────────────────────────────── */");
p(`  --face-display: ${T.type.$faces.display}, Impact, sans-serif;`);
p(`  --face-editorial: "${T.type.$faces.editorial}", Georgia, serif;`);
p(`  --face-ui: "${T.type.$faces.ui}", -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;`);
p(`  --face-mono: ${T.type.$faces.mono};`);
p();

p("  /* ── Type scale — 18 tokens ──────────────────────────────────── */");
for (const [name, t] of Object.entries(T.type)) {
  if (name.startsWith("$")) continue;
  p(`  --text-${name}-size: ${t.size};`);
  p(`  --text-${name}-line: ${t.line};`);
  p(`  --text-${name}-weight: ${t.weight};`);
  if (t.track && t.track !== "0") p(`  --text-${name}-track: ${t.track};`);
}
p();

p("  /* ── Spacing — 4pt base ──────────────────────────────────────── */");
for (const [k, v] of Object.entries(T.space)) {
  if (k.startsWith("$")) continue;
  p(`  --space-${k}: ${v.value};${" ".repeat(Math.max(1, 8 - v.value.length))}/* ${v.use} */`);
}
p();

p("  /* ── Radius ──────────────────────────────────────────────────── */");
for (const [k, v] of Object.entries(T.radius)) {
  p(`  --radius-${k}: ${v.value};${" ".repeat(Math.max(1, 8 - v.value.length))}/* ${v.use} */`);
}
p();

p("  /* ── Elevation ───────────────────────────────────────────────── */");
for (const [k, v] of Object.entries(T.elevation)) p(`  --elev-${k}: ${v.value};`);
p();

p("  /* ── Motion ──────────────────────────────────────────────────── */");
for (const [k, v] of Object.entries(T.motion)) {
  if (k.startsWith("$")) continue;
  p(`  --motion-${k}: ${v.duration};`);
  p(`  --ease-${k}: ${v.easing};`);
}
p();

p("  /* ── Layering ────────────────────────────────────────────────── */");
for (const [k, v] of Object.entries(T.z)) p(`  --z-${k}: ${v};`);
p();

p("  /* ── Controls ────────────────────────────────────────────────── */");
p(`  --hit-target: ${T.control["hit-target"].value};`);
p(`  --focus-width: ${T.control["focus-ring"].width};`);
p(`  --focus-offset: ${T.control["focus-ring"].offset};`);
p(`  --icon-size: ${T.control["icon-grid"].size};`);
p(`  --icon-stroke: ${T.control["icon-grid"].stroke};`);
p("}");
p();

p("/* ── Type helpers ──────────────────────────────────────────────── */");
for (const [name, t] of Object.entries(T.type)) {
  if (name.startsWith("$")) continue;
  const face = { display: "display", editorial: "editorial", ui: "ui", mono: "mono" }[t.face];
  p(`.text-${name} {`);
  p(`  font-family: var(--face-${face});`);
  p(`  font-size: var(--text-${name}-size);`);
  p(`  line-height: var(--text-${name}-line);`);
  p(`  font-weight: var(--text-${name}-weight);`);
  if (t.track && t.track !== "0") p(`  letter-spacing: var(--text-${name}-track);`);
  if (t.face === "display") p("  text-transform: uppercase;");
  p("}");
}
p();

p("/* ── Non-negotiables from §08 ──────────────────────────────────── */");
p("/* Every tappable element clears 44×44. Wrap smaller visuals in a transparent target. */");
p(".hit { min-width: var(--hit-target); min-height: var(--hit-target); }");
p();
p("/* Focus is never removed. Visible on light and navy grounds alike. */");
p(":where(a, button, input, select, textarea, [tabindex]):focus-visible {");
p("  outline: var(--focus-width) solid var(--focus);");
p("  outline-offset: var(--focus-offset);");
p("}");
p();
p("/* " + T.motion.$rule + " */");
p("@media (prefers-reduced-motion: reduce) {");
p("  *, *::before, *::after {");
p("    animation-duration: 0ms !important;");
p("    animation-iteration-count: 1 !important;");
p("    transition-duration: 0ms !important;");
p("    scroll-behavior: auto !important;");
p("  }");
p("}");
p();

writeFileSync(join(here, "clearsky.tokens.css"), out.join("\n") + "\n");

const n = {
  ramp: Object.keys(T.ramps).length * 10,
  semantic: Object.keys(T.semantic).length,
  type: Object.keys(T.type).filter((k) => !k.startsWith("$")).length,
  space: Object.keys(T.space).filter((k) => !k.startsWith("$")).length,
  radius: Object.keys(T.radius).length,
  elev: Object.keys(T.elevation).length,
  motion: Object.keys(T.motion).filter((k) => !k.startsWith("$")).length,
};
console.log(
  `tokens/clearsky.tokens.css written — ${n.ramp} ramp steps, ${n.semantic} semantic, ` +
  `${n.type} type, ${n.space} spacing, ${n.radius} radius, ${n.elev} elevation, ${n.motion} motion.`
);
