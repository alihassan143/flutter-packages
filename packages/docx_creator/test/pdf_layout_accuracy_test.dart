import 'dart:typed_data';
import 'dart:convert';

import 'package:docx_creator/docx_creator.dart';
import 'package:test/test.dart';

/// Uncompressed content streams of every page, in order.
List<String> _pageStreams(DocxBuiltDocument doc) {
  final pdf = latin1.decode(
      PdfExporter(compressContent: false).exportToBytes(doc),
      allowInvalid: true);
  return RegExp(r'stream\r?\n([\s\S]*?)endstream')
      .allMatches(pdf)
      .map((m) => m.group(1)!)
      .where((s) => s.contains(' Tj'))
      .toList();
}

/// The literal strings drawn with `Tj`, in drawing order.
List<String> _shownStrings(String content) =>
    RegExp(r'\(((?:\\.|[^\\)])*)\) Tj')
        .allMatches(content)
        .map((m) => m.group(1)!)
        .toList();

/// Baseline y of every text matrix set in [content].
Iterable<double> _textYs(String content) =>
    RegExp(r'1 0 0 1 [\d.-]+ ([\d.-]+) Tm')
        .allMatches(content)
        .map((m) => double.parse(m.group(1)!));

void main() {
  group('Inline runs', () {
    test('runs without whitespace between them are not separated', () {
      final doc = docx()
          .add(DocxParagraph(children: [
            DocxText('Word'),
            DocxText.bold('glued'),
            DocxText('together. H'),
            DocxText('2', isSubscript: true),
            DocxText('O'),
          ]))
          .build();
      final shown = _shownStrings(_pageStreams(doc).single);
      // No separating space glyph is drawn inside a glued group.
      expect(shown.join('|'), contains('Word|glued|together.|'));
      expect(shown.join('|'), contains('H|2|O'));
    });

    test('whitespace at a run boundary still separates words', () {
      final doc = docx()
          .add(DocxParagraph(children: [
            DocxText('one '),
            DocxText.bold('two'),
          ]))
          .build();
      expect(_shownStrings(_pageStreams(doc).single).join('|'),
          contains('one| |two'));
    });

    test('runs of spaces keep their width (code indentation)', () {
      final doc = docx()
          .add(DocxParagraph(children: [
            DocxText('a'),
            DocxLineBreak(),
            DocxText('    b'),
          ]))
          .build();
      final content = _pageStreams(doc).single;
      final xs = RegExp(
              r'1 0 0 1 ([\d.]+) [\d.-]+ Tm\n/F\w+ [\d.]+ Tf\n[\d. ]+rg\n\((a|b)\) Tj')
          .allMatches(content)
          .map((m) => double.parse(m.group(1)!))
          .toList();
      expect(xs, hasLength(2));
      expect(xs[1] - xs[0], greaterThan(10)); // 4 spaces of indentation
    });
  });

  group('Pagination', () {
    test('no text is drawn below the bottom margin on any page', () {
      final builder = docx();
      for (var i = 0; i < 60; i++) {
        builder.add(DocxParagraph.heading2('Section $i'));
        builder.add(DocxParagraph(
          lineSpacing: 360,
          lineRule: 'auto',
          children: [
            DocxText.bold('Bold lead-in text that is noticeably wider. '),
            DocxText('Body ${'words ' * 40}'),
          ],
        ));
        builder.add(DocxList(
            items: [DocxListItem.text('item a'), DocxListItem.text('item b')]));
      }
      final pages = _pageStreams(builder.build());
      expect(pages.length, greaterThan(5));
      for (final page in pages) {
        for (final y in _textYs(page)) {
          // Default bottom margin is 72pt; allow for descenders.
          expect(y, greaterThan(72 - 4));
        }
      }
    });

    test('a paragraph split across pages keeps every word exactly once', () {
      final words = List.generate(900, (i) => 'w$i');
      final doc = docx()
          .add(DocxParagraph(children: [
            DocxText('${words.take(450).join(' ')} '),
            DocxText.bold(words.skip(450).join(' ')),
          ]))
          .build();
      final pages = _pageStreams(doc);
      expect(pages.length, greaterThan(1));
      final shown = pages
          .expand(_shownStrings)
          .where((s) => s.trim().isNotEmpty)
          .toList();
      expect(shown, words);
    });

    test('long lists continue on the next page with their numbering', () {
      final doc = docx()
          .add(DocxList(
              isOrdered: true,
              items: List.generate(120, (i) => DocxListItem.text('entry $i'))))
          .build();
      final pages = _pageStreams(doc);
      expect(pages.length, greaterThan(1));
      final markers = pages
          .expand(_shownStrings)
          .where((s) => RegExp(r'^\d+\.$').hasMatch(s))
          .toList();
      expect(markers, List.generate(120, (i) => '${i + 1}.'));
    });
  });

  group('Lists', () {
    test('default numbering cycles 1 / a / i by level', () {
      final doc = docx()
          .add(DocxList(isOrdered: true, items: [
            DocxListItem.text('one'),
            DocxListItem.text('nested', level: 1),
            DocxListItem.text('deeper', level: 2),
            DocxListItem.text('two'),
          ]))
          .build();
      final shown = _shownStrings(_pageStreams(doc).single);
      expect(shown.where((s) => s.endsWith('.')).toList(),
          ['1.', 'a.', 'i.', '2.']);
    });

    test('a custom number format is used', () {
      final doc = docx()
          .add(DocxList(
              isOrdered: true,
              style: DocxListStyle.upperRoman,
              items: [DocxListItem.text('x'), DocxListItem.text('y')]))
          .build();
      final shown = _shownStrings(_pageStreams(doc).single);
      expect(shown, containsAllInOrder(['I.', 'II.']));
    });
  });

  group('Tables', () {
    test('grid column count accounts for colSpan in the first row', () {
      final table = DocxTable(rows: [
        DocxTableRow(cells: [
          DocxTableCell(colSpan: 2, children: [DocxParagraph.text('Name')]),
          DocxTableCell(children: [DocxParagraph.text('Score')]),
        ]),
        DocxTableRow(cells: [
          DocxTableCell(children: [DocxParagraph.text('a')]),
          DocxTableCell(children: [DocxParagraph.text('b')]),
          DocxTableCell(children: [DocxParagraph.text('1')]),
        ]),
      ]);
      expect(table.resolvedGridColumns, hasLength(3));
      final shown =
          _shownStrings(_pageStreams(docx().add(table).build()).single);
      expect(shown, containsAll(['Name', 'Score', 'a', 'b', '1']));
    });
  });

  group('HTML parsing', () {
    test('list type, link colour, cell alignment and spacing are kept',
        () async {
      final nodes = await DocxParser.fromHtml('''
        <ol type="a"><li>x</li></ol>
        <ul style="list-style-type: square"><li>y</li></ul>
        <p style="line-height: 2; margin-bottom: 20pt">a <a href="https://x.dev">link</a></p>
        <table><tr><th>H</th><td style="text-align: right" valign="top">9</td></tr></table>
        <div style="background: #eaf2f8 none">box</div>
        <p style="text-transform: uppercase">caps</p>
      ''');
      final lists = nodes.whereType<DocxList>().toList();
      expect(lists[0].style.numberFormat, DocxNumberFormat.lowerAlpha);
      expect(lists[1].style.bullet, DocxListStyle.square.bullet);

      final paragraphs = nodes.whereType<DocxParagraph>().toList();
      final p = paragraphs.first;
      expect(p.lineSpacing, 480);
      expect(p.lineRule, 'auto');
      expect(p.spacingAfter, 400);
      final link = p.children.whereType<DocxText>().last;
      expect(link.href, 'https://x.dev');
      expect(link.effectiveColorHex, '0563C1');

      final cells = nodes.whereType<DocxTable>().single.rows.single.cells;
      expect(
          (cells[0].children.single as DocxParagraph).align, DocxAlign.center);
      expect(
          (cells[1].children.single as DocxParagraph).align, DocxAlign.right);
      expect(cells[1].verticalAlign, DocxVerticalAlign.top);

      expect(paragraphs[1].shadingFill?.toUpperCase(), 'EAF2F8');
      expect((paragraphs[2].children.single as DocxText).isAllCaps, isTrue);
    });
  });

  group('Review fixes', () {
    test('row heights use span-aware columns and the table cell padding', () {
      final longText = 'word ' * 40;
      final table = DocxTable(
        gridColumns: const [8000, 1200],
        rows: [
          DocxTableRow(cells: [
            DocxTableCell(
                rowSpan: 2, children: [DocxParagraph.text('spanning')]),
            DocxTableCell(children: [DocxParagraph.text('b')]),
          ]),
          // The only cell of row 2 sits in the narrow second column.
          DocxTableRow(cells: [
            DocxTableCell(children: [DocxParagraph.text(longText)]),
          ]),
        ],
      );
      final exporter = PdfExporter();
      final heights = exporter.measureTableRowHeights(table, [400, 60]);
      final wide = exporter.measureTableRowHeights(
          DocxTable(rows: [
            DocxTableRow(cells: [
              DocxTableCell(children: [DocxParagraph.text(longText)])
            ])
          ]),
          [400]).single;
      // Measured in the narrow column it is drawn in, not in column 0.
      expect(heights[1], greaterThan(wide * 3));

      DocxTable padded(int? padding) => DocxTable(
            style: DocxTableStyle(cellPadding: padding),
            rows: [
              DocxTableRow(cells: [
                DocxTableCell(children: [DocxParagraph.text(longText)])
              ])
            ],
          );
      expect(
          exporter.measureTableRowHeights(padded(1440), [200]).single,
          greaterThan(
              exporter.measureTableRowHeights(padded(null), [200]).single));
    });

    test('tables never page-break inside a rowSpan group', () {
      final rows = <DocxTableRow>[];
      for (var i = 0; i < 80; i++) {
        rows.add(DocxTableRow(cells: [
          if (i % 5 == 0)
            DocxTableCell(rowSpan: 5, children: [DocxParagraph.text('g$i')]),
          DocxTableCell(children: [DocxParagraph.text('r$i')]),
        ]));
      }
      final pages = _pageStreams(docx().add(DocxTable(rows: rows)).build());
      expect(pages.length, greaterThan(1));
      for (final page in pages.skip(1)) {
        final firstRow = _shownStrings(page)
            .firstWhere((s) => RegExp(r'^r\d+$').hasMatch(s), orElse: () => '');
        if (firstRow.isEmpty) continue;
        expect(int.parse(firstRow.substring(1)) % 5, 0,
            reason: 'page starts mid-group at $firstRow');
      }
    });

    test('text-align is inherited, and explicit left survives in cells',
        () async {
      final nodes = await DocxParser.fromHtml(
          '<div style="text-align:center"><p>inherited</p></div>'
          '<table><tr><td style="text-align:center">'
          '<p style="text-align:left">explicit</p><p>cell</p>'
          '</td></tr></table>');
      expect(nodes.whereType<DocxParagraph>().first.align, DocxAlign.center);
      final cellParas = nodes
          .whereType<DocxTable>()
          .single
          .rows
          .single
          .cells
          .single
          .children
          .whereType<DocxParagraph>()
          .toList();
      expect(cellParas[0].align, DocxAlign.left);
      expect(cellParas[1].align, DocxAlign.center);
    });

    test('margin shorthand and longhands apply in declaration order', () async {
      final nodes =
          await DocxParser.fromHtml('<p style="margin-top:24px;margin:0">a</p>'
              '<p style="margin:0;margin-top:12pt">b</p>');
      final ps = nodes.whereType<DocxParagraph>().toList();
      expect(ps[0].spacingBefore, 0);
      expect(ps[1].spacingBefore, 240);
      expect(ps[1].spacingAfter, 0);
    });

    test('HSL link colors, list-style none and lowercase', () async {
      final nodes = await DocxParser.fromHtml(
          '<p><a href="https://x.dev" style="color: hsl(0, 100%, 50%)">red</a></p>'
          '<ol style="list-style-type: none"><li>x</li></ol>'
          '<p style="text-transform: lowercase">ABC</p>');
      final link = nodes
          .whereType<DocxParagraph>()
          .first
          .children
          .whereType<DocxText>()
          .single;
      expect(link.effectiveColorHex?.toUpperCase(), 'FF0000');

      final list = nodes.whereType<DocxList>().single;
      expect(list.style.bullet, '');
      expect(list.isOrdered, isFalse);
      final shown = _shownStrings(
          _pageStreams(DocxBuiltDocument(elements: [list])).single);
      expect(shown.where((s) => s.trim().isNotEmpty), ['x']);

      final lower = nodes
          .whereType<DocxParagraph>()
          .last
          .children
          .whereType<DocxText>()
          .single;
      expect(lower.content, 'abc');
    });
  });

  group('Pagination edge cases', () {
    test('a line taller than a page does not hang pagination', () {
      final doc = docx()
          .add(DocxParagraph(children: [
            DocxText('Figure:'),
            DocxLineBreak(),
            DocxInlineImage(
                bytes: Uint8List(0), extension: 'png', width: 50, height: 900),
            DocxLineBreak(),
            DocxText('after'),
          ]))
          .build();
      final pages = _pageStreams(doc);
      expect(pages.expand(_shownStrings), containsAll(['Figure:', 'after']));
    });

    test('an over-tall list item is placed alone, the rest continues', () {
      final doc = docx()
          .add(DocxList(isOrdered: true, items: [
            DocxListItem.text('short'),
            DocxListItem([
              DocxInlineImage(
                  bytes: Uint8List(0), extension: 'png', width: 50, height: 900)
            ]),
            for (var i = 0; i < 5; i++) DocxListItem.text('tail $i'),
          ]))
          .build();
      final pages = _pageStreams(doc);
      // The tail items must not be drawn on the page of the huge item.
      final lastPage =
          _shownStrings(pages.last).where((s) => s.trim().isNotEmpty).join(' ');
      expect(lastPage, contains('tail 4'));
      expect(pages.length, greaterThanOrEqualTo(3));
    });

    test('a table whose first row does not fit moves to the next page', () {
      final builder = docx();
      for (var i = 0; i < 40; i++) {
        builder.add(DocxParagraph.text('filler $i'));
      }
      builder.add(DocxTable(rows: [
        DocxTableRow(cells: [
          DocxTableCell(children: [
            for (var i = 0; i < 25; i++) DocxParagraph.text('cell line $i')
          ])
        ]),
      ]));
      final pages = _pageStreams(builder.build());
      String words(String page) =>
          _shownStrings(page).where((w) => w.trim().isNotEmpty).join(' ');
      final tablePage =
          pages.indexWhere((p) => words(p).contains('cell line 0 '));
      expect(tablePage, greaterThan(0));
      // The whole row moved to the fresh page instead of overflowing.
      expect(words(pages[tablePage]), contains('cell line 24'));
      for (final y in _textYs(pages[tablePage])) {
        expect(y, greaterThan(72 - 4));
      }
    });

    test('no-break spaces keep their words on one line', () {
      final doc = docx()
          .add(DocxParagraph(children: [
            DocxText('${'x' * 90} Mr. Smith'),
          ]))
          .build();
      final shown = _shownStrings(_pageStreams(doc).single);
      expect(shown, contains('Mr. Smith'));
    });

    test('a list split inside a sub-list keeps its nested numbering', () {
      final items = <DocxListItem>[];
      for (var i = 0; i < 70; i++) {
        items.add(DocxListItem.text('sub $i', level: 1));
      }
      final doc = docx()
          .add(DocxList(
              isOrdered: true, items: [DocxListItem.text('top'), ...items]))
          .build();
      final pages = _pageStreams(doc);
      expect(pages.length, greaterThan(1));
      final markers = pages
          .expand(_shownStrings)
          .where((s) => RegExp(r'^[a-z]+\.$').hasMatch(s))
          .toList();
      // 70 distinct letters: a..z, aa..az, ba..br - never restarting.
      expect(markers.toSet().length, 70);
      expect(markers.first, 'a.');
      expect(markers.last, 'br.');
    });
  });

  test('reading a DOCX keeps nested list indentation per level', () async {
    final doc = docx()
        .add(DocxList(isOrdered: true, items: [
          DocxListItem.text('top'),
          DocxListItem.text('nested', level: 1),
        ]))
        .build();
    final bytes = await DocxExporter().exportToBytes(doc);
    final read = await DocxReader.loadFromBytes(bytes);
    final list = read.elements.whereType<DocxList>().single;
    final nested = list.items[1];
    final style = nested.overrideStyle ?? list.style;
    // Level 1 sits at 1440 twips = indentPerLevel * (level + 1).
    expect(style.indentPerLevel * (nested.level + 1), 1440);
  });
}
