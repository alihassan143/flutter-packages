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

  test('annotations inside semantics are not rendered', () async {
    final widgets = await HTMLToPdf().convert(
        '<p><math><semantics><mi>z</mi><annotation encoding="TeX">z</annotation>'
        '</semantics></math></p>');
    expect(texts(flatten(widgets)), 'z');
  });
}
