import 'package:htmltopdfwidgets/htmltopdfwidgets.dart';
import 'package:htmltopdfwidgets/src/browser/css_style.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:test/test.dart';

/// `border-radius` was parsed into [CSSStyle.borderRadius] and honoured for
/// `<img>`, but `_buildBoxDecoration` never forwarded it, so block elements
/// always rendered square.
void main() {
  group('border-radius on block decoration', () {
    test('is parsed from CSS', () {
      final style = CSSStyle.parse('border-radius: 12px;');
      expect(style.borderRadius, 9.0); // 12px * 0.75
    });

    test('reaches the rendered box', () async {
      final widgets = await HTMLToPdf().convert(
        '<h6 style="width:200px;background-color:#E4E4E4;'
        'border-radius:12px;padding:10px;">rounded</h6>',
      );

      final decorated = widgets
          .whereType<pw.Container>()
          .map((c) => c.decoration)
          .whereType<pw.BoxDecoration>()
          .where((d) => d.borderRadius != null);

      expect(decorated, isNotEmpty,
          reason: 'no box carried a borderRadius into its decoration');
    });

    test('radius alone still produces a decoration', () async {
      // Previously returned null because only backgroundColor/border were
      // considered, silently dropping the radius.
      final widgets = await HTMLToPdf().convert(
        '<h6 style="width:200px;border-radius:8px;">radius only</h6>',
      );

      final hasRadius = widgets
          .whereType<pw.Container>()
          .map((c) => c.decoration)
          .whereType<pw.BoxDecoration>()
          .any((d) => d.borderRadius != null);

      expect(hasRadius, isTrue);
    });

    test('survives the large-block (page-spanning) path', () async {
      // <div> is not a "small block", so it goes through
      // _applyBlockDecorationToChildren, which rebuilds decorations for the
      // split top/middle/bottom sections rather than using the original.
      final widgets = await HTMLToPdf().convert(
        '<div style="background-color:#E4E4E4;border-radius:12px;'
        'padding:10px;">a large block</div>',
      );

      final radii = widgets
          .whereType<pw.Container>()
          .map((c) => c.decoration)
          .whereType<pw.BoxDecoration>()
          .map((d) => d.borderRadius)
          .whereType<pw.BorderRadius>()
          .toList();

      expect(radii, isNotEmpty,
          reason: 'split sections dropped the radius entirely');
      // The caps round outwards; the middle sections stay square.
      expect(radii.any((r) => r.topLeft.x > 0), isTrue,
          reason: 'top cap is not rounded');
      expect(radii.any((r) => r.bottomLeft.x > 0), isTrue,
          reason: 'bottom cap is not rounded');
    });

    test('a radius alone does not add filler spacing', () async {
      // Returning a decoration for radius-only elements must not make the
      // large-block helper emit its 8pt top/bottom filler strips.
      // No padding/margin, so topSpace == 0 and the filler strips are driven
      // purely by whether a decoration exists.
      const plain = '<div>text</div>';
      const rounded = '<div style="border-radius:12px;">text</div>';

      final a = await HTMLToPdf().convert(plain);
      final b = await HTMLToPdf().convert(rounded);

      expect(b.length, a.length,
          reason: 'radius-only block gained extra filler widgets');
    });
  });
}
