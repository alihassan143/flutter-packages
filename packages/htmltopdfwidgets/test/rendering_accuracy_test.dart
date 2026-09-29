import 'package:htmltopdfwidgets/htmltopdfwidgets.dart';
import 'package:htmltopdfwidgets/src/browser/css_style.dart';
import 'package:htmltopdfwidgets/src/browser/html_parser.dart';
import 'package:htmltopdfwidgets/src/browser/render_node.dart';
import 'package:test/test.dart';

/// Every [RichText] reachable from [widgets], in document order.
List<RichText> _richTexts(List<Widget> widgets) {
  final out = <RichText>[];
  void walk(Widget? w) {
    if (w == null || w is Text) return; // Text = list markers
    if (w is RichText) {
      out.add(w);
    } else if (w is Table) {
      for (final row in w.children) {
        row.children.forEach(walk);
      }
    } else if (w is MultiChildWidget) {
      w.children.forEach(walk);
    } else if (w is Container) {
      walk(w.child);
    } else if (w is SingleChildWidget) {
      walk(w.child);
    }
  }

  widgets.forEach(walk);
  return out;
}

List<TextSpan> _textSpans(InlineSpan span) {
  final out = <TextSpan>[];
  void walk(InlineSpan s) {
    if (s is TextSpan) {
      if (s.text != null) out.add(s);
      s.children?.forEach(walk);
    }
  }

  walk(span);
  return out;
}

String _plain(RichText rt) => _textSpans(rt.text).map((s) => s.text).join();

Future<List<String>> _lines(String html) async {
  final widgets = await HTMLToPdf().convert(html);
  return _richTexts(widgets).map(_plain).toList();
}

RenderNode _find(RenderNode node, String tag) {
  if (node.tagName == tag) return node;
  for (final c in node.children) {
    try {
      return _find(c, tag);
    } on StateError {
      continue;
    }
  }
  throw StateError('no <$tag>');
}

void main() {
  group('Whitespace', () {
    test('adjacent inline elements are not separated by invented spaces',
        () async {
      expect(await _lines('<p>Word<b>glued</b>together.</p>'),
          ['Wordgluedtogether.']);
    });

    test('whitespace between inline elements is kept as one space', () async {
      expect(await _lines('<p><b>a</b> <i>b</i>\n   <u>c</u></p>'), ['a b c']);
    });

    test('<br> inside a paragraph becomes a line break', () async {
      expect(await _lines('<p>one<br>two</p>'), ['one\ntwo']);
    });

    test('<pre> keeps spaces and newlines', () async {
      final lines = await _lines('<pre>a  b\n  c</pre>');
      expect(lines, ['a  b\n  c']);
    });
  });

  group('Lists', () {
    test('nested lists are not flattened into the parent item text', () async {
      final lines = await _lines(
          '<ul><li>Parent<ul><li>Child</li></ul></li><li>Next</li></ul>');
      expect(lines, containsAllInOrder(['Parent', 'Child', 'Next']));
      expect(lines.any((l) => l.contains('Parent') && l.contains('Child')),
          isFalse);
    });

    test('ordered list honours type and start', () async {
      final widgets = await HTMLToPdf()
          .convert('<ol type="a" start="3"><li>x</li><li>y</li></ol>'
              '<ol type="I"><li>x</li><li>y</li></ol>');
      final markers = <String>[];
      void walk(Widget? w) {
        if (w is Text) {
          markers.add(_plain(w));
        } else if (w is Table) {
          for (final r in w.children) {
            r.children.forEach(walk);
          }
        } else if (w is MultiChildWidget) {
          w.children.forEach(walk);
        } else if (w is SingleChildWidget) {
          walk(w.child);
        }
      }

      widgets.forEach(walk);
      expect(markers, ['c.', 'd.', 'I.', 'II.']);
    });
  });

  group('Inline formatting', () {
    test('links keep their annotation on nested formatting', () async {
      final widgets = await HTMLToPdf()
          .convert('<p><a href="https://x.dev">go <b>bold</b></a></p>');
      final spans = _textSpans(_richTexts(widgets).single.text);
      final bold = spans.firstWhere((s) => s.text == 'bold');
      expect(bold.annotation, isA<AnnotationUrl>());
    });

    test('sub/sup shift the baseline', () async {
      final widgets =
          await HTMLToPdf().convert('<p>H<sub>2</sub>O x<sup>2</sup></p>');
      final spans = _textSpans(_richTexts(widgets).single.text);
      expect(spans.firstWhere((s) => s.text == '2').baseline, lessThan(0));
      expect(spans.lastWhere((s) => s.text == '2').baseline, greaterThan(0));
    });

    test('text-transform is applied', () async {
      expect(await _lines('<p style="text-transform: uppercase">abc</p>'),
          ['ABC']);
    });
  });

  group('CSS parsing', () {
    test('CSS named colors use spec values', () {
      expect(
          CSSStyle.parse('color: navy').color, const PdfColor(0, 0, 128 / 255));
      expect(CSSStyle.parse('color: rebeccapurple').color,
          PdfColor.fromHex('#663399'));
    });

    test('hsl, rgb percentages and short hex parse', () {
      final c = CSSStyle.parse('color: hsl(0, 100%, 50%)').color!;
      expect([c.red, c.green, c.blue], [1.0, 0.0, 0.0]);
      expect(CSSStyle.parse('color: rgb(100%, 0%, 0%)').color!.red, 1.0);
      expect(CSSStyle.parse('color: #0f0').color!.green, 1.0);
    });

    test('longhand margin only overrides its own side', () {
      final base = CSSStyle.parse('margin: 10pt');
      final merged = base.merge(CSSStyle.parse('margin-top: 2pt'));
      expect(merged.margin!.top, 2);
      expect(merged.margin!.bottom, 10);
      expect(merged.margin!.left, 10);
    });

    test('per-side borders and border: none', () {
      final style = CSSStyle.parse('border-bottom: 2px dashed red');
      expect(style.resolvedBorder!.bottom.width, 1.5);
      expect(style.resolvedBorder!.top.style.paint, isFalse);
      expect(CSSStyle.parse('border: none').resolvedBorder, isNull);
    });

    test('numeric font weights and !important', () {
      expect(CSSStyle.parse('font-weight: 600').fontWeight, FontWeight.bold);
      expect(CSSStyle.parse('font-weight: 300').fontWeight, FontWeight.normal);
      expect(CSSStyle.parse('font-weight: bold !important').fontWeight,
          FontWeight.bold);
    });

    test('em font sizes are relative to the parent', () {
      final root = HtmlParser(
              htmlString:
                  '<div style="font-size: 20pt"><span style="font-size: 1.5em">x</span></div>')
          .parse();
      expect(_find(root, 'span').style.fontSize, 30);
    });

    test('unitless line-height is inherited as a factor', () {
      final root = HtmlParser(
              htmlString:
                  '<div style="line-height: 2"><p style="font-size: 20pt">x</p></div>')
          .parse();
      final p = _find(root, 'p');
      expect(p.style.lineHeightFactor, 2);
      expect(p.style.fontSize, 20);
    });
  });

  group('Stylesheets', () {
    RenderNode parse(String html) => HtmlParser(htmlString: html).parse();

    test('descendant and child combinators', () {
      final root = parse('''
        <style>div p { color: #ff0000 } section > span { color: #00ff00 }</style>
        <div><article><p>a</p></article></div>
        <section><em><span>b</span></em></section>''');
      expect(_find(root, 'p').style.color, const PdfColor(1, 0, 0));
      expect(_find(root, 'span').style.color, isNot(const PdfColor(0, 1, 0)));
    });

    test('specificity and !important order the cascade', () {
      final root = parse('''
        <style>
          #id { color: #0000ff }
          p.c { color: #00ff00 }
          p { color: #ff0000; font-weight: bold !important }
        </style>
        <p class="c" id="id" style="font-weight: normal">x</p>''');
      final p = _find(root, 'p');
      expect(p.style.color, const PdfColor(0, 0, 1));
      expect(p.style.fontWeight, FontWeight.bold);
    });

    test('multi-value declarations are not truncated', () {
      final root = parse(
          '<style>.box { margin: 4pt 8pt; border: 1pt solid #000 }</style><div class="box">x</div>');
      final div = _find(root, 'div');
      expect(div.style.margin!.left, 8);
      expect(div.style.resolvedBorder!.top.width, 1);
    });

    test('structural pseudo-classes and attribute selectors', () {
      final root = parse('''
        <style>li:first-child { color: #ff0000 } a[href^="https"] { color: #00ff00 }</style>
        <ul><li>a</li><li>b</li></ul><a href="https://x">l</a>''');
      final ul = _find(root, 'ul');
      final items = ul.children.where((c) => c.tagName == 'li').toList();
      expect(items[0].style.color, const PdfColor(1, 0, 0));
      expect(items[1].style.color, isNot(const PdfColor(1, 0, 0)));
      expect(_find(root, 'a').style.color, const PdfColor(0, 1, 0));
    });
  });

  group('Tables', () {
    test('colspan keeps cell content in a single spanning cell', () async {
      final widgets = await HTMLToPdf().convert('''
        <table>
          <tr><th colspan="2">Head</th></tr>
          <tr><td>a</td><td>b</td></tr>
        </table>''');
      expect(_richTexts(widgets).map(_plain).toList(), ['Head', 'a', 'b']);
      final tables = <Table>[];
      void walk(Widget? w) {
        if (w is Table) tables.add(w);
        if (w is SingleChildWidget) walk(w.child);
        if (w is Container) walk(w.child);
      }

      widgets.forEach(walk);
      expect(tables.first.children.single.children, hasLength(1));
      expect(tables.last.children.single.children, hasLength(2));
    });

    test('block content in cells is rendered, not flattened', () async {
      final lines = await _lines(
          '<table><tr><td><p>one</p><ul><li>two</li></ul></td></tr></table>');
      expect(lines, ['one', 'two']);
    });
  });

  group('Review fixes', () {
    RenderNode parse(String html) => HtmlParser(htmlString: html).parse();

    test('a rule after @import/@charset is not dropped', () {
      final root = parse('<style>@charset "utf-8"; @import url(x.css); '
          'p { color: #ff0000 }</style><p>x</p>');
      expect(_find(root, 'p').style.color, const PdfColor(1, 0, 0));
    });

    test('&nbsp; is kept (spacer paragraphs and indentation)', () async {
      expect(await _lines('<p>&nbsp;</p>'), [' ']);
      expect(
          await _lines('<p><b>a</b>&nbsp;&nbsp;&nbsp;<b>b</b></p>'), ['a   b']);
    });

    test('nested lists get their own default marker type', () {
      final root = parse('<ul style="list-style-type: square"><li>x'
          '<ol><li>y<ul><li>z</li></ul></li></ol></li></ul>');
      expect(_find(root, 'ol').style.listStyleType, 'decimal');
      // ul inside ul/ol ancestors (depth 2) cycles to "square".
      final inner = _find(_find(root, 'ol'), 'ul');
      expect(inner.style.listStyleType, 'square');
      expect(
          parse('<ul><li><ul><li>a</li></ul></li></ul>')
              .children
              .first
              .children
              .first
              .children
              .firstWhere((c) => c.tagName == 'ul')
              .style
              .listStyleType,
          'circle');
    });

    test('margin-left/right: auto centers the block', () {
      expect(
          CSSStyle.parse('width: 100pt; margin-left: auto; margin-right: auto')
              .centerHorizontally,
          isTrue);
      expect(CSSStyle.parse('margin-left: auto').centerHorizontally, isNull);
    });

    test('<hr> uses the first visible border side', () async {
      final widgets = await HTMLToPdf()
          .convert('<hr style="border: 0; border-top: 2pt solid #ff0000">');
      Divider? divider;
      void walk(Widget? w) {
        if (w is Divider) divider = w;
        if (w is SingleChildWidget) walk(w.child);
      }

      widgets.forEach(walk);
      expect(divider, isNotNull);
      expect(divider!.thickness, 2);
      expect(divider!.color, const PdfColor(1, 0, 0));
    });
  });

  group('Review fixes (round 2)', () {
    RenderNode parse(String html) => HtmlParser(htmlString: html).parse();

    test('a table cell longer than a page still paginates', () async {
      final long = 'Lorem ipsum dolor sit amet, consectetur. ' * 400;
      final widgets = await HTMLToPdf()
          .convert('<table><tr><td>$long</td><td>side</td></tr></table>');
      final doc = Document()..addPage(MultiPage(build: (_) => widgets));
      expect(await doc.save(), isNotEmpty);
      final table = widgets.whereType<Table>().single;
      expect(table.children.length, greaterThan(1)); // split into rows
    });

    test('explicit widths in span mode are not treated as flex weights',
        () async {
      final widgets = await HTMLToPdf().convert(
          '<table><tr><th colspan="2">Head</th></tr>'
          '<tr><td width="80">A</td><td>${'long text ' * 20}</td></tr></table>');
      final rowTable = widgets.whereType<Table>().last;
      final widths = rowTable.columnWidths!;
      final a = (widths[0] as FlexColumnWidth).flex;
      final b = (widths[1] as FlexColumnWidth).flex;
      // 80px = 60pt of ~480pt: the text column must get most of the width.
      expect(b, greaterThan(a * 3));
    });

    test('empty bordered or padded divs are still drawn', () async {
      final widgets = await HTMLToPdf()
          .convert('<p>a</p><div style="border-bottom:1px solid #ccc"></div>'
              '<div style="padding:10px;background:#eee"></div><p>b</p>');
      final boxes = widgets.whereType<Container>().toList();
      expect(boxes, hasLength(2));
    });

    test('@media width queries are evaluated for a printed page', () {
      final root = parse('<style>'
          '@media (max-width: 600px) { p { color: #ff0000 } }'
          '@media print and (min-width: 500px) { p { font-weight: bold } }'
          '@media screen { p { font-style: italic } }'
          '</style><p>x</p>');
      final p = _find(root, 'p');
      expect(p.style.color, isNot(const PdfColor(1, 0, 0)));
      expect(p.style.fontWeight, FontWeight.bold);
      expect(p.style.fontStyle, isNot(FontStyle.italic));
    });

    test('max-width caps without stretching', () {
      final style = CSSStyle.parse('max-width: 400px');
      expect(style.width, isNull);
      expect(style.maxWidth, 300);
    });
  });

  test('a mixed document lays out into a multi-page PDF', () async {
    final buffer = StringBuffer('<h1>Title</h1>');
    for (var i = 0; i < 40; i++) {
      buffer.write('<p>Paragraph $i with <b>bold</b> and <a href="#">link</a>.'
          ' ${'Lorem ipsum dolor sit amet. ' * 8}</p>');
      buffer.write('<ul><li>item<ul><li>nested</li></ul></li></ul>');
      buffer.write('<div style="background:#eee;border:1px solid #ccc;'
          'padding:4pt">box $i</div>');
    }
    final widgets = await HTMLToPdf().convert(buffer.toString());
    final doc = Document()..addPage(MultiPage(build: (_) => widgets));
    final bytes = await doc.save();
    expect(bytes.length, greaterThan(1000));
  });
}
