## 2.2.0

* **Rendering accuracy (new engine)** - output now tracks what a browser renders far more closely:
    * **Whitespace**: browser-style collapsing. Adjacent inline elements (`Word<b>glued</b>`) are no longer split by an invented space, and whitespace between elements is kept. `<br>` inside a paragraph now breaks the line instead of being dropped.
    * **Lists**: nested lists render as nested lists instead of being flattened into the parent item's text. Supports `type`, `start`, `reversed`, `value`, `list-style-type` (decimal, alpha, roman, greek, disc/circle/square), and per-depth bullets. Task-list items show only their checkbox.
    * **Tables**: `colspan`/`rowspan`, block content in cells (paragraphs, lists, images), `<caption>`, cell/row CSS borders and backgrounds, `valign`/`vertical-align`, `cellpadding`, explicit column widths, content-weighted column widths, and repeating `<thead>` rows. `border="0"`/`border: none` removes the grid.
    * **Margins**: vertical margins collapse between siblings and through parents; browser-default margins for headings, paragraphs, lists, blockquotes and `<pre>` (headings scale with `defaultFontSize`).
    * **`<pre>`/`<code>`**: whitespace preserved, monospace (Courier) font, background and padding applied.
    * **Inline**: `<sub>`/`<sup>` baseline shifts, `<small>`, `<big>`, `<ins>`, `<cite>`, `<kbd>`, `<font color/face/size>`, `<center>`, `<dl>/<dt>/<dd>`; links stay clickable on nested formatting (`<a><b>..</b></a>`).
    * **Images**: sized at 1px = 0.75pt by default, `margin: auto`/`text-align` centering, per-side borders.
* **CSS**:
    * `<style>` blocks now support descendant/child/sibling combinators, attribute selectors, structural pseudo-classes (`:first-child`, `:nth-child(odd)`, ...), specificity ordering and `!important`. Multi-value declarations (`margin: 0 auto`) are no longer truncated, and stylesheet values go through the same parser as inline styles (units were previously ignored).
    * Presentational attributes (`width`, `bgcolor`, `align`, ...) now sit below author CSS in the cascade, as in browsers.
    * All 148 CSS named colors with spec values (e.g. `red` is `#FF0000`, `navy` is `#000080`), `#rgb`/`#rgba`/`#rrggbbaa`, `rgb()`/`rgba()` with percentages or space syntax, `hsl()`/`hsla()`.
    * Longhands: `margin-*`, `padding-*`, `border-top/right/bottom/left`, `border-width/color/style`, `background`, `font` shorthand, `text-decoration-color/style` and combined decorations.
    * `em`/`%`/keyword font sizes resolve against the parent; numeric `font-weight` (600+ is bold); `line-height` (unitless, %, length; inherited); `letter-spacing`; `text-transform`; `white-space`; `vertical-align: super/sub`; `mm`, `cm`, `pc`, `ex`, `ch` units.
* **Defaults**: `HtmlTagStyle.codeBlockBackgroundColor` (inline `<code>`) and `codeblockColor` (`<pre>` background) now default to light grey instead of red/mid-grey. Links default to browser blue (`#0000EE`), `<th>` is bold and centered with no forced background, and `<blockquote>` is no longer italic.
* Removed debug `print` output from the new engine.

## 2.1.1

* **Branding & Documentation**:
    * Updated package logo with a modern, futuristic design.
    * Fixed broken "Buy Me a Coffee" icon on pub.dev by using a more stable button URL.
    * Improved README branding and asset link stability for better pub.dev compatibility.

## 2.1.0

* **Layout-First Rendering Engine**: Major architectural refactor for Chrome-like PDF accuracy.
    * **Calculated Constraints**: Every element now undergoes a virtual layout pass to resolve CSS Box Model constraints (padding, border, margin) before widget generation.
    * **Standardized Unit Conversion**: Implemented $1px = 0.75pt$ scaling to ensure PDF layouts precisely match browser/web views.
    * **Native Flexbox Support**: Added `display: flex` support with mapping to `pw.Flex`. Supports `flex-grow`, `flex-direction`, `justify-content`, and `align-items`.
    * **Enhanced Table Support**: Tables now support repeating headers across pages, cell alignment, and native PDF borders/backgrounds.
    * **Improved Page Spanning**: Refined block detection to allow long content (paragraphs, blockquotes, headers) to bridge across pages without "exceeded page height" errors.
* **Refactored Codebase**: Decoupled parsing (`HtmlParser`), layout calculation (`LayoutSolver`), and PDF construction (`PdfBuilder`) for better extensibility.

## 2.0.1

* **Fixes**:
    * ([#63](https://github.com/alihassan143/htmltopdfwidgets/pull/63)) feat: add .gitignore and remove ignored files by @alihassan143
    * ([#63](https://github.com/alihassan143/htmltopdfwidgets/pull/63)) fix: fixed issue of pdf generation when text for table cell is very long by @AbhishekDoshi26
    * ([#63](https://github.com/alihassan143/htmltopdfwidgets/pull/63)) fix: fixed pipeline by @AbhishekDoshi26
    * ([#63](https://github.com/alihassan143/htmltopdfwidgets/pull/63)) fix: removed whitespace in paragraph starting by @AbhishekDoshi26
    * ([#63](https://github.com/alihassan143/htmltopdfwidgets/pull/63)) fix: fixed column header background color by @AbhishekDoshi26
    * ([#61](https://github.com/alihassan143/htmltopdfwidgets/pull/61)) feat: Update legacy HTML to widgets and browser PDF builder, generating new test and example PDF outputs by @AbhishekDoshi26.

## 2.0.0
* **New Architecture**: Introduced a "Browser Rendering Engine" architecture for more robust HTML to PDF conversion.
    * **Style Engine**: Comprehensive CSS parsing and cascading support.
    * **Render Tree**: Intermediate DOM representation with fully computed styles.
    * **PDF Builder**: Modular PDF widget generation with better layout handling.
* **Unified API**: Updated `HTMLToPdf.convert` to support the new engine via `useNewEngine: true`.
* **Checkbox Enhancements**:
    * Fixed inline rendering of checkboxes (now flow with text).
    * Improved vertical alignment (centered by default, respects `vertical-align`).
* **Multi-Language Support**:
    * Added `textDirection` support for RTL languages (Arabic, Hebrew).
    * Added `fontFallback` support for Emojis and complex scripts in the new engine.
* **Enhanced Element Support**:
    * Improved Table rendering with full CSS support (borders, padding, background).
    * Better List handling (nested lists, custom bullets).
    * Support for `blockquote`, `pre`, `code`, `hr`, `checkbox`, and more.
* **Rendering Improvements**:
    * Fixed inline content rendering (bold, italic, mixed text).
    * Fixed list item text visibility.
    * Optimized default spacing to match legacy engine.
* **Custom Styles**: Added full support for `HtmlTagStyle` in the new engine.
* **Robustness**: Improved error handling for images and fonts.
* **Legacy Support**: Maintained full backward compatibility with the legacy engine (default).

## 2.0.0-beta.2

* **Checkbox Enhancements**:
    * Fixed inline rendering of checkboxes (now flow with text).
    * Improved vertical alignment (centered by default, respects `vertical-align`).
* **Multi-Language Support**:
    * Added `textDirection` support for RTL languages (Arabic, Hebrew).
    * Added `fontFallback` support for Emojis and complex scripts in the new engine.
* **Robustness**:
    * Improved error handling for images and fonts.

## 2.0.0-beta.1

*   **New Architecture**: Introduced a "Browser Rendering Engine" architecture for more robust HTML to PDF conversion.
    *   **Style Engine**: Comprehensive CSS parsing and cascading support (`lib/src/browser/css_style.dart`).
    *   **Render Tree**: Intermediate DOM representation with fully computed styles (`lib/src/browser/render_node.dart`).
    *   **PDF Builder**: Modular PDF widget generation with better layout handling (`lib/src/browser/pdf_builder.dart`).
*   **Unified API**: Updated `HTMLToPdf.convert` to support the new engine via `useNewEngine: true`.
*   **Enhanced Support**:
    *   Improved Table rendering with full CSS support (borders, padding, background).
    *   Better List handling (nested lists, custom bullets).
    *   Support for `blockquote`, `pre`, `code`, `hr`, `checkbox`, and more.
*   **Rendering Improvements**:
    *   Fixed inline content rendering (bold, italic, mixed text).
    *   Fixed list item text visibility.
    *   Optimized default spacing to match legacy engine.
*   **Custom Styles**: Added full support for `HtmlTagStyle` in the new engine.
*   **Legacy Support**: Maintained full backward compatibility with the legacy engine (default).

## 1.1.3
* *([#52](https://github.com/alihassan143/htmltopdfwidgets/pull/52)) fix css color parsing
## 1.1.1
* Fix markdown table issue and added more markdown properties modifiers
## 1.1.0
*([#46](https://github.com/alihassan143/htmltopdfwidgets/pull/46)) Add support for local image files

## 1.0.9
* added support for horizontal divider
* code block and pre tag support
## 1.0.8
* fix: Links get formatted but are not clickable in the PDF ([#35](https://github.com/alihassan143/htmltopdfwidgets/issues/35))
## 1.0.7
* fix nested child skipping issue fixed
## 1.0.6
* added wrap in paragraph element feature for html text
## 1.0.5
* Markdown to pdf support added
## 1.0.4
* Fix wrong styles of background color ([#31](https://github.com/alihassan143/htmltopdfwidgets/issues/31))
* Add support for custom fonts ([#34](https://github.com/alihassan143/htmltopdfwidgets/pull/34)) by @hig-dev
## 1.0.3
* Intial support for checkboxes
*([#25](https://github.com/alihassan143/htmltopdfwidgets/issues/25))
## 1.0.2
* update readme
*([#20](https://github.com/alihassan143/htmltopdfwidgets/issues/20))
## 1.0.1
* update readme
## 1.0.0
*  fix line break
*  fix Can't manage to render colors    
*  text alignment feature added    


## 0.0.9+2
*  fix internal css decoration not working
## 0.0.9+1

*  optimiz parse logic
*  documentation fixs
*  using override dependency for pdf due to underline and italic issues 
*  update readme 
## 0.0.9

*  optimiz parse logic
*  documentation fixs
*  using override dependency for pdf due to underline and italic issues 

## 0.0.8+2

*  support for html table tag added
## 0.0.8+1

*  update reamdme.md
## 0.0.8

*  support custom styles

## 0.0.7

*  support for dart sdk
*  nested elements children support
## 0.0.6

*  multiple styles on same text
*  font fallback and font added 
## 0.0.5

*  missing image element added
## 0.0.4

*  optimization
## 0.0.3

*  depedency updates
## 0.0.2

*  network image fixes.
## 0.0.1

* Describe initial release.
