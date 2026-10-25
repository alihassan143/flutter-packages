import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import 'render_docx_paragraph.dart';

class _ListItemParentData extends ContainerBoxParentData<RenderBox> {}

/// A two-child [RenderBox] laying out a list item's marker (bullet/number,
/// or an image bullet) at a fixed [markerWidth] column, with the item's
/// text content flowing in the remaining width — the same shape
/// `ListBuilder._buildListItem`'s `Row(SizedBox(width: 24), Expanded(...))`
/// already produces, just under one controlled render object instead of
/// three framework widgets.
///
/// Reuses [RenderDocxParagraph] for both children rather than laying out
/// text itself: a list item's marker and content are each just paragraph
/// text, nothing list-specific about how they're painted/hit-tested. When
/// the content child happens to be a [RenderDocxParagraph] (the common
/// case — see [ListBuilder._buildListItem]'s own `containsWidgetSpan`
/// guard), [getPositionForOffset] delegates to it directly, so a future
/// `DocxHitTester` extension can resolve taps inside list item text without
/// caring this is a list rather than a paragraph.
class RenderDocxListItem extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ListItemParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ListItemParentData> {
  RenderDocxListItem({required double markerWidth})
      : _markerWidth = markerWidth;

  double _markerWidth;
  double get markerWidth => _markerWidth;
  set markerWidth(double value) {
    if (_markerWidth == value) return;
    _markerWidth = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ListItemParentData) {
      child.parentData = _ListItemParentData();
    }
  }

  RenderBox get _marker => firstChild!;
  RenderBox get _content => childAfter(_marker)!;

  @override
  double computeMinIntrinsicWidth(double height) =>
      _markerWidth + _content.getMinIntrinsicWidth(height);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _markerWidth + _content.getMaxIntrinsicWidth(height);

  @override
  double computeMinIntrinsicHeight(double width) {
    final contentWidth = (width - _markerWidth).clamp(0.0, double.infinity);
    return math.max(
      _marker.getMinIntrinsicHeight(_markerWidth),
      _content.getMinIntrinsicHeight(contentWidth),
    );
  }

  @override
  double computeMaxIntrinsicHeight(double width) =>
      computeMinIntrinsicHeight(width);

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    return _content.getDistanceToActualBaseline(baseline);
  }

  @override
  void performLayout() {
    final marker = _marker;
    final content = _content;
    marker.layout(
      BoxConstraints(maxWidth: _markerWidth),
      parentUsesSize: true,
    );
    final contentWidth =
        (constraints.maxWidth - _markerWidth).clamp(0.0, double.infinity);
    content.layout(
      BoxConstraints(minWidth: contentWidth, maxWidth: contentWidth),
      parentUsesSize: true,
    );
    (marker.parentData as _ListItemParentData).offset = Offset.zero;
    (content.parentData as _ListItemParentData).offset =
        Offset(_markerWidth, 0);
    final height = math.max(marker.size.height, content.size.height);
    size = constraints.constrain(Size(constraints.maxWidth, height));
  }

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  /// Resolves a point in this render object's own coordinate space to a
  /// text position within the content child, or `null` when the point
  /// falls in the marker column or the content isn't a [RenderDocxParagraph]
  /// (the `containsWidgetSpan` fallback case).
  TextPosition? getPositionForOffset(Offset localPosition) {
    final content = _content;
    if (content is! RenderDocxParagraph) return null;
    final contentOffset = (content.parentData as _ListItemParentData).offset;
    if (localPosition.dx < contentOffset.dx) return null;
    return content.getPositionForOffset(localPosition - contentOffset);
  }

  /// The content child's plain text, or `''` when it isn't a
  /// [RenderDocxParagraph].
  String get plainText {
    final content = _content;
    return content is RenderDocxParagraph ? content.plainText : '';
  }
}
