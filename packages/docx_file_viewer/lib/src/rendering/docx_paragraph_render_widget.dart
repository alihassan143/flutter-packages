import 'package:flutter/widgets.dart';

import 'render_docx_paragraph.dart';

/// [MultiChildRenderObjectWidget] wrapping [RenderDocxParagraph].
///
/// Exposes [text]/[textAlign] as public fields the same way [RichText] does,
/// so existing code/tests that read a text widget's span tree translate
/// directly (`tester.widget<DocxParagraphRenderWidget>(...).text`).
///
/// [WidgetSpan.extractFromInlineSpan] — the same helper [RichText] itself
/// uses — pulls each [WidgetSpan]'s child out of [text]'s span tree in
/// document order and hands them to [RenderDocxParagraph] as children; the
/// extracted widgets already carry the `TextParentData.span` wiring that
/// render object's placeholder-dimension bookkeeping needs, so nothing else
/// has to be done here.
class DocxParagraphRenderWidget extends MultiChildRenderObjectWidget {
  DocxParagraphRenderWidget({
    super.key,
    required this.text,
    this.textAlign = TextAlign.start,
  }) : super(
          children:
              WidgetSpan.extractFromInlineSpan(text, TextScaler.noScaling),
        );

  final InlineSpan text;
  final TextAlign textAlign;

  @override
  RenderDocxParagraph createRenderObject(BuildContext context) {
    return RenderDocxParagraph(
      text: text,
      textAlign: textAlign,
      textDirection: Directionality.of(context),
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderDocxParagraph renderObject) {
    renderObject
      ..text = text
      ..textAlign = textAlign
      ..textDirection = Directionality.of(context);
  }
}
