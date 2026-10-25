// Regression tests for paged-mode keepNext and multi-column pagination.
//
// Before this fix, DocxWidgetGenerator's paged mode had no concept of
// DocxParagraph.keepNext (a heading could land alone at the bottom of a
// filler page while its body paragraph spilled to the next) and no concept
// of a section's columnCount at all (every section rendered full-width,
// one physical page per availableHeight regardless of column count).
import 'package:docx_creator/docx_creator.dart';
import 'package:docx_file_viewer/src/docx_view_config.dart';
import 'package:docx_file_viewer/src/widget_generator/docx_widget_generator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DocxBuiltDocument _docWith(List<DocxNode> elements, {DocxSectionDef? section}) =>
    DocxBuiltDocument(
      elements: elements,
      section: section,
      footnotes: [],
      endnotes: [],
      theme: DocxTheme(colors: DocxThemeColors(), fonts: DocxThemeFonts()),
    );

Future<void> _pump(WidgetTester tester, Widget page) {
  return tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SingleChildScrollView(child: page))));
}

/// Returns the index of the first page (in [pages]) whose rendered text
/// contains [marker].
Future<int> _pageIndexContaining(
    WidgetTester tester, List<Widget> pages, String marker) async {
  for (var i = 0; i < pages.length; i++) {
    await _pump(tester, pages[i]);
    if (find.textContaining(marker).evaluate().isNotEmpty) return i;
  }
  return -1;
}

void main() {
  group('Paged mode: keepNext', () {
    testWidgets(
        'a keepNext heading and its body move to the next page together, '
        'never split across a filler/heading-body boundary',
        (tester) async {
      const config =
          DocxViewConfig(pageMode: DocxPageMode.paged, pageWidth: 300, pageHeight: 400);

      // Sweep the filler count so the gap left on the filler page's last
      // slot cycles through a full range of possibilities - whatever gap
      // size would have let a bare heading slip in alone (but not with its
      // body) is guaranteed to show up somewhere in this range.
      for (var fillerCount = 3; fillerCount <= 10; fillerCount++) {
        final filler = List.generate(
            fillerCount, (i) => DocxParagraph(children: [DocxText('Filler$i')]));
        final doc = _docWith([
          ...filler,
          DocxParagraph(keepNext: true, children: [DocxText('HEADING_MARK')]),
          DocxParagraph(children: [DocxText('BODY_MARK')]),
        ]);

        final generator = DocxWidgetGenerator(config: config);
        final pages = generator.generateWidgets(doc);

        final headingPage = await _pageIndexContaining(tester, pages, 'HEADING_MARK');
        final bodyPage = await _pageIndexContaining(tester, pages, 'BODY_MARK');

        expect(headingPage, greaterThanOrEqualTo(0),
            reason: 'fillerCount=$fillerCount: heading must render somewhere');
        expect(bodyPage, headingPage,
            reason: 'fillerCount=$fillerCount: keepNext heading and body '
                'landed on different pages');
      }
    });

    testWidgets('keepNext is ignored when the pair cannot fit any single page',
        (tester) async {
      const config =
          DocxViewConfig(pageMode: DocxPageMode.paged, pageWidth: 300, pageHeight: 400);
      final doc = _docWith([
        DocxParagraph(keepNext: true, children: [DocxText('Heading')]),
        DocxParagraph(
            children: [DocxText(List.generate(300, (i) => 'word$i').join(' '))]),
      ]);

      final generator = DocxWidgetGenerator(config: config);
      // Must not loop forever or throw - falls back to normal pagination.
      final pages = generator.generateWidgets(doc);
      expect(pages.length, greaterThan(1));
    });
  });

  group('Paged mode: multi-column sections', () {
    testWidgets(
        'a 2-column section fitting one physical page renders as a single '
        'Row-of-2 page, with both columns on it',
        (tester) async {
      const config =
          DocxViewConfig(pageMode: DocxPageMode.paged, pageWidth: 400, pageHeight: 600);
      // Enough paragraphs to overflow column 1's height (forcing a second
      // slot = column 2) but not so many they overflow both columns.
      const count = 20;
      final doc = _docWith(
        List.generate(count, (i) => DocxParagraph(children: [DocxText('P$i')])),
        section: const DocxSectionDef(columnCount: 2),
      );

      final generator = DocxWidgetGenerator(config: config);
      final pages = generator.generateWidgets(doc);

      expect(pages, hasLength(1));
      await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: SingleChildScrollView(child: pages.single))));

      expect(find.byType(IntrinsicHeight), findsOneWidget);
      final row = tester.widget<Row>(find.descendant(
          of: find.byType(IntrinsicHeight), matching: find.byType(Row)));
      expect(row.children, hasLength(2));
      expect(row.children.every((c) => c is Expanded), true);

      for (var i = 0; i < count; i++) {
        // textContaining matches substrings ("P1" inside "P10") so just
        // assert presence, not an exact count.
        expect(find.textContaining('P$i'), findsAtLeastNWidgets(1));
      }
    });

    testWidgets(
        'a 2-column section with more content than one page holds advances '
        'to a second physical page once every column is full',
        (tester) async {
      const config =
          DocxViewConfig(pageMode: DocxPageMode.paged, pageWidth: 300, pageHeight: 400);
      // Enough paragraphs that 2 columns' worth of availableHeight can't
      // hold them all on one physical page.
      final doc = _docWith(
        List.generate(40, (i) => DocxParagraph(children: [DocxText('P$i')])),
        section: const DocxSectionDef(columnCount: 2),
      );

      final generator = DocxWidgetGenerator(config: config);
      final pages = generator.generateWidgets(doc);

      expect(pages.length, greaterThan(1),
          reason: 'column-aware pagination must advance to a new physical '
              'page once both columns of the current one are full');

      // The last paragraph must not have been crammed onto page 0 - real
      // pagination deferred it to a later page.
      final lastMarkerPage = await _pageIndexContaining(tester, pages, 'P39');
      expect(lastMarkerPage, greaterThan(0));
    });
  });
}
