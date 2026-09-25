---
feature: english-prose-justification
status: delivered
updated: 2026-09-25
branch: main
commits: f4d84ca..f4d84ca
---

# English Prose Justification

## Report

**What was built** — English (Latin-script) body prose is now justified so both margins are flush and word spacing is even, matching print/Kindle/Apple Books norms. Latin paragraphs use block form (no first-line indent) because Flutter's `TextAlign.justify` hangs leading whitespace on non-last lines and would delete an indent span on every wrap; paragraph gap already separates blocks. Chinese body keeps `TextAlign.start` + the two-em indent. Quotes, lists, centered labels, and headings are never justified. Script detection runs on `stripAllMarkers` text so `[[image:N]]` cannot flip a CJK paragraph to Latin. Pagination measures with the same indent helper as render.

**Verification**
- `flutter analyze` — PASS (No issues found)
- `flutter test` — PASS 164/164, including new `test/english_typography_test.dart`
- Reviewer found 2 CRITICALs (justify hangs indent; image markers vote Latin) — both fixed and re-verified; T2 acceptance amended to block-paragraph form.

**Journey log**
- Flutter `TextAlign.justify` hangs leading whitespace on non-last lines — a leading TextSpan indent cannot coexist with justify. Market-standard flush margins won; indent became block-form.
- `readerText` keeps `[[image:N]]`; any Latin/CJK heuristic must count `stripAllMarkers` output.
- Widget tests for paragraph paint must use `selectable: false` to observe `Text`/`Text.rich` (default `SelectableText` hides it).

## [S1] Problem

English (Latin-script) books render body lines with a ragged right edge and uneven word spacing. Chinese prose is unaffected. The reader currently forces `TextAlign.start` for all body text and always prefixes a CJK two-em indent (`　　`), which is wrong for English book typography.

## [S2] Design

Market-standard English book typography (print / Kindle / Apple Books):

1. **Justified body** — `TextAlign.justify` on Latin body prose so both margins are flush. CJK body keeps `TextAlign.start` (justify hangs the `　　` indent and CJK already fills evenly).
2. **Block paragraphs for justified Latin** — Flutter `TextAlign.justify` hangs leading whitespace on non-last lines, so a first-line indent span disappears on wrap. Latin body therefore uses **no text indent** (block form; paragraph gap is the visual separator), which is also a standard English ebook layout. CJK keeps the `　　` indent and `TextAlign.start`.
3. **Per-paragraph script detection** — a paragraph is Latin when Latin letters outnumber CJK ideographs; mixed/unknown falls back to Latin if `latin > 0 && latin >= cjk`. Detection runs on `stripAllMarkers` text only. Headings, quotes, lists, and centered labels never take the Latin justify path.
4. **Shared helpers** (`ReaderMarkup`) so render and pagination measure the same indent string/length:
   - `isLatinBody(String text) -> bool` (counts `stripAllMarkers` text only)
   - `indentPrefixFor(String plain) -> String` (`\u2003` or `　　`; Latin render path suppresses it)
   - `indentPrefixLengthFor(String plain) -> int`
5. Pagination `sliceDisplayText` indent prefix length follows the helper (was hard-coded `2`).
6. Justify does not change line breaking in Flutter — pagination metrics stay valid.

## [S3] Out of Scope

- Hyphenation engine (Flutter has none built-in; not required to fix ragged right).
- Book-level language picker / user setting.
- CJK justification (explicitly rejected earlier in this codebase).

## Tasks
- [x] T1: Add Latin detection + indent helpers on ReaderMarkup — acceptance: unit tests cover Latin, CJK, and mixed samples (covers: S2)
- [x] T2: ReaderParagraph justifies Latin body (quotes/lists/center/heading excluded) — acceptance: English body Text.rich is TextAlign.justify with no leading indent span; Chinese body keeps TextAlign.start + `　　`; quotes/lists never justified (covers: S2; depends: T1)
- [x] T3: Pagination uses the same indent prefix/length — acceptance: sliced fragments of indented Latin prose drop exactly one em-space, not two CJK spaces (covers: S2; depends: T1)
- [x] T4: Regression tests + full suite green — acceptance: `flutter analyze` clean, `flutter test` all pass (covers: S2; depends: T1, T2, T3)
