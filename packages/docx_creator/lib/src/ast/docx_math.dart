import 'package:xml/xml.dart';

import 'docx_node.dart';

/// A node in a simplified OMML (`m:oMath`) expression tree.
///
/// Only the common subset of Office Math Markup Language is modeled: plain
/// text runs, fractions, sub/superscripts and radicals. Anything else the
/// parser encounters (matrices, n-ary operators, accents, limits, ...) is
/// flattened to its plain text via [DocxMathText] instead of being dropped —
/// see `OmmlParser`.
abstract class DocxMathNode {
  const DocxMathNode();

  /// Plain-text rendering of this node and its children, used wherever a
  /// sub-expression (a numerator, a superscript, a radicand, ...) is shown
  /// as text rather than fully laid out — see [DocxMath] class doc.
  String flatten();
}

/// A run of literal text (`m:r`/`m:t`), or the flattened fallback for any
/// unrecognized OMML construct.
class DocxMathText extends DocxMathNode {
  final String text;
  const DocxMathText(this.text);

  @override
  String flatten() => text;
}

/// `m:f` — a fraction.
class DocxMathFraction extends DocxMathNode {
  final List<DocxMathNode> numerator;
  final List<DocxMathNode> denominator;
  const DocxMathFraction(this.numerator, this.denominator);

  @override
  String flatten() =>
      '(${flattenNodes(numerator)}/${flattenNodes(denominator)})';
}

/// `m:sSup` — a superscript.
class DocxMathSuperscript extends DocxMathNode {
  final List<DocxMathNode> base;
  final List<DocxMathNode> superscript;
  const DocxMathSuperscript(this.base, this.superscript);

  @override
  String flatten() => '${flattenNodes(base)}^${flattenNodes(superscript)}';
}

/// `m:sSub` — a subscript.
class DocxMathSubscript extends DocxMathNode {
  final List<DocxMathNode> base;
  final List<DocxMathNode> subscript;
  const DocxMathSubscript(this.base, this.subscript);

  @override
  String flatten() => '${flattenNodes(base)}_${flattenNodes(subscript)}';
}

/// `m:rad` — a radical (square root, or an n-th root when [degree] is set).
class DocxMathRadical extends DocxMathNode {
  final List<DocxMathNode> radicand;
  final List<DocxMathNode>? degree;
  const DocxMathRadical(this.radicand, [this.degree]);

  @override
  String flatten() => degree == null
      ? '√(${flattenNodes(radicand)})'
      : '${flattenNodes(degree!)}√(${flattenNodes(radicand)})';
}

/// Flattens a row of math nodes to plain text (used for numerators,
/// superscripts, radicands, ... — see [DocxMathNode.flatten]).
String flattenNodes(List<DocxMathNode> nodes) =>
    nodes.map((n) => n.flatten()).join();

/// An inline OMML equation (`m:oMath`, optionally wrapped in `m:oMathPara`).
///
/// Rendering (both PDF export and the Flutter viewer) gives each top-level
/// node in [children] real visual structure (a fraction bar, a raised
/// superscript, a radical sign) but renders *its* inner content — the
/// numerator, the base, the radicand, etc. — as flattened plain text rather
/// than recursing into further nested visual layout. This keeps the
/// renderer a bounded, "basic equation" renderer rather than a full
/// typesetting engine: deeply nested expressions still render (nothing is
/// ever dropped), just as flattened text at the nesting point.
class DocxMath extends DocxInline {
  final List<DocxMathNode> children;
  const DocxMath(this.children, {super.id});

  @override
  void accept(DocxVisitor visitor) => visitor.visitRawInline(this);

  @override
  void buildXml(XmlBuilder builder) {
    builder.element('m:oMath', nest: () {
      for (final node in children) {
        _buildNodeXml(builder, node);
      }
    });
  }

  static void _buildNodeXml(XmlBuilder builder, DocxMathNode node) {
    if (node is DocxMathText) {
      builder.element('m:r', nest: () {
        builder.element('m:t', nest: node.text);
      });
    } else if (node is DocxMathFraction) {
      builder.element('m:f', nest: () {
        builder.element('m:num', nest: () {
          for (final n in node.numerator) {
            _buildNodeXml(builder, n);
          }
        });
        builder.element('m:den', nest: () {
          for (final n in node.denominator) {
            _buildNodeXml(builder, n);
          }
        });
      });
    } else if (node is DocxMathSuperscript) {
      builder.element('m:sSup', nest: () {
        builder.element('m:e', nest: () {
          for (final n in node.base) {
            _buildNodeXml(builder, n);
          }
        });
        builder.element('m:sup', nest: () {
          for (final n in node.superscript) {
            _buildNodeXml(builder, n);
          }
        });
      });
    } else if (node is DocxMathSubscript) {
      builder.element('m:sSub', nest: () {
        builder.element('m:e', nest: () {
          for (final n in node.base) {
            _buildNodeXml(builder, n);
          }
        });
        builder.element('m:sub', nest: () {
          for (final n in node.subscript) {
            _buildNodeXml(builder, n);
          }
        });
      });
    } else if (node is DocxMathRadical) {
      builder.element('m:rad', nest: () {
        if (node.degree == null) {
          builder.element('m:radPr', nest: () {
            builder.element('m:degHide', attributes: {'m:val': '1'});
          });
        }
        builder.element('m:deg', nest: () {
          for (final n in node.degree ?? const <DocxMathNode>[]) {
            _buildNodeXml(builder, n);
          }
        });
        builder.element('m:e', nest: () {
          for (final n in node.radicand) {
            _buildNodeXml(builder, n);
          }
        });
      });
    }
  }
}
