// Regression test for GitHub issue #125: PdfExporter dropped italic on
// bold+italic runs everywhere, and dropped underline/strikethrough
// decorations specifically in list items and table cells (only the
// body-paragraph render path drew them).
import 'package:docx_creator/docx_creator.dart';
import 'package:test/test.dart';

List<DocxInline> _styledRuns() => [
      DocxText('plain '),
      DocxText('italic ', fontStyle: DocxFontStyle.italic),
      DocxText('underline ', decorations: [DocxTextDecoration.underline]),
      DocxText('struck ', decorations: [DocxTextDecoration.strikethrough]),
      DocxText('bold-italic',
          fontWeight: DocxFontWeight.bold, fontStyle: DocxFontStyle.italic),
    ];

/// Number of decoration strokes (the underline/strikethrough stroke
/// pattern, `0.5 w` followed by a moveto/lineto/stroke) in the content
/// stream.
int _decorationStrokeCount(String content) {
  final pattern = RegExp(r'0\.5 w\n[\d.-]+ [\d.-]+ m [\d.-]+ [\d.-]+ l S');
  return pattern.allMatches(content).length;
}

/// Finds the page content stream's own operators among all of a PDF's
/// `stream`/`endstream` blocks - needed once a non-WinAnsi character (e.g.
/// a checkbox glyph) forces the bundled fallback font to be embedded,
/// since its raw TrueType bytes are themselves a `stream`/`endstream`
/// block and, being ~380KB of binary noise, can easily contain a stray
/// two-letter match like `Tj` in it by pure chance.
String _pageContentStream(List<int> pdfBytes) {
  final pdf = String.fromCharCodes(pdfBytes);
  for (final m in RegExp(r'stream\r?\n([\s\S]*?)endstream').allMatches(pdf)) {
    final body = m.group(1)!;
    if (!body.contains('BT') || !body.contains('Tf')) continue;
    final printable = body.runes.where((c) => c >= 9 && c < 127).length;
    if (printable / body.length > 0.9) return body;
  }
  throw StateError('page content stream not found');
}

void main() {
  test('bold+italic gets its own font everywhere (heading, paragraph, list, '
      'table cell)', () {
    final doc = docx()
        .add(DocxParagraph(
            styleId: DocxHeadingLevel.h2.styleId, children: _styledRuns()))
        .add(DocxParagraph(children: _styledRuns()))
        .add(DocxList(items: [DocxListItem(_styledRuns())]))
        .add(DocxTable(rows: [
          DocxTableRow(cells: [DocxTableCell.rich(_styledRuns())])
        ]))
        .build();

    final bytes = PdfExporter(compressContent: false).exportToBytes(doc);
    final content = String.fromCharCodes(bytes);

    // A real bold-italic font (one of the standard 14, so no embedding
    // needed) rather than silently downgrading bold+italic to bold-only.
    expect(content, contains('/BaseFont /Helvetica-BoldOblique'));
    expect(content, contains(RegExp(r'/FBI [\d.]+ Tf')));
  });

  test('list items draw underline and strikethrough', () {
    final doc = docx()
        .add(DocxList(items: [DocxListItem(_styledRuns())]))
        .build();

    final bytes = PdfExporter(compressContent: false).exportToBytes(doc);
    final content = String.fromCharCodes(bytes);

    // One underline + one strikethrough for the two decorated runs.
    expect(_decorationStrokeCount(content), 2);
  });

  test('table cells draw underline and strikethrough', () {
    final doc = docx()
        .add(DocxTable(
          style: DocxTableStyle.plain, // no cell borders to muddy the count
          rows: [
            DocxTableRow(cells: [DocxTableCell.rich(_styledRuns())])
          ],
        ))
        .build();

    final bytes = PdfExporter(compressContent: false).exportToBytes(doc);
    final content = String.fromCharCodes(bytes);

    expect(_decorationStrokeCount(content), 2);
  });

  test(
      'adjacent words draw an explicit space glyph so extracted text keeps '
      'word boundaries', () {
    // _drawWordLine (paragraphs, and - via this PR - lists/table cells)
    // positions every word with its own absolute text-matrix move rather
    // than relying on natural glyph advance, so a text extractor (pypdf,
    // browser copy/paste, ...) sees no glyph-advance gap to infer a word
    // boundary from unless an actual space glyph is drawn between words.
    final doc = docx()
        .add(DocxParagraph.text('foo bar'))
        .add(DocxList(items: [DocxListItem.text('foo bar')]))
        .add(DocxTable(rows: [
          DocxTableRow(
              cells: [DocxTableCell(children: [DocxParagraph.text('foo bar')])])
        ]))
        .build();

    final bytes = PdfExporter(compressContent: false).exportToBytes(doc);
    final content = String.fromCharCodes(bytes);

    // One space glyph ("( ) Tj") per "foo bar" line above.
    expect('( ) Tj'.allMatches(content).length, 3);
  });

  test('checkbox box size follows its own run font size, not the line '
      'default', () {
    // Regression: _drawWordLine's checkbox branch sized the box from the
    // outer line fontSize instead of the word's own (word.fontSize ??
    // fontSize) - which _renderList/_renderCellParagraph's own,
    // now-deleted, drawing loops got right - so a checkbox in a larger run
    // silently drew at the document's default size instead of its own.
    final doc = docx()
        .add(DocxList(items: [
          DocxListItem([DocxText('☐ Task', fontSize: 30)])
        ]))
        .build();

    final bytes = PdfExporter(compressContent: false).exportToBytes(doc);
    final content = String.fromCharCodes(bytes);

    // boxSize = 30 * 0.8 = 24, not the ~12pt document default's 9.6.
    expect(content, contains(RegExp(r'24\.0 24\.0 re S')));
    expect(content, isNot(contains(RegExp(r'9\.6\d* 9\.6\d* re S'))));
  });

  test('a checkbox immediately followed by text still gets a separating '
      'space glyph', () {
    // Regression: the space-glyph fix above only fired in _drawWordLine's
    // plain-text branch, so a checkbox word (its own branch, drawn as
    // vector graphics rather than text) followed by a text word - a common
    // task-list shape, e.g. DocxText('☐ Task') - still had no space
    // glyph between them despite the positional gap.
    final doc = docx().add(DocxParagraph.text('☐ Task')).build();

    final bytes = PdfExporter(compressContent: false).exportToBytes(doc);
    final pageContent = _pageContentStream(bytes);

    // The checkbox glyph forces the Unicode-fallback embedded font (☐ has
    // no WinAnsi representation), which encodes glyphs as hex CIDs rather
    // than literal PDF strings - so count `Tj` operators instead of
    // matching a literal `( ) Tj`: one for the space glyph, one for "Task"
    // (the checkbox itself is drawn as vector graphics, not text).
    expect(RegExp(r'Tj').allMatches(pageContent).length, 2);
  });
}
