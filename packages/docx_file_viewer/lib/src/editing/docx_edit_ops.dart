/// Pure, immutable editing operations on a [DocxBuiltDocument].
///
/// The AST (`DocxParagraph`, `DocxText`, ...) is immutable by design -
/// docx_creator's public API and its own `copyWith` methods assume that, so
/// this module never mutates a node in place. Every function here takes a
/// document and returns a *new* document built with the AST's existing
/// `copyWith`/constructors; the input is never touched. That also makes
/// undo/redo trivial (see `docx_edit_command_stack.dart`): a previous
/// document reference is still perfectly valid after a later edit.
///
/// Scope for this first pass: only top-level paragraphs in
/// `DocxBuiltDocument.elements` (addressed by [DocxTextPosition.elementIndex])
/// and only paragraphs without floating images/shapes (see
/// [paragraphHasFloats] - a float renders as multiple side-by-side text
/// segments, so "one offset into the whole paragraph" isn't well-defined for
/// it yet). Editing inside table cells, list items, or floated paragraphs,
/// and formatting commands (bold/italic toggle over a selection) are not
/// covered - deliberately: this is groundwork for a `docx_file_editor`, not
/// the editor itself.
library;

import 'package:docx_creator/docx_creator.dart';

import 'docx_paragraph_text.dart';
import 'docx_text_position.dart';

/// Inserts [text] at [at] and returns the resulting document.
///
/// If [at] falls inside (or at the end of) an existing [DocxText] run, the
/// text is spliced into that run's content, so it inherits the run's
/// formatting - the same as typing inside a run in Word. If [at] falls
/// immediately before/after a non-text inline (an image, tab, checkbox,
/// line break, footnote/endnote ref - all atomic, can't be split), a brand
/// new plain [DocxText] run is inserted next to it instead.
DocxBuiltDocument insertText(
    DocxBuiltDocument doc, DocxTextPosition at, String text) {
  if (text.isEmpty) return doc;
  final paragraph = _paragraphAt(doc, at.elementIndex);
  final loc = locateInParagraph(paragraph, at.offset);
  if (loc == null) {
    throw RangeError('offset ${at.offset} is out of range for paragraph '
        '${at.elementIndex} (length ${paragraphTextLength(paragraph)})');
  }

  final children = List<DocxInline>.from(paragraph.children);

  if (loc.childIndex >= children.length) {
    // Cursor at the very end of the paragraph.
    if (children.isNotEmpty && children.last is DocxText) {
      final last = children.last as DocxText;
      children[children.length - 1] =
          last.copyWith(content: last.content + text);
    } else {
      children.add(DocxText(text));
    }
  } else {
    final child = children[loc.childIndex];
    if (child is DocxText) {
      final before = child.content.substring(0, loc.offsetInChild);
      final after = child.content.substring(loc.offsetInChild);
      children[loc.childIndex] = child.copyWith(content: before + text + after);
    } else if (loc.offsetInChild == 0) {
      children.insert(loc.childIndex, DocxText(text));
    } else {
      // offsetInChild == this atomic child's full length: cursor sits
      // right after it.
      children.insert(loc.childIndex + 1, DocxText(text));
    }
  }

  return _replaceParagraph(
      doc, at.elementIndex, paragraph.copyWith(children: children));
}

/// Deletes the text in `[start, end)` (both positions must share the same
/// [DocxTextPosition.elementIndex] - cross-paragraph deletion isn't covered
/// by this op; merge paragraphs first via [mergeWithPrevious] if needed) and
/// returns the resulting document.
///
/// A non-text inline (tab, checkbox, image, line break, footnote/endnote
/// ref) is atomic: if the range touches any part of it at all, the whole
/// thing is removed, mirroring how Word treats these as a single
/// "character" for selection/deletion purposes.
DocxBuiltDocument deleteRange(
    DocxBuiltDocument doc, DocxTextPosition start, DocxTextPosition end) {
  if (start.elementIndex != end.elementIndex) {
    throw ArgumentError(
        'deleteRange only supports a single paragraph; got elementIndex '
        '${start.elementIndex} and ${end.elementIndex}');
  }
  if (end.offset < start.offset) {
    throw ArgumentError('end.offset must be >= start.offset');
  }
  if (start.offset == end.offset) return doc;

  final paragraph = _paragraphAt(doc, start.elementIndex);
  if (paragraphHasFloats(paragraph)) {
    throw ArgumentError(
        'deleteRange does not support paragraphs with floating content');
  }

  final newChildren = <DocxInline>[];
  var childStart = 0;
  for (final child in paragraph.children) {
    final len = inlineRenderedLength(child);
    final childEnd = childStart + len;

    final overlaps = childStart < end.offset && childEnd > start.offset;
    if (!overlaps) {
      newChildren.add(child);
    } else if (child is DocxText) {
      final cutStart = (start.offset - childStart).clamp(0, len);
      final cutEnd = (end.offset - childStart).clamp(0, len);
      final kept = child.content.substring(0, cutStart) +
          child.content.substring(cutEnd);
      if (kept.isNotEmpty) newChildren.add(child.copyWith(content: kept));
    }
    // else: non-text atomic child fully overlapped by the range -> dropped.

    childStart = childEnd;
  }

  return _replaceParagraph(
      doc, start.elementIndex, paragraph.copyWith(children: newChildren));
}

/// Splits the paragraph at [elementIndex] into two paragraphs at [at] -
/// what pressing Enter does. Both halves keep the original paragraph's
/// block-level formatting (alignment, spacing, style, ...), matching Word.
DocxBuiltDocument splitParagraph(DocxBuiltDocument doc, DocxTextPosition at) {
  final paragraph = _paragraphAt(doc, at.elementIndex);
  final loc = locateInParagraph(paragraph, at.offset);
  if (loc == null) {
    throw RangeError('offset ${at.offset} is out of range for paragraph '
        '${at.elementIndex} (length ${paragraphTextLength(paragraph)})');
  }

  final children = paragraph.children;
  final List<DocxInline> before;
  final List<DocxInline> after;

  if (loc.childIndex >= children.length) {
    before = List<DocxInline>.from(children);
    after = [];
  } else {
    final child = children[loc.childIndex];
    final len = inlineRenderedLength(child);
    if (child is DocxText && loc.offsetInChild > 0 && loc.offsetInChild < len) {
      before = [
        ...children.take(loc.childIndex),
        child.copyWith(content: child.content.substring(0, loc.offsetInChild)),
      ];
      after = [
        child.copyWith(content: child.content.substring(loc.offsetInChild)),
        ...children.skip(loc.childIndex + 1),
      ];
    } else if (loc.offsetInChild == 0) {
      before = List<DocxInline>.from(children.take(loc.childIndex));
      after = List<DocxInline>.from(children.skip(loc.childIndex));
    } else {
      before = List<DocxInline>.from(children.take(loc.childIndex + 1));
      after = List<DocxInline>.from(children.skip(loc.childIndex + 1));
    }
  }

  final elements = List<DocxNode>.from(doc.elements);
  elements.replaceRange(at.elementIndex, at.elementIndex + 1, [
    paragraph.copyWith(children: before),
    paragraph.copyWith(children: after),
  ]);
  return _copyDoc(doc, elements);
}

/// Merges the paragraph at [elementIndex] into its predecessor - what
/// pressing Backspace at the start of a paragraph does. The surviving
/// paragraph keeps the *first* (preceding) paragraph's block-level
/// formatting, matching Word.
DocxBuiltDocument mergeWithPrevious(DocxBuiltDocument doc, int elementIndex) {
  if (elementIndex <= 0 || elementIndex >= doc.elements.length) {
    throw RangeError('elementIndex $elementIndex has no previous paragraph '
        'to merge into');
  }
  final prev = doc.elements[elementIndex - 1];
  final curr = doc.elements[elementIndex];
  if (prev is! DocxParagraph || curr is! DocxParagraph) {
    throw ArgumentError('mergeWithPrevious only supports merging paragraphs');
  }

  final merged = prev.copyWith(children: [...prev.children, ...curr.children]);
  final elements = List<DocxNode>.from(doc.elements);
  elements.replaceRange(elementIndex - 1, elementIndex + 1, [merged]);
  return _copyDoc(doc, elements);
}

DocxParagraph _paragraphAt(DocxBuiltDocument doc, int elementIndex) {
  if (elementIndex < 0 || elementIndex >= doc.elements.length) {
    throw RangeError.index(elementIndex, doc.elements, 'elementIndex');
  }
  final node = doc.elements[elementIndex];
  if (node is! DocxParagraph) {
    throw ArgumentError(
        'elementIndex $elementIndex is a ${node.runtimeType}, not a DocxParagraph');
  }
  if (paragraphHasFloats(node)) {
    throw ArgumentError(
        'elementIndex $elementIndex has floating content, which this editing '
        'module does not support yet');
  }
  return node;
}

DocxBuiltDocument _replaceParagraph(
    DocxBuiltDocument doc, int elementIndex, DocxParagraph replacement) {
  final elements = List<DocxNode>.from(doc.elements);
  elements[elementIndex] = replacement;
  return _copyDoc(doc, elements);
}

/// `DocxBuiltDocument` has no `copyWith` of its own (it's a read/write
/// container, not meant to be edited in place) - rebuild it with every
/// field carried over except [elements].
DocxBuiltDocument _copyDoc(DocxBuiltDocument doc, List<DocxNode> elements) {
  return DocxBuiltDocument(
    elements: elements,
    section: doc.section,
    stylesXml: doc.stylesXml,
    numberingXml: doc.numberingXml,
    settingsXml: doc.settingsXml,
    fontTableXml: doc.fontTableXml,
    fontTableRelsXml: doc.fontTableRelsXml,
    themeXml: doc.themeXml,
    contentTypesXml: doc.contentTypesXml,
    rootRelsXml: doc.rootRelsXml,
    headerBgXml: doc.headerBgXml,
    headerBgRelsXml: doc.headerBgRelsXml,
    footnotesXml: doc.footnotesXml,
    endnotesXml: doc.endnotesXml,
    numberingRelsXml: doc.numberingRelsXml,
    numberingImages: doc.numberingImages,
    fonts: doc.fonts,
    footnotes: doc.footnotes,
    endnotes: doc.endnotes,
    theme: doc.theme,
  );
}
