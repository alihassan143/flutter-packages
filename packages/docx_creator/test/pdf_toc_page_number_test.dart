// Regression test: a document's TOC field caches whatever page numbers
// Word last computed, which never match this library's own PDF pagination.
// PdfExporter must rewrite those cached digits against where each heading
// actually lands in the exported PDF instead of carrying the stale numbers
// through verbatim.
import 'package:docx_creator/docx_creator.dart';
import 'package:test/test.dart';

/// Every literal string this PDF actually draws with `Tj`, concatenated -
/// avoids false matches against unrelated binary (e.g. embedded font bytes)
/// that a raw substring search over the whole file would hit.
String _drawnText(List<int> pdfBytes) {
  final content = String.fromCharCodes(pdfBytes);
  final tj = RegExp(r'\(((?:[^()\\]|\\.)*)\)\s*Tj');
  return tj.allMatches(content).map((m) => m.group(1)!).join();
}

void main() {
  test('TOC page numbers are recomputed against actual PDF pagination',
      () async {
    final toc = DocxTableOfContents(cachedContent: [
      DocxParagraph(children: [DocxText('ChapterOne'), DocxText(' 99')]),
      DocxParagraph(children: [DocxText('ChapterTwo'), DocxText(' 99')]),
      DocxParagraph(children: [DocxText('ChapterThree'), DocxText(' 99')]),
    ]);

    final doc = docx()
        .add(toc)
        .add(DocxParagraph.heading1('ChapterOne'))
        .add(DocxParagraph.heading1('ChapterTwo')
            .copyWith(pageBreakBefore: true))
        .add(DocxParagraph.heading1('ChapterThree')
            .copyWith(pageBreakBefore: true))
        .build();

    final bytes = PdfExporter(compressContent: false).exportToBytes(doc);
    final drawn = _drawnText(bytes);

    // ChapterOne is on page 1 (same page as the TOC itself), Two on page 2,
    // Three on page 3 - never the stale cached "99".
    expect(drawn, isNot(contains('99')));
    expect(drawn, contains('ChapterOne'));
    expect(drawn, contains('ChapterTwo'));
    expect(drawn, contains('ChapterThree'));
  });

  test('TOC entry with no matching heading is left untouched', () async {
    final toc = DocxTableOfContents(cachedContent: [
      DocxParagraph(children: [DocxText('OrphanEntry'), DocxText(' 7')]),
    ]);

    final doc = docx().add(toc).build();

    final bytes = PdfExporter(compressContent: false).exportToBytes(doc);
    final drawn = _drawnText(bytes);

    // No heading paragraphs anywhere in the document, so nothing is
    // recomputed - the original cached digit survives unchanged.
    expect(drawn, contains('OrphanEntry'));
    expect(drawn, contains('7'));
  });
}
