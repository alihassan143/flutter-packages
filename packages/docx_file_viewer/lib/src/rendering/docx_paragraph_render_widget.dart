import 'package:flutter/widgets.dart';

import 'render_docx_paragraph.dart';

/// Thin [LeafRenderObjectWidget] wrapping [RenderDocxParagraph].
///
/// Exposes [text]/[textAlign] as public fields the same way [RichText] does,
/// so existing code/tests that read a text widget's span tree translate
/// directly (`tester.widget<DocxParagraphRenderWidget>(...).text`).
class DocxParagraphRenderWidget extends LeafRenderObjectWidget {
  const DocxParagraphRenderWidget({
    super.key,
    required this.text,
    this.textAlign = TextAlign.start,
  });

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
