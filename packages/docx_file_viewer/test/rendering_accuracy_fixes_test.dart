import 'dart:typed_data';

import 'package:docx_creator/docx_creator.dart';
import 'package:docx_file_viewer/src/docx_view_config.dart';
import 'package:docx_file_viewer/src/rendering/docx_paragraph_render_widget.dart';
import 'package:docx_file_viewer/src/theme/docx_view_theme.dart';
import 'package:docx_file_viewer/src/utils/block_index_counter.dart';
import 'package:docx_file_viewer/src/utils/docx_units.dart';
import 'package:docx_file_viewer/src/widget_generator/image_builder.dart';
import 'package:docx_file_viewer/src/widget_generator/list_builder.dart';
import 'package:docx_file_viewer/src/widget_generator/paragraph_builder.dart';
import 'package:docx_file_viewer/src/widget_generator/shape_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class MockParagraphBuilder extends ParagraphBuilder {
  MockParagraphBuilder()
      : super(config: const DocxViewConfig(), theme: DocxViewTheme.light());

  @override
  Widget build(DocxParagraph paragraph, {BlockIndexCounter? counter}) {
    return const Text('Paragraph');
  }
}

void main() {
  group('DocxUnits.twipsToPixels', () {
    test('converts twips to pixels via the pt->px factor, not just twips/20',
        () {
      // 1440 twips = 1 inch = 96 logical pixels at the standard 96 DPI this
      // package renders at (twips/20 = points, *1.333 = pixels).
      expect(DocxUnits.twipsToPixels(1440), closeTo(96, 0.5));
    });
  });

  group('Image sizing renders at the correct scale', () {
    testWidgets('a 100pt-wide image renders at ~133 logical pixels, not 100',
        (tester) async {
      final builder = ImageBuilder(config: const DocxViewConfig());
      final image = DocxImage(
        bytes: onePixelPng,
        extension: 'png',
        width: 100,
        height: 50,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: builder.buildBlockImage(image)),
      ));
      await tester.pump();

      final widget = tester.widget<Image>(find.byType(Image));
      // 100pt * 1.333 ≈ 133.3px - well above the raw 100 the old bug produced.
      expect(widget.width, closeTo(133.3, 1));
      expect(widget.height, closeTo(66.65, 1));
    });
  });

  group('Shape sizing renders at the correct scale', () {
    testWidgets('a 100pt-wide shape renders at ~133 logical pixels',
        (tester) async {
      final builder = ShapeBuilder(config: const DocxViewConfig());
      final shapeBlock = DocxShapeBlock.rectangle(width: 100, height: 50);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: builder.buildBlockShape(shapeBlock)),
      ));
      await tester.pump();

      final container = tester.widget<Container>(find.byType(Container).last);
      expect(container.constraints?.maxWidth, closeTo(133.3, 1));
    });
  });

  group('Bullet glyph fallback', () {
    testWidgets(
        'a Private-Use-Area bullet character (Wingdings/Symbol-style) '
        'falls back to a portable bullet instead of a tofu box',
        (tester) async {
      final theme = DocxViewTheme.light();
      final config = const DocxViewConfig();
      final builder = ListBuilder(
        theme: theme,
        config: config,
        paragraphBuilder: MockParagraphBuilder(),
      );

      // U+F0B7 is the codepoint Word commonly emits for a bullet character
      // in the "Symbol" font - meaningless without that font installed.
      final list = DocxList(
        isOrdered: false,
        style: const DocxListStyle(
          bullet: '',
          fontFamily: 'Symbol',
        ),
        items: const [
          DocxListItem([DocxText('Item one')]),
        ],
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: builder.build(list)),
      ));
      await tester.pump();

      // The marker now renders through DocxParagraphRenderWidget (the
      // custom render-object core), not a plain `Text` widget.
      final markerText = tester
          .widgetList<DocxParagraphRenderWidget>(
              find.byType(DocxParagraphRenderWidget))
          .map((w) => w.text.toPlainText())
          .firstWhere((t) => t != 'Item one', orElse: () => '');
      expect(markerText.runes.first, isNot(inInclusiveRange(0xE000, 0xF8FF)));
    });
  });
}

final Uint8List onePixelPng = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);
