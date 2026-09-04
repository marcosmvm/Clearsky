#!/usr/bin/env node
// Enforces the Clearsky rule: nothing may use a colour, size, radius, shadow or
// duration absent from the UI Kit. Reads tokens/clearsky.tokens.json as the authority.
//
//   node tokens/check.mjs              fail on NEW violations only (default, CI-safe)
//   node tokens/check.mjs --strict     fail on every violation
//   node tokens/check.mjs --baseline   re-record the accepted debt
//   node tokens/check.mjs --report     print the full breakdown, never fail
//
// The retired colour used as TEXT is always an error and can never be baselined.

import { readFileSync, writeFileSync, readdirSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join, relative } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..");
const T = JSON.parse(readFileSync(join(here, "clearsky.tokens.json"), "utf8"));
const BASELINE = join(here, "check.baseline.json");

const argv = new Set(process.argv.slice(2));
const MODE = argv.has("--baseline") ? "baseline"
  : argv.has("--strict") ? "strict"
  : argv.has("--report") ? "report" : "diff";

/* ── Build the allowed sets ─────────────────────────────────────────── */
const up = (s) => s.toUpperCase();
const allowedColour = new Set();
for (const steps of Object.values(T.ramps)) for (const hex of Object.values(steps)) allowedColour.add(up(hex));
for (const t of Object.values(T.semantic)) allowedColour.add(up(t.value));
// Pure black and white are permitted — the Kit uses them as ramp-label ink.
allowedColour.add("#FFFFFF"); allowedColour.add("#000000");

const allowedRadius = new Set(Object.values(T.radius).map((r) => parseFloat(r.value)));
const allowedDuration = new Set();
for (const [k, m] of Object.entries(T.motion)) {
  if (k.startsWith("$")) continue;
  allowedDuration.add(m.duration);
  if (m.durationMax) {
    // Ambient and bloom are ranges: accept any whole second inside them.
    const lo = parseFloat(m.duration), hi = parseFloat(m.durationMax);
    for (let s = lo; s <= hi; s += 0.1) allowedDuration.add(`${Math.round(s * 10) / 10}s`.replace(".0s", "s"));
  }
}
const allowedShadow = new Set(Object.values(T.elevation).map((e) => e.value.replace(/\s+/g, "")));

const RETIRED = Object.keys(T.retired).map(up);

/* ── Scan ───────────────────────────────────────────────────────────── */
const SCAN = readdirSync(root).filter((f) => /\.(dc\.html|html|js|css|mjs|ts|tsx|jsx)$/.test(f) && f !== "check.mjs");
const violations = [];

const add = (file, line, kind, value, note) =>
  violations.push({ id: `${file}:${line}:${kind}:${value}`, file, line, kind, value, note });

for (const file of SCAN) {
  const text = readFileSync(join(root, file), "utf8");
  const lines = text.split("\n");

  lines.forEach((ln, i) => {
    const no = i + 1;

    // 1. Retired colour used as TEXT — always fatal, never baselined.
    //    Resolves the nearest preceding CSS/JSX property for each occurrence, so a value
    //    reached through a ternary (color: x ? '#8FA2BD' : INK) is caught like a direct one.
    for (const r of RETIRED) {
      const re = new RegExp(r, "gi");
      let m;
      while ((m = re.exec(ln))) {
        const before = ln.slice(0, m.index);

        // Which CSS/JSX property does this value belong to? Match ONLY real colour
        // properties and take the last one — matching any identifier would let a
        // ternary's operands (color: a ? INK : '#8FA2BD') masquerade as the property.
        let name = "";
        const props = /\b(color|background|background-color|backgroundColor|border|border-color|borderColor|stroke|fill|outline|outline-color|outlineColor|box-shadow|boxShadow|caret-color|caretColor|text-decoration-color|textDecorationColor)\s*[:=]/g;
        let pm, lastIdx = -1;
        while ((pm = props.exec(before))) {
          name = pm[1].toLowerCase();
          lastIdx = pm.index;
        }

        // If a tag closed after that property, the hex is TEXT CONTENT (the Kit printing
        // the hex it retires), not a style value. Not a violation.
        const lastGt = before.lastIndexOf(">");
        if (lastGt > lastIdx) continue;

        const isPaint = /^(background|backgroundcolor|stroke|fill|border|bordercolor|boxshadow|outline|outlinecolor)$/.test(name.replace(/-/g, ""));
        const isText = /color$/.test(name.replace(/-/g, "")) && !isPaint;

        if (isText) {
          violations.push({
            id: `RETIRED:${file}:${no}:${m.index}`, file, line: no, kind: "retired-as-text",
            value: r, note: T.retired[r] ? T.retired[r].reason : "retired", fatal: true,
          });
        }
      }
    }

    // 2. Colours outside the token set.
    let m;
    const hex = /#[0-9A-Fa-f]{6}\b/g;
    while ((m = hex.exec(ln))) {
      const v = up(m[0]);
      if (!allowedColour.has(v)) add(file, no, "colour", v, "not in any ramp or semantic token");
    }

    // 3. Radii outside the scale.
    const rad = /border-radius\s*:\s*['"]?\s*([0-9.]+)px/gi;
    while ((m = rad.exec(ln))) {
      const v = parseFloat(m[1]);
      if (!allowedRadius.has(v)) add(file, no, "radius", `${v}px`, "not in the radius scale");
    }

    // 4. Transition/animation durations outside the motion scale.
    const dur = /(?:transition|animation)(?:-duration)?\s*:\s*[^;'"]*?([0-9.]+m?s)/gi;
    while ((m = dur.exec(ln))) {
      const v = m[1];
      if (!allowedDuration.has(v)) add(file, no, "duration", v, "not in the motion scale");
    }

    // 5. Box-shadows outside the elevation scale.
    const sh = /box-shadow\s*:\s*['"]?([^;'"]+)/gi;
    while ((m = sh.exec(ln))) {
      const v = m[1].trim().replace(/\s+/g, "");
      if (v !== "none" && !allowedShadow.has(v)) add(file, no, "shadow", m[1].trim().slice(0, 46), "not in the elevation scale");
    }
  });
}

/* ── Report ─────────────────────────────────────────────────────────── */
const fatal = violations.filter((v) => v.fatal);
const soft = violations.filter((v) => !v.fatal);

const byKind = {};
for (const v of soft) (byKind[v.kind] ||= []).push(v);
const byFile = {};
for (const v of soft) (byFile[v.file] ||= []).push(v);

const bar = "─".repeat(66);
console.log(`\n${bar}\nClearsky token check — authority: tokens/clearsky.tokens.json v${T.$version}\n${bar}`);
console.log(`Scanned ${SCAN.length} files.`);
console.log(`Allowed: ${allowedColour.size} colours · ${allowedRadius.size} radii · ${allowedShadow.size} shadows\n`);

if (fatal.length) {
  console.log(`✗ RETIRED COLOUR USED AS TEXT — ${fatal.length} occurrence(s). Always fatal.`);
  for (const v of fatal) console.log(`    ${v.file}:${v.line}  ${v.value}  — ${v.note}`);
  console.log();
}

for (const [kind, vs] of Object.entries(byKind)) {
  const distinct = new Set(vs.map((v) => v.value));
  console.log(`  ${kind.padEnd(9)} ${String(vs.length).padStart(4)} occurrences · ${distinct.size} distinct`);
}
console.log();
for (const [file, vs] of Object.entries(byFile).sort((a, b) => b[1].length - a[1].length)) {
  console.log(`  ${String(vs.length).padStart(4)}  ${file}`);
}

if (MODE === "report") {
  console.log(`\nTop offending values:`);
  const counts = {};
  for (const v of soft) counts[`${v.kind} ${v.value}`] = (counts[`${v.kind} ${v.value}`] || 0) + 1;
  Object.entries(counts).sort((a, b) => b[1] - a[1]).slice(0, 25)
    .forEach(([k, n]) => console.log(`  ${String(n).padStart(4)} × ${k}`));
  process.exit(0);
}

if (MODE === "baseline") {
  writeFileSync(BASELINE, JSON.stringify({
    $note: "Accepted token debt. New violations fail CI; these are burned down deliberately. Never add a retired-as-text entry here — those are always fatal.",
    $recorded: new Date().toISOString().slice(0, 10),
    count: soft.length,
    ids: soft.map((v) => v.id).sort(),
  }, null, 2) + "\n");
  console.log(`\n✓ Baseline recorded: ${soft.length} accepted violations → tokens/check.baseline.json`);
  console.log(fatal.length ? `✗ ${fatal.length} fatal retired-as-text violation(s) NOT baselined — fix them.` : "");
  process.exit(fatal.length ? 1 : 0);
}

const base = existsSync(BASELINE) ? new Set(JSON.parse(readFileSync(BASELINE, "utf8")).ids) : new Set();
const fresh = soft.filter((v) => !base.has(v.id));

if (MODE === "strict") {
  console.log(`\n${bar}`);
  const bad = soft.length + fatal.length;
  console.log(bad ? `✗ STRICT: ${bad} violation(s).` : "✓ STRICT: clean.");
  process.exit(bad ? 1 : 0);
}

console.log(`\n${bar}`);
console.log(`Baseline: ${base.size} accepted · New: ${fresh.length} · Fatal: ${fatal.length}`);
if (fresh.length) {
  console.log(`\n✗ NEW violations not in the baseline:`);
  for (const v of fresh.slice(0, 40)) console.log(`    ${v.file}:${v.line}  ${v.kind} ${v.value}`);
  if (fresh.length > 40) console.log(`    …and ${fresh.length - 40} more`);
}
const fail = fresh.length + fatal.length;
console.log(fail ? `\n✗ FAIL — ${fail} issue(s) to resolve.\n` : `\n✓ PASS — no new token violations.\n`);
process.exit(fail ? 1 : 0);
