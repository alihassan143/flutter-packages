import 'dart:math' as math;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'layout/layout_node.dart';
import 'layout/unit_converter.dart';

/// A laid-out piece of math: its widget plus the vertical metrics needed to
/// align it on a shared baseline with its neighbours.
class MathBox {
  final pw.Widget widget;

  /// Total height in points.
  final double height;

  /// Distance from the bottom of the box up to its baseline.
  final double depth;

  /// Horizontal space to remove after this box (negative `mspace`).
  final double pullBack;

  const MathBox(this.widget, this.height, this.depth, {this.pullBack = 0});

  double get ascent => height - depth;
}

/// Inherited rendering state while descending a MathML tree (`mstyle`,
/// `mathcolor`, `mathsize`, `mathvariant`, display vs. text style).
class _MathCtx {
  final double size;
  final bool display;
  final PdfColor? color;

  const _MathCtx(this.size, {this.display = false, this.color});

  _MathCtx copyWith({double? size, bool? display, PdfColor? color}) =>
      _MathCtx(size ?? this.size,
          display: display ?? this.display, color: color ?? this.color);
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

  static final _whitespace = RegExp(r'\s+');
  static final _invisibleOperators = RegExp('[⁡-⁤]');
  static final _latinLetter = RegExp(r'^[A-Za-z]$');

  double get _baseSize => textStyle.fontSize ?? 12;

  /// Whether the standard PDF fonts (Latin-1 only) render the formula: no
  /// custom font and no fallback fonts were supplied.
  bool get _standardFontsOnly => textStyle.font == null && fontFallback.isEmpty;

  /// `display="block"` (case-insensitive) or CSS `display: block`.
  static bool isDisplayBlock(LayoutNode math) =>
      (math.attributes['display'] ?? '').toLowerCase() == 'block';

  /// Builds the whole `<math>` element.
  MathBox build(LayoutNode math, {bool display = false}) {
    final ctx = _applyStyle(
        math, _MathCtx(_baseSize, display: display || isDisplayBlock(math)));
    return _row(_children(math), ctx);
  }

  List<LayoutNode> _children(LayoutNode node) => node.children
      .where((c) =>
          c.tagName != '#text' || (c.text != null && c.text!.trim().isNotEmpty))
      .where((c) => c.tagName != 'annotation' && c.tagName != 'annotation-xml')
      .toList();

  /// Applies an element's MathML style attributes and CSS color.
  _MathCtx _applyStyle(LayoutNode node, _MathCtx ctx) {
    var result = ctx;
    final a = node.attributes;
    // Color comes from the element's computed style: the HTML parser maps
    // `mathcolor` to CSS `color`, so it cascades like any other color.
    final color = node.style.color;
    if (color != null) result = result.copyWith(color: color);

    final sizeAttr = (a['mathsize'] ?? a['fontsize'])?.trim().toLowerCase();
    if (sizeAttr != null) {
      final size = switch (sizeAttr) {
        'small' => result.size * 0.8,
        'normal' => result.size,
        'big' => result.size * 1.2,
        _ => sizeAttr.endsWith('%')
            ? (double.tryParse(sizeAttr.replaceAll('%', '')) ?? 100) /
                100 *
                result.size
            : _length(sizeAttr, result.size),
      };
      if (size != null && size > 0) result = result.copyWith(size: size);
    }

    final displayStyle = a['displaystyle']?.toLowerCase();
    if (displayStyle == 'true') result = result.copyWith(display: true);
    if (displayStyle == 'false') result = result.copyWith(display: false);
    return result;
  }

  MathBox _node(LayoutNode node, _MathCtx parent) {
    final ctx = _applyStyle(node, parent);
    switch (node.tagName) {
      case '#text':
      case 'mtext':
      case 'ms':
        return _token(_text(node), ctx,
            variant: node.attributes['mathvariant']);
      case 'mi':
        final text = _text(node).trim();
        // Single-letter identifiers are italic by default (MathML spec).
        final variant = node.attributes['mathvariant'] ??
            (text.runes.length == 1 && _latinLetter.hasMatch(text)
                ? 'italic'
                : 'normal');
        return _token(text, ctx, variant: variant);
      case 'mn':
        return _token(_text(node).trim(), ctx,
            variant: node.attributes['mathvariant']);
      case 'mo':
        return _operator(_text(node).trim(), ctx, node);
      case 'mspace':
        final width = _length(node.attributes['width'], ctx.size) ?? 0;
        return MathBox(pw.SizedBox(width: math.max(0, width)), 0, 0,
            pullBack: width < 0 ? -width : 0);
      case 'mfrac':
        return _fraction(node, ctx);
      case 'msup':
      case 'msub':
      case 'msubsup':
        return _scripts(node, ctx);
      case 'msqrt':
        return _root(_row(_children(node), ctx), null, ctx);
      case 'mroot':
        final kids = _children(node);
        if (kids.length < 2) return _row(kids, ctx);
        return _root(
            _node(kids[0], ctx),
            _node(kids[1],
                ctx.copyWith(size: _scaled(ctx.size, 2), display: false)),
            ctx);
      case 'munder':
      case 'mover':
      case 'munderover':
        return _underOver(node, ctx);
      case 'mfenced':
        return _fenced(node, ctx);
      case 'mtable':
        return _table(node, ctx);
      case 'semantics':
        final kids = _children(node);
        return kids.isEmpty ? _empty() : _node(kids.first, ctx);
      default:
        // math, mrow, mstyle, mpadded, mphantom, merror, unknown elements.
        final box = _row(_children(node), ctx);
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
      buffer.write(_rawText(c));
    }
    return buffer
        .toString()
        .replaceAll(_whitespace, ' ')
        // Invisible operators (function application, invisible times...).
        .replaceAll(_invisibleOperators, '');
  }

  String _rawText(LayoutNode node) {
    final buffer = StringBuffer(node.text ?? '');
    for (final c in node.children) {
      buffer.write(_rawText(c));
    }
    return buffer.toString();
  }

  double _scaled(double size, int levels) =>
      math.max(_baseSize * _minScale, size * math.pow(_scriptScale, levels));

  static const _namedSpaces = {
    'veryverythinmathspace': 1 / 18,
    'verythinmathspace': 2 / 18,
    'thinmathspace': 3 / 18,
    'mediummathspace': 4 / 18,
    'thickmathspace': 5 / 18,
    'verythickmathspace': 6 / 18,
    'veryverythickmathspace': 7 / 18,
  };

  /// A MathML length in points: named spaces, `em`/`ex` relative to the
  /// current size, bare numbers as points, anything else via the shared CSS
  /// unit converter (px, pt, in, cm, mm, pc). Negative values are kept.
  double? _length(String? value, double size) {
    if (value == null) return null;
    final v = value.trim().toLowerCase();
    if (v.isEmpty) return null;
    final named = _namedSpaces[v];
    if (named != null) return named * size;
    final negative = v.startsWith('-');
    final body = negative ? v.substring(1) : v;
    double? result;
    if (body.endsWith('em') && !body.endsWith('rem')) {
      final n = double.tryParse(body.substring(0, body.length - 2));
      result = n == null ? null : n * size;
    } else if (body.endsWith('ex')) {
      final n = double.tryParse(body.substring(0, body.length - 2));
      result = n == null ? null : n * size * 0.5;
    } else if (double.tryParse(body) != null) {
      result = double.parse(body);
    } else {
      result = UnitConverter.parseAndConvertToPt(body, elementFontSize: size);
    }
    if (result == null) return null;
    return negative ? -result : result;
  }

  /// Common math symbols the standard (Latin-1) PDF fonts can't draw, and
  /// the closest text they can, used only when no Unicode font is given.
  static const _asciiFallback = {
    '−': '-', // minus
    '′': "'", // prime
    '″': "''",
    '≤': '<=',
    '≥': '>=',
    '≠': '!=',
    '≈': '~',
    '→': '->',
    '←': '<-',
    '↔': '<->',
    '⇒': '=>',
    '⇔': '<=>',
    '∞': 'oo',
    '⋅': '·', // dot operator -> middle dot
    '∗': '*',
    '∈': 'in',
    '…': '...',
    // <mo> large operators are drawn (see _largeOperator); these cover the
    // same glyphs in other token elements and bare text.
    '∑': 'Sigma', '∏': 'Pi', '∫': 'int',
    'α': 'alpha', 'β': 'beta', 'γ': 'gamma',
    'δ': 'delta', 'ε': 'epsilon', 'θ': 'theta',
    'λ': 'lambda', 'μ': 'mu', 'π': 'pi',
    'σ': 'sigma', 'τ': 'tau', 'φ': 'phi',
    'ω': 'omega', 'Δ': 'Delta', 'Σ': 'Sigma',
    'Ω': 'Omega', 'Π': 'Pi',
  };

  String _displayable(String text) {
    if (!_standardFontsOnly) return text;
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final ch = String.fromCharCode(rune);
      buffer.write(rune <= 0xFF ? ch : (_asciiFallback[ch] ?? ch));
    }
    return buffer.toString();
  }

  pw.TextStyle _style(_MathCtx ctx, String? variant) {
    final v = variant?.toLowerCase() ?? 'normal';
    return textStyle.copyWith(
      fontSize: ctx.size,
      color: ctx.color ?? textStyle.color,
      fontStyle:
          v.contains('italic') ? pw.FontStyle.italic : pw.FontStyle.normal,
      fontWeight:
          v.contains('bold') ? pw.FontWeight.bold : pw.FontWeight.normal,
      fontFallback: fontFallback,
      decoration: pw.TextDecoration.none,
      lineSpacing: 0,
    );
  }

  MathBox _token(String text, _MathCtx ctx,
      {String? variant, double left = 0, double right = 0}) {
    if (text.isEmpty) return _empty();
    return MathBox(
      pw.Padding(
        padding: pw.EdgeInsets.only(left: left, right: right),
        child: pw.Text(_displayable(text),
            style: _style(ctx, variant), softWrap: false),
      ),
      ctx.size * _lineFactor,
      ctx.size * _descentFactor,
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

  /// Operators after which the next operator is binary (not a prefix).
  static const _closingOperators = {
    ')',
    ']',
    '}',
    '|',
    '!',
    "'",
    '′',
    '″',
  };

  static const _largeOperators = {'∑', '∏', '∫'};

  MathBox _operator(String op, _MathCtx ctx, LayoutNode node,
      {bool prefix = false}) {
    if (op.isEmpty) return _empty();
    if (_largeOperators.contains(op)) return _largeOperator(op, ctx);
    final size = ctx.size;
    final isScript = size < _baseSize * 0.95;
    final space = _noSpaceOperators.contains(op) || isScript || prefix
        ? 0.0
        : size * 0.22;
    final lspace = _length(node.attributes['lspace'], size);
    final rspace = _length(node.attributes['rspace'], size);
    final trailing = op == ',' || op == ';' ? size * 0.17 : 0.0;
    return _token(op, ctx,
        left: math.max(0, lspace ?? space),
        right: math.max(0, rspace ?? (space + trailing)));
  }

  /// Sum, product and integral signs, drawn as vector shapes so they render
  /// with any font (the standard PDF fonts have none of these glyphs).
  MathBox _largeOperator(String op, _MathCtx ctx) {
    final scale = ctx.display ? 1.6 : 1.15;
    final h = ctx.size * scale;
    final w = op == '∫' ? ctx.size * 0.5 : ctx.size * 0.85;
    final color = ctx.color ?? textStyle.color ?? PdfColors.black;
    final stroke = math.max(0.6, ctx.size * 0.07);
    final sign = pw.CustomPaint(
      size: PdfPoint(w, h),
      painter: (canvas, box) {
        final bw = box.x;
        final bh = box.y;
        canvas
          ..setStrokeColor(color)
          ..setLineWidth(stroke);
        switch (op) {
          case '∑': // sigma
            canvas
              ..moveTo(bw, bh * 0.92)
              ..lineTo(bw * 0.95, bh)
              ..lineTo(0, bh)
              ..lineTo(bw * 0.55, bh / 2)
              ..lineTo(0, 0)
              ..lineTo(bw * 0.95, 0)
              ..lineTo(bw, bh * 0.08);
          case '∏': // pi
            canvas
              ..moveTo(0, bh)
              ..lineTo(bw, bh)
              ..moveTo(bw * 0.2, bh)
              ..lineTo(bw * 0.2, 0)
              ..moveTo(bw * 0.8, bh)
              ..lineTo(bw * 0.8, 0);
          default: // integral
            canvas
              ..moveTo(bw, bh * 0.95)
              ..curveTo(bw * 0.8, bh * 1.02, bw * 0.55, bh, bw * 0.5, bh * 0.8)
              ..lineTo(bw * 0.5, bh * 0.2)
              ..curveTo(bw * 0.45, 0, bw * 0.2, -bh * 0.02, 0, bh * 0.05);
        }
        canvas.strokePath();
      },
    );
    final pad = ctx.size * 0.1;
    return MathBox(
      pw.Padding(
          padding: pw.EdgeInsets.symmetric(horizontal: pad), child: sign),
      h,
      // Centered on the math axis (~0.25em above the baseline).
      math.max(0, h / 2 - ctx.size * 0.25),
    );
  }

  /// Lays boxes out horizontally with their baselines aligned.
  MathBox _row(List<LayoutNode> nodes, _MathCtx ctx) {
    final boxes = <MathBox>[];
    for (var i = 0; i < nodes.length; i++) {
      final n = nodes[i];
      // A leading operator, or one right after another operator that isn't
      // a closing fence/postfix, is a prefix (e.g. unary minus): no spacing.
      final prefix = n.tagName == 'mo' &&
          (i == 0 ||
              (nodes[i - 1].tagName == 'mo' &&
                  !_closingOperators.contains(_text(nodes[i - 1]).trim())));
      boxes.add(prefix
          ? _operator(_text(n).trim(), _applyStyle(n, ctx), n, prefix: true)
          : _node(n, ctx));
    }
    return _rowOf(boxes);
  }

  MathBox _rowOf(List<MathBox> boxes) {
    if (boxes.isEmpty) return _empty();
    if (boxes.length == 1 && boxes.single.pullBack == 0) return boxes.single;
    final depth = boxes.map((b) => b.depth).reduce(math.max);
    final ascent = boxes.map((b) => b.ascent).reduce(math.max);
    // Negative spaces pull everything after them back to the left.
    final children = <pw.Widget>[];
    var shift = 0.0;
    for (final b in boxes) {
      pw.Widget child = pw.Padding(
        padding: pw.EdgeInsets.only(bottom: depth - b.depth),
        child: b.widget,
      );
      if (shift > 0) {
        child =
            pw.Transform.translate(offset: PdfPoint(-shift, 0), child: child);
      }
      children.add(child);
      shift += b.pullBack;
    }
    return MathBox(
      pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: children,
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

  double _lineThickness(String? value, double size) {
    final defaultThickness = math.max(0.4, size * 0.05);
    final v = value?.trim().toLowerCase();
    if (v == null || v.isEmpty || v == 'medium') return defaultThickness;
    if (v == 'thin') return defaultThickness / 2;
    if (v == 'thick') return defaultThickness * 2;
    if (v.endsWith('%')) {
      final n = double.tryParse(v.substring(0, v.length - 1));
      return n == null ? defaultThickness : defaultThickness * n / 100;
    }
    final length = _length(v, size);
    return length == null ? defaultThickness : math.max(0, length);
  }

  MathBox _fraction(LayoutNode node, _MathCtx ctx) {
    final kids = _children(node);
    if (kids.length < 2) return _row(kids, ctx);
    final size = ctx.size;
    // Inline fractions use smaller numerator/denominator, like TeX's text
    // style; display fractions keep the full size. Both parts are in text
    // style themselves.
    final partCtx = ctx.copyWith(
        size: ctx.display ? size : _scaled(size, 1), display: false);
    final num = _node(kids[0], partCtx);
    final den = _node(kids[1], partCtx);
    final thickness = _lineThickness(node.attributes['linethickness'], size);
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
                      color: ctx.color ?? textStyle.color ?? PdfColors.black))
              : null),
    );
    final height = num.height + den.height + 2 * gap + thickness;
    // The fraction bar sits on the math axis, ~0.25em above the baseline.
    final depth = den.height + gap + thickness / 2 - size * 0.25;
    return MathBox(widget, height, math.max(0, depth));
  }

  MathBox _scripts(LayoutNode node, _MathCtx ctx) {
    final kids = _children(node);
    if (kids.isEmpty) return _empty();
    final size = ctx.size;
    final base = _node(kids[0], ctx);
    final scriptCtx = ctx.copyWith(size: _scaled(size, 1), display: false);
    MathBox? sub;
    MathBox? sup;
    if (node.tagName == 'msub' && kids.length > 1) {
      sub = _node(kids[1], scriptCtx);
    } else if (node.tagName == 'msup' && kids.length > 1) {
      sup = _node(kids[1], scriptCtx);
    } else if (node.tagName == 'msubsup' && kids.length > 2) {
      sub = _node(kids[1], scriptCtx);
      sup = _node(kids[2], scriptCtx);
    }

    // Superscript baseline ~0.45em above the base baseline, subscript
    // ~0.25em below it; with both, keep a 0.1em gap between them.
    final subShift = size * 0.25;
    var supShift = size * 0.45;
    if (sub != null && sup != null) {
      final subTop = sub.ascent - subShift;
      supShift = math.max(supShift, subTop + sup.depth + size * 0.1);
    }
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

  MathBox _root(MathBox radicand, MathBox? index, _MathCtx ctx) {
    final size = ctx.size;
    final gap = size * 0.12;
    final thickness = math.max(0.5, size * 0.05);
    final height = radicand.height + gap + thickness;
    final signWidth = size * 0.55;
    final color = ctx.color ?? textStyle.color ?? PdfColors.black;

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

  MathBox _underOver(LayoutNode node, _MathCtx ctx) {
    final kids = _children(node);
    if (kids.isEmpty) return _empty();
    final base = _node(kids[0], ctx);
    final scriptCtx = ctx.copyWith(size: _scaled(ctx.size, 1), display: false);
    MathBox? under;
    MathBox? over;
    if (node.tagName == 'munder' && kids.length > 1) {
      under = _node(kids[1], scriptCtx);
    } else if (node.tagName == 'mover' && kids.length > 1) {
      over = _node(kids[1], scriptCtx);
    } else if (node.tagName == 'munderover' && kids.length > 2) {
      under = _node(kids[1], scriptCtx);
      over = _node(kids[2], scriptCtx);
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

  MathBox _fenced(LayoutNode node, _MathCtx ctx) {
    final open = node.attributes['open'] ?? '(';
    final close = node.attributes['close'] ?? ')';
    final separators =
        (node.attributes['separators'] ?? ',').replaceAll(' ', '');
    final kids = _children(node);
    final boxes = <MathBox>[_token(open, ctx)];
    for (var i = 0; i < kids.length; i++) {
      if (i > 0 && separators.isNotEmpty) {
        final sep = separators[math.min(i - 1, separators.length - 1)];
        boxes.add(_token(sep, ctx, right: ctx.size * 0.17));
      }
      boxes.add(_node(kids[i], ctx));
    }
    boxes.add(_token(close, ctx));
    return _rowOf(boxes);
  }

  MathBox _table(LayoutNode node, _MathCtx ctx) {
    final size = ctx.size;
    // `mlabeledtr` rows carry their label in the first cell; it is kept as
    // a leading column.
    final rows = node.children
        .where((c) => c.tagName == 'mtr' || c.tagName == 'mlabeledtr')
        .toList();
    if (rows.isEmpty) return _empty();
    final cellCtx = ctx.copyWith(display: false);
    var height = 0.0;
    var columns = 0;
    final rowBoxes = <List<MathBox>>[];
    for (final row in rows) {
      final cells = row.children.where((c) => c.tagName == 'mtd').toList();
      final boxes = cells.map((c) => _row(_children(c), cellCtx)).toList();
      columns = math.max(columns, boxes.length);
      height += boxes.isEmpty
          ? 0
          : boxes.map((b) => b.height).reduce(math.max) + size * 0.2;
      rowBoxes.add(boxes);
    }
    final tableRows = [
      for (final boxes in rowBoxes)
        pw.TableRow(children: [
          for (var c = 0; c < columns; c++)
            c < boxes.length
                ? pw.Padding(
                    padding: pw.EdgeInsets.symmetric(
                        horizontal: size * 0.4, vertical: size * 0.1),
                    child: pw.Center(child: boxes[c].widget),
                  )
                : pw.SizedBox(),
        ]),
    ];
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
