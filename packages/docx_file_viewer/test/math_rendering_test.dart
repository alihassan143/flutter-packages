// Basic OMML equation rendering: a DocxMath fraction should produce a
// numerator/denominator pair of Text widgets, not be silently dropped.
import 'package:docx_creator/docx_creator.dart';
import 'package:docx_file_viewer/docx_file_viewer.dart';
import 'package:docx_file_viewer/src/widget_generator/paragraph_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a math fraction renders its numerator and denominator',
      (tester) async {
    final paragraph = DocxParagraph(children: [
      DocxText('Equation: '),
      const DocxMath([
        DocxMathFraction([DocxMathText('1')], [DocxMathText('2')]),
      ]),
    ]);

    final builder = ParagraphBuilder(
      config: const DocxViewConfig(enableSelection: false),
      theme: DocxViewTheme.light(),
      docxTheme: DocxTheme.empty(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 400, child: builder.build(paragraph)),
        ),
      ),
    );

    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });
}
