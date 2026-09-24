#!/usr/bin/env node
// Measured WCAG contrast check. Resolves the GROUND behind each text colour and
// measures it, rather than blocklisting a hex.
//
//   node tokens/contrast.mjs            fail on NEW failures only (CI default)
//   node tokens/contrast.mjs --report   full breakdown, never fails
//   node tokens/contrast.mjs --baseline re-record accepted debt
//
// Why this exists: the UI Kit retired #8FA2BD on the strength of one measurement
// (2.58:1 on white). True, and the wrong conclusion — the value was simultaneously
// the system's only on-dark ink. The resulting blanket sweep regressed 31 passing
// texts to failing across three files. A value-based check cannot catch that class
// of error; only a ground-aware one can.
//
// KNOWN LIMITATION — READ BEFORE TRUSTING A NUMBER.
// There is no DOM here. These .dc.html files put whole component trees on single
// lines, so ancestry is approximated by indentation. That is good enough to surface
// candidates and NOT good enough to gate a build: a misresolved ground shows up as
// an "X on X" pair at 1.00:1, which is a resolver failure, not a real defect. Treat
// every row as a lead to verify by eye, never as a verdict. This is why CI runs it
// for information only. Replacing the heuristic with a real DOM parse is the fix.

import { readFileSync, writeFileSync, readdirSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..");
const BASELINE = join(here, "contrast.baseline.json");
const argv = new Set(process.argv.slice(2));
const MODE = argv.has("--baseline") ? "baseline" : argv.has("--report") ? "report" : "diff";

/* ── WCAG 2.1 ───────────────────────────────────────────────────────── */
const lum = (hex) => {
  const h = hex.replace("#", "");
  const [r, g, b] = [0, 2, 4].map((i) => parseInt(h.slice(i, i + 2), 16) / 255);
  const f = (c) => (c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);
  return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
};
const ratio = (a, b) => {
  const [la, lb] = [lum(a), lum(b)];
  const [hi, lo] = la > lb ? [la, lb] : [lb, la];
  return (hi + 0.05) / (lo + 0.05);
};

// AA: 4.5:1 normal text; 3:1 for large text (>=24px, or >=18.66px when bold).
const required = (px, weight) => (px >= 24 || (px >= 18.66 && weight >= 700) ? 3.0 : 4.5);

/* ── Scan ───────────────────────────────────────────────────────────── */
const FILES = readdirSync(root).filter((f) => /\.dc\.html$/.test(f));
const HEX = "#[0-9A-Fa-f]{6}";
const LOOKBACK = 60; // lines to search upward for the enclosing ground

const results = [];

for (const file of FILES) {
  const lines = readFileSync(join(root, file), "utf8").split("\n");

  lines.forEach((ln, i) => {
    // Every text colour on this line, direct or via a ternary.
    const colours = [];
    const re = new RegExp(`\\bcolor\\s*:\\s*[^;,}]{0,120}`, "gi");
    let cm;
    while ((cm = re.exec(ln))) {
      const seg = cm[0];
      if (/^background|^border|^outline/i.test(seg)) continue;
      for (const h of seg.match(new RegExp(HEX, "g")) || []) colours.push({ hex: h.toUpperCase(), at: cm.index });
    }
    if (!colours.length) return;

    // Font size and weight on the same element, for the AA threshold.
    const fs = /font-?[sS]ize\s*:\s*['"]?([0-9.]+)px/.exec(ln);
    const fw = /font-?[wW]eight\s*:\s*['"]?([0-9]{3})/.exec(ln);
    const px = fs ? parseFloat(fs[1]) : 14;
    const weight = fw ? parseInt(fw[1], 10) : 400;
    const need = required(px, weight);

    // Resolve the enclosing ground. There is no DOM here, so ancestry is approximated
    // by indentation: a background declared on an earlier line with STRICTLY LESS
    // indentation is an ancestor's, while one at the same or deeper indentation belongs
    // to a sibling and must not be treated as this element's ground. Without that guard
    // the resolver returns a sibling's fill and reports 1.00:1 against the element's own
    // colour — noise that would make the whole check untrustworthy.
    const indent = (s) => s.length - s.trimStart().length;
    const myIndent = indent(ln);
    let ground = null, groundLine = null;
    for (let j = i - 1; j >= Math.max(0, i - LOOKBACK) && !ground; j--) {
      if (!lines[j].trim()) continue;
      if (indent(lines[j]) >= myIndent) continue; // sibling or deeper — not our ground
      const bg = new RegExp(`background(?:-color)?\\s*:\\s*[^;,}]{0,160}`, "gi");
      let bm, last = null;
      while ((bm = bg.exec(lines[j]))) {
        const hs = bm[0].match(new RegExp(HEX, "g"));
        if (hs) last = hs; // a gradient yields several stops
      }
      if (last) { ground = last.map((h) => h.toUpperCase()); groundLine = j + 1; }
    }
    if (!ground) return; // unresolvable — never guessed

    for (const c of colours) {
      // Worst stop of a gradient is the honest number.
      let worst = Infinity, worstGround = ground[0];
      for (const g of ground) {
        const r = ratio(c.hex, g);
        if (r < worst) { worst = r; worstGround = g; }
      }
      if (worst + 1e-9 < need) {
        results.push({
          id: `${file}:${i + 1}:${c.hex}:${worstGround}`,
          file, line: i + 1, fg: c.hex, bg: worstGround,
          ratio: Math.round(worst * 100) / 100, need, px, weight, groundLine,
          text: (ln.match(/>([^<>{]{3,42})</) || ln.match(/,\s*'([^']{3,42})'/) || [, ""])[1].trim(),
        });
      }
    }
  });
}

/* ── Report ─────────────────────────────────────────────────────────── */
const bar = "─".repeat(72);
console.log(`\n${bar}\nClearsky contrast check — WCAG 2.1 AA, ground-resolved\n${bar}`);
console.log(`Scanned ${FILES.length} pages. ${results.length} text/ground pairs below threshold.`);
const selfPairs = results.filter((r) => r.ratio <= 1.01).length;
console.log(`HEURISTIC — grounds are resolved by indentation, not a DOM. ${selfPairs} row(s) report`);
console.log(`1.00:1 (same colour on itself), which means the resolver missed, not that the design is`);
console.log(`broken. Verify each row by eye. This tool informs; it does not gate.\n`);

const byFile = {};
for (const r of results) (byFile[r.file] ||= []).push(r);
for (const [f, rs] of Object.entries(byFile).sort((a, b) => b[1].length - a[1].length)) {
  console.log(`  ${String(rs.length).padStart(4)}  ${f}`);
}

if (MODE === "report") {
  console.log(`\nWorst 20:\n`);
  results.sort((a, b) => a.ratio - b.ratio).slice(0, 20).forEach((r) =>
    console.log(`  ${r.ratio.toFixed(2)}:1 (needs ${r.need})  ${r.fg} on ${r.bg}  ${r.file}:${r.line}  ${r.px}px  ${r.text}`));
  process.exit(0);
}

if (MODE === "baseline") {
  writeFileSync(BASELINE, JSON.stringify({
    $note: "Accepted contrast debt. CI fails on NEW failures. Burn these down deliberately.",
    $recorded: new Date().toISOString().slice(0, 10),
    count: results.length,
    ids: [...new Set(results.map((r) => r.id))].sort(),
  }, null, 2) + "\n");
  console.log(`\n✓ Baseline recorded: ${results.length} accepted → tokens/contrast.baseline.json\n`);
  process.exit(0);
}

const base = existsSync(BASELINE) ? new Set(JSON.parse(readFileSync(BASELINE, "utf8")).ids) : new Set();
const fresh = results.filter((r) => !base.has(r.id));
console.log(`\n${bar}\nBaseline: ${base.size} accepted · New: ${fresh.length}`);
if (fresh.length) {
  console.log(`\n✗ NEW contrast failures:\n`);
  fresh.slice(0, 30).forEach((r) =>
    console.log(`  ${r.file}:${r.line}  ${r.fg} on ${r.bg} = ${r.ratio}:1, needs ${r.need}  (${r.px}px)  ${r.text}`));
  if (fresh.length > 30) console.log(`  …and ${fresh.length - 30} more`);
}
console.log(fresh.length ? `\n✗ FAIL\n` : `\n✓ PASS — no new contrast failures.\n`);
process.exit(fresh.length ? 1 : 0);
