# Changelog

All notable changes to this project will be documented in this file.

## [1.0.4] - 2026-09-13

### Added
- **`DocxViewConfig.showFootnotes`** (#83, restored per #121): boolean flag (default `true`). Set to `false` to hide the footnotes section at the bottom of the document and disable inline footnote reference taps.
- **`DocxViewConfig.showEndnotes`** (#83, restored per #121): boolean flag (default `true`). Set to `false` to hide the endnotes section and disable inline endnote reference taps.
- `copyWith` now supports `showFootnotes` and `showEndnotes` parameters (previously missing).
- Restored `test/issue_83_notes_config_test.dart` — 10 unit/widget tests covering config defaults, `copyWith` behaviour, and widget generator output.

### Fixed
- The #83 fix above was implemented once already but was accidentally reverted shortly after landing (see #121) — it is re-applied here, unchanged in behavior.

## [1.0.3] - 2026-07-26

### 🐛 Bug Fixes

- **Image/shape sizing was too small** — `DocxImage`/`DocxInlineImage`/`DocxShapeBlock` dimensions are stored in points, but were passed straight through to Flutter's `width`/`height` as if already logical pixels; they're now correctly scaled via `DocxUnits.pointsToPixels` (points × 96/72), matching how the same document renders in Word
- **`DocxUnits.twipsToPixels`** divided by 20 (twips → points) and stopped there instead of continuing on to pixels; fixed to twips → points → pixels (`twips / 20 * 1.333`)
- **List bullets stored as Word's Symbol/Wingdings Private-Use-Area glyphs** (e.g. `U+F0B7`) rendered as a "tofu" box on platforms without that exact font installed; these now fall back to a portable Unicode bullet instead
- **Dotted/dashed paragraph and table borders were invisible** — Flutter's `BorderSide` only supports solid or none, and they were previously mapped to `BorderStyle.none`; they're now drawn solid instead of silently disappearing (the closer of the two approximations)

### 🔧 Improvements

- Bumped `docx_creator` dependency to `1.3.0`

### 🧪 Tests

- Added `test/rendering_accuracy_fixes_test.dart` — covers the twips/points → pixel scaling fix (image and shape sizing) and the Private-Use-Area bullet fallback

## [1.0.2] - 2026-05-16

### ✨ New Features

- **First-line indent** (`w:firstLine`) — positive `indentFirstLine` now prepends a zero-height `WidgetSpan` spacer so the first line is indented relative to the paragraph body
- **Hanging indent** (`w:hanging`) — negative `indentFirstLine` values reduce the container left padding to approximate hanging-indent layout
- **Line-rule variants** — `lineRule` values `'exact'` and `'atLeast'` are now handled separately from `'auto'`: `exact` clamps the scale to 0.5–10, `atLeast` floors it at 1.0

### 🐛 Bug Fixes

- **Multi-column vertical merge placeholder** — a cell spanning N columns across multiple rows previously produced N separate thin placeholders in continuation rows; it now correctly emits one wide placeholder whose width covers all spanned columns

### 🧪 Tests

- Added `test/parser_test.dart` — 5 unit tests covering the cascade rule, table grid matrix, crash immunity, first-line indent spacer, and line-rule variants
- Added `test/widget_test.dart` — 4 widget tests covering row height `ConstrainedBox`, multi-column vMerge placeholder child count, search highlight character ranges, and floating image `Row` layout

### 🔧 Improvements

- Extracted `_resolveLineHeightScale()` helper in `ParagraphBuilder` to centralise line-height logic
- `TableBuilder._buildRow()` now tracks a parallel `skipColSpans` array alongside `skipCounts` to correctly group multi-column vertical merges
- Added `.claude/` and `graphify-out/` to `.gitignore`

## [1.0.1] - 2026-01-07

### 🎉 Stable Release

This release marks the stable 1.0.0 version with a complete architecture overhaul and significant feature improvements.

### ✨ New Features

- **Paged View Mode** - Documents can now be rendered in distinct page blocks (print layout style) in addition to continuous scrolling
- **Content-Aware Pagination** - Smart page breaks based on content height estimation
- **Embedded Font Loading** - Full support for OOXML font embedding with deobfuscation
- **Theme Color Resolution** - Proper handling of theme colors with tint/shade modifiers
- **Drop Cap Support** - Rich drop cap rendering with proper text wrapping
- **Floating Image Layout** - Left/right floating images with text wrap
- **Headers & Footers** - First page, odd/even page header/footer support
- **Footnotes & Endnotes** - Interactive footnote/endnote references with tap-to-view dialog
- **Table Conditional Formatting** - Support for first row, last row, first column, last column, and banded styles
- **Checkbox Support** - Interactive checkbox rendering in documents
- **Shape Rendering** - Basic shape support (rectangles, text boxes)

### 🔧 Improvements

- **Search Navigation** - Auto-scroll to search matches with dynamic alignment
- **Style Resolution** - Full style inheritance from named styles, paragraph, and run properties
- **Color Resolution** - Theme color, tint, and shade calculation
- **Border Rendering** - Complete border support for paragraphs and tables
- **Performance** - Optimized widget generation for large documents

### 🏗️ Architecture

- Migrated to modular builder pattern (`ParagraphBuilder`, `TableBuilder`, `ListBuilder`, etc.)
- Introduced `DocxWidgetGenerator` as the central rendering engine
- Added `DocxViewTheme` for comprehensive theming support
- Added `DocxSearchController` for programmatic search control
- Added `BlockIndexCounter` for search indexing

---

## [0.0.8]

### Fixed

- Bullet alignment improved
- Heading styles corrected

---

## [0.0.7]

### Added

- Text alignment from styles now parsed
- Background color and borders now parsed for paragraph and text elements

---

## [0.0.6]

### Fixed

- Styles were too much larger than expected
- If color is defined, don't apply default color

---

## [0.0.5]

### Added

- Styles now parsed from file for paragraph and character
- Text alignment now parsed from file

---

## [0.0.4]

### Fixed

- Ordered and unordered lists now render correctly

---

## [0.0.3]

### Fixed

- Resolved an issue where the divider was not being added correctly in the widget

### Breaking Changes

- Removed a static function to facilitate easier addition of new features in the future

---

## [0.0.2]

### Fixed

- Tag-based text not rendered issue resolved

---

## [0.0.1]

### Added

- Initial release