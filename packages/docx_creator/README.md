# docx_creator

[![pub package](https://img.shields.io/pub/v/docx_creator.svg)](https://pub.dev/packages/docx_creator)
[![Dart SDK](https://img.shields.io/badge/Dart-%3E%3D2.19.0-blue)](https://dart.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A **developer-first DOCX generation library** for Dart. Create, parse, read, and edit Microsoft Word documents with a fluent API, HTML/Markdown parsers, and full OpenXML compliance.

🔗 **[Live Demo / Showcase](https://alihassan143.github.io/flutter-packages/)** — try the Builder API, HTML/Markdown parsers, DOCX/PDF readers, and every export format right in your browser.

## ✨ Features

| Feature                        | Description                                                |
| ------------------------------ | ---------------------------------------------------------- |
| 🔧**Fluent Builder API** | Chain methods to create documents quickly                  |
| 🌐**HTML Parser**        | Convert HTML to DOCX with 141 CSS named colors             |
| 📝**Markdown Parser**    | Parse Markdown including tables and nested lists           |
| 📖**DOCX Reader**        | Load and edit existing .docx files                         |
| 📕**PDF Reader**         | Parse PDF files to DOCX structure                          |
| 📄**PDF Export**         | Export documents directly to PDF (pure Dart), with an automatic Unicode fallback font |
| ⬇️**Markdown Export**    | Export documents directly to Markdown (GFM)                |
| 🌍**HTML Export**        | Export documents directly to HTML                           |
| 🎨**Drawing Shapes**     | 70+ preset shapes (rectangles, arrows, stars, etc.)        |
| 🖼️**Images**           | Embed local, remote, or base64 images (Inline & Floating)  |
| 📊**Tables**             | Styled tables, merged cells, borders, & conditional styles |
| 📋**Lists**              | Bullet, numbered, and nested lists (9 levels)              |
| 🔤**Fonts**              | Embed custom fonts with OOXML obfuscation                  |
| 📄**Sections**           | Headers, footers, page orientation, backgrounds            |
| 📌**Footnotes**          | Full support for footnotes and endnotes                    |
| 🧢**Drop Caps**          | Stylized drop caps for paragraph beginnings                |
| 🎨**Theme Support**      | Theme colors, tints, shades, and font themes               |
| 🧬**Advanced Styling**   | Proper inheritance from docDefaults and style hierarchy    |
| 🤖**AI-Ready**           | Optimized for AI agents with[llm.txt](llm.txt) context        |

---

## 📋 What's Actually Supported: DOCX vs. PDF

`docx_creator` builds one internal document model (the `DocxNode` AST) and can export it to either **DOCX** (via `DocxExporter`, full OpenXML) or **PDF** (via `PdfExporter`, a from-scratch pure-Dart writer — no native/system dependencies). They don't have identical capabilities: DOCX export is the primary, feature-complete target; PDF export covers the vast majority of the same model but has a short list of known gaps, listed explicitly below rather than glossed over.

### Side-by-side

| Feature | DOCX | PDF |
| --- | :---: | :---: |
| Headings, paragraphs, all text runs (bold/italic/underline/strike/double-strike/caps/small-caps/outline/shadow/emboss/imprint) | ✅ | ✅ |
| Custom font size, character spacing, superscript/subscript | ✅ | ✅ |
| Text color & highlight/shading (hex) | ✅ | ✅ |
| Theme color/tint/shade (text and shading) | ✅ | ⚠️ resolved to its literal hex where set; PDF has no OOXML theme palette to resolve `accent1` etc. against |
| Custom/embedded fonts (TTF) | ✅ (OOXML-obfuscated) | ✅ (embedded with correct glyph widths & ToUnicode; used in paragraphs, table cells, and lists) |
| Paragraph alignment (left/center/right/justify) | ✅ | ✅ |
| Paragraph spacing, line spacing (auto/exact/atLeast), left/right/first-line indent, padding | ✅ | ✅ |
| Paragraph borders (incl. `<hr>`, blockquote rules) | ✅ | ✅ (actually drawn, not just spaced) |
| `pageBreakBefore` | ✅ | ✅ |
| Bullet/numbered lists, 9 levels, nested, custom bullets/formats, image bullets | ✅ | ✅ per-level bullets/number formats matching the DOCX numbering, also inside table cells; lists split across pages; image bullets render as the default bullet |
| Tables: merged cells (colSpan/rowSpan) | ✅ | ✅ (correct grid placement, no overlap; a tall rowSpan cell spreads its extra height over every row it covers, like a browser) |
| Tables: per-cell/table borders, incl. "no border" styles | ✅ | ✅ |
| Tables: real column widths | ✅ | ✅ |
| Tables: cell shading, margins (all four sides), vertical alignment, conditional formatting | ✅ | ✅ shading, margins and vertical alignment; cnfStyle not visually distinct in PDF |
| Tables: nested tables/lists inside cells | ✅ | ✅ |
| Tables spanning multiple pages | N/A (Word reflows natively) | ✅ splits by row automatically; header rows repeat on every page and are never left alone at the bottom of one |
| Images: inline & floating, wrapping, alignment | ✅ | ✅ (floating-specific wrap/z-order collapses to normal inline flow in PDF) |
| Image formats | PNG/JPEG/GIF/BMP as provided | ✅ PNG/GIF/BMP/etc. decoded & re-embedded as JPEG; JPEG passthrough |
| Image borders | ✅ | ✅ drawn for both block-level and inline images |
| Text using non-Latin scripts (Cyrillic, Greek, Vietnamese, etc.) without a custom font | ✅ | ✅ auto-embeds a bundled fallback font (DejaVu Sans) the first time it's needed; CJK/Arabic still need an explicit `addFont()` |
| Drawing shapes (70+ presets), block-level | ✅ | ✅ |
| Drawing shapes, inline (inside a paragraph run) | ✅ | ✅ |
| Hyperlinks | ✅ | ✅ real clickable `/Annot` links |
| Headers & footers | ✅ | ✅ |
| Section background color/image (stretch/fit/center/tile, opacity) | ✅ | ✅ |
| Multiple sections (independent page size/orientation/margins) | ✅ | ✅ |
| Section break type (continuous/nextPage/evenPage/oddPage) | ✅ | N/A (PDF has no section-break concept) |
| Drop caps | ✅ (true Word text-wrap) | ✅ true wrap-around: following text flows in a narrower column beside the letter |
| Footnotes | ✅ | ✅ rendered at the bottom of the page; space is auto-reserved so body text can't overlap it. Font size matches body text (no automatic downscale) |
| Endnotes | ✅ | ✅ rendered on a trailing "Endnotes" page, with a superscript reference marker at the citation point |
| Table of Contents | ✅ (live field, recalculated by Word) | ⚠️ cached TOC content renders as static text; page numbers aren't recomputed against PDF pagination |
| Checkboxes (☐ ☑ ☒) | ✅ | ✅ |
| Multi-page pagination | N/A | ✅ automatic; paragraphs and tables both split cleanly across pages with no overlap; a nested list inside a table cell numbers correctly per level |
| Long words/URLs wider than the line | N/A | ✅ split across lines like any other overflow, instead of drawing past the margin |
| Raw/unmodeled OOXML passthrough ("Shadow Model") | ✅ | N/A (DOCX-specific fidelity feature) |

**Reading it both ways works too**: `DocxReader` round-trips everything in the DOCX column above — load a `.docx`, every property listed as ✅ comes back onto the AST correctly, not just write-only.

If a gap above matters for your use case, please open an issue — they're tracked, just not implemented yet.

---

## Help Maintenance

I've been maintaining quite many repos these days and burning out slowly. If you could help me cheer up, buying me a cup of coffee will make my life really happy and get much energy out of it.

<a href="https://www.buymeacoffee.com/alihassan13" target="_blank">
  <img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" width="180">
</a>

## 🤖 AI-Agent Friendly

This package includes an **[llm.txt](https://github.com/alihassan143/flutter-packages/tree/main/packages/docx_creator/llm.txt)** file at the root, providing a structured map of the codebase and architectural patterns to help AI coding agents work more effectively and safely.

## 📦 Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  docx_creator: ^1.4.0
```

Then run:

```bash
dart pub get
```

---

## 🚀 Quick Start

### Hello World

```dart
import 'package:docx_creator/docx_creator.dart';

void main() async {
  // Create a simple document
  final doc = docx()
    .h1('Hello, World!')
    .p('This is my first DOCX document.')
    .build();

  // Save to file
  await DocxExporter().exportToFile(doc, 'hello.docx');
}
```

### From HTML

```dart
final htmlContent = '''
<h1>Report Title</h1>
<p>This is a <b>bold</b> and <i>italic</i> paragraph.</p>
<ul>
  <li>Item 1</li>
  <li>Item 2</li>
</ul>
''';

final elements = await DocxParser.fromHtml(htmlContent);
final doc = DocxBuiltDocument(elements: elements);
await DocxExporter().exportToFile(doc, 'from_html.docx');
```

### From Markdown

```dart
final markdown = '''
# Project Report

## Summary
This is **important** information.

- Task 1: Complete
- Task 2: In Progress
''';

final elements = await MarkdownParser.parse(markdown);
final doc = DocxBuiltDocument(elements: elements);
await DocxExporter().exportToFile(doc, 'from_markdown.docx');
```

---

## 📖 Documentation

### Table of Contents

1. [Builder API](#builder-api)
2. [Text Formatting](#text-formatting)
3. [Lists](#lists)
4. [Tables](#tables)
5. [Images](#images)
6. [Shapes &amp; Drawings](#shapes--drawings)
7. [HTML Parser](#html-parser)
8. [Markdown Parser](#markdown-parser)
9. [Markdown Export](#markdown-export)
10. [DOCX Reader &amp; Editor](#docx-reader--editor)
11. [PDF Reader](#pdf-reader)
12. [PDF Export](#pdf-export)
13. [Sections &amp; Page Layout](#sections--page-layout)
14. [Font Embedding](#font-embedding)
15. [API Reference](#api-reference)

---

## PDF Export

Export documents directly to PDF with the `PdfExporter`. This is a pure Dart implementation with no native dependencies.

### Basic Usage

```dart
import 'package:docx_creator/docx_creator.dart';

// Create a document
final doc = docx()
  .h1('PDF Export Demo')
  .p('This document will be exported to PDF.')
  .bullet(['Feature 1', 'Feature 2', 'Feature 3'])
  .build();

// Export to PDF file
await PdfExporter().exportToFile(doc, 'output.pdf');

// Or get as bytes
final pdfBytes = PdfExporter().exportToBytes(doc);
```

### From HTML or Markdown

```dart
// From HTML
final html = '<h1>Title</h1><p>Content with <b>bold</b>.</p>';
final htmlDoc = DocxBuiltDocument(elements: await DocxParser.fromHtml(html));
await PdfExporter().exportToFile(htmlDoc, 'from_html.pdf');

// From Markdown
final md = '# Title\n\nParagraph with **bold**.';
final mdDoc = DocxBuiltDocument(elements: await MarkdownParser.parse(md));
await PdfExporter().exportToFile(mdDoc, 'from_markdown.pdf');
```

### Automatic Unicode Fallback Font

If your text uses a script a standard PDF font can't render — Cyrillic, Greek, Vietnamese, and other scripts covered by [DejaVu Sans](https://dejavu-fonts.github.io) — the exporter automatically embeds a bundled fallback font the first time it's needed, with **zero network or filesystem access** (it works on web too). You don't need to do anything:

```dart
final doc = docx().p('Привет, мир! Γειά σου κόσμε!').build();
await PdfExporter().exportToFile(doc, 'cyrillic_greek.pdf'); // just works
```

An explicit `addFont()` call always takes priority over the fallback. CJK and Arabic scripts need dedicated, much larger, shaping-aware fonts that aren't reasonable to bundle unconditionally — for those, call `addFont()` with a font that covers them.

### Supported Features

| Feature                                          | Support |
| ------------------------------------------------- | ------- |
| Headings (H1-H6)                                   | ✅      |
| Bold/Italic/Underline/Strikethrough                | ✅      |
| Custom font sizes, superscript/subscript           | ✅      |
| Text colors, highlight/background shading          | ✅      |
| Custom embedded fonts (TTF), incl. in tables/lists | ✅      |
| Automatic Unicode fallback font (Cyrillic/Greek/etc.) | ✅   |
| Text alignment (left/center/right/justify)         | ✅      |
| Paragraph spacing/indent/padding/borders           | ✅      |
| Forced page breaks (`pageBreakBefore`)             | ✅      |
| Bullet & numbered lists (nested)                   | ✅      |
| Tables: merged cells (colSpan/rowSpan)              | ✅      |
| Tables: real column widths & per-cell/table borders | ✅      |
| Tables: nested lists/tables in cells               | ✅      |
| Tables spanning multiple pages                     | ✅ auto-splits by row, repeats header rows |
| Long words/URLs wider than the line                | ✅ split across lines |
| Images (PNG/JPEG/GIF/BMP), alignment               | ✅      |
| Inline images inside paragraph text                | ✅      |
| Image borders                                        | ✅      |
| Hyperlinks (clickable)                              | ✅      |
| Headers & footers                                   | ✅      |
| Section background (color/image, opacity)          | ✅      |
| Drop caps                                            | ✅ true wrap-around |
| Footnotes                                            | ✅ auto-reserves page space |
| Endnotes                                             | ✅ trailing page with reference markers |
| Inline shapes (shape inside a paragraph run)       | ✅      |
| Page sizes (A4, Letter)                              | ✅      |
| Multi-page pagination                                | ✅ automatic, no overlap |

See the **"What's Actually Supported: DOCX vs. PDF"** section near the top of this README for the full side-by-side with DOCX.

---

## Builder API

The `DocxDocumentBuilder` provides a fluent interface for document creation:

```dart
final doc = DocxDocumentBuilder()
  // Headings
  .h1('Title')
  .h2('Chapter')
  .h3('Section')
  
  // Paragraphs
  .p('Simple paragraph text')
  .p('Right-aligned', align: DocxAlign.right)
  
  // Lists
  .bullet(['Item 1', 'Item 2', 'Item 3'])
  .numbered(['Step 1', 'Step 2', 'Step 3'])
  
  // Tables
  .table([
    ['Header 1', 'Header 2'],
    ['Cell 1', 'Cell 2'],
  ])
  
  // Special elements
  .pageBreak()
  .hr()  // Horizontal rule
  .quote('Blockquote text')
  .code('print("Hello");')
  
  .build();
```

### Short vs Full Method Names

| Short               | Full                  | Description     |
| ------------------- | --------------------- | --------------- |
| `h1(text)`        | `heading1(text)`    | Heading level 1 |
| `h2(text)`        | `heading2(text)`    | Heading level 2 |
| `h3(text)`        | `heading3(text)`    | Heading level 3 |
| `p(text)`         | `text(content)`     | Paragraph       |
| `bullet(items)`   | `addList(DocxList)` | Bullet list     |
| `numbered(items)` | `addList(DocxList)` | Numbered list   |
| `hr()`            | `divider()`         | Horizontal rule |

---

## Text Formatting

Create rich text with `DocxText` and `DocxParagraph`:

```dart
final doc = DocxDocumentBuilder()
  .add(DocxParagraph(children: [
    // Basic formatting
    DocxText('Bold ', fontWeight: DocxFontWeight.bold),
    DocxText('Italic ', fontStyle: DocxFontStyle.italic),
    DocxText('Underline ', decoration: DocxTextDecoration.underline),
    DocxText('Strikethrough', decoration: DocxTextDecoration.strikethrough),
  
    // Colors
    DocxText('Red text ', color: DocxColor.red),
    DocxText('Custom color ', color: DocxColor('#FF6600')),
    DocxText('With background ', shadingFill: 'FFFF00'),
  
    // Font size
    DocxText('Large text', fontSize: 24),
  
    // Superscript/Subscript
    DocxText('E=mc'),
    DocxText('2', isSuperscript: true),
    DocxText(' H'),
    DocxText('2', isSubscript: true),
    DocxText('O'),
  
    // Highlighting
    DocxText('Highlighted', highlight: DocxHighlight.yellow),
  
    // Hyperlinks
    DocxText('Click here', 
      href: 'https://example.com',
      color: DocxColor.blue,
      decoration: DocxTextDecoration.underline),
  ]))
  
  // Paragraph with specific line spacing
  .add(DocxParagraph(
    children: [DocxText('Exact Spacing')],
    lineSpacing: 240,       // 12 pt
    lineRule: 'exact',      // 'auto', 'exact', 'atLeast'
  ))
  .build();
```

### Available Colors

```dart
// Predefined colors
DocxColor.black, DocxColor.white, DocxColor.red, DocxColor.blue,
DocxColor.green, DocxColor.yellow, DocxColor.orange, DocxColor.purple,
DocxColor.gray, DocxColor.lightGray, DocxColor.darkGray, DocxColor.cyan,
DocxColor.magenta, DocxColor.pink, DocxColor.brown, DocxColor.navy,
DocxColor.teal, DocxColor.lime, DocxColor.gold, DocxColor.silver

// Custom hex colors
DocxColor('#FF5722')
DocxColor('4285F4')  // # is optional
```

---

## Lists

### Simple Lists

```dart
// Bullet list
.bullet(['First item', 'Second item', 'Third item'])

// Numbered list
.numbered(['Step 1', 'Step 2', 'Step 3'])
```

### Nested Lists

```dart
final nestedList = DocxList(
  style: DocxListStyle.disc,
  items: [
    DocxListItem.text('Level 0 - First', level: 0),
    DocxListItem.text('Level 1 - Nested', level: 1),
    DocxListItem.text('Level 2 - Deep', level: 2),
    DocxListItem.text('Level 1 - Back', level: 1),
    DocxListItem.text('Level 0 - Root', level: 0),
  ],
);

docx().add(nestedList).build();
```

### List Styles

```dart
DocxListStyle.disc       // • Solid disc (default)
DocxListStyle.circle     // ◦ Circle
DocxListStyle.square     // ▪ Square
DocxListStyle.dash       // - Dash
DocxListStyle.arrow      // → Arrow
DocxListStyle.check      // ✓ Checkmark
DocxListStyle.decimal    // 1, 2, 3
DocxListStyle.lowerAlpha // a, b, c
DocxListStyle.upperAlpha // A, B, C
DocxListStyle.lowerRoman // i, ii, iii
DocxListStyle.upperRoman // I, II, III
```

---

## Tables

### Simple Table

```dart
.table([
  ['Name', 'Age', 'City'],
  ['Alice', '25', 'New York'],
  ['Bob', '30', 'Los Angeles'],
])
```

### Styled Table

```dart
final styledTable = DocxTable(
  rows: [
    DocxTableRow(cells: [
      DocxTableCell(
        children: [DocxParagraph(children: [
          DocxText('Header', fontWeight: DocxFontWeight.bold, color: DocxColor.white)
        ])],
        shadingFill: '4472C4',  // Blue background
        verticalAlign: DocxVerticalAlign.center,
      ),
      // More cells...
    ], isHeader: true),  // Repeats at the top of every PDF page the table continues on
    // More rows...
  ],
);
```

### Merged Cells and Cell Padding

```dart
DocxTable(
  rows: [
    DocxTableRow(cells: [
      DocxTableCell(
        rowSpan: 2,          // Covers this row and the next
        marginLeft: 144,     // Padding in twips (1/20 pt)
        marginRight: 144,
        marginTop: 100,      // Top padding in twips
        marginBottom: 100,   // Bottom padding in twips
        children: [DocxParagraph.text('Spans two rows')],
      ),
      DocxTableCell.text('Row 1'),
    ]),
    DocxTableRow(cells: [DocxTableCell.text('Row 2')]),
  ],
);
```

- Cell margins are written to `w:tcMar` and read back by `DocxReader`. A table-wide `DocxTableStyle.cellPadding` (`w:tblCellMar`) applies to every cell that has no margins of its own.
- In PDF export, a `rowSpan` cell taller than its rows spreads the extra height across all of them, in proportion to their heights, as browsers do.
- Rows with `isHeader: true` (or the first row of a table with `hasHeader: true`) repeat at the top of each continuation page. They are Word's "repeat as header row" (`w:tblHeader`).

---

## Images

```dart
import 'dart:io';

// From file
final imageBytes = await File('logo.png').readAsBytes();
final doc = docx()
  .add(DocxImage(
    bytes: imageBytes,
    extension: 'png',
    width: 200,
    height: 100,
    align: DocxAlign.center,
  ))
  .build();

// Inline image in paragraph
.add(DocxParagraph(children: [
  DocxText('See image: '),
  DocxInlineImage(bytes: imageBytes, extension: 'png', width: 50, height: 50),
  DocxText(' above.'),
]))
```

---

## Shapes & Drawings

Create DrawingML shapes with 70+ presets:

```dart
// Basic shapes
DocxShapeBlock.rectangle(
  width: 200,
  height: 60,
  fillColor: DocxColor.blue,
  outlineColor: DocxColor.black,
  outlineWidth: 2,
  text: 'Click Me',
  align: DocxAlign.center,
)

DocxShapeBlock.ellipse(width: 100, height: 100, fillColor: DocxColor.green)
DocxShapeBlock.circle(diameter: 80, fillColor: DocxColor.red)
DocxShapeBlock.triangle(width: 100, height: 100, fillColor: DocxColor.yellow)
DocxShapeBlock.star(points: 5, fillColor: DocxColor.gold)
DocxShapeBlock.diamond(width: 80, fillColor: DocxColor.purple)
DocxShapeBlock.rightArrow(width: 100, height: 40, fillColor: DocxColor.blue)
DocxShapeBlock.leftArrow(width: 100, height: 40, fillColor: DocxColor.red)

// Inline shapes in paragraph
.add(DocxParagraph(children: [
  DocxShape.circle(diameter: 30, fillColor: DocxColor.red),
  DocxText(' Red circle '),
  DocxShape.star(points: 5, fillColor: DocxColor.gold),
  DocxText(' Gold star'),
]))
```

### Shape Presets

Over 70 preset shapes including: `rect`, `ellipse`, `triangle`, `diamond`, `star4`, `star5`, `star6`, `rightArrow`, `leftArrow`, `upArrow`, `downArrow`, `heart`, `lightning`, `flowChartProcess`, `flowChartDecision`, and many more.

---

## HTML Parser

### Supported HTML Tags

| Tag                   | Output                 |
| --------------------- | ---------------------- |
| `<h1>` - `<h6>`   | Headings               |
| `<p>`               | Paragraph              |
| `<b>`, `<strong>` | Bold                   |
| `<i>`, `<em>`     | Italic                 |
| `<u>`               | Underline              |
| `<s>`, `<del>`    | Strikethrough          |
| `<mark>`            | Highlight              |
| `<sup>`             | Superscript            |
| `<sub>`             | Subscript              |
| `<a href="">`       | Hyperlink              |
| `<code>`            | Inline code            |
| `<pre>`             | Code block             |
| `<ul>`, `<ol>`    | Lists (`type`, `list-style-type` map to number formats and bullets) |
| `<table>`           | Tables (`colspan`/`rowspan`, `<thead>` header rows, `cellpadding`, `align`/`valign`) |
| `<img>`             | Images                 |
| `<blockquote>`      | Blockquote             |
| `<hr>`              | Horizontal rule        |
| `<br>`              | Line break             |
| `<div>`, `<span>` | Containers with styles |
| `<dl>`, `<dt>`, `<dd>` | Definition list (term + indented definition) |

### Supported CSS Properties

```css
color: red;                    /* Text color: hex, rgb()/rgba(), hsl()/hsla(), or 141 named colors */
color: #FF5722;               /* Hex color */
color: dodgerblue;            /* CSS named color (141 supported) */
color: hsl(210, 80%, 50%);    /* HSL color */
background-color: yellow;      /* Background/shading */
font-size: 16px;              /* Font size: px, pt, em, rem, and % are all converted correctly */
font-weight: bold;            /* Bold (also matches numeric weights 600-900) */
font-style: italic;           /* Italic */
text-align: center;           /* Alignment */
text-decoration: underline;   /* Underline/strikethrough */
margin-left: 20px;            /* Paragraph/cell indentation */
padding-left: 20px;           /* Paragraph/cell indentation */
text-indent: 20px;            /* First-line indentation */
margin-top: 12px;             /* Paragraph spacing before (margin-bottom: after; margin shorthand too) */
line-height: 1.5;             /* Line spacing */
text-transform: uppercase;    /* All caps (font-variant: small-caps for small caps) */
list-style-type: lower-alpha; /* List number format or bullet */
background: #EEE;             /* Shorthand for shading */

/* Table cells */
padding: 4px 8px;             /* Cell padding; 1-4 values, padding-top/-bottom/-left/-right too */
vertical-align: middle;       /* Cell vertical alignment (or the valign attribute) */
```

On `<table>`, the `cellpadding` attribute pads every cell on all four sides unless the cell sets its own padding.

Property matching is case- and whitespace-insensitive (`FONT-WEIGHT:BOLD` works the same as `font-weight: bold`), and grouped selectors (`.foo, .bar { ... }`) apply to every class listed.

### CSS Named Colors

All **141 W3C CSS3 Extended Color Keywords** are supported:

```html
<span style="color: dodgerblue;">DodgerBlue</span>
<span style="color: mediumvioletred;">MediumVioletRed</span>
<span style="color: darkolivegreen;">DarkOliveGreen</span>
<span style="color: papayawhip;">PapayaWhip</span>
```

Including grey/gray variations: `grey`, `darkgrey`, `lightgrey`, etc.

### Example

```dart
final html = '''
<div style="background-color: #f0f0f0; padding: 10px;">
  <h1 style="color: navy;">Report Title</h1>
  <p>This is <span style="color: red; font-weight: bold;">important</span> text.</p>
  <table border="1">
    <tr style="background-color: #4472C4; color: white;">
      <th>Name</th>
      <th>Status</th>
    </tr>
    <tr>
      <td>Task 1</td>
      <td style="background-color: lightgreen;">Complete</td>
    </tr>
  </table>
</div>
''';

final elements = await DocxParser.fromHtml(html);
```

---

## Markdown Parser

### Supported Syntax

| Markdown          | Output          |
| ----------------- | --------------- |
| `# Heading`     | H1-H6           |
| `**bold**`      | Bold            |
| `*italic*`      | Italic          |
| `~~strike~~`    | Strikethrough   |
| `[text](url)`   | Links           |
| `` `code` ``      | Inline code     |
| `` ``` ``         | Code blocks     |
| `- item`        | Bullet list     |
| `1. item`       | Numbered list   |
| `> quote`       | Blockquote      |
| `---`           | Horizontal rule |
| `                 | a               |
| `[ ]` / `[x]` | Task lists      |

### Nested Lists

```markdown
- Level 1
    - Level 2
        - Level 3
    - Level 2
- Level 1
```

Nested lists are automatically converted to multi-level Word lists with proper indentation.

### Tables with Alignment

```markdown
| Left | Center | Right |
|:-----|:------:|------:|
| L    | C      | R     |
```

Column alignment from the `:---`/`:---:`/`---:` delimiter row is applied to each cell.

Ordered lists preserve their start number (`5. Five` starts numbering at 5), and a list item spanning multiple paragraphs (separated by a blank line, indented under the marker) stays one logical item instead of splitting into several.

---

## Markdown Export

Export documents directly to Markdown (GitHub-Flavored Markdown) with `MarkdownExporter` — the reverse direction of the Markdown parser above.

```dart
import 'package:docx_creator/docx_creator.dart';

final doc = docx()
  .h1('Report')
  .p('Body text with **bold** and *italic*.')
  .bullet(['Item 1', 'Item 2'])
  .table([
    ['Name', 'Status'],
    ['Task 1', 'Done'],
  ])
  .build();

final markdown = MarkdownExporter().export(doc);
await MarkdownExporter().exportToFile(doc, 'report.md');
```

### Supported Features

| Feature | Support |
| --- | --- |
| Headings (H1-H6) | ✅ |
| Bold/Italic/Bold+Italic/Strikethrough | ✅ |
| Inline code (CommonMark-correct backtick fencing) | ✅ |
| Links, superscript/subscript/underline (HTML passthrough), highlighted text | ✅ |
| Fenced code blocks, blockquotes, horizontal rules | ✅ |
| Nested bullet/numbered lists, GFM task-list items | ✅ |
| Tables (synthesized header separator row) | ✅ |
| Inline/block images (as data URIs) | ✅ |
| Footnote/endnote references with trailing definitions | ✅ |
| Table cell merges (colSpan/rowSpan) | ⚠️ collapses to a plain cell — Markdown tables have no merge syntax |
| Floating images, drawing shapes, raw OOXML, section breaks, TOC fields | ❌ no Markdown equivalent |

---

## DOCX Reader & Editor

### Loading an Existing Document

```dart
// From file path
final doc = await DocxReader.load('existing.docx');

// From bytes
final bytes = await File('existing.docx').readAsBytes();
final doc = await DocxReader.loadFromBytes(bytes);
```

### Accessing Elements

```dart
for (final element in doc.elements) {
  if (element is DocxParagraph) {
    for (final child in element.children) {
      if (child is DocxText) {
        print('Text: ${child.content}');
        print('Bold: ${child.fontWeight == DocxFontWeight.bold}');
        print('Color: ${child.color?.hex}');
      }
    }
  } else if (element is DocxTable) {
    print('Table with ${element.rows.length} rows');
  } else if (element is DocxList) {
    print('List with ${element.items.length} items');
  }
}
```

### Modifying and Re-Saving

```dart
// Load document
final doc = await DocxReader.load('report.docx');

// Modify elements
final modifiedElements = <DocxNode>[];
for (final element in doc.elements) {
  if (element is DocxParagraph) {
    // Find and replace text
    final newChildren = element.children.map((child) {
      if (child is DocxText) {
        return DocxText(
          child.content.replaceAll('OLD', 'NEW'),
          fontWeight: child.fontWeight,
          color: child.color,
        );
      }
      return child;
    }).toList();
    modifiedElements.add(DocxParagraph(children: newChildren));
  } else {
    modifiedElements.add(element);
  }
}

// Add new content
modifiedElements.add(DocxParagraph.text('Added on: ${DateTime.now()}'));

// Create new document preserving metadata
final editedDoc = DocxBuiltDocument(
  elements: modifiedElements,
  // Preserve original document properties
  section: doc.section,
  stylesXml: doc.stylesXml,
  numberingXml: doc.numberingXml,
);

// Save
await DocxExporter().exportToFile(editedDoc, 'report_edited.docx');
```

### Round-Trip Pipeline

```dart
// Load → Parse → Modify → Export
final original = await DocxReader.load('input.docx');

// All formatting, lists, tables, shapes are preserved
final elements = List<DocxNode>.from(original.elements);

// Add new content
elements.add(DocxParagraph.heading2('New Section'));
elements.add(DocxParagraph.text('Content added programmatically.'));

// Export with preserved metadata
final output = DocxBuiltDocument(
  elements: elements,
  stylesXml: original.stylesXml,
  numberingXml: original.numberingXml,
);

await DocxExporter().exportToFile(output, 'output.docx');
```

---

## PDF Reader

Parse PDF documents and convert them to editable `DocxBuiltDocument` objects. The reader supports a wide variety of PDF formats including legacy and modern PDFs.

### Basic Usage

```dart
// Load PDF from file
final pdf = await PdfReader.load('input.pdf');

// Load from bytes
final bytes = await File('input.pdf').readAsBytes();
final pdf = await PdfReader.loadFromBytes(bytes);

// Convert to DOCX
final doc = pdf.toDocx();
await DocxExporter().exportToFile(doc, 'converted.docx');
```

### Content Extraction

Access extracted elements directly:

```dart
final pdf = await PdfReader.loadFromBytes(pdfBytes);

print('Pages: ${pdf.pageCount}');
print('PDF Version: ${pdf.version}');
print('Page Size: ${pdf.pageWidth} x ${pdf.pageHeight}');

// Iterate over extracted elements
for (final element in pdf.elements) {
  if (element is DocxParagraph) {
    // Text content with formatting
    for (final child in element.children) {
      if (child is DocxText) {
        print('Text: ${child.content}');
        print('Bold: ${child.fontWeight == DocxFontWeight.bold}');
      }
    }
  } else if (element is DocxImage) {
    // Images are encoded as PNG
    print('Image: ${element.bytes.length} bytes');
    // Use directly in Flutter: Image.memory(element.bytes)
  } else if (element is DocxTable) {
    print('Table: ${element.rows.length} rows');
  }
}

// Get all text as a single string
print(pdf.text);
```

### Image Extraction

Images are automatically extracted and encoded as PNG:

```dart
final pdf = await PdfReader.loadFromBytes(pdfBytes);

// Quick access to all images
for (final img in pdf.images) {
  print('${img.width}x${img.height}, ${img.bytes.length} bytes');
  
  // Save to file
  await File('image_${pdf.images.indexOf(img)}.png')
      .writeAsBytes(img.bytes);
  
  // Use in Flutter
  // Image.memory(img.bytes)
}

// Images are also available in elements list as DocxImage
for (final element in pdf.elements) {
  if (element is DocxImage) {
    // element.bytes contains PNG data
  }
}
```

### Supported Features

| Feature                         | Status    |
| ------------------------------- | --------- |
| Text extraction                 | ✅        |
| Text formatting (bold, italic)  | ✅        |
| Font detection                  | ✅        |
| Font sizes and colors           | ✅        |
| Paragraph grouping              | ✅        |
| Images (JPEG, PNG, FlateDecode) | ✅        |
| Table detection                 | ✅ (beta) |
| Multi-page documents            | ✅        |
| PDF 1.4 standard format         | ✅        |
| PDF 1.5+ XRef streams           | ✅        |
| Object streams                  | ✅        |
| FlateDecode compression         | ✅        |
| LZWDecode compression           | ✅        |
| ASCII85/ASCIIHex encoding       | ✅        |

### Limitations

- **Image-only (scanned) PDFs**: If a PDF contains only images with no text operators, no text will be extracted. Consider using OCR separately.
- **Complex layouts**: Multi-column layouts may not preserve exact positioning.
- **Vertical Text**: Vertical writing modes are not yet supported.

---

## Sections & Page Layout

```dart
final doc = DocxDocumentBuilder()
  .section(
    orientation: DocxPageOrientation.portrait,
    pageSize: DocxPageSize.a4,
    backgroundColor: DocxColor('#F0F8FF'),
    header: DocxHeader(children: [
      DocxParagraph.text('Company Name', align: DocxAlign.right),
    ]),
    footer: DocxFooter(children: [
      DocxParagraph.text('Page 1', align: DocxAlign.center),
    ]),
  )
  .h1('Document Title')
  .p('Content...')
  .build();
```

### Multi-Section Documents

```dart
docx()
  .p('Portrait section content')
  .addSectionBreak(DocxSectionDef(
    orientation: DocxPageOrientation.portrait,
  ))
  .p('Landscape section content')
  .addSectionBreak(DocxSectionDef(
    orientation: DocxPageOrientation.landscape,
  ))
  .build();
```

---

## Footnotes & Endnotes

Add academic citations and notes programmatically:

```dart
final doc = docx()
  .p('This statement needs a citation.')
  .addFootnote(DocxFootnote(
    footnoteId: 1,
    content: [
      DocxParagraph.text('Source: Official Documentation, 2024.'),
    ],
  ))
  .p('Unexpected finding.')
  .addEndnote(DocxEndnote(
    endnoteId: 1,
    content: [
      DocxParagraph.text('Further investigation required.'),
    ],
  ))
  .build();
```

> **Note:** IDs must be unique. Word handles re-numbering automatically, but you must provide improved internal IDs for linking.

---

## Font Embedding

Embed custom fonts with OOXML-compliant obfuscation:

```dart
import 'dart:io';

final fontBytes = await File('fonts/Roboto-Regular.ttf').readAsBytes();

final doc = DocxDocumentBuilder()
  .addFont('Roboto', fontBytes)
  .add(DocxParagraph(children: [
    DocxText('Custom font text', fontFamily: 'Roboto'),
  ]))
  .build();

```

> **Note:** Fonts are automatically obfuscated per the OpenXML specification.
> **High Fidelity:** When reading existing documents, `docx_creator` preserves embedded fonts byte-for-byte, ensuring exact visual fidelity during round-trip edits.

---

## API Reference

### DocxDocumentBuilder

| Method                              | Parameters                   | Description          |
| ----------------------------------- | ---------------------------- | -------------------- |
| `h1(text)`                        | `String text`              | Add H1 heading       |
| `h2(text)`                        | `String text`              | Add H2 heading       |
| `h3(text)`                        | `String text`              | Add H3 heading       |
| `heading(level, text)`            | `DocxHeadingLevel, String` | Add heading at level |
| `p(text, {align})`                | `String, DocxAlign?`       | Add paragraph        |
| `bullet(items)`                   | `List<String>`             | Add bullet list      |
| `numbered(items)`                 | `List<String>`             | Add numbered list    |
| `table(data, {hasHeader, style})` | `List<List<String>>`       | Add table            |
| `pageBreak()`                     | -                            | Add page break       |
| `hr()`                            | -                            | Add horizontal rule  |
| `quote(text)`                     | `String`                   | Add blockquote       |
| `code(code)`                      | `String`                   | Add code block       |
| `add(node)`                       | `DocxNode`                 | Add any node         |
| `addFont(name, bytes)`            | `String, Uint8List`        | Embed font           |
| `section({...})`                  | Various                      | Set page properties  |
| `build()`                         | -                            | Build document       |

### DocxExporter / PdfExporter / MarkdownExporter / HtmlExporter

All four exporters share the same shape:

| Method                      | Parameters                    | Description  |
| --------------------------- | ----------------------------- | ------------ |
| `exportToFile(doc, path)` | `DocxBuiltDocument, String` | Save to file |
| `exportToBytes(doc)`      | `DocxBuiltDocument`         | Get as bytes (`DocxExporter`/`PdfExporter`) |
| `export(doc)`             | `DocxBuiltDocument`         | Get as a string (`MarkdownExporter`/`HtmlExporter`) |

### DocxReader

| Method                   | Parameters    | Description         |
| ------------------------ | ------------- | ------------------- |
| `load(path)`           | `String`    | Load from file path |
| `loadFromBytes(bytes)` | `Uint8List` | Load from bytes     |

### DocxParser

| Method               | Parameters | Description             |
| -------------------- | ---------- | ----------------------- |
| `fromHtml(html)`   | `String` | Parse HTML to nodes     |
| `fromMarkdown(md)` | `String` | Parse Markdown to nodes |

### MarkdownParser

| Method              | Parameters | Description             |
| ------------------- | ---------- | ----------------------- |
| `parse(markdown)` | `String` | Parse Markdown to nodes |

---

## Troubleshooting

### Common Issues

**Q: Fonts don't display correctly in Word**

A: Ensure the font is embedded using `addFont()`. Embedded fonts are obfuscated per OpenXML spec.

**Q: Images don't appear**

A: Verify image bytes are valid and extension matches format (`png`, `jpg`, `gif`).

**Q: Lists don't have bullets/numbers**

A: Ensure you're using the fluent API (`bullet()`, `numbered()`) or properly structured `DocxList` with `DocxListItem`.

**Q: Colors look wrong**

A: Use 6-digit hex codes without # prefix for `shadingFill`. For `DocxColor`, you can use `#RRGGBB` or plain `RRGGBB`.

---

## Examples

See the `example/` directory for comprehensive examples:

- [`manual_builder_example.dart`](example/manual_builder_example.dart) - All builder API features
- [`html_parser_example.dart`](example/html_parser_example.dart) - HTML to DOCX
- [`markdown_parser_example.dart`](example/markdown_parser_example.dart) - Markdown to DOCX
- [`reader_editor_example.dart`](example/reader_editor_example.dart) - Read, edit, save workflow

---

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contributing

Contributions welcome! Please read our contributing guidelines and submit PRs to the main repository.
