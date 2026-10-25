import 'package:docx_creator/docx_creator.dart';

/// How many characters of rendered text one inline child contributes.
///
/// Mirrors the span lengths `ParagraphBuilder.buildInlineSpans` actually
/// paints (see `paragraph_builder.dart`): [DocxText] contributes its content
/// length, [DocxLineBreak] 1, [DocxTab] 4 (it paints as 4 literal spaces,
/// not a real tab stop), [DocxCheckbox] 2 (glyph + space), footnote/endnote
/// refs however many digits their id prints as, and a non-floating
/// [DocxInlineImage]/[DocxShape] 1 - they paint as a `WidgetSpan`, which
/// `TextPainter`/`RenderParagraph` also count as exactly one character when
/// resolving a tap position. Floating images/shapes never reach this
/// function (see the scope note on [locateInParagraph]).
int inlineRenderedLength(DocxInline inline) {
  if (inline is DocxText) return inline.content.length;
  if (inline is DocxLineBreak) return 1;
  if (inline is DocxTab) return 4;
  if (inline is DocxCheckbox) return 2;
  if (inline is DocxFootnoteRef) return '${inline.footnoteId}'.length;
  if (inline is DocxEndnoteRef) return '${inline.endnoteId}'.length;
  if (inline is DocxInlineImage || inline is DocxShape) return 1;
  return 0;
}

/// Total rendered-text length of a paragraph's children.
int paragraphTextLength(DocxParagraph paragraph) =>
    paragraph.children.fold(0, (sum, c) => sum + inlineRenderedLength(c));

/// Whether [paragraph] has any floating inline (image or shape).
///
/// A paragraph with a float renders as multiple side-by-side `Row`/text
/// segments instead of one contiguous `RichText`, so a single
/// "offset into the whole paragraph" doesn't address one span tree.
/// Editing/hit-testing such paragraphs is out of scope for this pass -
/// callers should check this first and decline (return null) rather than
/// silently computing a wrong offset.
bool paragraphHasFloats(DocxParagraph paragraph) => paragraph.children.any(
      (c) =>
          (c is DocxInlineImage &&
              c.positionMode == DocxDrawingPosition.floating) ||
          (c is DocxShape && c.position == DocxDrawingPosition.floating),
    );

/// Where rendered-text [offset] falls among a non-floating paragraph's
/// children: which child index contains it, and the offset within that
/// child's own text (e.g. within a [DocxText]'s `content`).
///
/// [offset] may equal the paragraph's total text length (cursor at the very
/// end) - in that case `childIndex == paragraph.children.length` and
/// `offsetInChild == 0`, meaning "after the last child, nothing to split."
/// Returns null for an out-of-range offset or a paragraph with floats (see
/// [paragraphHasFloats]).
({int childIndex, int offsetInChild})? locateInParagraph(
    DocxParagraph paragraph, int offset) {
  if (offset < 0 || paragraphHasFloats(paragraph)) return null;

  var remaining = offset;
  for (var i = 0; i < paragraph.children.length; i++) {
    final len = inlineRenderedLength(paragraph.children[i]);
    if (remaining <= len) return (childIndex: i, offsetInChild: remaining);
    remaining -= len;
  }
  if (remaining == 0) {
    return (childIndex: paragraph.children.length, offsetInChild: 0);
  }
  return null; // offset past the end of the paragraph's text
}
