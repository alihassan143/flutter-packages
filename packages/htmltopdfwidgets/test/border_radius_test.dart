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
  });
}
