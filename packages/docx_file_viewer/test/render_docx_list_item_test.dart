import 'package:docx_creator/docx_creator.dart';
import 'package:docx_file_viewer/src/docx_view_config.dart';
import 'package:docx_file_viewer/src/rendering/docx_list_item_render_widget.dart';
import 'package:docx_file_viewer/src/rendering/docx_paragraph_render_widget.dart';
import 'package:docx_file_viewer/src/rendering/render_docx_list_item.dart';
import 'package:docx_file_viewer/src/theme/docx_view_theme.dart';
import 'package:docx_file_viewer/src/widget_generator/list_builder.dart';
import 'package:docx_file_viewer/src/widget_generator/paragraph_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RenderDocxListItem', () {
    testWidgets('lays out marker and content in separate columns',
        (tester) async {
      final key = GlobalKey();

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 200,
            child: DocxListItemRenderWidget(
              key: key,
              markerWidth: 24,
              marker: const DocxParagraphRenderWidget(
                text: TextSpan(text: '•'),
              ),
              content: const DocxParagraphRenderWidget(
                text: TextSpan(text: 'Item one'),
              ),
            ),
          ),
        ),
      );

      final render =
          key.currentContext!.findRenderObject() as RenderDocxListItem;
      expect(render.plainText, 'Item one');

      // A tap in the marker column (x < markerWidth) isn't content text.
      expect(render.getPositionForOffset(const Offset(5, 5)), isNull);
      // A tap past the marker column resolves into the content text.
      final position = render.getPositionForOffset(const Offset(30, 5));
      expect(position, isNotNull);
    });

    testWidgets('marker column width matches the constructor value',
        (tester) async {
      final markerKey = GlobalKey();
      final contentKey = GlobalKey();

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 200,
            child: DocxListItemRenderWidget(
              markerWidth: 24,
              marker: DocxParagraphRenderWidget(
                key: markerKey,
                text: const TextSpan(text: '1.'),
              ),
              content: DocxParagraphRenderWidget(
                key: contentKey,
                text: const TextSpan(text: 'Item one'),
              ),
            ),
          ),
        ),
      );

      final markerBox =
          markerKey.currentContext!.findRenderObject() as RenderBox;
      final contentBox =
          contentKey.currentContext!.findRenderObject() as RenderBox;
      final markerGlobal = markerBox.localToGlobal(Offset.zero);
      final contentGlobal = contentBox.localToGlobal(Offset.zero);
      expect(contentGlobal.dx - markerGlobal.dx, 24);
    });
  });

  group('ListBuilder uses RenderDocxListItem for plain-text items', () {
    testWidgets(
        'a non-selectable plain-text list renders through '
        'DocxListItemRenderWidget, not Row/SizedBox/Expanded', (tester) async {
      final paragraphBuilder = ParagraphBuilder(
        config: const DocxViewConfig(enableSelection: false),
        theme: DocxViewTheme.light(),
      );
      final builder = ListBuilder(
        theme: DocxViewTheme.light(),
        config: const DocxViewConfig(enableSelection: false),
        paragraphBuilder: paragraphBuilder,
      );
      final list = DocxList.bullet(['Item one', 'Item two']);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: builder.build(list)),
      ));

      expect(find.byType(DocxListItemRenderWidget), findsNWidgets(2));
      expect(find.byType(RichText), findsNothing);

      final contentTexts = tester
          .widgetList<DocxListItemRenderWidget>(
              find.byType(DocxListItemRenderWidget))
          .map((w) => (w.content as DocxParagraphRenderWidget).text.toPlainText())
          .toList();
      expect(contentTexts, ['Item one', 'Item two']);
    });

    testWidgets('selection mode (default) still uses the Row/SelectableText fallback',
        (tester) async {
      final paragraphBuilder = ParagraphBuilder(
        config: const DocxViewConfig(),
        theme: DocxViewTheme.light(),
      );
      final builder = ListBuilder(
        theme: DocxViewTheme.light(),
        config: const DocxViewConfig(),
        paragraphBuilder: paragraphBuilder,
      );
      final list = DocxList.bullet(['Item one']);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: builder.build(list)),
      ));

      expect(find.byType(DocxListItemRenderWidget), findsNothing);
      expect(find.byType(SelectableText), findsOneWidget);
      // The marker still migrated to the custom render core regardless of
      // the content path - see ListBuilder._buildListItem's comment.
      expect(find.byType(DocxParagraphRenderWidget), findsOneWidget);
    });
  });
}
