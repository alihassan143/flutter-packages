import 'package:docx_creator/docx_creator.dart';
import 'package:docx_file_viewer/docx_file_viewer.dart';
import 'package:docx_file_viewer/src/widget_generator/paragraph_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Dark Mode Theming', () {
    late ParagraphBuilder paragraphBuilder;
    late DocxViewTheme darkTheme;

    setUp(() {
      darkTheme = DocxViewTheme.dark();
      paragraphBuilder = ParagraphBuilder(
        theme: darkTheme,
        config: const DocxViewConfig(enableSelection: false),
      );
    });

    testWidgets('resolves "auto" color to theme default (white70/white)',
        (tester) async {
      final paragraph = DocxParagraph(
        children: [
          DocxText('Auto Color', color: DocxColor('auto')),
        ],
      );

      final widget = paragraphBuilder.build(paragraph);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: widget),
      ));

      final richTextFinder = find.byType(DocxParagraphRenderWidget);
      expect(richTextFinder, findsOneWidget);
      final richText = tester.widget<DocxParagraphRenderWidget>(richTextFinder);
      final span = richText.text as TextSpan;

      // Found span structure might be nested.
      // DocxText usually creates a span.
      // Let's verify children if needed, or if it's the direct span.
      // Based on builder logic, it returns a textspan with children.

      // Let's check the style of the first child span if generic.
      // Actually _buildTextSpan returns a list of spans.
      // ParagraphBuilder combines them.

      // We expect the theme default color on the relevant span.
      // Since 'auto' returns theme default, and baseStyle uses it.

      // If richText.text.style.color is used, check that.
      // Or check children.

      Color? effectiveColor;
      if (span.children != null && span.children!.isNotEmpty) {
        final child = span.children!.first as TextSpan;
        effectiveColor = child.style?.color;
      } else {
        effectiveColor = span.style?.color;
      }

      expect(effectiveColor, darkTheme.defaultTextStyle.color);
    });

    testWidgets('inverts explicit black (#000000) to white on dark background',
        (tester) async {
      final paragraph = DocxParagraph(
        children: [
          DocxText('Black Text', color: DocxColor('000000')),
        ],
      );

      final widget = paragraphBuilder.build(paragraph);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: widget),
      ));

      final richTextFinder = find.byType(DocxParagraphRenderWidget);
      final richText = tester.widget<DocxParagraphRenderWidget>(richTextFinder);
      final span = richText.text as TextSpan;

      Color? effectiveColor;
      if (span.children != null && span.children!.isNotEmpty) {
        final child = span.children!.first as TextSpan;
        effectiveColor = child.style?.color;
      } else {
        effectiveColor = span.style?.color;
      }

      // Should be inverted to white
      expect(effectiveColor, Colors.white);
    });

    testWidgets('preserves explicit color (e.g. Red) on dark background',
        (tester) async {
      final paragraph = DocxParagraph(
        children: [
          DocxText('Red Text', color: DocxColor('FF0000')),
        ],
      );

      final widget = paragraphBuilder.build(paragraph);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: widget),
      ));

      final richTextFinder = find.byType(DocxParagraphRenderWidget);
      final richText = tester.widget<DocxParagraphRenderWidget>(richTextFinder);
      final span = richText.text as TextSpan;

      Color? effectiveColor;
      if (span.children != null && span.children!.isNotEmpty) {
        final child = span.children!.first as TextSpan;
        effectiveColor = child.style?.color;
      } else {
        effectiveColor = span.style?.color;
      }

      debugPrint('Effective Color Found: $effectiveColor');
      // Should stay red
      expect(effectiveColor, const Color(0xFFFF0000));
    });
  });
}
