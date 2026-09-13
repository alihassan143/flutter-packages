// Tests for GitHub issue #83 — hide footnotes and endnotes via DocxViewConfig.

import 'package:docx_creator/docx_creator.dart';
import 'package:docx_file_viewer/src/docx_view_config.dart';
import 'package:docx_file_viewer/src/widget_generator/docx_widget_generator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DocxBuiltDocument _docWithNotes() {
  return DocxBuiltDocument(
    elements: [DocxParagraph(children: [DocxText('Body text')])],
    footnotes: [
      DocxFootnote(footnoteId: 1, content: [
        DocxParagraph(children: [DocxText('Footnote one')])
      ]),
    ],
    endnotes: [
      DocxEndnote(endnoteId: 1, content: [
        DocxParagraph(children: [DocxText('Endnote one')])
      ]),
    ],
    theme: DocxTheme(colors: DocxThemeColors(), fonts: DocxThemeFonts()),
  );
}

void main() {
  group('Issue #83 — DocxViewConfig showFootnotes / showEndnotes', () {
    // -----------------------------------------------------------------
    // Config unit tests
    // -----------------------------------------------------------------

    test('defaults are true', () {
      const config = DocxViewConfig();
      expect(config.showFootnotes, isTrue);
      expect(config.showEndnotes, isTrue);
    });

    test('can be set to false', () {
      const config = DocxViewConfig(showFootnotes: false, showEndnotes: false);
      expect(config.showFootnotes, isFalse);
      expect(config.showEndnotes, isFalse);
    });

    test('copyWith propagates showFootnotes and showEndnotes', () {
      const original = DocxViewConfig(showFootnotes: true, showEndnotes: true);
      final updated =
          original.copyWith(showFootnotes: false, showEndnotes: false);
      expect(updated.showFootnotes, isFalse);
      expect(updated.showEndnotes, isFalse);
    });

    test('copyWith preserves existing values when not overridden', () {
      const original =
          DocxViewConfig(showFootnotes: false, showEndnotes: false);
      final updated = original.copyWith(enableSearch: false);
      expect(updated.showFootnotes, isFalse);
      expect(updated.showEndnotes, isFalse);
    });

    test('mixed flag combinations are valid', () {
      const config = DocxViewConfig(showFootnotes: true, showEndnotes: false);
      expect(config.showFootnotes, isTrue);
      expect(config.showEndnotes, isFalse);
    });

    // -----------------------------------------------------------------
    // Widget generator tests
    // -----------------------------------------------------------------

    testWidgets('footnotes appear when showFootnotes=true',
        (WidgetTester tester) async {
      final config = const DocxViewConfig(
        showFootnotes: true,
        showEndnotes: true,
        pageMode: DocxPageMode.continuous,
      );
      final generator = DocxWidgetGenerator(config: config);
      final widgets = generator.generateWidgets(_docWithNotes());

      final allText = widgets
          .whereType<Padding>()
          .map((p) => p.child)
          .whereType<Text>()
          .map((t) => t.data ?? '')
          .join();

      expect(allText, contains('Footnotes'),
          reason: 'Footnotes section header should appear');
    });

    testWidgets('footnotes are hidden when showFootnotes=false',
        (WidgetTester tester) async {
      final config = const DocxViewConfig(
        showFootnotes: false,
        showEndnotes: true,
        pageMode: DocxPageMode.continuous,
      );
      final generator = DocxWidgetGenerator(config: config);
      final widgets = generator.generateWidgets(_docWithNotes());

      final allText = widgets
          .whereType<Padding>()
          .map((p) => p.child)
          .whereType<Text>()
          .map((t) => t.data ?? '')
          .join();

      expect(allText, isNot(contains('Footnotes')),
          reason: 'Footnotes section header must be absent');
    });

    testWidgets('endnotes appear when showEndnotes=true',
        (WidgetTester tester) async {
      final config = const DocxViewConfig(
        showFootnotes: true,
        showEndnotes: true,
        pageMode: DocxPageMode.continuous,
      );
      final generator = DocxWidgetGenerator(config: config);
      final widgets = generator.generateWidgets(_docWithNotes());

      final allText = widgets
          .whereType<Padding>()
          .map((p) => p.child)
          .whereType<Text>()
          .map((t) => t.data ?? '')
          .join();

      expect(allText, contains('Endnotes'));
    });

    testWidgets('endnotes are hidden when showEndnotes=false',
        (WidgetTester tester) async {
      final config = const DocxViewConfig(
        showFootnotes: true,
        showEndnotes: false,
        pageMode: DocxPageMode.continuous,
      );
      final generator = DocxWidgetGenerator(config: config);
      final widgets = generator.generateWidgets(_docWithNotes());

      final allText = widgets
          .whereType<Padding>()
          .map((p) => p.child)
          .whereType<Text>()
          .map((t) => t.data ?? '')
          .join();

      expect(allText, isNot(contains('Endnotes')));
    });

    testWidgets('both hidden when both flags are false',
        (WidgetTester tester) async {
      final config = const DocxViewConfig(
        showFootnotes: false,
        showEndnotes: false,
        pageMode: DocxPageMode.continuous,
      );
      final generator = DocxWidgetGenerator(config: config);
      final widgets = generator.generateWidgets(_docWithNotes());

      final allText = widgets
          .whereType<Padding>()
          .map((p) => p.child)
          .whereType<Text>()
          .map((t) => t.data ?? '')
          .join();

      expect(allText, isNot(contains('Footnotes')));
      expect(allText, isNot(contains('Endnotes')));
    });
  });
}
