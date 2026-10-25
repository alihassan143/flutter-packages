import 'dart:typed_data';

import 'package:docx_creator/docx_creator.dart';
import 'package:docx_file_viewer/src/docx_view_config.dart';
import 'package:docx_file_viewer/src/rendering/docx_paragraph_render_widget.dart';
import 'package:docx_file_viewer/src/rendering/render_docx_paragraph.dart';
import 'package:docx_file_viewer/src/theme/docx_view_theme.dart';
import 'package:docx_file_viewer/src/widget_generator/paragraph_builder.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RenderDocxParagraph', () {
    testWidgets('hit-testing resolves a point to the correct text position',
        (tester) async {
      const span = TextSpan(text: 'Hello World');
      final key = GlobalKey();

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 400,
            child: DocxParagraphRenderWidget(key: key, text: span),
          ),
        ),
      );

      final render = key.currentContext!.findRenderObject() as RenderDocxParagraph;
      expect(render.plainText, 'Hello World');

      // Use the render object's own caret-rect for offset 6 ("Hello |World")
      // to find an x-coordinate guaranteed to be at/after that position,
      // rather than guessing a pixel value against font metrics.
      final caretAtSix = render.getCaretRect(const TextPosition(offset: 6));
      final position =
          render.getPositionForOffset(Offset(caretAtSix.left + 1, 5));
      expect(position.offset, greaterThanOrEqualTo(6));
    });

    testWidgets('caret rect is positioned at the requested text offset',
        (tester) async {
      const span = TextSpan(text: 'AB');
      final key = GlobalKey();

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 400,
            child: DocxParagraphRenderWidget(key: key, text: span),
          ),
        ),
      );

      final render = key.currentContext!.findRenderObject() as RenderDocxParagraph;
      final caretAtStart = render.getCaretRect(const TextPosition(offset: 0));
      final caretAfterA = render.getCaretRect(const TextPosition(offset: 1));

      expect(caretAtStart.left, 0);
      expect(caretAfterA.left, greaterThan(caretAtStart.left));
    });

    testWidgets('selection boxes cover the requested range', (tester) async {
      const span = TextSpan(text: 'Hello World');
      final key = GlobalKey();

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 400,
            child: DocxParagraphRenderWidget(key: key, text: span),
          ),
        ),
      );

      final render = key.currentContext!.findRenderObject() as RenderDocxParagraph;
      final boxes = render
          .getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 5));

      expect(boxes, isNotEmpty);
      expect(boxes.first.left, 0);
    });

    testWidgets('a tap on a recognizer span fires it', (tester) async {
      var tapped = false;
      final recognizer = TapGestureRecognizer()..onTap = () => tapped = true;
      addTearDown(recognizer.dispose);
      final span = TextSpan(children: [
        const TextSpan(text: 'before '),
        TextSpan(text: 'link', recognizer: recognizer),
      ]);
      final key = GlobalKey();

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 400,
            child: DocxParagraphRenderWidget(key: key, text: span),
          ),
        ),
      );

      final render =
          key.currentContext!.findRenderObject() as RenderDocxParagraph;
      // "before link" -> offset 10 lands inside "link".
      final caret = render.getCaretRect(const TextPosition(offset: 10));
      final renderBox = find.byType(DocxParagraphRenderWidget);
      await tester.tapAt(
          tester.getTopLeft(renderBox) + Offset(caret.left + 1, 5));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    });

    testWidgets('overflow is clipped, not left to bleed into siblings',
        (tester) async {
      final key = GlobalKey();

      // Force a height far shorter than the laid-out text needs.
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 50,
              height: 10,
              child: DocxParagraphRenderWidget(
                key: key,
                text: const TextSpan(
                    text: 'A long run of text that will wrap onto many '
                        'lines inside a very narrow, very short box.'),
              ),
            ),
          ),
        ),
      );

      // Must not throw during paint, and must stay sized to the box its
      // parent gave it rather than growing to fit the overflowing text.
      final render =
          key.currentContext!.findRenderObject() as RenderDocxParagraph;
      expect(render.size, const Size(50, 10));
      expect(tester.takeException(), isNull);
    });

    testWidgets('exposes paragraph text to accessibility', (tester) async {
      final handle = tester.ensureSemantics();
      const span = TextSpan(text: 'Hello World');

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 400,
            child: DocxParagraphRenderWidget(text: span),
          ),
        ),
      );

      expect(
        tester.getSemantics(find.byType(DocxParagraphRenderWidget)),
        matchesSemantics(label: 'Hello World'),
      );
      handle.dispose();
    });

    testWidgets('disposing the widget tree does not throw', (tester) async {
      const span = TextSpan(text: 'Hello World');
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 400,
            child: DocxParagraphRenderWidget(text: span),
          ),
        ),
      );
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  });

  group('ParagraphBuilder uses RenderDocxParagraph for plain text', () {
    testWidgets(
        'a non-selectable plain-text paragraph renders through DocxParagraphRenderWidget, not RichText',
        (tester) async {
      final builder = ParagraphBuilder(
        theme: DocxViewTheme.light(),
        config: const DocxViewConfig(enableSelection: false),
      );
      final paragraph = DocxParagraph(children: [
        DocxText('Plain, bold-free text', fontWeight: DocxFontWeight.bold),
      ]);

      final widget = builder.build(paragraph);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: widget)));

      expect(find.byType(DocxParagraphRenderWidget), findsOneWidget);

      final rendered =
          tester.widget<DocxParagraphRenderWidget>(find.byType(DocxParagraphRenderWidget));
      expect((rendered.text as TextSpan).toPlainText(), 'Plain, bold-free text');
    });

    testWidgets(
        'a paragraph containing an inline image still falls back to RichText (WidgetSpan not supported)',
        (tester) async {
      final builder = ParagraphBuilder(
        theme: DocxViewTheme.light(),
        config: const DocxViewConfig(enableSelection: false),
      );
      final paragraph = DocxParagraph(children: [
        DocxText('before '),
        DocxInlineImage(
            bytes: Uint8List(0), extension: 'png', width: 20, height: 20),
        DocxText(' after'),
      ]);

      final widget = builder.build(paragraph);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: widget)));

      // Falls back to the existing RichText path since this render object
      // is a leaf with no child render objects for the WidgetSpan image.
      expect(find.byType(RichText), findsWidgets);
      expect(find.byType(DocxParagraphRenderWidget), findsNothing);
    });

    testWidgets('selection mode (default) still uses SelectableText.rich',
        (tester) async {
      final builder = ParagraphBuilder(
        theme: DocxViewTheme.light(),
        config: const DocxViewConfig(), // enableSelection defaults to true
      );
      final paragraph =
          DocxParagraph(children: [DocxText('Selectable text')]);

      final widget = builder.build(paragraph);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: widget)));

      expect(find.byType(SelectableText), findsOneWidget);
      expect(find.byType(DocxParagraphRenderWidget), findsNothing);
    });
  });
}
