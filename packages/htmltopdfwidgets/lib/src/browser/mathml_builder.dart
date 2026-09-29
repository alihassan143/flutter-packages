import 'dart:math' as math;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'layout/layout_node.dart';

/// A laid-out piece of math: its widget plus the vertical metrics needed to
/// align it on a shared baseline with its neighbours.
class MathBox {
  final pw.Widget widget;

  /// Total height in points.
  final double height;

  /// Distance from the bottom of the box up to its baseline.
  final double depth;

  const MathBox(this.widget, this.height, this.depth);

  double get ascent => height - depth;
}

/// Renders MathML (`<math>` and its presentation elements) into `pdf`
/// widgets: fractions, sub/superscripts, roots, under/over scripts, fences,
/// tables and token elements.
///
/// Vertical metrics are estimated from font sizes (text lines are ~1.16em
/// tall with ~0.23em below the baseline), which is enough to line up
/// numerators, scripts and surrounding text on a common baseline.
class MathMLBuilder {
  MathMLBuilder({
    required this.textStyle,
    this.fontFallback = const [],
  });

  /// Base style (font, color, size) of the surrounding text.
  final pw.TextStyle textStyle;
  final List<pw.Font> fontFallback;

  static const double _lineFactor = 1.16;
  static const double _descentFactor = 0.23;

  /// Scripts shrink by this factor, down to [_minScale] of the base size.
  static const double _scriptScale = 0.71;
  static const double _minScale = 0.5;

  double get _baseSize => textStyle.fontSize ?? 12;

  /// Builds the whole `<math>` element.
  MathBox build(LayoutNode math) {
    final display = math.attributes['display'] == 'block';
    return _row(_children(math), _baseSize, display: display);
  }

  List<LayoutNode> _children(LayoutNode node) => node.children
      .where((c) =>
          c.tagName != '#text' || (c.text != null && c.text!.trim().isNotEmpty))
      .where((c) => c.tagName != 'annotation' && c.tagName != 'annotation-xml')
      .toList();

  MathBox _node(LayoutNode node, double size, {bool display = false}) {
    switch (node.tagName) {
      case '#text':
      case 'mtext':
      case 'ms':
        return _token(_text(node), size, italic: false);
      case 'mi':
        final text = _text(node).trim();
        // Single-letter identifiers are italic by default (MathML spec).
        final variant = node.attributes['mathvariant'];
        final italic = variant != null
            ? variant.contains('italic')
            : text.runes.length == 1 && RegExp(r'[A-Za-z]').hasMatch(text);
        return _token(text, size,
            italic: italic, bold: variant?.contains('bold') ?? false);
      case 'mn':
        return _token(_text(node).trim(), size, italic: false);
      case 'mo':
        return _operator(_text(node).trim(), size, node);
      case 'mspace':
        final width = _length(node.attributes['width'], size) ?? 0;
        return MathBox(pw.SizedBox(width: width), 0, 0);
      case 'mfrac':
        return _fraction(node, size, display);
      case 'msup':
      case 'msub':
      case 'msubsup':
        return _scripts(node, size);
      case 'msqrt':
        return _root(_row(_children(node), size), null, size);
      case 'mroot':
        final kids = _children(node);
        if (kids.length < 2) return _row(kids, size);
        return _root(
            _node(kids[0], size), _node(kids[1], _scaled(size, 2)), size);
      case 'munder':
      case 'mover':
      case 'munderover':
        return _underOver(node, size);
      case 'mfenced':
        return _fenced(node, size);
      case 'mtable':
        return _table(node, size);
      case 'semantics':
        final kids = _children(node);
        return kids.isEmpty ? _empty() : _node(kids.first, size);
      default:
        // math, mrow, mstyle, mpadded, mphantom, merror, unknown elements.
        final box = _row(_children(node), size, display: display);
        if (node.tagName == 'mphantom') {
          return MathBox(
              pw.Opacity(opacity: 0, child: box.widget), box.height, box.depth);
        }
        return box;
    }
  }

  MathBox _empty() => MathBox(pw.SizedBox(), 0, 0);

  String _text(LayoutNode node) {
    final buffer = StringBuffer(node.text ?? '');
    for (final c in node.children) {
      buffer.write(_text(c));
    }
    return buffer
        .toString()
        .replaceAll(RegExp(r'\s+'), ' ')
        // Invisible operators (function application, invisible times...).
        .replaceAll(RegExp('[⁡-⁤]'), '');
  }

  double _scaled(double size, int levels) =>
      math.max(_baseSize * _minScale, size * math.pow(_scriptScale, levels));

  double? _length(String? value, double size) {
    if (value == null) return null;
    final v = value.trim();
    final n = double.tryParse(v.replaceAll(RegExp(r'[a-z%]+$'), ''));
    if (n == null) {
      const named = {
        'veryverythinmathspace': 1 / 18,
        'verythinmathspace': 2 / 18,
        'thinmathspace': 3 / 18,
        'mediummathspace': 4 / 18,
        'thickmathspace': 5 / 18,
        'verythickmathspace': 6 / 18,
        'veryverythickmathspace': 7 / 18,
      };
      final f = named[v];
      return f == null ? null : f * size;
    }
    if (v.endsWith('em')) return n * size;
    if (v.endsWith('ex')) return n * size * 0.5;
    if (v.endsWith('px')) return n * 0.75;
    return n;
  }

  pw.TextStyle _style(double size, {bool italic = false, bool bold = false}) =>
      textStyle.copyWith(
        fontSize: size,
        fontStyle: italic ? pw.FontStyle.italic : pw.FontStyle.normal,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        fontFallback: fontFallback,
        decoration: pw.TextDecoration.none,
        lineSpacing: 0,
      );

  MathBox _token(String text, double size,
      {bool italic = false,
      bool bold = false,
      double left = 0,
      double right = 0}) {
    if (text.isEmpty) return _empty();
    // U+2212 MINUS SIGN is missing from the standard PDF fonts.
    final shown = text.replaceAll('−', '-');
    return MathBox(
      pw.Padding(
        padding: pw.EdgeInsets.only(left: left, right: right),
        child: pw.Text(shown,
            style: _style(size, italic: italic, bold: bold), softWrap: false),
      ),
      size * _lineFactor,
      size * _descentFactor,
    );
  }

  static const _noSpaceOperators = {
    '(',
    ')',
    '[',
    ']',
    '{',
    '}',
    '|',
    ',',
    ';',
    '.',
    '!',
    "'",
    '′',
  };

  MathBox _operator(String op, double size, LayoutNode node,
      {bool prefix = false}) {
    final isScript = size < _baseSize * 0.95;
    final space = _noSpaceOperators.contains(op) || isScript || prefix
        ? 0.0
        : size * 0.22;
    final lspace = _length(node.attributes['lspace'], size);
    final rspace = _length(node.attributes['rspace'], size);
    final trailing = op == ',' || op == ';' ? size * 0.17 : 0.0;
    if (op.isEmpty) return _empty();
    return _token(op, size,
        left: lspace ?? space, right: rspace ?? (space + trailing));
  }

  /// Lays boxes out horizontally with their baselines aligned.
  MathBox _row(List<LayoutNode> nodes, double size, {bool display = false}) {
    final boxes = <MathBox>[];
    for (var i = 0; i < nodes.length; i++) {
      final n = nodes[i];
      // A leading operator (or one right after another operator) is a
      // prefix, e.g. unary minus: no spacing around it.
      final prefix =
          n.tagName == 'mo' && (i == 0 || nodes[i - 1].tagName == 'mo');
      boxes.add(prefix
          ? _operator(_text(n).trim(), size, n, prefix: true)
          : _node(n, size, display: display));
    }
    return _rowOf(boxes);
  }

  MathBox _rowOf(List<MathBox> boxes) {
    if (boxes.isEmpty) return _empty();
    if (boxes.length == 1) return boxes.single;
    final depth = boxes.map((b) => b.depth).reduce(math.max);
    final ascent = boxes.map((b) => b.ascent).reduce(math.max);
    return MathBox(
      pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          for (final b in boxes)
            pw.Padding(
              padding: pw.EdgeInsets.only(bottom: depth - b.depth),
              child: b.widget,
            ),
        ],
      ),
      ascent + depth,
      depth,
    );
  }

  /// Stacks boxes vertically, centered horizontally. Uses a one-column
  /// intrinsic-width table so the column is as wide as its widest row
  /// (pdf has no IntrinsicWidth widget).
  pw.Widget _stack(List<pw.Widget> rows, {pw.TableBorder? border}) => pw.Table(
        tableWidth: pw.TableWidth.min,
        defaultColumnWidth: const pw.IntrinsicColumnWidth(),
        border: border,
        children: [
          for (final r in rows) pw.TableRow(children: [pw.Center(child: r)]),
        ],
      );

  MathBox _fraction(LayoutNode node, double size, bool display) {
    final kids = _children(node);
    if (kids.length < 2) return _row(kids, size);
    // Inline fractions use smaller numerator/denominator, like TeX's
    // text style; display fractions keep the full size.
    final partSize = display ? size : _scaled(size, 1);
    final num = _node(kids[0], partSize);
    final den = _node(kids[1], partSize);
    final thickness = node.attributes['linethickness'] == '0'
        ? 0.0
        : math.max(0.4, size * 0.05);
    final gap = size * 0.12;
    final pad = size * 0.1;

    final widget = pw.Padding(
      padding: pw.EdgeInsets.symmetric(horizontal: size * 0.1),
      child: _stack([
        pw.Padding(
            padding: pw.EdgeInsets.only(bottom: gap, left: pad, right: pad),
            child: num.widget),
        pw.Padding(
            padding: pw.EdgeInsets.only(top: gap, left: pad, right: pad),
            child: den.widget),
      ],
          border: thickness > 0
              ? pw.TableBorder(
                  horizontalInside: pw.BorderSide(
                      width: thickness,
                      color: textStyle.color ?? PdfColors.black))
              : null),
    );
    final height = num.height + den.height + 2 * gap + thickness;
    // The fraction bar sits on the math axis, ~0.25em above the baseline.
    final depth = den.height + gap + thickness / 2 - size * 0.25;
    return MathBox(widget, height, math.max(0, depth));
  }

  MathBox _scripts(LayoutNode node, double size) {
    final kids = _children(node);
    if (kids.isEmpty) return _empty();
    final base = _node(kids[0], size);
    final scriptSize = _scaled(size, 1);
    MathBox? sub;
    MathBox? sup;
    if (node.tagName == 'msub' && kids.length > 1) {
      sub = _node(kids[1], scriptSize);
    } else if (node.tagName == 'msup' && kids.length > 1) {
      sup = _node(kids[1], scriptSize);
    } else if (node.tagName == 'msubsup' && kids.length > 2) {
      sub = _node(kids[1], scriptSize);
      sup = _node(kids[2], scriptSize);
    }

    // Superscript baseline ~0.45em above the base baseline, subscript
    // ~0.25em below it.
    final supShift = size * 0.45;
    final subShift = size * 0.25;
    final ascent =
        math.max(base.ascent, sup == null ? 0.0 : supShift + sup.ascent);
    final depth =
        math.max(base.depth, sub == null ? 0.0 : subShift + sub.depth);
    final height = ascent + depth;

    pw.Widget placed(MathBox box, double baselineFromBottom) => pw.Container(
          height: height,
          alignment: pw.Alignment.bottomLeft,
          padding: pw.EdgeInsets.only(
              bottom: math.max(0, baselineFromBottom - box.depth)),
          child: box.widget,
        );

    final scriptColumn = <pw.Widget>[];
    if (sup != null) scriptColumn.add(placed(sup, depth + supShift));
    if (sub != null) scriptColumn.add(placed(sub, depth - subShift));

    return MathBox(
      pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          placed(base, depth),
          pw.SizedBox(width: size * 0.05),
          if (scriptColumn.length == 1)
            scriptColumn.single
          else if (scriptColumn.length == 2)
            pw.Stack(children: scriptColumn),
        ],
      ),
      height,
      depth,
    );
  }

  MathBox _root(MathBox radicand, MathBox? index, double size) {
    final gap = size * 0.12;
    final thickness = math.max(0.5, size * 0.05);
    final height = radicand.height + gap + thickness;
    final signWidth = size * 0.55;
    final color = textStyle.color ?? PdfColors.black;

    final sign = pw.CustomPaint(
      size: PdfPoint(signWidth, height),
      painter: (canvas, box) {
        final h = box.y;
        final w = box.x;
        canvas
          ..setStrokeColor(color)
          ..setLineWidth(thickness)
          ..moveTo(0, h * 0.42)
          ..lineTo(w * 0.25, h * 0.52)
          ..lineTo(w * 0.55, 0)
          ..lineTo(w, h - thickness / 2)
          ..strokePath();
      },
    );

    final body = pw.Container(
      padding:
          pw.EdgeInsets.only(top: gap, left: size * 0.08, right: size * 0.05),
      decoration: pw.BoxDecoration(
          border:
              pw.Border(top: pw.BorderSide(width: thickness, color: color))),
      child: radicand.widget,
    );

    final children = <pw.Widget>[];
    if (index != null) {
      children.add(pw.Padding(
        padding: pw.EdgeInsets.only(bottom: height * 0.45),
        child: index.widget,
      ));
    }
    children
      ..add(sign)
      ..add(body);

    return MathBox(
      pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: children,
      ),
      math.max(height, index == null ? 0 : height * 0.45 + index.height),
      radicand.depth,
    );
  }

  MathBox _underOver(LayoutNode node, double size) {
    final kids = _children(node);
    if (kids.isEmpty) return _empty();
    final base = _node(kids[0], size);
    final scriptSize = _scaled(size, 1);
    MathBox? under;
    MathBox? over;
    if (node.tagName == 'munder' && kids.length > 1) {
      under = _node(kids[1], scriptSize);
    } else if (node.tagName == 'mover' && kids.length > 1) {
      over = _node(kids[1], scriptSize);
    } else if (node.tagName == 'munderover' && kids.length > 2) {
      under = _node(kids[1], scriptSize);
      over = _node(kids[2], scriptSize);
    }
    return MathBox(
      _stack([
        if (over != null) over.widget,
        base.widget,
        if (under != null) under.widget,
      ]),
      base.height + (over?.height ?? 0) + (under?.height ?? 0),
      base.depth + (under?.height ?? 0),
    );
  }

  MathBox _fenced(LayoutNode node, double size) {
    final open = node.attributes['open'] ?? '(';
    final close = node.attributes['close'] ?? ')';
    final separators =
        (node.attributes['separators'] ?? ',').replaceAll(' ', '');
    final kids = _children(node);
    final boxes = <MathBox>[_token(open, size)];
    for (var i = 0; i < kids.length; i++) {
      if (i > 0 && separators.isNotEmpty) {
        final sep = separators[math.min(i - 1, separators.length - 1)];
        boxes.add(_token(sep, size, right: size * 0.17));
      }
      boxes.add(_node(kids[i], size));
    }
    boxes.add(_token(close, size));
    return _rowOf(boxes);
  }

  MathBox _table(LayoutNode node, double size) {
    final rows = node.children.where((c) => c.tagName == 'mtr').toList();
    if (rows.isEmpty) return _empty();
    var height = 0.0;
    final tableRows = <pw.TableRow>[];
    for (final row in rows) {
      final cells = row.children.where((c) => c.tagName == 'mtd').toList();
      final boxes = cells.map((c) => _row(_children(c), size)).toList();
      height += boxes.isEmpty
          ? 0
          : boxes.map((b) => b.height).reduce(math.max) + size * 0.2;
      tableRows.add(pw.TableRow(children: [
        for (final b in boxes)
          pw.Padding(
            padding: pw.EdgeInsets.symmetric(
                horizontal: size * 0.4, vertical: size * 0.1),
            child: pw.Center(child: b.widget),
          ),
      ]));
    }
    return MathBox(
      pw.Table(
        tableWidth: pw.TableWidth.min,
        defaultColumnWidth: const pw.IntrinsicColumnWidth(),
        children: tableRows,
      ),
      height,
      // Tables are centered on the math axis.
      math.max(0, height / 2 - size * 0.25),
    );
  }
}
