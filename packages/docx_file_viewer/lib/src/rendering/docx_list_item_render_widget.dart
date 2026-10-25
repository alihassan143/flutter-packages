import 'package:flutter/widgets.dart';

import 'render_docx_list_item.dart';

/// Thin [MultiChildRenderObjectWidget] wrapping [RenderDocxListItem].
///
/// [marker] and [content] can be any widget — typically both
/// [DocxParagraphRenderWidget]s (plain bullet/number and plain text), but
/// [marker] may be an `Image.memory` for an image bullet, and [content]
/// falls back to `RichText`/`SelectableText.rich` when it contains a
/// [WidgetSpan] or OS-level selection is on — see
/// `ListBuilder._buildListItem`.
class DocxListItemRenderWidget extends MultiChildRenderObjectWidget {
  DocxListItemRenderWidget({
    super.key,
    required this.marker,
    required this.content,
    required this.markerWidth,
  }) : super(children: [marker, content]);

  final Widget marker;
  final Widget content;
  final double markerWidth;

  @override
  RenderDocxListItem createRenderObject(BuildContext context) {
    return RenderDocxListItem(markerWidth: markerWidth);
  }

  @override
  void updateRenderObject(
      BuildContext context, RenderDocxListItem renderObject) {
    renderObject.markerWidth = markerWidth;
  }
}
