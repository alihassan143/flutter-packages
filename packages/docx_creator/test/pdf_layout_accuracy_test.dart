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
