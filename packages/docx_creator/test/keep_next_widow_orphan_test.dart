import 'package:docx_creator/docx_creator.dart';
import 'package:docx_creator/src/exporters/pdf/pdf_layout_engine.dart';
import 'package:test/test.dart';

void main() {
  group('keepNext / keepLines round-trip', () {
    test('survive a full DOCX round-trip', () async {
      final doc = docx()
          .add(DocxParagraph(
            keepNext: true,
            keepLines: true,
            children: [DocxText('Heading')],
          ))
          .build();

      final bytes = await DocxExporter().exportToBytes(doc);
      final reloaded = await DocxReader.loadFromBytes(bytes);

      final paragraph = reloaded.elements.whereType<DocxParagraph>().first;
      expect(paragraph.keepNext, isTrue);
      expect(paragraph.keepLines, isTrue);
    });

    test('default to false and are omitted from w:pPr', () async {
      final doc = docx().add(DocxParagraph.text('Plain')).build();

      final bytes = await DocxExporter().exportToBytes(doc);
      final reloaded = await DocxReader.loadFromBytes(bytes);

      final paragraph = reloaded.elements.whereType<DocxParagraph>().first;
      expect(paragraph.keepNext, isFalse);
      expect(paragraph.keepLines, isFalse);
    });

    test('copyWith preserves and overrides keepNext/keepLines', () {
      final base = DocxParagraph(keepNext: true, children: [DocxText('a')]);
      expect(base.copyWith().keepNext, isTrue);
      expect(base.copyWith().keepLines, isFalse);
      expect(base.copyWith(keepLines: true).keepLines, isTrue);
    });
  });

  group('PdfLayoutEngine keepNext', () {
    test('a keepNext paragraph moves to the next page together with its '
        'successor instead of being orphaned at the bottom', () {
      final engine = PdfLayoutEngine(
        pageWidth: 600,
        pageHeight: 800,
        marginLeft: 50,
        marginRight: 50,
        marginTop: 50,
        marginBottom: 50,
      );

      final heading =
          DocxParagraph(keepNext: true, children: [DocxText('Heading')]);
      final body = DocxParagraph.text('Body text that follows the heading.');

      final headingHeight = engine.measureNode(heading);
      final bodyHeight = engine.measureNode(body);
      final unitHeight = engine.measureNode(DocxParagraph.text('x'));

      // Fill the page so only `headingHeight` (plus up to one more line of
      // slack) is left - enough for the heading alone, not enough for the
      // heading plus the body that must stay with it.
      final fillerCount =
          ((engine.contentHeight - headingHeight) / unitHeight).floor();
      final filler =
          List.generate(fillerCount, (_) => DocxParagraph.text('x'));
      expect(bodyHeight, greaterThanOrEqualTo(unitHeight));

      final pages = engine.paginate([...filler, heading, body]);

      expect(pages.length, 2, reason: 'filler page + heading/body page');
      expect(
        pages[0].any((n) => identical(n, heading)),
        isFalse,
        reason: 'heading must not be left alone on the filler page',
      );
      expect(pages[1].any((n) => identical(n, heading)), isTrue);
      expect(pages[1].any((n) => identical(n, body)), isTrue);
    });

    test('keepNext is ignored when the pair cannot fit on any single page',
        () {
      final engine = PdfLayoutEngine(pageWidth: 600, pageHeight: 800);

      final heading =
          DocxParagraph(keepNext: true, children: [DocxText('Heading')]);
      final hugeBody = DocxParagraph.text('word ' * 2000);

      // Should not loop forever or throw - falls back to normal pagination.
      final pages = engine.paginate([heading, hugeBody]);
      expect(pages.length, greaterThan(1));
    });
  });

  group('PdfLayoutEngine widow/orphan control', () {
    test('does not leave a single orphaned line at the bottom of a page',
        () {
      final engine = PdfLayoutEngine(
        pageWidth: 600,
        pageHeight: 800,
        marginLeft: 50,
        marginRight: 50,
        marginTop: 50,
        marginBottom: 50,
      );

      // A multi-line paragraph sized so a naive split would leave exactly
      // one line on the current page and the rest on the next.
      final paragraph = DocxParagraph.text('word word word word word ' * 40);
      final unitHeight = engine.measureNode(DocxParagraph.text('x'));
      final paragraphHeight = engine.measureNode(paragraph);
      expect(paragraphHeight, lessThanOrEqualTo(engine.contentHeight),
          reason: 'paragraph must fit a clean page for this test to apply');

      final fillerCount =
          ((engine.contentHeight - unitHeight * 1.2) / unitHeight).floor();
      final filler =
          List.generate(fillerCount, (_) => DocxParagraph.text('x'));

      final pages = engine.paginate([...filler, paragraph]);

      // Whatever landed on the filler page must not be a 1-line fragment of
      // `paragraph` while a multi-line remainder starts the next page. (A
      // filler unit, or the untouched `paragraph` itself pushed whole to
      // this page, are both fine - only a genuine split fragment matters.)
      final fillerPageLast = pages.first.last;
      final isFillerUnit = filler.any((f) => identical(f, fillerPageLast));
      if (fillerPageLast is DocxParagraph &&
          !identical(fillerPageLast, paragraph) &&
          !isFillerUnit &&
          pages.length > 1) {
        final fragmentHeight = engine.measureParagraph(fillerPageLast);
        expect(fragmentHeight, greaterThan(unitHeight * 1.5),
            reason: 'fragment left on this page must be more than one line');
      }
    });
  });
}
