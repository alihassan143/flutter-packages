import 'package:htmltopdfwidgets/htmltopdfwidgets.dart';
import 'package:test/test.dart';

/// Issue #44: MathML `<math>` support (fractions and friends).
void main() {
  List<Widget> flatten(List<Widget> widgets) {
    final out = <Widget>[];
    void walk(Widget? w) {
      if (w == null) return;
      out.add(w);
      if (w is RichText) {
        void spans(InlineSpan s) {
          if (s is WidgetSpan) walk(s.child);
          if (s is TextSpan) s.children?.forEach(spans);
        }

        spans(w.text);
      } else if (w is Table) {
        for (final r in w.children) {
          r.children.forEach(walk);
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

  String texts(List<Widget> all) => all
      .whereType<Text>()
      .map((t) => (t.text as TextSpan).text ?? '')
      .join('|');

  test('an inline fraction is a stacked numerator/denominator in the text',
      () async {
    final widgets = await HTMLToPdf().convert(
        '<p>Half is <math><mfrac><mn>1</mn><mn>2</mn></mfrac></math>.</p>');
    final richText = widgets.whereType<RichText>().single;
    final spans = <InlineSpan>[];
    void collect(InlineSpan s) {
      spans.add(s);
      if (s is TextSpan) s.children?.forEach(collect);
    }

    collect(richText.text);
    final mathSpan = spans.whereType<WidgetSpan>().single;
    // The formula is lowered so its baseline meets the text baseline.
    expect(mathSpan.baseline, lessThan(0));

    final all = flatten(widgets);
    final fraction = all.whereType<Table>().first;
    expect(fraction.children, hasLength(2)); // numerator, denominator
    expect(fraction.border?.horizontalInside, isNotNull); // fraction bar
    expect(texts(all), contains('1|2'));
  });

  test('display math renders centered on its own line', () async {
    final widgets = await HTMLToPdf()
        .convert('<p>Before</p><math display="block"><mi>x</mi><mo>=</mo>'
            '<mfrac><mrow><mo>-</mo><mi>b</mi></mrow><mn>2</mn></mfrac></math>'
            '<p>After</p>');
    expect(widgets.whereType<Align>(), isNotEmpty);
    final all = flatten(widgets);
    expect(texts(all), contains('x|=|-|b|2'));
  });

  test('scripts, roots, under/over, fences and tables all lay out', () async {
    const html = '''
      <p><math><msup><mi>x</mi><mn>2</mn></msup><mo>+</mo>
        <msub><mi>y</mi><mi>i</mi></msub><mo>+</mo>
        <msubsup><mi>a</mi><mi>i</mi><mn>2</mn></msubsup></math></p>
      <p><math><msqrt><mi>b</mi></msqrt><mroot><mi>x</mi><mn>3</mn></mroot>
        <munderover><mo>+</mo><mi>i</mi><mi>n</mi></munderover>
        <mfenced><mi>a</mi><mi>b</mi></mfenced></math></p>
      <math display="block"><mtable><mtr><mtd><mn>1</mn></mtd><mtd><mn>0</mn></mtd></mtr>
        <mtr><mtd><mn>0</mn></mtd><mtd><mn>1</mn></mtd></mtr></mtable></math>
    ''';
    final widgets = await HTMLToPdf().convert(html);
    final all = flatten(widgets);
    final shown = texts(all);
    for (final part in [
      'x|2',
      'y|i',
      'a|2|i',
      'b|3|x',
      '(|a|,|b|)',
      '1|0|0|1'
    ]) {
      expect(shown, contains(part));
    }
    expect(all.whereType<CustomPaint>(), hasLength(2)); // two radical signs

    final doc = Document()..addPage(MultiPage(build: (_) => widgets));
    expect(await doc.save(), isNotEmpty);
  });

  group('Review fixes', () {
    List<Text> textsOf(List<Widget> widgets) =>
        flatten(widgets).whereType<Text>().toList();
    String str(Text t) => (t.text as TextSpan).text ?? '';
    double sizeOf(Text t) => (t.text as TextSpan).style!.fontSize!;

    test('display fractions keep full size inside <semantics>', () async {
      final widgets = await HTMLToPdf().convert(
          '<math display="block"><semantics><mrow><mfrac><mn>1</mn><mn>2</mn>'
          '</mfrac></mrow><annotation encoding="TeX">x</annotation>'
          '</semantics></math>');
      final one = textsOf(widgets).firstWhere((t) => str(t) == '1');
      expect(sizeOf(one), 12);
    });

    test('glyphs missing from standard fonts get a fallback', () async {
      final widgets = await HTMLToPdf().convert(
          '<p><math><munderover><mo>&sum;</mo><mi>i</mi><mi>n</mi></munderover>'
          '<mi>&pi;</mi><mo>&le;</mo><mo>&minus;</mo></math></p>');
      final shown = textsOf(widgets).map(str).toList();
      expect(shown, containsAll(['pi', '<=', '-']));
      // The sum sign is drawn as a vector shape.
      expect(flatten(widgets).whereType<CustomPaint>(), isNotEmpty);
    });

    test('large operators outside <mo> fall back to Latin-1 text', () async {
      final widgets = await HTMLToPdf()
          .convert('<p><math><mi>&sum;</mi><mtext>&prod;</mtext><mi>&int;</mi>'
              '</math></p>');
      final shown = textsOf(widgets).map(str).toList();
      expect(shown, containsAll(['Sigma', 'Pi', 'int']));
      for (final s in shown) {
        expect(s.runes.every((r) => r <= 0xFF), isTrue,
            reason: '"$s" has a glyph the standard fonts lack');
      }
    });

    test('a binary operator after a closing fence keeps its spacing', () async {
      final widgets = await HTMLToPdf().convert(
          '<p><math><mo>(</mo><mi>a</mi><mo>)</mo><mo>+</mo><mi>b</mi></math></p>');
      final plus = flatten(widgets)
          .whereType<Padding>()
          .firstWhere((p) => p.child is Text && str(p.child as Text) == '+');
      expect((plus.padding as EdgeInsets).left, greaterThan(0));
    });

    test('linethickness units (0px) remove the bar', () async {
      final widgets = await HTMLToPdf().convert(
          '<p><math><mfrac linethickness="0px"><mi>n</mi><mi>k</mi></mfrac>'
          '</math></p>');
      final fraction = flatten(widgets).whereType<Table>().first;
      expect(fraction.border, isNull);
    });

    test('mathcolor and element CSS color apply to tokens', () async {
      final widgets = await HTMLToPdf()
          .convert('<p><math><mstyle mathcolor="red"><mi>r</mi></mstyle>'
              '<mi style="color:#00ff00">g</mi><mi>k</mi></math></p>');
      Text t(String s) => textsOf(widgets).firstWhere((x) => str(x) == s);
      expect((t('r').text as TextSpan).style!.color, const PdfColor(1, 0, 0));
      expect((t('g').text as TextSpan).style!.color, const PdfColor(0, 1, 0));
      expect((t('k').text as TextSpan).style!.color,
          isNot(const PdfColor(1, 0, 0)));
    });

    test('mlabeledtr rows are rendered', () async {
      final widgets = await HTMLToPdf().convert(
          '<math display="block"><mtable><mlabeledtr><mtd><mtext>(1)</mtext>'
          '</mtd><mtd><mi>x</mi></mtd></mlabeledtr></mtable></math>');
      expect(textsOf(widgets).map(str), containsAll(['(1)', 'x']));
    });

    test('mspace understands absolute units', () async {
      final widgets = await HTMLToPdf().convert(
          '<p><math><mi>a</mi><mspace width="1in"/><mi>b</mi></math></p>');
      final space = flatten(widgets)
          .whereType<SizedBox>()
          .firstWhere((s) => s.width != null && s.width! > 0);
      expect(space.width, 72);
    });

    test('display math is detected case-insensitively and via CSS', () async {
      for (final html in [
        '<math display="BLOCK"><mi>x</mi></math>',
        '<math style="display:block"><mi>x</mi></math>',
      ]) {
        final widgets = await HTMLToPdf().convert(html);
        expect(widgets.whereType<Align>(), isNotEmpty, reason: html);
      }
    });
  });

  test('annotations inside semantics are not rendered', () async {
    final widgets = await HTMLToPdf().convert(
        '<p><math><semantics><mi>z</mi><annotation encoding="TeX">z</annotation>'
        '</semantics></math></p>');
    expect(texts(flatten(widgets)), 'z');
  });
}
