/// A position within a document's editable text.
///
/// [elementIndex] indexes into the top-level `DocxBuiltDocument.elements`
/// list (so it only addresses top-level paragraphs - see the editing module
/// README note for why nested content, e.g. table cells and list items, is
/// out of scope for this first pass). [offset] is a character offset into
/// that paragraph's *rendered* text: every [DocxText] run and every
/// character-producing inline (line break = 1, tab = 4, checkbox = 2,
/// footnote/endnote ref = however many digits its id has) counts for its
/// real rendered length, and a non-floating inline image/shape counts as 1
/// (it paints as a single placeholder character via a `WidgetSpan`, which is
/// how `TextPainter`/`RenderParagraph` count it too - see
/// `docx_paragraph_text.dart`).
class DocxTextPosition {
  final int elementIndex;
  final int offset;

  const DocxTextPosition({required this.elementIndex, required this.offset});

  @override
  bool operator ==(Object other) =>
      other is DocxTextPosition &&
      other.elementIndex == elementIndex &&
      other.offset == offset;

  @override
  int get hashCode => Object.hash(elementIndex, offset);

  @override
  String toString() => 'DocxTextPosition(elementIndex: $elementIndex, offset: $offset)';
}
