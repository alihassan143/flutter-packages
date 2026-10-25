import 'package:docx_creator/docx_creator.dart';
import 'package:docx_file_viewer/src/docx_view_config.dart';
import 'package:docx_file_viewer/src/widget_generator/docx_widget_generator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Multi-column section rendering', () {
    test('a 2-column section renders a Row of 2 columns in continuous mode',
        () {
      final generator =
          DocxWidgetGenerator(config: const DocxViewConfig(pageMode: DocxPageMode.continuous));

      final doc = DocxBuiltDocument(
        elements: List.generate(
          4,
          (i) => DocxParagraph(children: [DocxText('Paragraph $i')]),
        ),
        section: const DocxSectionDef(columnCount: 2),
        theme: DocxTheme(colors: DocxThemeColors(), fonts: DocxThemeFonts()),
      );

      final widgets = generator.generateWidgets(doc);

      final rows = widgets.whereType<IntrinsicHeight>().toList();
      expect(rows, hasLength(1));
      final row = rows.single.child as Row;
      expect(row.children, hasLength(2));
      expect(row.children.every((c) => c is Expanded), true);
    });

    test('a single-column section renders plain flow, no Row wrapper', () {
      final generator =
          DocxWidgetGenerator(config: const DocxViewConfig(pageMode: DocxPageMode.continuous));

      final doc = DocxBuiltDocument(
        elements: List.generate(
          4,
          (i) => DocxParagraph(children: [DocxText('Paragraph $i')]),
        ),
        section: const DocxSectionDef(),
        theme: DocxTheme(colors: DocxThemeColors(), fonts: DocxThemeFonts()),
      );

      final widgets = generator.generateWidgets(doc);

      expect(widgets.whereType<IntrinsicHeight>(), isEmpty);
    });

    test(
        'a mid-document section break switches column count for its own segment',
        () {
      final generator =
          DocxWidgetGenerator(config: const DocxViewConfig(pageMode: DocxPageMode.continuous));

      final doc = DocxBuiltDocument(
        elements: [
          DocxParagraph(children: [DocxText('Single-column intro')]),
          const DocxSectionBreakBlock(DocxSectionDef(columnCount: 3)),
          DocxParagraph(children: [DocxText('Three-column body 1')]),
          DocxParagraph(children: [DocxText('Three-column body 2')]),
        ],
        section: const DocxSectionDef(), // final section: single column
        theme: DocxTheme(colors: DocxThemeColors(), fonts: DocxThemeFonts()),
      );

      final widgets = generator.generateWidgets(doc);

      final rows = widgets.whereType<IntrinsicHeight>().toList();
      expect(rows, hasLength(1));
      final row = rows.single.child as Row;
      expect(row.children, hasLength(3));
    });
  });
}
