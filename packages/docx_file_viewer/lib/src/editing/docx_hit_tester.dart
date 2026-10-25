import 'package:docx_creator/docx_creator.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../rendering/render_docx_paragraph.dart';
import '../widgets/docx_node_bound.dart';
import 'docx_paragraph_text.dart';
import 'docx_text_position.dart';

/// Resolves a screen position to a [DocxTextPosition] in the document.
///
/// Scope: only paragraphs rendered as a single contiguous `RichText`/
/// `SelectableText.rich` - i.e. without floating images/shapes (see
/// [paragraphHasFloats]), since a float splits a paragraph's text across
/// multiple side-by-side widgets and there's no single span tree to resolve
/// an offset against. That covers the common case; resolving inside a
/// floated paragraph is out of scope for this groundwork pass.
class DocxHitTester {
  const DocxHitTester._();

  /// [context] must be at or below the `DocxNodeBound` that wraps the
  /// paragraph widget tree actually under [globalPosition] (e.g. the
  /// `BuildContext` a `GestureDetector`/`Listener` around that widget sees
  /// in its tap callback). [document] is the currently-rendered document,
  /// used to resolve which `elements` index the found node is at.
  ///
  /// Returns null when: no `DocxNodeBound` ancestor is found, it doesn't
  /// wrap a [DocxParagraph], that paragraph isn't in [document.elements]
  /// (stale `document` reference), it has floating content, or no
  /// text-rendering render object is found under [context] (nothing painted there, or
  /// an unexpected text-rendering widget).
  static DocxTextPosition? resolve({
    required BuildContext context,
    required Offset globalPosition,
    required DocxBuiltDocument document,
  }) {
    final node = DocxNodeBound.of(context)?.node;
    if (node is! DocxParagraph || paragraphHasFloats(node)) return null;

    final elementIndex = document.elements.indexOf(node);
    if (elementIndex == -1) return null;

    final renderObject = context.findRenderObject();
    if (renderObject == null) return null;

    final renderer = _findTextRenderer(renderObject);
    if (renderer == null) return null;

    // RenderParagraph (plain RichText), RenderEditable (SelectableText.rich —
    // the default, since DocxViewConfig.enableSelection defaults to true) and
    // RenderDocxParagraph (the custom leaf from render_docx_paragraph.dart)
    // resolve a point to a TextPosition with different APIs: RenderParagraph/
    // RenderDocxParagraph want a point already in local coordinates,
    // RenderEditable wants the raw global point and converts internally (and
    // also adjusts for its scroll/paint offset, which a plain globalToLocal
    // wouldn't).
    final TextPosition textPosition;
    if (renderer is RenderDocxParagraph) {
      textPosition = renderer.getPositionForOffset(renderer.globalToLocal(globalPosition));
    } else if (renderer is RenderParagraph) {
      textPosition = renderer.getPositionForOffset(renderer.globalToLocal(globalPosition));
    } else if (renderer is RenderEditable) {
      textPosition = renderer.getPositionForPoint(globalPosition);
    } else {
      return null;
    }

    // `ParagraphBuilder.buildInlineSpans` inserts a leading `WidgetSpan`
    // placeholder for a paragraph's first-line indent (`w:firstLine` > 0,
    // see paragraph_builder.dart) - that placeholder counts as one extra
    // character in the TextPainter's offset space, ahead of every real
    // child, so it must be subtracted to get back to the paragraph model's
    // own offsets. RenderDocxParagraph never carries a WidgetSpan (see its
    // own doc comment) — a firstLine-indented paragraph always renders
    // through the RichText/SelectableText.rich path instead, so this never
    // applies when renderer is a RenderDocxParagraph.
    final hasIndentPlaceholder = renderer is! RenderDocxParagraph && (node.indentFirstLine ?? 0) > 0;
    final maxOffset = paragraphTextLength(node);
    final rawOffset = textPosition.offset - (hasIndentPlaceholder ? 1 : 0);
    final offset = rawOffset < 0 ? 0 : (rawOffset > maxOffset ? maxOffset : rawOffset);
    return DocxTextPosition(elementIndex: elementIndex, offset: offset);
  }

  static RenderBox? _findTextRenderer(RenderObject root) {
    RenderBox? found;
    void visit(RenderObject object) {
      if (found != null) return;
      if (object is RenderParagraph || object is RenderEditable || object is RenderDocxParagraph) {
        found = object as RenderBox;
        return;
      }
      object.visitChildren(visit);
    }
    visit(root);
    return found;
  }
}
