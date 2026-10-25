// Regression test: paged mode must flow an oversized paragraph/list/table
// across multiple pages instead of letting it overflow a single page's
// Container. Before this fix, DocxWidgetGenerator bucketed whole elements
// by estimated height, so anything taller than one page just overflowed.
import 'package:docx_creator/docx_creator.dart';
import 'package:docx_file_viewer/src/docx_view_config.dart';
import 'package:docx_file_viewer/src/widget_generator/docx_widget_generator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DocxBuiltDocument _docWith(List<DocxNode> elements) => DocxBuiltDocument(
      elements: elements,
      footnotes: [],
      endnotes: [],
      theme: DocxTheme(colors: DocxThemeColors(), fonts: DocxThemeFonts()),
    );

Future<void> _pump(WidgetTester tester, Widget page) {
  return tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: page))));
}

void main() {
  testWidgets('an oversized paragraph is split across pages, not overflowed',
      (tester) async {
    final words = List.generate(200, (i) => 'WORD$i');
    final doc = _docWith([
      DocxParagraph(
          children: [DocxText(words.join(' '), fontSize: 20)]),
    ]);

    const config =
        DocxViewConfig(pageMode: DocxPageMode.paged, pageWidth: 300, pageHeight: 400);
    final generator = DocxWidgetGenerator(config: config);
    final pages = generator.generateWidgets(doc);

    expect(pages.length, greaterThan(1));

    await _pump(tester, pages.first);
    expect(find.textContaining('WORD0'), findsWidgets);
    expect(find.textContaining('WORD199'), findsNothing);

    await _pump(tester, pages.last);
    expect(find.textContaining('WORD199'), findsWidgets);
  });

  testWidgets('an oversized list is split between items, not overflowed',
      (tester) async {
    final items = List.generate(
        60, (i) => DocxListItem.text('Item number $i with some filler text'));
    final doc = _docWith([DocxList(items: items)]);

    const config =
        DocxViewConfig(pageMode: DocxPageMode.paged, pageWidth: 300, pageHeight: 400);
    final generator = DocxWidgetGenerator(config: config);
    final pages = generator.generateWidgets(doc);

    expect(pages.length, greaterThan(1));

    await _pump(tester, pages.first);
    expect(find.textContaining('Item number 0 '), findsWidgets);
    expect(find.textContaining('Item number 59 '), findsNothing);

    await _pump(tester, pages.last);
    expect(find.textContaining('Item number 59 '), findsWidgets);
  });

  testWidgets('an oversized table is split between rows, not overflowed',
      (tester) async {
    final rows = List.generate(
        60,
        (i) => DocxTableRow(cells: [
              DocxTableCell(children: [
                DocxParagraph(
                    children: [DocxText('Row $i cell content here')])
              ]),
            ]));
    final doc = _docWith([DocxTable(rows: rows)]);

    const config =
        DocxViewConfig(pageMode: DocxPageMode.paged, pageWidth: 300, pageHeight: 400);
    final generator = DocxWidgetGenerator(config: config);
    final pages = generator.generateWidgets(doc);

    expect(pages.length, greaterThan(1));

    await _pump(tester, pages.first);
    expect(find.textContaining('Row 0 cell'), findsWidgets);
    expect(find.textContaining('Row 59 cell'), findsNothing);

    await _pump(tester, pages.last);
    expect(find.textContaining('Row 59 cell'), findsWidgets);
  });

  test('DocxWidgetGenerator yields a single page for short content', () {
    const config =
        DocxViewConfig(pageMode: DocxPageMode.paged, pageWidth: 794);
    final generator = DocxWidgetGenerator(config: config);
    final doc = _docWith(
        [DocxParagraph(children: [DocxText('Short paragraph.')])]);

    final widgets = generator.generateWidgets(doc);

    expect(widgets.length, 1);
  });
}
