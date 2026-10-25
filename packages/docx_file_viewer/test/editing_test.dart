// Tests for the editor-readiness groundwork (lib/src/editing/): hit-testing,
// the pure edit ops, and the undo/redo stack. These are deliberately scoped
// to top-level, non-floating paragraphs — see docx_edit_ops.dart's doc
// comment for what's out of scope and why.
import 'dart:typed_data';

import 'package:docx_creator/docx_creator.dart';
import 'package:docx_file_viewer/docx_file_viewer.dart';
import 'package:docx_file_viewer/src/widget_generator/docx_widget_generator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DocxBuiltDocument _doc(List<DocxNode> elements) =>
    DocxBuiltDocument(elements: elements, section: DocxSectionDef());

void main() {
  group('docx_paragraph_text', () {
    test('paragraphTextLength sums rendered-text length of children', () {
      final p = DocxParagraph(children: [
        DocxText('Hello '), // 6
        DocxLineBreak(), // 1
        DocxTab(), // 4
        DocxText('World'), // 5
      ]);
      expect(paragraphTextLength(p), 6 + 1 + 4 + 5);
    });

    test('paragraphHasFloats is true only for floating image/shape', () {
      final plain = DocxParagraph(children: [DocxText('x')]);
      expect(paragraphHasFloats(plain), isFalse);

      final floated = DocxParagraph(children: [
        DocxText('x'),
        DocxInlineImage(
          bytes: Uint8List(0),
          extension: 'png',
          width: 10,
          height: 10,
          positionMode: DocxDrawingPosition.floating,
        ),
      ]);
      expect(paragraphHasFloats(floated), isTrue);
    });

    test('locateInParagraph finds the child and offset within it', () {
      final p = DocxParagraph(
          children: [DocxText('Hello '), DocxText('World')]); // 6 + 5

      expect(locateInParagraph(p, 0), (childIndex: 0, offsetInChild: 0));
      expect(locateInParagraph(p, 3), (childIndex: 0, offsetInChild: 3));
      expect(locateInParagraph(p, 6), (childIndex: 0, offsetInChild: 6));
      expect(locateInParagraph(p, 7), (childIndex: 1, offsetInChild: 1));
      // Total length (11) resolves to "end of the last child", not the
      // children.length branch — that branch is only for an empty paragraph.
      expect(locateInParagraph(p, 11), (childIndex: 1, offsetInChild: 5));
      expect(locateInParagraph(p, 12), isNull); // past the end
      expect(locateInParagraph(p, -1), isNull);
    });

    test('locateInParagraph returns null for a paragraph with floats', () {
      final p = DocxParagraph(children: [
        DocxInlineImage(
          bytes: Uint8List(0),
          extension: 'png',
          width: 10,
          height: 10,
          positionMode: DocxDrawingPosition.floating,
        ),
      ]);
      expect(locateInParagraph(p, 0), isNull);
    });

    test('DocxMath counts as one rendered character, like other WidgetSpans',
        () {
      final math = DocxMath([DocxMathText('x')]);
      final p = DocxParagraph(
          children: [DocxText('a'), math, DocxText('b')]); // 1 + 1 + 1
      expect(paragraphTextLength(p), 3);
      // Offset 2 (the boundary right after the equation) resolves to "end
      // of the equation child" per locateInParagraph's boundary convention
      // (same as any other child boundary - see the plain-text-runs test
      // above). Before the fix, DocxMath counted as 0 chars, so this would
      // have resolved one child further in (into 'b') instead.
      expect(locateInParagraph(p, 2), (childIndex: 1, offsetInChild: 1));
    });
  });

  group('docx_edit_ops', () {
    test('insertText splices into an existing run', () {
      final doc = _doc([
        DocxParagraph(children: [DocxText('Hello World')]),
      ]);
      final result = insertText(
          doc, const DocxTextPosition(elementIndex: 0, offset: 5), ',');
      final p = result.elements.single as DocxParagraph;
      expect((p.children.single as DocxText).content, 'Hello, World');
    });

    test('insertText at the end of the paragraph appends', () {
      final doc = _doc([
        DocxParagraph(children: [DocxText('Hello')]),
      ]);
      final result = insertText(
          doc, const DocxTextPosition(elementIndex: 0, offset: 5), '!');
      final p = result.elements.single as DocxParagraph;
      expect((p.children.single as DocxText).content, 'Hello!');
    });

    test('insertText does not mutate the original document', () {
      final original = DocxText('Hello');
      final doc = _doc([
        DocxParagraph(children: [original]),
      ]);
      insertText(doc, const DocxTextPosition(elementIndex: 0, offset: 0), 'X');
      expect(original.content, 'Hello'); // untouched
      expect((doc.elements.single as DocxParagraph).children.single, original);
    });

    test('deleteRange removes text within a single run', () {
      final doc = _doc([
        DocxParagraph(children: [DocxText('Hello World')]),
      ]);
      final result = deleteRange(
        doc,
        const DocxTextPosition(elementIndex: 0, offset: 5),
        const DocxTextPosition(elementIndex: 0, offset: 11),
      );
      final p = result.elements.single as DocxParagraph;
      expect((p.children.single as DocxText).content, 'Hello');
    });

    test('deleteRange spanning multiple runs drops a fully-covered run', () {
      final doc = _doc([
        DocxParagraph(
            children: [DocxText('abc'), DocxText('def'), DocxText('ghi')]),
      ]);
      // Delete "cdefg" -> left with "ab" + "hi"
      final result = deleteRange(
        doc,
        const DocxTextPosition(elementIndex: 0, offset: 2),
        const DocxTextPosition(elementIndex: 0, offset: 7),
      );
      final p = result.elements.single as DocxParagraph;
      expect(p.children.map((c) => (c as DocxText).content).join(), 'abhi');
    });

    test('deleteRange removes an atomic non-text child entirely', () {
      final doc = _doc([
        DocxParagraph(
            children: [DocxText('a'), DocxLineBreak(), DocxText('b')]),
      ]);
      final result = deleteRange(
        doc,
        const DocxTextPosition(elementIndex: 0, offset: 1),
        const DocxTextPosition(elementIndex: 0, offset: 2),
      );
      final p = result.elements.single as DocxParagraph;
      expect(p.children.map((c) => (c as DocxText).content).join(), 'ab');
    });

    test('deleteRange throws for a stale position past the paragraph end',
        () {
      final doc = _doc([
        DocxParagraph(children: [DocxText('Hi')]), // length 2
      ]);
      expect(
        () => deleteRange(
          doc,
          const DocxTextPosition(elementIndex: 0, offset: 0),
          const DocxTextPosition(elementIndex: 0, offset: 5),
        ),
        throwsRangeError,
      );
    });

    test('splitParagraph turns one paragraph into two at the offset', () {
      final doc = _doc([
        DocxParagraph(
            align: DocxAlign.center,
            children: [DocxText('Hello World')]),
      ]);
      final result = splitParagraph(
          doc, const DocxTextPosition(elementIndex: 0, offset: 5));
      expect(result.elements.length, 2);
      final first = result.elements[0] as DocxParagraph;
      final second = result.elements[1] as DocxParagraph;
      expect((first.children.single as DocxText).content, 'Hello');
      expect((second.children.single as DocxText).content, ' World');
      // Block-level formatting carried over to both halves.
      expect(first.align, DocxAlign.center);
      expect(second.align, DocxAlign.center);
    });

    test('mergeWithPrevious reverses a split', () {
      final doc = _doc([
        DocxParagraph(children: [DocxText('Hello')]),
        DocxParagraph(children: [DocxText(' World')]),
      ]);
      final result = mergeWithPrevious(doc, 1);
      expect(result.elements.length, 1);
      final p = result.elements.single as DocxParagraph;
      expect(p.children.map((c) => (c as DocxText).content).join(), 'Hello World');
    });

    test('mergeWithPrevious throws for elementIndex 0 (no predecessor)', () {
      final doc = _doc([DocxParagraph(children: [DocxText('x')])]);
      expect(() => mergeWithPrevious(doc, 0), throwsRangeError);
    });
  });

  group('DocxEditCommandStack', () {
    test('undo/redo round-trips through a sequence of edits', () {
      final original = _doc([
        DocxParagraph(children: [DocxText('Hello')]),
      ]);
      final stack = DocxEditCommandStack(original);
      expect(stack.canUndo, isFalse);
      expect(stack.canRedo, isFalse);

      final afterInsert = insertText(
          stack.current, const DocxTextPosition(elementIndex: 0, offset: 5), '!');
      stack.push(afterInsert);
      expect((stack.current.elements.single as DocxParagraph).children.single
          as DocxText, isA<DocxText>());
      expect(
          ((stack.current.elements.single as DocxParagraph).children.single
                  as DocxText)
              .content,
          'Hello!');

      final afterSplit = splitParagraph(
          stack.current, const DocxTextPosition(elementIndex: 0, offset: 5));
      stack.push(afterSplit);
      expect(stack.current.elements.length, 2);

      expect(stack.canUndo, isTrue);
      final undone = stack.undo();
      expect(undone.elements.length, 1);
      expect(
          ((undone.elements.single as DocxParagraph).children.single
                  as DocxText)
              .content,
          'Hello!');

      final undoneAgain = stack.undo();
      expect(undoneAgain, same(original));
      expect(stack.canUndo, isFalse);

      final redone = stack.redo();
      expect(((redone.elements.single as DocxParagraph).children.single
              as DocxText)
          .content, 'Hello!');

      final redoneAgain = stack.redo();
      expect(redoneAgain.elements.length, 2);
      expect(stack.canRedo, isFalse);
    });

    test('push after undo drops the redo history', () {
      final doc = _doc([DocxParagraph(children: [DocxText('a')])]);
      final stack = DocxEditCommandStack(doc);
      stack.push(insertText(
          stack.current, const DocxTextPosition(elementIndex: 0, offset: 1), 'b'));
      stack.undo();
      stack.push(insertText(
          stack.current, const DocxTextPosition(elementIndex: 0, offset: 1), 'c'));
      expect(stack.canRedo, isFalse);
      expect(((stack.current.elements.single as DocxParagraph).children.single
              as DocxText)
          .content, 'ac');
    });

    test('undo with nothing to undo throws', () {
      final stack =
          DocxEditCommandStack(_doc([DocxParagraph(children: [])]));
      expect(() => stack.undo(), throwsStateError);
    });
  });

  group('DocxHitTester', () {
    // DocxHitTester.resolve requires a context at-or-below the DocxNodeBound
    // that wraps the paragraph (it walks ANCESTORS to find it) — so the
    // context must come from inside the generated widget tree, not from a
    // wrapper placed around it.
    Finder textRenderFinder() => find.descendant(
          of: find.byType(DocxNodeBound),
          matching: find.byWidgetPredicate(
              (w) => w is RichText || w is SelectableText),
        );

    testWidgets('resolves a tap at the start of the text to offset 0',
        (tester) async {
      final generator =
          DocxWidgetGenerator(config: const DocxViewConfig());
      final paragraph =
          DocxParagraph(children: [DocxText('Hello World')]);
      final doc = _doc([paragraph]);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: generator.generateWidget(paragraph)!,
        ),
      ));

      final textFinder = textRenderFinder().first;
      final context = tester.element(textFinder);
      final topLeft = tester.getTopLeft(textFinder);
      final position = DocxHitTester.resolve(
        context: context,
        globalPosition: topLeft + const Offset(1, 1),
        document: doc,
      );

      expect(position, isNotNull);
      expect(position!.elementIndex, 0);
      expect(position.offset, 0);
    });

    testWidgets('clamps a tap past the end of the text to the max offset',
        (tester) async {
      final generator =
          DocxWidgetGenerator(config: const DocxViewConfig());
      final paragraph = DocxParagraph(children: [DocxText('Hi')]);
      final doc = _doc([paragraph]);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: generator.generateWidget(paragraph)!,
        ),
      ));

      final textFinder = textRenderFinder().first;
      final context = tester.element(textFinder);
      final bottomRight = tester.getBottomRight(textFinder);
      final position = DocxHitTester.resolve(
        context: context,
        globalPosition: bottomRight + const Offset(500, 0),
        document: doc,
      );

      expect(position, isNotNull);
      expect(position!.offset, paragraphTextLength(paragraph));
    });

    testWidgets('returns null for a stale document reference',
        (tester) async {
      final generator =
          DocxWidgetGenerator(config: const DocxViewConfig());
      final paragraph = DocxParagraph(children: [DocxText('Hi')]);
      final otherDoc = _doc([DocxParagraph(children: [DocxText('other')])]);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: generator.generateWidget(paragraph)!,
        ),
      ));

      final textFinder = textRenderFinder().first;
      final context = tester.element(textFinder);
      final topLeft = tester.getTopLeft(textFinder);
      final position = DocxHitTester.resolve(
        context: context,
        globalPosition: topLeft,
        document: otherDoc, // paragraph isn't in this document's elements
      );

      expect(position, isNull);
    });

    testWidgets(
        'accounts for the first-line-indent placeholder span',
        (tester) async {
      final generator =
          DocxWidgetGenerator(config: const DocxViewConfig());
      // indentFirstLine > 0 makes buildInlineSpans insert a leading
      // WidgetSpan placeholder ahead of the real text - without subtracting
      // it, every resolved offset would be off by one.
      final paragraph = DocxParagraph(
          indentFirstLine: 200, children: [DocxText('Hello World')]);
      final doc = _doc([paragraph]);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: generator.generateWidget(paragraph)!,
        ),
      ));

      final textFinder = textRenderFinder().first;
      final context = tester.element(textFinder);
      final topLeft = tester.getTopLeft(textFinder);
      final position = DocxHitTester.resolve(
        context: context,
        // Lands a couple of characters into "Hello", past the indent
        // placeholder. Without subtracting the placeholder, this would
        // resolve one character further in (2) than it actually does (1).
        globalPosition: topLeft + const Offset(30, 1),
        document: doc,
      );

      expect(position, isNotNull);
      expect(position!.offset, 1);
    });
  });
}
