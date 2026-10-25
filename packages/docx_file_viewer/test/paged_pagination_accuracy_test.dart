// Regression test for paged-mode pagination accuracy.
//
// The old estimator counted a fixed 24px per line regardless of font size,
// so a 60pt paragraph and a 12pt paragraph counted as the same height. Real
// measurement (via TextPainter, using the exact spans ParagraphBuilder
// paints) must make font size actually affect how many pages a document
// needs.
import 'package:docx_creator/docx_creator.dart';
import 'package:docx_file_viewer/docx_file_viewer.dart';
import 'package:docx_file_viewer/src/widget_generator/docx_widget_generator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<DocxNode> _paragraphs(int count, double fontSize) => List.generate(
      count,
      (i) => DocxParagraph(
          children: [DocxText('Paragraph $i', fontSize: fontSize)]),
    );

int _pageCountFor(double fontSize, int count) {
  const config = DocxViewConfig(pageMode: DocxPageMode.paged, pageWidth: 794);
  final generator = DocxWidgetGenerator(config: config);
  final doc = DocxBuiltDocument(
    elements: _paragraphs(count, fontSize),
    section: DocxSectionDef(),
  );
  return generator.generateWidgets(doc).length;
}

void main() {
  test('larger font size produces more pages for the same paragraph count',
      () {
    const count = 20;
    final smallFontPages = _pageCountFor(12, count);
    final largeFontPages = _pageCountFor(60, count);

    // Blind to font size, the old heuristic gave both the same page count.
    expect(largeFontPages, greaterThan(smallFontPages));
  });

  test('DocxWidgetGenerator yields a single page for short content', () {
    const config = DocxViewConfig(pageMode: DocxPageMode.paged, pageWidth: 794);
    final generator = DocxWidgetGenerator(config: config);
    final doc = DocxBuiltDocument(
      elements: [DocxParagraph(children: [DocxText('Short paragraph.')])],
      section: DocxSectionDef(),
    );

    final widgets = generator.generateWidgets(doc);

    expect(widgets.length, 1);
    expect(widgets.first, isA<Container>());
  });
}
