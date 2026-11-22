// Writes lib/engines/collation_table.dart: the weights of ICU's root
// collation, as Genbeya sorts names and titles with
// `localeCompare(other, undefined, { numeric: true, sensitivity: "base" })`
// and people with a plain `localeCompare`, for the scripts and punctuation
// names use, and the canonical decompositions and combining marks that
// `normalize("NFD")` and `\p{M}` stand for. Dart has no ICU; the table lets
// lib/engines/collation.dart sort the same way. Characters outside it sort
// after it by code point, as ICU's implicit weights roughly do.
//
//   node make-collation.mjs
import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const base = new Intl.Collator("und", { sensitivity: "base" });

const ranges = [
  [0x0000, 0x024f], // Latin, with its punctuation and controls
  [0x0250, 0x02ff], // IPA, spacing modifiers
  [0x0300, 0x036f], // combining marks
  [0x0370, 0x03ff], // Greek
  [0x0400, 0x052f], // Cyrillic
  [0x1e00, 0x1eff], // Latin extended additional (Vietnamese)
  [0x2000, 0x206f], // general punctuation
  [0x20a0, 0x20cf], // currency
  [0x2100, 0x218f], // letterlike, number forms
  [0x2190, 0x22ff], // arrows, mathematical operators
  [0x2460, 0x24ff], // enclosed alphanumerics
  [0x2500, 0x27bf], // box drawing, shapes, dingbats
  [0x0530, 0x06ff], // Armenian, Hebrew, Arabic
  [0x0900, 0x097f], // Devanagari
  [0x0e00, 0x0e7f], // Thai
  [0x1f00, 0x1fff], // Greek extended
  [0x2070, 0x209f], // superscripts and subscripts
  [0x2c60, 0x2c7f], // Latin extended C
  [0x3000, 0x30ff], // CJK punctuation, kana
  [0xa720, 0xa7ff], // Latin extended D
  [0xfb00, 0xfb4f], // ligatures (ﬁ)
  [0xfe30, 0xfe6f], // CJK compatibility and small forms
  [0xff00, 0xffef], // full-width forms
  [0x1d400, 0x1d7ff], // mathematical letters
  [0x1f000, 0x1faff], // emoji and other symbols
];
// Hangul syllables take one place here and a block of weights in the table:
// they are numbered in the order of their letters, as ICU sorts them.
const HANGUL_FIRST = 0xac00;
const HANGUL_COUNT = 11172;
const chars = [String.fromCodePoint(HANGUL_FIRST)];
for (const [from, to] of ranges) {
  for (let code = from; code <= to; code++) {
    if (code >= 0xd800 && code <= 0xdfff) continue;
    chars.push(String.fromCodePoint(code));
  }
}

const ignorable = chars.filter((c) => base.compare(c, "") === 0);
const weighted = chars.filter((c) => base.compare(c, "") !== 0).sort(base.compare);
const rank = new Map();
let next = 0;
let hangul = 0;
weighted.forEach((c, i) => {
  if (i === 0 || base.compare(weighted[i - 1], c) !== 0) next++;
  if (c.codePointAt(0) === HANGUL_FIRST) {
    hangul = next;
    next += HANGUL_COUNT - 1;
  }
  rank.set(c, next);
});
const listed = weighted.filter((c) => c.codePointAt(0) !== HANGUL_FIRST);

// Characters that ICU expands into two (æ = ae, ß = ss, ĳ = ij, ﬁ = fi, …).
const letters = [..."abcdefghijklmnopqrstuvwxyz"];
const pairs = letters.flatMap((a) => letters.map((b) => a + b));
const expansions = new Map();
for (const c of listed) {
  if (/[a-z0-9]/i.test(c)) continue;
  const pair = pairs.find((p) => base.compare(c, p) === 0);
  if (pair) expansions.set(c, [rank.get(pair[0]), rank.get(pair[1])]);
}

// Decimal digits of every script: numeric collation compares runs of them
// by value. Other characters that weigh like digits (², ①) stay single.
const digits = [];
for (let code = 0; code <= 0x10ffff; code++) {
  if (code >= 0xd800 && code <= 0xdfff) continue;
  const c = String.fromCodePoint(code);
  if (!/\p{Nd}/u.test(c)) continue;
  const value = [..."0123456789"].findIndex((d) => base.compare(c, d) === 0);
  if (value >= 0) digits.push([code, value]);
}

// Full strength: accents (secondary), then case (tertiary), within each
// primary weight. Strings are decomposed first (NFD), so a precomposed
// letter weighs as its base letter followed by its marks.
const accent = new Intl.Collator("und", { sensitivity: "accent" });
const variant = new Intl.Collator("und", { sensitivity: "variant" });
const known = new Set(chars);
const decompositions = new Map();
for (const c of chars) {
  const d = c.normalize("NFD");
  if (d !== c && [...d].every((x) => known.has(x))) decompositions.set(c, [...d].map((x) => x.codePointAt(0)));
}
const secondary = new Map();
const tertiary = new Map();
const groups = new Map();
for (const c of listed) {
  if (decompositions.has(c)) continue;
  const r = rank.get(c);
  groups.set(r, [...(groups.get(r) ?? []), c]);
}
for (const members of groups.values()) {
  const byAccent = [...members].sort((a, b) => accent.compare(a, b) || variant.compare(a, b));
  let s2 = 0;
  let t = 0;
  byAccent.forEach((c, i) => {
    const previous = byAccent[i - 1];
    if (i === 0 || accent.compare(previous, c) !== 0) {
      s2++;
      t = 0;
    } else if (variant.compare(previous, c) !== 0) t++;
    if (s2 !== 1) secondary.set(c, s2);
    if (t !== 0) tertiary.set(c, t);
  });
}
// Expansions keep their case: Æ after æ.
for (const c of expansions.keys()) if (c !== c.toLowerCase()) tertiary.set(c, 1);
const marks = ignorable.filter((c) => accent.compare(c, "") !== 0).sort(accent.compare);
marks.forEach((c, i) => {
  if (i === 0 || accent.compare(marks[i - 1], c) !== 0) secondary.set(c, 1000 + i);
  else secondary.set(c, secondary.get(marks[i - 1]));
});
const markRanges = [];
for (let code = 0; code <= 0x10ffff; code++) {
  if (code >= 0xd800 && code <= 0xdfff) continue;
  if (!/\p{M}/u.test(String.fromCodePoint(code))) continue;
  const last = markRanges.at(-1);
  if (last && last[1] === code - 1) last[1] = code;
  else markRanges.push([code, code]);
}

const hex = (c) => `0x${c.codePointAt(0).toString(16).padStart(4, "0")}`;
const singles = listed.filter((c) => !expansions.has(c)).map((c) => `${hex(c)}: ${rank.get(c)}`);
const out = `// Generated by tool/conformance/make-collation.mjs from ICU ${process.versions.icu}; do not edit.
// The primary weights of ICU's root collation (see collation.dart).
// ignore_for_file: lines_longer_than_80_chars

/// Code points ICU ignores at base strength (controls, combining marks, …).
const collationIgnorable = <int>{${ignorable.map(hex).join(", ")}};

/// Primary weight by code point; equal weights compare equal at base strength.
const collationWeights = <int, int>{${singles.join(", ")}};

/// Code points that weigh as two letters.
const collationExpansions = <int, List<int>>{${[...expansions].map(([c, w]) => `${hex(c)}: [${w.join(", ")}]`).join(", ")}};

/// Decimal digits by code point, with their value: numeric collation
/// compares runs of them by value, below every weight from 0 up.
const collationDigits = <int, int>{${digits.map(([code, value]) => `0x${code.toString(16)}: ${value}`).join(", ")}};

/// The weight of "0": numbers sort after every weight below it.
const collationDigitWeight = ${rank.get("0")};

/// Secondary weights other than 1: letters that differ from their base by an
/// accent they can't be decomposed into (ø) weigh 2 and up; marks from 1000 up.
const collationSecondary = <int, int>{${[...secondary].map(([c, w]) => `${hex(c)}: ${w}`).join(", ")}};

/// Tertiary weights (case) other than 0.
const collationTertiary = <int, int>{${[...tertiary].map(([c, w]) => `${hex(c)}: ${w}`).join(", ")}};

/// Canonical decompositions (NFD) of the code points in the table.
const unicodeDecompositions = <int, List<int>>{${[...decompositions].map(([c, d]) => `${hex(c)}: [${d.map((x) => "0x" + x.toString(16)).join(", ")}]`).join(", ")}};

/// Combining marks (\\p{M}), as first and last code point of each range.
const unicodeMarkRanges = <int>[${markRanges.map(([a, b]) => `0x${a.toString(16)}, 0x${b.toString(16)}`).join(", ")}];

/// The weight of the first Hangul syllable (U+AC00); the others follow it.
const collationHangulWeight = ${hangul};

/// Weights above this belong to code points outside the table.
const collationMaxWeight = ${next};
`;
writeFileSync(join(here, "../../lib/engines/collation_table.dart"), out);
console.log(`${decompositions.size} decompositions, ${marks.length} marks, ${markRanges.length} mark ranges, ${digits.length} digits, ${listed.length} weighted, ${ignorable.length} ignorable, ${expansions.size} expansions, ${next} weights`);
