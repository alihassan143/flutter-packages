// Regression test: a document's TOC field caches whatever page numbers
// Word last computed, which never match this library's own PDF pagination.
// PdfExporter must rewrite those cached digits against where each heading
// actually lands in the exported PDF instead of carrying the stale numbers
// through verbatim.
import 'dart:typed_data';

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

/// 0-indexed page the given text's LAST occurrence is actually drawn on, by
/// parsing the PDF back with this package's own [PdfReader] (ground truth,
/// independent of whatever page number the TOC rewrite believes it used).
/// Searches from the last page backward because the TOC's own cached entry
/// (earlier in the document) also contains the heading's title text - the
/// real heading paragraph is always the later occurrence. Whitespace is
/// collapsed on both sides since the text extractor inserts extra spacing
/// for inter-glyph positioning adjustments that don't reflect real spaces.
Future<int> _pageIndexOf(List<int> pdfBytes, String needle) async {
  final normalizedNeedle = needle.replaceAll(RegExp(r'\s+'), ' ');
  final pdfDoc = await PdfReader.loadFromBytes(Uint8List.fromList(pdfBytes));
  for (var p = pdfDoc.pageCount - 1; p >= 0; p--) {
    final text =
        pdfDoc.extractTextForPage(p).replaceAll(RegExp(r'\s+'), ' ');
    if (text.contains(normalizedNeedle)) return p;
  }
  return -1;
}

void main() {
  test('TOC page numbers are recomputed against actual PDF pagination',
      () async {
    // A real Word-cached TOC entry places the page number after a tab
    // (the dot-leader tab stop) - not as a second run glued directly onto
    // the title - so model that here too (see _withRecomputedPageNumber's
    // tab-adjacency check).
    final toc = DocxTableOfContents(cachedContent: [
      DocxParagraph(
          children: [DocxText('ChapterOne'), DocxTab(), DocxText('99')]),
      DocxParagraph(
          children: [DocxText('ChapterTwo'), DocxTab(), DocxText('99')]),
      DocxParagraph(
          children: [DocxText('ChapterThree'), DocxTab(), DocxText('99')]),
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
    // Three on page 3 - never the stale cached "99", and each title must be
    // paired with its OWN correct page number (not just "a" number, and not
    // shifted onto a different entry).
    expect(drawn, isNot(contains('99')));
    expect(drawn, contains('ChapterOne1'));
    expect(drawn, contains('ChapterTwo2'));
    expect(drawn, contains('ChapterThree3'));
  });

  test('TOC entry with no matching heading is left untouched', () async {
    final toc = DocxTableOfContents(cachedContent: [
      DocxParagraph(
          children: [DocxText('OrphanEntry'), DocxTab(), DocxText('7')]),
    ]);

    final doc = docx().add(toc).build();

    final bytes = PdfExporter(compressContent: false).exportToBytes(doc);
    final drawn = _drawnText(bytes);

    // No heading paragraphs anywhere in the document, so nothing is
    // recomputed - the original cached digit survives unchanged.
    expect(drawn, contains('OrphanEntry'));
    expect(drawn, contains('7'));
  });

  test(
      'TOC page number matches where a large heading actually lands, '
      'not where it would land at the dry run\'s fallback font size',
      () async {
    // Heading1 is 2x the base font size. The dry run that computes TOC page
    // numbers must resolve that real size (via the section's layout) or it
    // under-measures the heading and can believe it fits on an earlier page
    // than where it actually renders. 25 filler paragraphs leave just enough
    // room on page 1 for the heading's wrongly-small dry-run estimate at the
    // 12pt fallback, but not its real height at Heading1's real 24pt -
    // calibrated empirically: reverting the _layoutEngine fix on this exact
    // scenario makes the TOC say page 1 while the heading actually draws on
    // page 2.
    final filler = DocxParagraph(
        children: [DocxText('Filler paragraph line of body text.')]);
    final toc = DocxTableOfContents(cachedContent: [
      DocxParagraph(children: [
        DocxText('Calibration Heading Text Example'),
        DocxTab(),
        DocxText('99'),
      ]),
    ]);

    var builder = docx().add(toc);
    for (var i = 0; i < 25; i++) {
      builder = builder.add(filler);
    }
    builder = builder
        .add(DocxParagraph.heading1('Calibration Heading Text Example'));
    final doc = builder.build();

    final bytes = PdfExporter(compressContent: false).exportToBytes(doc);
    final actualPage =
        await _pageIndexOf(bytes, 'Calibration Heading Text Example') + 1;
    expect(actualPage, 2,
        reason: 'calibration assumption: heading should land on page 2');

    final drawn = _drawnText(bytes);
    expect(drawn, isNot(contains('99')));
    expect(drawn, contains('Calibration Heading Text Example$actualPage'));
  });

  test('a heading split across a page boundary is only counted once',
      () async {
    // A heading whose own wrapped text is taller than the remaining page
    // gets split (fitted part on this page, rest on the next) by
    // PdfLayoutEngine/PdfExporter.splitParagraph. Both fragments keep the
    // Heading1 styleId (so the continuation still renders at heading size),
    // so the TOC page-number collection must not count the continuation as
    // a second heading - that would consume a page number meant for
    // ChapterTwo and shift every entry after it.
    final longHeadingText = List.generate(40, (i) => 'WordNumber$i').join(' ');
    final toc = DocxTableOfContents(cachedContent: [
      DocxParagraph(children: [
        DocxText(longHeadingText),
        DocxTab(),
        DocxText('99'),
      ]),
      DocxParagraph(children: [
        DocxText('ChapterTwo'),
        DocxTab(),
        DocxText('99'),
      ]),
    ]);

    final filler = DocxParagraph(
        children: [DocxText('Filler paragraph line of body text.')]);
    var builder = docx().add(toc);
    // Push the long heading far enough down page 1 that its own wrapped
    // lines don't all fit before the page ends, forcing a split.
    for (var i = 0; i < 22; i++) {
      builder = builder.add(filler);
    }
    final doc = builder
        .add(DocxParagraph.heading1(longHeadingText))
        .add(DocxParagraph.heading1('ChapterTwo'))
        .build();

    final bytes = PdfExporter(compressContent: false).exportToBytes(doc);

    // However many pages the split heading spans, ChapterTwo must resolve
    // to wherever it actually lands - never to a page number that was
    // meant for (and double-consumed by) the split heading's continuation.
    final chapterTwoActualPage =
        await _pageIndexOf(bytes, 'ChapterTwo') + 1;
    final drawn = _drawnText(bytes);
    expect(drawn, isNot(contains('99')));
    expect(drawn, contains('ChapterTwo$chapterTwoActualPage'));
  });
}
