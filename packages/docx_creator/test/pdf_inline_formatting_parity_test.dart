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
}
