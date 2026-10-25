import 'package:docx_creator/docx_creator.dart';
import 'package:flutter/widgets.dart';

/// Marks a widget subtree as the rendering of [node].
///
/// Pure metadata - doesn't affect layout or paint. An editor built on top of
/// this viewer needs to answer "which [DocxNode] is under this tap/cursor",
/// "where does this screen position map to in the document". Hit-testing
/// (e.g. `HitTestResult` from a tap, or `Element.visitChildElements`) finds
/// the nearest [DocxNodeBound] ancestor/descendant and reads [node] off it,
/// rather than re-deriving source-node identity from rendered text, which a
/// read-only viewer has no reason to keep around.
///
/// Wraps the result of [DocxWidgetGenerator.generateWidget] for each
/// top-level block it renders - not (yet) the composite float/table-wrap
/// layouts in `_generateBlockWidgets`, which combine multiple source nodes
/// into one Row and don't map cleanly to a single [node].
class DocxNodeBound extends StatelessWidget {
  /// The document node this subtree was rendered from.
  final DocxNode node;

  final Widget child;

  const DocxNodeBound({super.key, required this.node, required this.child});

  /// Finds the nearest [DocxNodeBound] at or above [context], if any.
  static DocxNodeBound? of(BuildContext context) {
    DocxNodeBound? found;
    context.visitAncestorElements((element) {
      if (element.widget is DocxNodeBound) {
        found = element.widget as DocxNodeBound;
        return false;
      }
      return true;
    });
    return found;
  }

  @override
  Widget build(BuildContext context) => child;
}
