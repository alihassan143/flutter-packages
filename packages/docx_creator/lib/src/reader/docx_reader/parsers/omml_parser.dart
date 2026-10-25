import 'package:xml/xml.dart';

import '../../../../docx_creator.dart';

/// Parses OMML (`m:oMath`) equations into a [DocxMath] tree.
///
/// Covers the common constructs — runs, fractions, sub/superscripts and
/// radicals (`m:r`, `m:f`, `m:sSup`, `m:sSub`, `m:rad`). Anything else
/// (matrices, n-ary operators, accents, limits, ...) is flattened to its
/// plain text (every `m:t` descendant, concatenated) rather than dropped, so
/// content is never silently lost even where visual fidelity is basic.
class OmmlParser {
  /// Parses an `m:oMath` or `m:oMathPara` element.
  static DocxMath? parse(XmlElement element) {
    final oMath = element.name.local == 'oMathPara'
        ? element.findElements('m:oMath').firstOrNull
        : element;
    if (oMath == null) return null;
    return DocxMath(_parseRow(oMath.childElements));
  }

  static List<DocxMathNode> _parseRow(Iterable<XmlElement> elements) =>
      elements.map(_parseNode).whereType<DocxMathNode>().toList();

  static DocxMathNode? _parseNode(XmlElement el) {
    switch (el.name.local) {
      case 'r':
        final text =
            el.findAllElements('m:t').map((t) => t.innerText).join();
        return text.isEmpty ? null : DocxMathText(text);
      case 'f':
        final num = el.findElements('m:num').firstOrNull;
        final den = el.findElements('m:den').firstOrNull;
        return DocxMathFraction(
          num == null ? const [] : _parseRow(num.childElements),
          den == null ? const [] : _parseRow(den.childElements),
        );
      case 'sSup':
        final base = el.findElements('m:e').firstOrNull;
        final sup = el.findElements('m:sup').firstOrNull;
        return DocxMathSuperscript(
          base == null ? const [] : _parseRow(base.childElements),
          sup == null ? const [] : _parseRow(sup.childElements),
        );
      case 'sSub':
        final base = el.findElements('m:e').firstOrNull;
        final sub = el.findElements('m:sub').firstOrNull;
        return DocxMathSubscript(
          base == null ? const [] : _parseRow(base.childElements),
          sub == null ? const [] : _parseRow(sub.childElements),
        );
      case 'rad':
        final radPr = el.findElements('m:radPr').firstOrNull;
        final degHidden = radPr
                ?.findElements('m:degHide')
                .firstOrNull
                ?.getAttribute('m:val') ==
            '1';
        final deg = el.findElements('m:deg').firstOrNull;
        final body = el.findElements('m:e').firstOrNull;
        return DocxMathRadical(
          body == null ? const [] : _parseRow(body.childElements),
          degHidden || deg == null ? null : _parseRow(deg.childElements),
        );
      default:
        // Unrecognized construct (matrix, n-ary, accent, limit, ...):
        // flatten to its plain text rather than dropping it.
        final text = el.findAllElements('m:t').map((t) => t.innerText).join();
        return text.isEmpty ? null : DocxMathText(text);
    }
  }
}
