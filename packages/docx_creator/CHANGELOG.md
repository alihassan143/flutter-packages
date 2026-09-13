## 1.3.3

### Changed
- **Bumped `xml` lower bound to 7.0.1** (#122): was pinned to `^6.6.1`.
- Dependency constraints rewritten from caret (`^x.y.z`) to explicit `">=x.y.z <(x+1).0.0"` ranges for every dependency and dev_dependency, and other lower bounds bumped to the latest versions verified against the full test suite: `archive` 4.0.9 → 4.2.0, `image` 4.8.0 → 4.9.2, `html` 0.15.6 → 0.15.7. `dart pub get`, `dart analyze`, and the full `dart test` suite (406 tests) all pass against the new constraints.

## 1.3.2

### Fixed
- **PDF export — text/images overlapping other content**: several independent bugs that could each cause rendered content to overlap or overwrite whatever was drawn after it, all found and fixed together while investigating reports of unreliable PDF output:
  - **Inline images/shapes ignored in line-height**: a line containing an inline image or shape (e.g. a badge icon, a paragraph-level `DocxShape`) advanced the cursor by only a normal text line's height, regardless of how tall the image/shape actually was — so anything drawn after it (remaining lines, the next paragraph, a table) landed on top of it instead of below. Both the renderer's per-line height and `PdfLayoutEngine`'s pagination-time paragraph measurement now account for inline media height.
  - **Font objects written before rendering**: fonts embedded lazily during rendering — most commonly the automatic Unicode fallback font, embedded the first time a character outside WinAnsi (e.g. an emoji) is encountered — were written to the PDF, and added to every page's `/Resources /Font` dictionary, *before* rendering happened, so any such font's object was never actually created and every page's font list had already been finalized without it. The content stream still referenced it via `Tf`, an undefined resource, which viewers handle by substituting a fallback font using the raw character/glyph codes — silently turning readable text using that font into wrong/garbled glyphs. Font objects are now written only after every page has been rendered, once the full set of fonts actually used is known.
  - **Unescaped PDF font names**: a font name containing PDF delimiter characters (the bundled fallback font is named `DejaVu Sans (docx_creator fallback)`, with both spaces and parentheses) was written straight into `/FontName`/`/BaseFont` instead of being hex-escaped per PDF name syntax. `/DejaVuSans(docx_creatorfallback)` parses as the name `/DejaVuSans` followed by a stray literal string, corrupting the rest of that font dictionary — viewers that recover from the resulting parse error typically can't resolve the font at all, again falling back to raw-code substitution and garbled text (this was the concrete cause behind headings mixing an emoji with plain text, e.g. "✨ Features", rendering as scrambled characters like ") H D W X U H V").
  - **Table cell / paragraph wrapping didn't know about the fallback font**: `PdfExporter` switches an entire text run to the (generally wider) Unicode fallback font if *any* character in that run needs it — not just the fallback-needing character itself. `PdfLayoutEngine`'s line-wrap measurement, however, concatenated every run into one plain-text buffer before wrapping, discarding run boundaries, and always measured with plain standard-font metrics — undercounting the width of plain-ASCII words that share a run with e.g. an emoji, wrapping fewer lines than the renderer actually produces. The extra rendered line then spilled past the row/paragraph's reserved height into whatever was drawn next (most visible in tables with an emoji/icon prefix in a cell alongside longer text).
- **`ImageResolver` no longer embeds non-decodable "image" bytes**: a source that isn't actually a real raster image once fetched/decoded (e.g. an SVG — shields.io-style badges are a common real case — or an HTML error page returned instead of the expected image) is now rejected (`resolve` returns `null`, so callers fall back to their normal text placeholder) instead of being passed through under a guessed extension. Previously such bytes reached the PDF writer's raw-bytes-as-pixel-buffer fallback path, which has no relation between the declared image size and the actual byte count, and rendered as a block of solid garbage overlapping whatever content followed it.

## 1.3.1

### Docs
- Added a link to the live [Showcase demo](https://alihassan143.github.io/flutter-packages/) — a web app exercising the Builder API, HTML/Markdown parsers, DOCX/PDF readers, and every export format side by side.

## 1.3.0

### Added
- **`MarkdownExporter`** (DOCX → Markdown): the missing reverse direction of `MarkdownParser`. Covers headings, inline formatting (bold/italic/strikethrough/inline code/links/superscript/subscript/underline/highlight), fenced code blocks, blockquotes, horizontal rules, nested bullet/numbered/task lists, tables, inline/block images (as data URIs), and footnote/endnote references with trailing definitions.
- **PDF export — automatic Unicode fallback font**: text using a script a standard PDF font can't render (Cyrillic, Greek, Vietnamese, and other scripts covered by DejaVu Sans) now renders correctly by default instead of silently vanishing or showing `?`. The exporter bundles DejaVu Sans (Bitstream Vera License, embeddable/redistributable — see `lib/src/exporters/pdf/fonts/DEJAVU_SANS_LICENSE.txt`) and lazily embeds it only when actually needed, with zero network or filesystem access so it works identically on web. An explicit `addFont()`/`fontFamily` request always takes priority. Does not cover CJK or Arabic, which need dedicated, much larger, shaping-aware fonts — use `addFont()` for those.

### Fixed
- **HTML parser — table row/cell colors** (#100): background/text color parsing only matched literal 6-digit hex; named colors (`lightgreen`), `rgb()`, and 3-digit hex now work, `<tr style="...">` is now read (previously only `<td>`/`<th>` own style was), and `<thead>` rows are now marked `DocxTableRow.isHeader`.
- **HTML parser — whitespace and inline flow** (#101): text nodes are now whitespace-collapsed per normal HTML rules (`<p>Hello\n   World</p>` → "Hello World", not the literal source whitespace); loose inline content next to a block sibling (`<div><p>A</p>loose <span>text</span></div>`) now merges into one paragraph instead of splitting into several.
- **HTML parser — CSS value parsing** (#102): `font-size` now converts px/em/rem/% to points instead of taking the raw number as points; style-keyword matching (`font-weight`/`font-style`/`text-decoration`/`text-align`) is now case- and whitespace-insensitive; `font-weight: 600`–`900` is now treated as bold; `hsl()`/`hsla()` colors are supported; grouped selectors (`.foo, .bar { ... }`) apply to every class in the group; `margin`/`padding`/`text-indent` now map to paragraph/cell indentation.
- **HTML parser — lists and definition lists** (#103): `<ol start="n">` is now honored; nested `<ul>`/`<ol>` are stamped with an override style reflecting their own type when flattened into the parent; `<dl>`/`<dt>`/`<dd>` now render as a bold-term paragraph plus an indented definition instead of garbling into one run of concatenated text.
- **Markdown parser — table alignment** (#104): column alignment (`:---`, `:---:`, `---:`) is now applied; previously parsed by `package:markdown` but never read, so every column rendered left-aligned. Also fixed in the same pass: computed row `isHeader` was never actually passed to `DocxTableRow`.
- **Markdown parser — list structure** (#105): ordered list start numbers (`5. Five`) are now preserved; a loose list item with multiple paragraphs stays one logical item instead of splitting into one entry per paragraph; nested sublists get the same type-preserving override style as the HTML parser fix above.
- **PDF export — Unicode text loss**: `PdfFontManager`/`EmbeddedFont` iterated UTF-16 code units instead of Unicode code points, so any character outside the Basic Multilingual Plane (most emoji, some rare CJK) was split into two invalid glyph lookups even on the embedded-font path (#106).
- **PDF export — shape pagination**: `DocxShapeBlock` had no measurement case and used a fixed ~18pt estimate while rendering at its real (possibly much taller) height, so pagination could judge a tall shape as fitting near a page bottom and then draw past the margin (#107, partial).
- **PDF export — nested list numbering**: a nested list inside a table cell continued its parent's numbering instead of restarting at 1 per level (#107).
- **PDF export — long words/URLs overflowing the margin** (#107): a single word or URL wider than the available line width was never broken and drew straight past the right margin; it's now split across lines like any other overflow, in paragraphs, headings, table cells, list items, and drop caps. Pagination's line-count estimates were updated to match, so page breaks stay correctly positioned.
- **`HtmlExporter` (DOCX → HTML) — missing node types** (#108): `DocxShapeBlock`, `DocxDropCap`, `DocxSectionBreakBlock`, `DocxTableOfContents`, and `DocxRawXml` were silently dropped from the output entirely — worst case, a drop-cap paragraph lost its actual text, not just its styling. All now render (or, for constructs with no HTML equivalent, are marked with an HTML comment instead of vanishing without a trace). `DocxCheckbox`, `DocxFootnoteRef`, and `DocxEndnoteRef` are now handled at the inline level, with footnote/endnote content rendered in a trailing linked "notes" section.

### Changed
- Dependency lower bounds bumped to versions verified against the full test suite: `markdown` ^7.3.0 → ^7.3.1, `uuid` ^4.5.3 → ^4.6.0, `equatable` ^2.0.8 → ^2.1.0, `test` ^1.30.0 → ^1.31.2 (dev). `xml`/`image` were left on their current major versions pending a compatibility review of their next major releases.

---

## 1.2.8

### Fixed
- **`DocxTableCell.marginLeft`/`marginRight` now generate `w:tcMar`** (#98): previously stored on the AST but never written to the cell's XML.
- **Theme color/fill round-tripping**: `DocxText.themeColor/themeTint/themeShade` are now written to `w:color`; `DocxParagraph.themeFill/themeFillTint/themeFillShade` are now written to `w:shd` (both were silently dropped on export). Extracted a shared `writeShading`/`writeTextColor` helper (`core/xml_extension.dart`) used by `DocxText`, `DocxParagraph`, and `DocxTableCell` so this class of bug can't reoccur independently in each class.
- **`DocxSectionDef.breakType`** (continuous/evenPage/oddPage) is now written as `w:type` on section breaks; previously every break behaved as `nextPage` regardless of the setting.
- **`DocxTableCell.copyWith`/`DocxTableStyle.copyWith`** no longer silently drop `themeFill*`, `cnfStyle`, `cellPadding`, and `borderWidth` when copying.
- **`DocxListStyle` theme color/font** are now applied when generating custom bullet/number `numbering.xml` definitions.
- **DOCX reader round-trip gaps**: `w:tcMar`, image `a:ln` borders, standalone-paragraph `w:cnfStyle`, and table-wide `w:tblCellMar` are now parsed back into the AST (previously write-only).
- **PDF export — headers/footers**: `DocxHeader`/`DocxFooter` content was never rendered at all; now renders.
- **PDF export — tables**: complete rewrite of table rendering. `colSpan`/`rowSpan` are now honored (previously ignored, causing misaligned/overlapping cells); real column widths are used instead of an even split; per-cell/table borders and `DocxTableStyle.plain` (no border) are respected instead of always drawing black gridlines; nested lists/tables inside cells now render instead of leaving a blank gap; tables taller than one page now split across pages instead of drawing past the bottom margin.
- **PDF export — pagination**: `DocxParagraph.pageBreakBefore` is now honored; paragraph height calculation now accounts for per-run custom font sizes and `spacingBefore`/`spacingAfter`/padding, fixing text overlap at page boundaries.
- **PDF export — paragraphs**: `indentRight` is now applied; paragraph borders (e.g. `<hr>`, blockquote rules) are now actually drawn instead of only affecting spacing.
- **PDF export — images**: `DocxImage.align` (center/right) is now honored instead of always rendering flush-left; inline `DocxInlineImage`s inside paragraph runs are no longer silently dropped.
- **PDF export — hyperlinks**: `DocxText.href` now produces a real clickable `/Annot /Link` instead of just styled text.
- **PDF export — drop caps**: `DocxDropCap` letter and following text no longer vanish.
- **PDF export — table of contents**: `DocxTableOfContents.cachedContent` now renders instead of vanishing.
- **PDF export — embedded fonts**: the CIDFontType2 `/W` glyph-width array is now emitted (was previously omitted, so every glyph fell back to a single default width and text spacing was garbled); the `ToUnicode` CMap now correctly maps glyph ID → Unicode instead of Unicode → Unicode, fixing copy/paste and text search; `Helvetica-Bold` now declares its own (wider) `/Widths` array instead of reusing the regular Helvetica table; custom registered fonts now apply inside table cells and list items, not just body paragraphs.
- **PDF export — file size**: fonts (including embedded TTF bytes) are now written once per document instead of once per section.
- **PDF export — image corruption (all images)**: JPEG image XObjects were built as a Dart `String` via `String.fromCharCodes`, which then went through `utf8.encode()` at final PDF serialization — silently corrupting any raw byte >= 0x80 and desyncing the declared `/Length` from what was actually written. Every image embedded via the JPEG/DCTDecode path was corrupted in the output file; fixed by building the object as raw bytes instead. Non-JPEG images (PNG/GIF/BMP/etc.) were also wrapped directly in `/FlateDecode` as if the original *container* file bytes were already-decoded raw pixels, which does not produce valid image data in any real viewer — they're now decoded and re-embedded as JPEG through the (now-correct) DCTDecode path. Declared `/Width`/`/Height` are now the image's real pixel dimensions instead of its on-page point size.
- **PDF export — footnotes**: `DocxFootnoteRef`/`doc.footnotes` are now rendered at the bottom of the page, above the footer, with pagination reserving the vertical space each page's referenced footnotes need so body content can't overlap them.
- **PDF export — section background**: `DocxSectionDef.backgroundColor` and `.backgroundImage` (stretch/fit/center/tile fill modes, with opacity via a new `/ExtGState` alpha resource) are now painted per page instead of being silently ignored.
- **PDF export — image borders**: `DocxImage.border`/`DocxInlineImage.border` are now drawn in PDF (previously written to DOCX only), for both block-level images and inline images inside paragraph runs.
- **PDF export — inline shapes**: an inline `DocxShape` inside a paragraph run is now rendered instead of being silently dropped (only block-level `DocxShapeBlock` rendered before).
- **PDF export — endnotes**: `doc.endnotes` are now rendered on a trailing "Endnotes" page (previously never rendered in PDF at all), and `DocxFootnoteRef`/`DocxEndnoteRef` now draw a visible superscript reference marker in the body text at the citation point (previously footnote/endnote content was found by scanning paragraph children directly, with no marker shown where the citation actually was).
- **PDF export — drop caps now wrap around**: `DocxDropCap`'s rest-of-paragraph text flows through a narrower column beside the large letter for its `lines` span, then returns to full paragraph width, instead of the previous approach of concatenating the letter and all following text into one paragraph at the letter's oversized font. `PdfLayoutEngine.measureNode`'s `DocxDropCap` case now accounts for the rest-of-paragraph text length (previously estimated only from the letter's own font size), so pagination stays in sync with what's actually drawn.
- **PDF export — footnotes referenced from a drop cap**: a `DocxFootnoteRef` inside a `DocxDropCap.restOfParagraph` is now detected by pagination's footnote scan; previously it only looked at top-level `DocxParagraph` children, so a footnote cited from within a drop cap got no reserved space and its content silently never rendered (the reference marker still drew).

### Removed
- Deleted `lib/src/parsers/html_parser_backup.dart`, a 1,261-line unreferenced duplicate of the HTML parser superseded by the split `parsers/html/*` modules.

### Added
- `test/ast_field_completeness_test.dart` and `test/pdf_table_rendering_test.dart` covering the fixes above.
- Further `test/pdf_table_rendering_test.dart` coverage for endnotes (trailing page, no-endnotes no-op), drop cap wrap-around (narrow-then-full-width line positions), and the drop-cap/footnote interaction bug above; `test/pdf_pagination_test.dart` coverage for the `DocxDropCap` height estimate scaling with text length.
- `PdfExporter.convertDocxFileToPdfBytes(docxFilePath)`: a static convenience wrapper around `DocxReader.load` + `exportToBytes` for converting an existing `.docx` file straight to PDF bytes in one call.

---

## 1.2.7

### Fixed
- **Invisible footer table borders**: `DocxFooter.imageAndText` now correctly sets `size: 0` and `color: DocxColor.white` on the `borderNone` constant so table borders are truly invisible. Previously the `DocxBorderSide` defaults (`size=4`, `color=black`) were used, producing a 0.5pt black border.

---

## 1.2.6

### Fixed
- **Hyperlinks now generate clickable links** (#95): `DocxText.link` and the `href` parameter on `DocxText` were previously ignored during export. The generated XML now wraps the run in a `w:hyperlink` element with a proper relationship ID, and the corresponding `TargetMode=External` entry is added to `word/_rels/document.xml.rels`. All `const` constructors are preserved.
- **DocxListStyle is now fully respected** (#94): `DocxListItem.buildXmlWithStyle` previously ignored the `style` parameter entirely. Custom bullet characters, number formats (lowerAlpha, upperRoman, etc.), indentation, and font/color properties are now applied. Non-default styles receive their own `abstractNum` definition in `numbering.xml`, and each list item's `w:ind` reflects the effective `indentPerLevel` and `hangingIndent` from the style or per-item `overrideStyle`.

### Added
- **14 unit tests** covering hyperlink XML generation, relationship deduplication, and list style application (`test/issues_95_94_83_test.dart`).

---

## 1.2.5

### Fixed
- **Standardized Footer/Header Image Rendering**: Fixed a critical issue where images in footers and headers were invisible in Microsoft Word due to missing DrawingML attributes and namespace discrepancies.
  - Added mandatory `distT`, `distB`, `distL`, and `distR` attributes to `wp:inline`.
  - Added `wp:effectExtent` element for proper boundary calculation.
  - Synchronized `xmlns:mc`, `xmlns:w14`, and `xmlns:wp14` namespaces across all header and footer generators.
- **Table-based Footer Layout**: Added `DocxFooter.imageAndText` factory for easier creation of professional footer layouts with images and text.

### Added
- **Global Image Rendering Tests**: Added `test/footer_global_fix_test.dart` to verify OOXML compliance of image generation without workarounds.

---

## 1.2.4

### Fixed
- **Images Not Showing in MS Word**: Fixed critical issue where images in body, headers, and footers would render in LibreOffice but not in Microsoft Word (#90).
  - Added required `wp:cNvGraphicFramePr` element (with `a:graphicFrameLocks noChangeAspect="1"`) to both inline (`wp:inline`) and floating (`wp:anchor`) image drawings, as mandated by the OOXML specification.
  - Added missing `xmlns:a` (DrawingML) and `xmlns:pic` (Picture) namespace declarations to header and footer XML files, which are separate documents from `document.xml` and require their own namespace bindings.

### Added
- **MS Word Compatibility Tests**: Added 8 comprehensive tests (`image_ms_word_compat_test.dart`) that generate DOCX files, extract the ZIP, and verify XML structure for MS Word compatibility — including `wp:cNvGraphicFramePr` presence, namespace declarations, `.rels` files, media inclusion, and content type registration.

---

## 1.2.3

### Fixed
- **Invalid Path Decoding**: Added try-catch around `Uri.decodeFull` in `FileLoaderImpl` to prevent crashes when encountering invalid percent-encoded sequences (like a literal `%`) in file paths, especially on Windows (#89).
- **Zip Encoding Validation**: Added null/empty check for ZIP encoding results in `DocxExporter` to ensure document integrity (#85).

### Added
- **Custom Section Margins**: Added support for `marginTop`, `marginBottom`, `marginLeft`, and `marginRight` parameters in `DocxDocumentBuilder.section()`, allowing precise page layout control (#88).
- **AI Context**: Added `llm.txt` to the package root to provide better context for AI agents working with this codebase.

### Improved
- **Path Handling**: Enhanced `FileLoaderImpl` to correctly handle encoded file paths for local images (#77).

---

## 1.2.2

### Fixed
- **HTML image sizing**: `HtmlImageParser` now honors CSS-declared sizes (`<img style="width: 600px; height: 400px">`), converts pixel-valued `width`/`height` attributes to DOCX points via the 72/96 DPI ratio, and falls back to the intrinsic pixel size of the decoded image when no HTML-level sizing is present (#86).
- **Oversized images clipping the page**: `ImageResolver` now caps the final width at ~451 pt (the printable content width of an A4/Letter page with 1" side margins) preserving aspect ratio, so large source images stay inside the text frame.

---

## 1.2.1

### Added
- **Modular DOCX Generator Architecture**: Refactored the monolithic `DocxExporter` into specialized generator classes (`DocumentGenerator`, `StylesGenerator`, `RelationshipsGenerator`, etc.) for improved maintainability and extensibility.

### Fixed
- **Table Widths**: Corrected `w:tcW` (table cell width) generation when `gridColumns` are specified, ensuring accurate table layouts in Microsoft Word (#82).
- **Footer Images**: Fixed issue where images in footers were not rendering in Word due to missing relationship (`.rels`) files (#80).
- **Table Width Calculation**: Improved logic for calculating automatic column widths for better visual fidelity.

---

## 1.2.0

### Added
- **Multiple Text Decorations**: Added support for combining multiple text decorations (e.g., Bold + Underline + Strikethrough) on a single `DocxText` node.
- **Improved Decoration API**: Updated `DocxText` to use a `decorations` list, while maintaining backward compatibility with `isUnderline` and `isStrike` getters.

### Fixed
- **Heading Parsing**: Resolved an issue in `HtmlBlockParser` where nested elements (like `<b>` or `<i>`) inside heading tags (`h1`-`h6`) were being lost during HTML parsing.
- **Reader Compatibility**: Updated `DocxReader` and `PdfReader` to support multiple decorations.

---

## 1.1.9

### Fixed
- **Image Borders**: Corrected XML element order (`a:prstGeom` before `a:ln`) in `DocxInlineImage` to ensure borders are properly rendered in Microsoft Word.
- **Paragraph Alignment**: Fixed issue where left-aligned paragraphs in table cells incorrectly inherited table styles by always emitting explicit justification tags (`w:jc`).
- **Paragraph Padding**: Fixed unwanted horizontal lines appearing when using `paddingTop` or `paddingBottom` by defaulting to invisible `nil` borders (#70).

### Improved
- **Alignment Mapping**: Updated `DocxAlign` to use modern `start` and `end` values for better compatibility and RTL support.

---

## 1.1.8

### Fixed
- **Vertical Text Alignment**: Added support for vertical text alignment via `DocxTextAlignment` enum and `textAlignment` property in `DocxParagraph` and related factory methods (#72).
- **Header Visibility**: Fixed issue where custom headers were only visible on the first page by defaulting `headerReference` to `w:type="default"` (#73).
- **Table Row Height Enforcement**: Ensured strict matching of custom table row heights by adding `w:hRule="exact"` to the generated `w:trHeight` tag (#74).

---

## 1.1.7

### Fixed
- **Paragraph Justification**: Fixed critical issue where `DocxAlign.justify` caused document corruption by incorrectly mapping to `w:val="justify"`. Now correctly maps to `w:val="both"`.

### Added
- **Image Borders**: Added support for image outlines (Simple Frame) via the `border` parameter in `DocxImage` and `DocxInlineImage`.
- **Regression Tests**: Added `test/justification_and_border_test.dart` to verify alignment mapping and image border generation.

---

## 1.1.6

### Fixed
- **Web Compatibility**: Removed all direct `dart:io` dependencies to enable full Flutter Web support.
  - Replaced `dart:io` `File` usages with platform-agnostic `FileSaver` and `FileLoader` abstractions.
  - Replaced `dart:io` `zlib` compression with `package:archive` for PDF generation and parsing on web.
  - Updated `ImageResolver` to handle file loading via `FileLoader`.

---

## 1.1.4

### Fixed
- **Critical Word Compatibility**: Fixed issue where documents were not opening in Microsoft Word due to incorrect XML tag ordering.
  - Reordered `w:rPr` (run properties) children to strictly follow the OOXML schema (e.g., `rFonts` -> `color` -> `sz`).
  - Reordered `w:tblPr` (table properties) and `w:tcPr` (cell properties) to match schema requirements.
- **Newline Handling**: Fixed issue where newlines in `DocxText` were ignored. Now converts `\n` to `<w:br/>`.
- **Web Support**: Fixed `exportToFile` failure on web platforms.
  - Replaced direct `dart:io` imports with a platform-agnostic `FileSaver` utility.
  - Added proper web implementation using `dart:js_interop` and `package:web`.

---

## 1.1.3

### Fixed
- **DOCX Padding & Backgrounds**: Fixed critical issue where paragraph padding and background colors were ignored by Word.
  - Implemented strict OOXML schema compliance for `w:pPr` element order (`pStyle` -> `numPr` -> `pBdr` -> `shd` -> ...).
  - Fixed internal `w:pBdr` child order (`top` -> `left` -> `bottom` -> `right`) which previously caused border blocks to be invalidated.
  - Corrected `w:space` unit conversion (twips to points) for padding.
- **PDF Background Alignment**: Fixed issue where text rendered outside its background rectangle.
  - Corrected text baseline calculation to standard font metrics (approx. 1em offset) ensuring text sits strictly inside the background box.
- **PDF Rendering Loop**: Fixed bug where multi-line paragraphs were not updating the Y-coordinate correctly during rendering.

### Improved
- **AST Refactoring**: Cleaned up `DocxParagraph` by removing deprecated fields (`borderBottom`) and unifying styling logic.

---

## 1.1.2

### Added
- **PDF Reader Improvements**: Major enhancements for broader PDF compatibility:
  - **XRef Stream Support**: Complete parsing of PDF 1.5+ cross-reference streams with `/W` array, `/Index` array, and proper decompression.
  - **Object Stream Support**: Parse compressed objects stored within object streams (PDF 1.5+).
  - **Fallback Object Scanning**: Automatic object recovery when xref table/stream is corrupted or malformed.
  - **LZW Decoding**: Full implementation of LZWDecode filter for older PDFs.
  - **PNG Image Encoding**: Raw RGB pixel data (from FlateDecode images) is now properly encoded as PNG format for direct use in Flutter.
  - **Improved Font Parsing**: Balanced bracket matching for nested dictionary structures.

- **PDF Exporter Improvements**:
  - **Helvetica-Bold Width Table**: Added complete character width table for Helvetica-Bold with accurate per-character measurements.
  - **Fixed Binary Stream Handling**: Corrected compression corruption issue where binary compressed data was incorrectly converted through String encoding.

### Fixed
- **Bold Text Spacing**: Fixed issue where bold text characters appeared too close together due to inaccurate width calculations using only a 1.05x multiplier instead of proper Helvetica-Bold metrics.
- **Blank PDF Generation**: Fixed blank PDFs caused by binary FlateDecode stream data being corrupted during intermediate String conversions.
- **Image Extraction**: Fixed image extraction returning raw RGB bytes instead of usable image format. Images are now properly encoded as PNG.

### Improved
- **PdfDocument Documentation**: Enhanced documentation explaining the purpose of both `elements` and `images` lists.
- **Error Handling**: Better error recovery during PDF parsing with informative warnings.

---

## 1.1.1

### Fixed
- **Code Cleanup**: Removed unused optional parameters (`isStrikethrough`, `isUnderline`) in PDF reader classes to fix analyzer warnings.
- **Internal Optimization**: Improved code quality in `pdf_classes.dart` by removing unused fields.

---

## 1.1.0

### Added
- **PDF Export**: New `PdfExporter` class for exporting documents directly to PDF format.
  - Pure Dart implementation with no native dependencies
  - Supports text formatting (bold, italic, underline, strikethrough)
  - Per-character font metrics for accurate text measurement (Helvetica)
  - Bold font width scaling (1.05x) for proper heading layout
  - Superscript and subscript support with proper positioning
  - Custom font sizes with per-line height calculation
  - Background colors for paragraphs and inline text
  - Table rendering with cell backgrounds and borders
  - List rendering (bullet and numbered)
  - Image embedding (PNG format)
  - Multi-page support with configurable page sizes (Letter, A4)
  - Text alignment (left, center, right, justify)

### Example
```dart
import 'package:docx_creator/docx_creator.dart';

final doc = docx().h1('Title').p('Content').build();
await PdfExporter().exportToFile(doc, 'output.pdf');
```

---

## 1.0.9

### Fixed
- **Table Border Fidelity**: Fixed critical issues with conditional table borders (first row, last row, first column, last column, banding) not being correctly applied or inherited.
  - Resolved conflicts between cell-level borders, table-level borders, and named style borders.
  - Ensures correct visual rendering of complex table styles like "Grid Table 4 - Accent 1".
- **Table Color Resolution**: Fixed logic where 'auto' colors in tables were not correctly resolving to black/transparent based on context.
- **Fallback Logic**: Improved fallback logic for table borders when specific side borders are undefined.

### Improved
- **High-Fidelity Round-Trip**: Enhanced the preservation of table style properties during read/write cycles.

---

## 1.0.8

### Fixed
- **Advanced Style Inheritance**: Implemented proper `docDefaults` resolution for paragraph and run properties.
- **Table Text Styling**: Fixed text styling in tables to respect paragraph-level run properties (`w:rPr`).

### Added
- **Theme Color Support**: Added support for `themeColor`, `themeTint`, and `themeShade` in text and styling.
- **Character Spacing**: Added support for parsing `w:spacing` in run properties.

---

## 1.0.7

### Fixed
- **Table Row Heights**: Fixed missing `w:trHeight` parsing and export. Calendar tables and other tables with explicit row heights now preserve their dimensions.
- **Table Overlap**: Added parsing and export for `w:tblOverlap` attribute on floating tables.
- **Embedded Font Variants**: Fixed font reading to parse all font embed types (`w:embedRegular`, `w:embedBold`, `w:embedItalic`, `w:embedBoldItalic`) instead of only Regular. This fixes missing font files during round-trip.
- **Table Border Export**: Tables with a `styleId` (e.g., "Calendar3", "LightList-Accent3") no longer emit explicit `<w:tblBorders>` that was incorrectly overriding the named style definition.
- **Text Style Inheritance**: Fixed inline parser to only emit **direct** run properties (color, font size, fonts), not inherited ones from styles. This allows table cell text to properly inherit styling from table styles via `cnfStyle` conditional formatting.

---

## 1.0.6

### Fixed
- **Table Style Fidelity**: Fixed critical issue where table cell borders defined in Named Table Styles (via `w:tblStylePr`) were ignored.
  - Updated `DocxStyle` parser to correctly extract `w:tcBorders` from table style conditionals.
  - Fixed logic to properly prioritize table style borders when paragraph borders are absent.

## 1.0.5

### Fixed
- **Font Fidelity**: Fixed critical issue where embedded fonts were lost during the read-export cycle due to mismatched relationship IDs and filenames.
  - Preserved exact filenames and relationship IDs from the original document.
  - Updated `fontTable.xml.rels` handling to ensure valid links to embedded font files.
- **Line Spacing Fidelity**: Fixed issue where specific line spacing rules (e.g., 'Exactly' vs 'At Least') were ignored.
  - Added support for parsing and exporting `w:lineRule` attribute in paragraphs and styles.
  - Ensures visual vertical spacing matches the original document precisely.
- **Style Inheritance**: Fixed issue where paragraph styles (like 'Heading 1') were lost on export.
  - Added parsing for `w:pStyle` property in `DocxStyle` and `DocxParagraph`.
- **Inline Font Merging**: Fixed logic where direct font formatting (e.g., hints) completely overwrote character style fonts.
  - Implemented proper merging of direct font properties with underlying character style fonts.
- **Theme Support**: Added parsing for theme-related font attributes (`w:asciiTheme`, `w:eastAsiaTheme`, etc.) to preserve theme-based font selection.

## 1.0.4

### Added
- **Table Style Resolver**: Added full support for Named Table Styles (`w:tblStylePr`) and Conditional Formatting (`w:tblLook`).
  - Supports 'First Row', 'Last Row', 'First Column', 'Last Column', and 'Banded Rows/Columns' formatting.
  - Automatically resolves and "bakes" effective styles (shading, borders, fonts) into table cells for visual fidelity.
- **Floating Images**: Added parser support for floating images with precise positioning.
  - Supports `wp:anchor` parsing.
  - Handles `relativeFrom` (margin, page, column) and alignment attributes.
- **Drop Caps**: Added support for Drop Caps (`w:dropCap`) in paragraphs.
- **Footnotes & Endnotes**: Added comprehensive support for parsing and exporting Footnotes and Endnotes.
- **Text Borders**: Added support for parsing text borders (`w:bdr`).

### Fixed
- **Table Styles**: Fixed issue where table styles were not correctly applied to cells during parsing.
- **Attribute Export**: Fixed invalid hex color format (removed `#` prefix) in `w:fill` attribute generation to ensure compatibility with Microsoft Word.
- **Cell Copying**: Fixed `DocxTableCell.copyWith` bug that caused style properties to be lost when modifying table cells.

---

## 1.0.3

### Improved
- **Modular DocxReader Architecture**: Refactored 1797-line monolithic `docx_reader.dart` into 11 focused modules:
  - `reader_context.dart` - Shared state manager
  - `parsers/style_parser.dart` - Style resolution
  - `parsers/block_parser.dart` - Paragraph/list parsing
  - `parsers/inline_parser.dart` - Text/image/shape parsing
  - `parsers/table_parser.dart` - Table/rowspan handling
  - `parsers/section_parser.dart` - Headers/footers/sections
  - `handlers/relationship_manager.dart` - OOXML relationships
  - `handlers/font_reader.dart` - Embedded font extraction
- **Modular HTML Parser Architecture**: Refactored 1259-line `html_parser.dart` into 8 modules:
  - `html/parser_context.dart` - CSS class map & shared state
  - `html/style_context.dart` - Style inheritance context
  - `html/color_utils.dart` - 141 CSS named colors
  - `html/block_parser.dart` - Block elements
  - `html/inline_parser.dart` - Inline elements
  - `html/table_parser.dart` - Tables with nested support
  - `html/list_parser.dart` - Ordered/unordered lists
  - `html/image_parser.dart` - Image elements

### Fixed
- **UTF-8 Encoding**: Fixed XML content parsing to use proper UTF-8 decoding in DocxReader
- **Shape Parsing**: Restored full shape dimension/color/preset parsing in refactored reader
- **Nested Table Support**: HTML parser now correctly handles tables inside table cells
- **Background Inheritance**: Fixed `resetBackground()` to properly clear nullable `shadingFill` values

---

## 1.0.2

### Added
- **DrawingML Shapes**: Full support for 70+ preset shapes (rectangles, ellipses, stars, arrows, flowchart symbols, etc.)
  - Block-level shapes (`DocxShapeBlock`) and inline shapes (`DocxShape`)
  - Fill colors, outline colors, and outline widths
  - Text content inside shapes
  - Rotation support
  - Floating and inline positioning
- **Shape Reader Support**: Shapes are now preserved when reading existing DOCX files
- **141 CSS Named Colors**: Full W3C CSS3 Extended Color Keywords support in HTML parser
  - All grey/gray spelling variations supported
  - Includes colors like `dodgerblue`, `mediumvioletred`, `papayawhip`, etc.
- **Comprehensive Examples**: Added four complete example files:
  - `manual_builder_example.dart` - All builder API features
  - `html_parser_example.dart` - All HTML/CSS features
  - `markdown_parser_example.dart` - All Markdown features
  - `reader_editor_example.dart` - Full read-edit-write workflow

### Improved
- **Documentation**: Complete rewrite of README.md and new DOCUMENTATION.md with:
  - Full API reference tables
  - All supported HTML tags and CSS properties
  - Step-by-step DOCX Reader/Editor guide
  - OpenXML internals explanation
  - Troubleshooting section
- **Color Handling**: Improved color class with automatic hex normalization (strips `#` and `0x` prefixes)
- **List Rendering**: Enhanced 9-level nested list support with proper abstract numbering

### Fixed
- **Background Color Inheritance**: Fixed CSS `background-color` incorrectly inheriting to inline children
- **Code Block Visibility**: Fixed text visibility in code blocks when used with background colors

---

## 1.0.1

### Fixed
- **List Rendering**: Fixed numbered and bullet lists not displaying markers in Word when multiple lists appear in the same document.
- **Color Parsing**: Fixed `HtmlParser` color parsing for font colors and background highlights. Now supports:
  - Hex codes (3-digit and 6-digit)
  - RGB/RGBA formats
  - Extended CSS named colors (including `grey`, `lime`, `maroon`, etc.)
- **Highlight Mapping**: Fixed incorrect default highlight color (no longer defaults to yellow for unknown colors).

### Improved
- **OOXML Compliance**: Updated `numbering.xml` generation to match python-docx patterns for better Word compatibility (`w:nsid`, `w:tmpl`, `w:tabs`).

---

## 1.0.0

- Initial version.
