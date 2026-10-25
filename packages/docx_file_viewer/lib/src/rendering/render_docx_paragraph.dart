import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A leaf [RenderBox] that lays out and paints plain (non-[WidgetSpan])
/// paragraph text directly through a [TextPainter], the same primitive
/// [RenderParagraph] uses internally — but under our own control, with one
/// API regardless of whether the viewer's selection mode is on or off.
///
/// This is the foundation an editor needs: a single render object that can
/// answer "what text position is under this point" ([getPositionForOffset])
/// and "where should the caret draw for this position" ([getCaretRect]),
/// instead of the viewer's two different text widgets (`RichText`/
/// `SelectableText.rich`, backed by `RenderParagraph`/`RenderEditable`
/// respectively) with two incompatible APIs for the same question.
///
/// Known limitation: unlike [RenderParagraph], this does not support
/// [WidgetSpan] children (inline images/shapes/math, or the first-line-
/// indent spacer) — it is a true leaf with no child render objects. A
/// paragraph row containing one of those still renders through the existing
/// `RichText`/`SelectableText.rich` path; see
/// `ParagraphBuilder._containsWidgetSpan`. Supporting [WidgetSpan] here would
/// mean becoming a multi-child render object with placeholder dimensions,
/// much closer to reimplementing [RenderParagraph] itself — left for when an
/// editor actually needs inline-widget content to carry carets/selection.
class RenderDocxParagraph extends RenderBox {
  RenderDocxParagraph({
    required InlineSpan text,
    TextAlign textAlign = TextAlign.start,
    required TextDirection textDirection,
  }) : _textPainter = TextPainter(
          text: text,
          textAlign: textAlign,
          textDirection: textDirection,
        );

  final TextPainter _textPainter;

  @override
  void dispose() {
    _textPainter.dispose();
    super.dispose();
  }

  InlineSpan get text => _textPainter.text!;
  set text(InlineSpan value) {
    if (_textPainter.text == value) return;
    _textPainter.text = value;
    markNeedsLayout();
  }

  TextAlign get textAlign => _textPainter.textAlign;
  set textAlign(TextAlign value) {
    if (_textPainter.textAlign == value) return;
    _textPainter.textAlign = value;
    markNeedsLayout();
  }

  TextDirection get textDirection => _textPainter.textDirection!;
  set textDirection(TextDirection value) {
    if (_textPainter.textDirection == value) return;
    _textPainter.textDirection = value;
    markNeedsLayout();
  }

  void _layoutText(double minWidth, double maxWidth) {
    _textPainter.layout(minWidth: minWidth, maxWidth: maxWidth);
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    _layoutText(0, double.infinity);
    return _textPainter.minIntrinsicWidth;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    _layoutText(0, double.infinity);
    return _textPainter.maxIntrinsicWidth;
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    _layoutText(0, width);
    return _textPainter.height;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    _layoutText(0, width);
    return _textPainter.height;
  }

  @override
  double computeDistanceToActualBaseline(TextBaseline baseline) {
    _layoutText(0, constraints.maxWidth);
    return _textPainter.computeDistanceToActualBaseline(baseline);
  }

  @override
  void performLayout() {
    _layoutText(constraints.minWidth, constraints.maxWidth);
    size = constraints.constrain(_textPainter.size);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    // RichText/RenderParagraph clip overflow by default; this painter
    // doesn't unless we tell it to, so a parent constraining us below the
    // laid-out text's size (e.g. a narrow column) would otherwise bleed
    // into whatever's drawn next to it.
    if (_textPainter.size.width > size.width ||
        _textPainter.size.height > size.height) {
      context.pushClipRect(
        needsCompositing,
        offset,
        Offset.zero & size,
        (context, offset) => _textPainter.paint(context.canvas, offset),
      );
    } else {
      _textPainter.paint(context.canvas, offset);
    }
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    // hitTestSelf claims every pointer hit on this box, so a span's own
    // recognizer (link taps, footnote-reference taps) only fires if we
    // dispatch to it ourselves - RenderParagraph does this internally,
    // we're not going through it anymore.
    if (event is! PointerDownEvent) return;
    final position = _textPainter.getPositionForOffset(entry.localPosition);
    final span = _textPainter.text?.getSpanForPosition(position);
    if (span is TextSpan) span.recognizer?.addPointer(event);
  }

  // RenderParagraph reports its text to accessibility services; this leaf
  // didn't, so a screen reader skipped every paragraph rendered through it.
  // This restores the paragraph-level label. Known gap, same shape as the
  // WidgetSpan limitation above: an interactive span (a link, a footnote
  // reference) isn't exposed as its own distinguishable semantics node the
  // way RenderParagraph's assembleSemanticsNode does per-span - the whole
  // paragraph reads as one block of text. Worth revisiting once an editor
  // needs per-span semantics (e.g. announcing "link" for a hyperlink run).
  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..isSemanticBoundary = true
      ..textDirection = textDirection
      ..label = plainText;
  }

  /// Resolves a point in this render object's own coordinate space to a text
  /// position — the primitive hit-testing (tap-to-caret, tap-to-selection)
  /// needs, without going through `RenderParagraph`/`RenderEditable`-specific
  /// APIs that disagree on local-vs-global offsets.
  TextPosition getPositionForOffset(Offset localPosition) {
    return _textPainter.getPositionForOffset(localPosition);
  }

  /// Where to draw a caret for [position], in this render object's own
  /// coordinate space.
  Rect getCaretRect(TextPosition position, {double caretWidth = 1.0}) {
    final offset = _textPainter.getOffsetForCaret(
      position,
      Rect.fromLTWH(0, 0, caretWidth, 0),
    );
    final caretHeight = _textPainter.getFullHeightForCaret(position, Rect.zero);
    return Rect.fromLTWH(offset.dx, offset.dy, caretWidth, caretHeight);
  }

  /// Selection-highlight boxes for [selection], in this render object's own
  /// coordinate space — the same primitive [RenderEditable] uses internally
  /// for its selection painting, so a future caret/selection layer built on
  /// this render object gets identical geometry without needing that class.
  List<TextBox> getBoxesForSelection(TextSelection selection) {
    return _textPainter.getBoxesForSelection(selection);
  }

  /// The plain text content of this paragraph, for callers (hit-testing,
  /// tests) that need it without reaching into [text]'s span tree.
  String get plainText => _textPainter.text?.toPlainText() ?? '';
}
