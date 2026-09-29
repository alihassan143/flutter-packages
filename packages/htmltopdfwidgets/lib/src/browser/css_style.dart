import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart';

import 'css_values.dart';
import 'layout/unit_converter.dart';

enum Display { block, inline, none, flex, table, tableRow, tableCell }

/// Image fit mode, similar to CSS object-fit
enum ObjectFit { contain, cover, fill, fitWidth, fitHeight, none, scaleDown }

/// Vertical alignment for table cells
enum VerticalAlign { top, middle, bottom, baseline }

/// Table layout algorithm
enum TableLayout { auto, fixed }

enum FlexDirection { row, column, rowReverse, columnReverse }

enum JustifyContent {
  flexStart,
  flexEnd,
  center,
  spaceBetween,
  spaceAround,
  spaceEvenly
}

enum AlignItems { flexStart, flexEnd, center, baseline, stretch }

/// CSS `text-transform`.
enum TextTransform { none, uppercase, lowercase, capitalize }

/// CSS `white-space`.
enum WhiteSpace { normal, pre, preWrap, preLine, nowrap }

/// Inline baseline shift (`vertical-align: super | sub`, `<sup>`, `<sub>`).
enum BaselineShift { none, superscript, subscript }

/// Bit flags recording which sides of a margin/padding were specified, so a
/// longhand such as `margin-top` only overrides that side when merged.
class EdgeMask {
  static const int top = 1;
  static const int right = 2;
  static const int bottom = 4;
  static const int left = 8;
  static const int all = 15;
}

class CSSStyle {
  final PdfColor? color;
  final PdfColor? backgroundColor;
  final double? fontSize;
  final FontWeight? fontWeight;
  final FontStyle? fontStyle;
  final TextDecoration? textDecoration;
  final PdfColor? textDecorationColor;
  final TextDecorationStyle? textDecorationStyle;
  final Display? display;
  final double? width;
  final double? height;

  /// Absolute line height in points.
  final double? lineHeight;

  /// Unitless line-height multiplier (e.g. `line-height: 1.5`). Inherited as
  /// a factor, so it scales with each descendant's own font size.
  final double? lineHeightFactor;
  final EdgeInsets? padding;
  final int? paddingMask;
  final EdgeInsets? margin;
  final int? marginMask;
  final Border? border;
  final Border? borderTop;
  final Border? borderRight;
  final Border? borderBottom;
  final Border? borderLeft;
  final String? fontFamily;
  final TextAlign? textAlign;
  final ObjectFit? objectFit;
  final VerticalAlign? verticalAlign;
  final double? borderRadius;
  final bool? borderCollapse;
  final TextDirection? textDirection;
  final TableLayout? tableLayout;
  final double? letterSpacing;
  final TextTransform? textTransform;
  final WhiteSpace? whiteSpace;
  final BaselineShift? baselineShift;
  final String? listStyleType;
  final double? textIndent;

  /// `margin-left: auto; margin-right: auto` - center a sized block.
  final bool? centerHorizontally;

  // Flex layout properties
  final int? flexGrow;
  final FlexDirection? flexDirection;
  final JustifyContent? justifyContent;
  final AlignItems? alignItems;

  const CSSStyle({
    this.color,
    this.backgroundColor,
    this.fontSize,
    this.fontWeight,
    this.fontStyle,
    this.textDecoration,
    this.textDecorationColor,
    this.textDecorationStyle,
    this.display,
    this.width,
    this.height,
    this.lineHeight,
    this.lineHeightFactor,
    this.padding,
    this.paddingMask,
    this.margin,
    this.marginMask,
    this.border,
    this.borderTop,
    this.borderRight,
    this.borderBottom,
    this.borderLeft,
    this.fontFamily,
    this.textAlign,
    this.objectFit,
    this.verticalAlign,
    this.borderRadius,
    this.borderCollapse,
    this.textDirection,
    this.tableLayout,
    this.letterSpacing,
    this.textTransform,
    this.whiteSpace,
    this.baselineShift,
    this.listStyleType,
    this.textIndent,
    this.centerHorizontally,
    this.flexGrow,
    this.flexDirection,
    this.justifyContent,
    this.alignItems,
  });

  /// Merges this style with another style. The other style takes precedence.
  CSSStyle merge(CSSStyle other) {
    final m = _mergeInsets(margin, marginMask, other.margin, other.marginMask);
    final p =
        _mergeInsets(padding, paddingMask, other.padding, other.paddingMask);

    // A shorthand `border` resets every side, so it clears per-side borders
    // set by a lower-priority rule (and vice versa for per-side overrides).
    final otherHasShorthand = other.border != null;
    return CSSStyle(
      color: other.color ?? color,
      backgroundColor: other.backgroundColor ?? backgroundColor,
      fontSize: other.fontSize ?? fontSize,
      fontWeight: other.fontWeight ?? fontWeight,
      fontStyle: other.fontStyle ?? fontStyle,
      textDecoration: other.textDecoration ?? textDecoration,
      textDecorationColor: other.textDecorationColor ?? textDecorationColor,
      textDecorationStyle: other.textDecorationStyle ?? textDecorationStyle,
      display: other.display ?? display,
      width: other.width ?? width,
      height: other.height ?? height,
      // Absolute and unitless line heights are mutually exclusive.
      lineHeight: other.lineHeightFactor != null
          ? null
          : (other.lineHeight ?? lineHeight),
      lineHeightFactor: other.lineHeight != null
          ? null
          : (other.lineHeightFactor ?? lineHeightFactor),
      padding: p.$1,
      paddingMask: p.$2,
      margin: m.$1,
      marginMask: m.$2,
      border: other.border ?? border,
      borderTop: other.borderTop ?? (otherHasShorthand ? null : borderTop),
      borderRight:
          other.borderRight ?? (otherHasShorthand ? null : borderRight),
      borderBottom:
          other.borderBottom ?? (otherHasShorthand ? null : borderBottom),
      borderLeft: other.borderLeft ?? (otherHasShorthand ? null : borderLeft),
      fontFamily: other.fontFamily ?? fontFamily,
      textAlign: other.textAlign ?? textAlign,
      objectFit: other.objectFit ?? objectFit,
      verticalAlign: other.verticalAlign ?? verticalAlign,
      borderRadius: other.borderRadius ?? borderRadius,
      borderCollapse: other.borderCollapse ?? borderCollapse,
      textDirection: other.textDirection ?? textDirection,
      tableLayout: other.tableLayout ?? tableLayout,
      letterSpacing: other.letterSpacing ?? letterSpacing,
      textTransform: other.textTransform ?? textTransform,
      whiteSpace: other.whiteSpace ?? whiteSpace,
      baselineShift: other.baselineShift ?? baselineShift,
      listStyleType: other.listStyleType ?? listStyleType,
      textIndent: other.textIndent ?? textIndent,
      centerHorizontally: other.centerHorizontally ?? centerHorizontally,
      flexGrow: other.flexGrow ?? flexGrow,
      flexDirection: other.flexDirection ?? flexDirection,
      justifyContent: other.justifyContent ?? justifyContent,
      alignItems: other.alignItems ?? alignItems,
    );
  }

  static (EdgeInsets?, int?) _mergeInsets(
      EdgeInsets? base, int? baseMask, EdgeInsets? over, int? overMask) {
    if (over == null) return (base, baseMask);
    final oMask = overMask ?? EdgeMask.all;
    if (base == null || oMask == EdgeMask.all) return (over, oMask);
    final bMask = baseMask ?? EdgeMask.all;
    double pick(int bit, double b, double o) => (oMask & bit) != 0 ? o : b;
    return (
      EdgeInsets.only(
        top: pick(EdgeMask.top, base.top, over.top),
        right: pick(EdgeMask.right, base.right, over.right),
        bottom: pick(EdgeMask.bottom, base.bottom, over.bottom),
        left: pick(EdgeMask.left, base.left, over.left),
      ),
      bMask | oMask
    );
  }

  /// Inherits inheritable properties from a parent style.
  CSSStyle inheritFrom(CSSStyle parent) {
    return CSSStyle(
      color: color ?? parent.color,
      fontSize: fontSize ?? parent.fontSize,
      fontWeight: fontWeight ?? parent.fontWeight,
      fontStyle: fontStyle ?? parent.fontStyle,
      textDecoration: textDecoration ?? parent.textDecoration,
      textDecorationColor: textDecorationColor ?? parent.textDecorationColor,
      textDecorationStyle: textDecorationStyle ?? parent.textDecorationStyle,
      fontFamily: fontFamily ?? parent.fontFamily,
      textAlign: textAlign ?? parent.textAlign,
      textDirection: textDirection ?? parent.textDirection,
      lineHeight:
          lineHeight ?? (lineHeightFactor == null ? parent.lineHeight : null),
      lineHeightFactor: lineHeightFactor ??
          (lineHeight == null ? parent.lineHeightFactor : null),
      letterSpacing: letterSpacing ?? parent.letterSpacing,
      textTransform: textTransform ?? parent.textTransform,
      whiteSpace: whiteSpace ?? parent.whiteSpace,
      baselineShift: baselineShift ?? parent.baselineShift,
      listStyleType: listStyleType ?? parent.listStyleType,
      textIndent: textIndent ?? parent.textIndent,
      // Non-inherited properties
      backgroundColor: backgroundColor,
      display: display,
      width: width,
      height: height,
      padding: padding,
      paddingMask: paddingMask,
      margin: margin,
      marginMask: marginMask,
      border: border,
      borderTop: borderTop,
      borderRight: borderRight,
      borderBottom: borderBottom,
      borderLeft: borderLeft,
      objectFit: objectFit,
      verticalAlign: verticalAlign,
      borderRadius: borderRadius,
      borderCollapse: borderCollapse,
      tableLayout: tableLayout,
      centerHorizontally: centerHorizontally,
      flexGrow: flexGrow,
      flexDirection: flexDirection,
      justifyContent: justifyContent,
      alignItems: alignItems,
    );
  }

  /// The effective border combining the `border` shorthand with any
  /// per-side overrides, or null when no visible side remains.
  Border? get resolvedBorder {
    if (border == null &&
        borderTop == null &&
        borderRight == null &&
        borderBottom == null &&
        borderLeft == null) {
      return null;
    }
    final top = borderTop?.top ?? border?.top ?? BorderSide.none;
    final right = borderRight?.right ?? border?.right ?? BorderSide.none;
    final bottom = borderBottom?.bottom ?? border?.bottom ?? BorderSide.none;
    final left = borderLeft?.left ?? border?.left ?? BorderSide.none;
    bool visible(BorderSide s) => s.style.paint && s.width > 0;
    if (!visible(top) &&
        !visible(right) &&
        !visible(bottom) &&
        !visible(left)) {
      return null;
    }
    return Border(top: top, right: right, bottom: bottom, left: left);
  }

  /// Parses a CSS declaration list (`prop: value; ...`) into a [CSSStyle].
  ///
  /// [parentFontSize] resolves relative font sizes (`em`, `%`, `larger`);
  /// other `em` lengths resolve against the element's own font size.
  static CSSStyle parse(String cssString, {double? parentFontSize}) {
    if (cssString.trim().isEmpty) return const CSSStyle();
    final declarations = <String, String>{};
    final cleaned =
        cssString.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
    for (final declaration in _splitDeclarations(cleaned)) {
      final idx = declaration.indexOf(':');
      if (idx <= 0) continue;
      final property = declaration.substring(0, idx).trim().toLowerCase();
      var value = declaration.substring(idx + 1).trim();
      value = value.replaceAll(RegExp(r'!\s*important$'), '').trim();
      if (property.isEmpty || value.isEmpty) continue;
      declarations[property] = value;
    }
    return fromDeclarations(declarations, parentFontSize: parentFontSize);
  }

  /// Splits on `;` outside of parentheses/quotes (data URIs contain `;`).
  static List<String> _splitDeclarations(String css) {
    final out = <String>[];
    final buf = StringBuffer();
    var depth = 0;
    String? quote;
    for (final ch in css.split('')) {
      if (quote != null) {
        if (ch == quote) quote = null;
      } else if (ch == '"' || ch == "'") {
        quote = ch;
      } else if (ch == '(') {
        depth++;
      } else if (ch == ')' && depth > 0) {
        depth--;
      } else if (ch == ';' && depth == 0) {
        out.add(buf.toString());
        buf.clear();
        continue;
      }
      buf.write(ch);
    }
    if (buf.isNotEmpty) out.add(buf.toString());
    return out;
  }

  /// Builds a style from already-split declarations, applied in order.
  static CSSStyle fromDeclarations(Map<String, String> declarations,
      {double? parentFontSize}) {
    final baseFont = parentFontSize ?? UnitConverter.defaultBaseFontSizePt;

    // Font size first: other em-based lengths depend on it.
    double? fontSize;
    final fontShorthand = declarations['font'];
    if (fontShorthand != null) {
      final sizeToken = CssValues.splitTokens(fontShorthand).firstWhere(
          (t) => _parseFontSize(t.split('/').first, baseFont) != null,
          orElse: () => '');
      if (sizeToken.isNotEmpty) {
        fontSize = _parseFontSize(sizeToken.split('/').first, baseFont);
      }
    }
    if (declarations['font-size'] != null) {
      fontSize =
          _parseFontSize(declarations['font-size']!, baseFont) ?? fontSize;
    }
    final emBase = fontSize ?? baseFont;

    double? len(String v) =>
        UnitConverter.parseAndConvertToPt(v, elementFontSize: emBase);

    var style = CSSStyle(fontSize: fontSize);

    declarations.forEach((property, value) {
      final lower = value.toLowerCase();
      switch (property) {
        case 'color':
          style = style.merge(CSSStyle(color: CssValues.parseColor(value)));
          break;
        case 'background-color':
          style = style
              .merge(CSSStyle(backgroundColor: CssValues.parseColor(value)));
          break;
        case 'background':
          for (final t in CssValues.splitTokens(value)) {
            final c = CssValues.parseColor(t);
            if (c != null) {
              style = style.merge(CSSStyle(backgroundColor: c));
              break;
            }
          }
          break;
        case 'font':
          final tokens = CssValues.splitTokens(value);
          for (final t in tokens) {
            final w = _parseFontWeight(t);
            if (w != null && t != 'normal') {
              style = style.merge(CSSStyle(fontWeight: w));
            }
            if (t.toLowerCase() == 'italic' || t.toLowerCase() == 'oblique') {
              style = style.merge(const CSSStyle(fontStyle: FontStyle.italic));
            }
            if (t.contains('/')) {
              final lh = _parseLineHeight(t.split('/').last, emBase);
              if (lh != null) style = style.merge(lh);
            }
          }
          final famIdx = tokens.indexWhere(
              (t) => _parseFontSize(t.split('/').first, baseFont) != null);
          if (famIdx >= 0 && famIdx < tokens.length - 1) {
            style = style.merge(CSSStyle(
                fontFamily:
                    _firstFamily(tokens.sublist(famIdx + 1).join(' '))));
          }
          break;
        case 'font-weight':
          style = style.merge(CSSStyle(fontWeight: _parseFontWeight(value)));
          break;
        case 'font-style':
          style = style.merge(CSSStyle(fontStyle: _parseFontStyle(value)));
          break;
        case 'text-decoration':
        case 'text-decoration-line':
          final tokens = CssValues.splitTokens(value);
          style = style.merge(CSSStyle(
            textDecoration: _parseTextDecoration(lower),
            textDecorationColor: tokens
                .map(CssValues.parseColor)
                .firstWhere((c) => c != null, orElse: () => null),
            textDecorationStyle:
                tokens.contains('double') ? TextDecorationStyle.double : null,
          ));
          break;
        case 'text-decoration-color':
          style = style.merge(
              CSSStyle(textDecorationColor: CssValues.parseColor(value)));
          break;
        case 'text-decoration-style':
          style = style.merge(CSSStyle(
              textDecorationStyle: lower == 'double'
                  ? TextDecorationStyle.double
                  : TextDecorationStyle.solid));
          break;
        case 'display':
          style = style.merge(CSSStyle(display: _parseDisplay(value)));
          break;
        case 'width':
        case 'max-width':
          // max-width is treated as width when no explicit width is given.
          if (property == 'max-width' && declarations.containsKey('width')) {
            break;
          }
          final w = len(value);
          if (w != null) style = style.merge(CSSStyle(width: w));
          break;
        case 'height':
          final h = len(value);
          if (h != null) style = style.merge(CSSStyle(height: h));
          break;
        case 'line-height':
          final lh = _parseLineHeight(value, emBase);
          if (lh != null) style = style.merge(lh);
          break;
        case 'letter-spacing':
          style = style.merge(
              CSSStyle(letterSpacing: lower == 'normal' ? 0 : len(value)));
          break;
        case 'text-transform':
          style = style.merge(CSSStyle(textTransform: _parseTransform(lower)));
          break;
        case 'white-space':
          style = style.merge(CSSStyle(whiteSpace: _parseWhiteSpace(lower)));
          break;
        case 'text-indent':
          style = style.merge(CSSStyle(textIndent: len(value)));
          break;
        case 'list-style-type':
        case 'list-style':
          final type = CssValues.splitTokens(lower)
              .firstWhere((t) => _listStyleTypes.contains(t), orElse: () => '');
          if (type.isNotEmpty) {
            style = style.merge(CSSStyle(listStyleType: type));
          }
          break;
        case 'padding':
          final p = _parseEdgeInsets(value, emBase);
          if (p != null) style = style.merge(CSSStyle(padding: p));
          break;
        case 'margin':
          final m = _parseEdgeInsets(value, emBase);
          if (m != null) {
            final tokens = CssValues.splitTokens(lower);
            final autoH = (tokens.length == 1 && tokens[0] == 'auto') ||
                ((tokens.length == 2 || tokens.length == 3) &&
                    tokens[1] == 'auto') ||
                (tokens.length == 4 &&
                    tokens[1] == 'auto' &&
                    tokens[3] == 'auto');
            style = style.merge(
                CSSStyle(margin: m, centerHorizontally: autoH ? true : null));
          }
          break;
        case 'padding-top':
        case 'padding-right':
        case 'padding-bottom':
        case 'padding-left':
        case 'margin-top':
        case 'margin-right':
        case 'margin-bottom':
        case 'margin-left':
          final isMargin = property.startsWith('margin');
          final side = property.split('-').last;
          final v = lower == 'auto' ? 0.0 : (len(value) ?? 0.0);
          final mask = _sideMask(side);
          final insets = EdgeInsets.only(
            top: side == 'top' ? v : 0,
            right: side == 'right' ? v : 0,
            bottom: side == 'bottom' ? v : 0,
            left: side == 'left' ? v : 0,
          );
          final bothAuto = isMargin &&
              (side == 'left' || side == 'right') &&
              declarations['margin-left']?.trim().toLowerCase() == 'auto' &&
              declarations['margin-right']?.trim().toLowerCase() == 'auto';
          style = style.merge(isMargin
              ? CSSStyle(
                  margin: insets,
                  marginMask: mask,
                  centerHorizontally: bothAuto ? true : null)
              : CSSStyle(padding: insets, paddingMask: mask));
          break;
        case 'border':
          final side = _parseBorderSide(value, emBase);
          if (side != null) {
            style = style.merge(CSSStyle(
                border:
                    Border(top: side, right: side, bottom: side, left: side)));
          }
          break;
        case 'border-top':
        case 'border-right':
        case 'border-bottom':
        case 'border-left':
          final side = _parseBorderSide(value, emBase);
          if (side != null) {
            style = style.merge(_sideBorder(property.split('-').last, side));
          }
          break;
        case 'border-width':
        case 'border-color':
        case 'border-style':
          // Longhands adjust the shorthand border (defaulting to solid black).
          final current = style.border?.top ??
              const BorderSide(width: 0.75, color: PdfColors.black);
          BorderSide updated = current;
          if (property == 'border-width') {
            final w = _borderWidth(CssValues.splitTokens(lower).first, emBase);
            if (w != null) updated = _copySide(current, width: w);
          } else if (property == 'border-color') {
            final c = CssValues.parseColor(CssValues.splitTokens(value).first);
            if (c != null) updated = _copySide(current, color: c);
          } else {
            updated = _copySide(current,
                style: _borderStyle(CssValues.splitTokens(lower).first));
          }
          style = style.merge(CSSStyle(
              border: Border(
                  top: updated,
                  right: updated,
                  bottom: updated,
                  left: updated)));
          break;
        case 'font-family':
          style = style.merge(CSSStyle(fontFamily: _firstFamily(value)));
          break;
        case 'text-align':
          style = style.merge(CSSStyle(textAlign: _parseTextAlign(value)));
          break;
        case 'object-fit':
          style = style.merge(CSSStyle(objectFit: _parseObjectFit(value)));
          break;
        case 'vertical-align':
          if (lower == 'super' || lower == 'sub') {
            style = style.merge(CSSStyle(
                baselineShift: lower == 'super'
                    ? BaselineShift.superscript
                    : BaselineShift.subscript));
          } else {
            style = style
                .merge(CSSStyle(verticalAlign: _parseVerticalAlign(value)));
          }
          break;
        case 'border-radius':
          final r = len(CssValues.splitTokens(value).first);
          if (r != null) style = style.merge(CSSStyle(borderRadius: r));
          break;
        case 'border-collapse':
          if (lower == 'collapse') {
            style = style.merge(const CSSStyle(borderCollapse: true));
          }
          if (lower == 'separate') {
            style = style.merge(const CSSStyle(borderCollapse: false));
          }
          break;
        case 'direction':
          if (lower == 'rtl') {
            style =
                style.merge(const CSSStyle(textDirection: TextDirection.rtl));
          }
          if (lower == 'ltr') {
            style =
                style.merge(const CSSStyle(textDirection: TextDirection.ltr));
          }
          break;
        case 'table-layout':
          if (lower == 'fixed') {
            style = style.merge(const CSSStyle(tableLayout: TableLayout.fixed));
          }
          if (lower == 'auto') {
            style = style.merge(const CSSStyle(tableLayout: TableLayout.auto));
          }
          break;
        case 'flex-grow':
          style = style.merge(CSSStyle(flexGrow: int.tryParse(value)));
          break;
        case 'flex':
          final grow = int.tryParse(CssValues.splitTokens(value).first);
          if (grow != null) style = style.merge(CSSStyle(flexGrow: grow));
          break;
        case 'flex-direction':
          style =
              style.merge(CSSStyle(flexDirection: _parseFlexDirection(value)));
          break;
        case 'justify-content':
          style = style
              .merge(CSSStyle(justifyContent: _parseJustifyContent(value)));
          break;
        case 'align-items':
          style = style.merge(CSSStyle(alignItems: _parseAlignItems(value)));
          break;
      }
    });

    return style;
  }

  static const _listStyleTypes = {
    'disc',
    'circle',
    'square',
    'decimal',
    'decimal-leading-zero',
    'lower-alpha',
    'upper-alpha',
    'lower-latin',
    'upper-latin',
    'lower-roman',
    'upper-roman',
    'lower-greek',
    'none',
  };

  static int _sideMask(String side) {
    switch (side) {
      case 'top':
        return EdgeMask.top;
      case 'right':
        return EdgeMask.right;
      case 'bottom':
        return EdgeMask.bottom;
      default:
        return EdgeMask.left;
    }
  }

  static CSSStyle _sideBorder(String side, BorderSide s) {
    switch (side) {
      case 'top':
        return CSSStyle(borderTop: Border(top: s));
      case 'right':
        return CSSStyle(borderRight: Border(right: s));
      case 'bottom':
        return CSSStyle(borderBottom: Border(bottom: s));
      default:
        return CSSStyle(borderLeft: Border(left: s));
    }
  }

  static String? _firstFamily(String value) {
    final first = value.split(',').first.trim();
    final unquoted = first.replaceAll(RegExp('[\'"]'), '').trim();
    return unquoted.isEmpty ? null : unquoted;
  }

  static double? _parseFontSize(String value, double parentSize) {
    final v = value.trim().toLowerCase();
    const keywords = {
      'xx-small': 0.5625,
      'x-small': 0.625,
      'small': 0.8125,
      'medium': 1.0,
      'large': 1.125,
      'x-large': 1.5,
      'xx-large': 2.0,
      'xxx-large': 3.0,
    };
    if (keywords.containsKey(v)) {
      return UnitConverter.defaultBaseFontSizePt * keywords[v]!;
    }
    if (v == 'smaller') return parentSize / 1.2;
    if (v == 'larger') return parentSize * 1.2;
    if (v.endsWith('%')) {
      final n = double.tryParse(v.substring(0, v.length - 1));
      return n == null ? null : parentSize * n / 100;
    }
    if (v.endsWith('em') && !v.endsWith('rem')) {
      final n = double.tryParse(v.substring(0, v.length - 2));
      return n == null ? null : parentSize * n;
    }
    // Bare numbers are not valid font sizes (they'd match font weights in
    // the `font` shorthand), except 0.
    if (double.tryParse(v) != null) return null;
    return UnitConverter.parseAndConvertToPt(v);
  }

  static CSSStyle? _parseLineHeight(String value, double fontSize) {
    final v = value.trim().toLowerCase();
    if (v == 'normal') return const CSSStyle(lineHeightFactor: 1.2);
    final factor = double.tryParse(v);
    if (factor != null) return CSSStyle(lineHeightFactor: factor);
    if (v.endsWith('%')) {
      final n = double.tryParse(v.substring(0, v.length - 1));
      return n == null ? null : CSSStyle(lineHeight: fontSize * n / 100);
    }
    final pt = UnitConverter.parseAndConvertToPt(v, elementFontSize: fontSize);
    return pt == null ? null : CSSStyle(lineHeight: pt);
  }

  static TextTransform? _parseTransform(String v) {
    switch (v) {
      case 'uppercase':
        return TextTransform.uppercase;
      case 'lowercase':
        return TextTransform.lowercase;
      case 'capitalize':
        return TextTransform.capitalize;
      case 'none':
        return TextTransform.none;
    }
    return null;
  }

  static WhiteSpace? _parseWhiteSpace(String v) {
    switch (v) {
      case 'pre':
        return WhiteSpace.pre;
      case 'pre-wrap':
      case 'break-spaces':
        return WhiteSpace.preWrap;
      case 'pre-line':
        return WhiteSpace.preLine;
      case 'nowrap':
        return WhiteSpace.nowrap;
      case 'normal':
        return WhiteSpace.normal;
    }
    return null;
  }

  static BorderStyle _borderStyle(String token) {
    switch (token) {
      case 'none':
      case 'hidden':
        return BorderStyle.none;
      case 'dashed':
        return BorderStyle.dashed;
      case 'dotted':
        return BorderStyle.dotted;
      default:
        return BorderStyle.solid;
    }
  }

  static const _borderStyleTokens = {
    'none',
    'hidden',
    'solid',
    'dashed',
    'dotted',
    'double',
    'groove',
    'ridge',
    'inset',
    'outset',
  };

  static double? _borderWidth(String token, double fontSize) {
    switch (token) {
      case 'thin':
        return 0.75;
      case 'medium':
        return 2.25;
      case 'thick':
        return 3.75;
    }
    return UnitConverter.parseAndConvertToPt(token, elementFontSize: fontSize);
  }

  static BorderSide _copySide(BorderSide s,
      {double? width, PdfColor? color, BorderStyle? style}) {
    return BorderSide(
        width: width ?? s.width,
        color: color ?? s.color,
        style: style ?? s.style);
  }

  /// Parses a border shorthand (`1px solid red`, any token order). Returns
  /// [BorderSide.none] for `none`/`0`, null if nothing was recognised.
  static BorderSide? _parseBorderSide(String value, double fontSize) {
    final tokens = CssValues.splitTokens(value.toLowerCase());
    if (tokens.isEmpty) return null;
    double? width;
    PdfColor? color;
    BorderStyle? style;
    var recognised = false;
    for (final t in tokens) {
      if (_borderStyleTokens.contains(t)) {
        style = _borderStyle(t);
        recognised = true;
        continue;
      }
      final w = _borderWidth(t, fontSize);
      if (w != null) {
        width = w;
        recognised = true;
        continue;
      }
      final c = CssValues.parseColor(t);
      if (c != null) {
        color = c;
        recognised = true;
      }
    }
    if (!recognised) return null;
    if (style == BorderStyle.none || width == 0) return BorderSide.none;
    // Per CSS a border without a style is not drawn, but a width/color-only
    // declaration is almost always meant as solid, so treat it that way.
    return BorderSide(
      width: width ?? 0.75,
      color: color ?? PdfColors.black,
      style: style ?? BorderStyle.solid,
    );
  }

  static FontWeight? _parseFontWeight(String value) {
    final v = value.trim().toLowerCase();
    switch (v) {
      case 'bold':
      case 'bolder':
        return FontWeight.bold;
      case 'normal':
      case 'lighter':
        return FontWeight.normal;
    }
    final n = int.tryParse(v);
    if (n != null && n >= 100 && n <= 1000) {
      return n >= 600 ? FontWeight.bold : FontWeight.normal;
    }
    return null;
  }

  static FontStyle? _parseFontStyle(String value) {
    switch (value.trim().toLowerCase()) {
      case 'italic':
      case 'oblique':
        return FontStyle.italic;
      case 'normal':
        return FontStyle.normal;
      default:
        return null;
    }
  }

  static TextDecoration? _parseTextDecoration(String value) {
    final decorations = <TextDecoration>[];
    if (value.contains('underline')) decorations.add(TextDecoration.underline);
    if (value.contains('line-through')) {
      decorations.add(TextDecoration.lineThrough);
    }
    if (value.contains('overline')) decorations.add(TextDecoration.overline);
    if (decorations.isEmpty) {
      return value.contains('none') ? TextDecoration.none : null;
    }
    return decorations.length == 1
        ? decorations.first
        : TextDecoration.combine(decorations);
  }

  static Display? _parseDisplay(String value) {
    switch (value.trim().toLowerCase()) {
      case 'block':
      case 'list-item':
      case 'flow-root':
        return Display.block;
      case 'inline':
      case 'inline-block':
        return Display.inline;
      case 'none':
        return Display.none;
      case 'flex':
      case 'inline-flex':
        return Display.flex;
      case 'table':
        return Display.table;
      case 'table-row':
        return Display.tableRow;
      case 'table-cell':
        return Display.tableCell;
      default:
        return null;
    }
  }

  static EdgeInsets? _parseEdgeInsets(String value, double fontSize) {
    final parts = CssValues.splitTokens(value);
    final values = parts
        .map((p) => p.toLowerCase() == 'auto'
            ? 0.0
            : (UnitConverter.parseAndConvertToPt(p,
                    elementFontSize: fontSize) ??
                0.0))
        .toList();

    if (values.isEmpty) return null;

    if (values.length == 1) {
      return EdgeInsets.all(values[0]);
    } else if (values.length == 2) {
      return EdgeInsets.symmetric(vertical: values[0], horizontal: values[1]);
    } else if (values.length == 3) {
      // top, horizontal, bottom
      return EdgeInsets.only(
          top: values[0], left: values[1], right: values[1], bottom: values[2]);
    } else {
      return EdgeInsets.fromLTRB(values[3], values[0], values[1], values[2]);
    }
  }

  static TextAlign? _parseTextAlign(String value) {
    switch (value.trim().toLowerCase()) {
      case 'left':
      case 'start':
        return TextAlign.left;
      case 'right':
      case 'end':
        return TextAlign.right;
      case 'center':
        return TextAlign.center;
      case 'justify':
        return TextAlign.justify;
      default:
        return null;
    }
  }

  static ObjectFit? _parseObjectFit(String value) {
    switch (value.trim().toLowerCase()) {
      case 'contain':
        return ObjectFit.contain;
      case 'cover':
        return ObjectFit.cover;
      case 'fill':
        return ObjectFit.fill;
      case 'none':
        return ObjectFit.none;
      case 'scale-down':
        return ObjectFit.scaleDown;
      default:
        return null;
    }
  }

  static VerticalAlign? _parseVerticalAlign(String value) {
    switch (value.trim().toLowerCase()) {
      case 'top':
      case 'text-top':
        return VerticalAlign.top;
      case 'middle':
        return VerticalAlign.middle;
      case 'bottom':
      case 'text-bottom':
        return VerticalAlign.bottom;
      case 'baseline':
        return VerticalAlign.baseline;
      default:
        return null;
    }
  }

  static FlexDirection? _parseFlexDirection(String value) {
    switch (value.trim().toLowerCase()) {
      case 'row':
        return FlexDirection.row;
      case 'column':
        return FlexDirection.column;
      case 'row-reverse':
        return FlexDirection.rowReverse;
      case 'column-reverse':
        return FlexDirection.columnReverse;
      default:
        return null;
    }
  }

  static JustifyContent? _parseJustifyContent(String value) {
    switch (value.trim().toLowerCase()) {
      case 'flex-start':
      case 'start':
      case 'left':
        return JustifyContent.flexStart;
      case 'flex-end':
      case 'end':
      case 'right':
        return JustifyContent.flexEnd;
      case 'center':
        return JustifyContent.center;
      case 'space-between':
        return JustifyContent.spaceBetween;
      case 'space-around':
        return JustifyContent.spaceAround;
      case 'space-evenly':
        return JustifyContent.spaceEvenly;
      default:
        return null;
    }
  }

  static AlignItems? _parseAlignItems(String value) {
    switch (value.trim().toLowerCase()) {
      case 'flex-start':
      case 'start':
        return AlignItems.flexStart;
      case 'flex-end':
      case 'end':
        return AlignItems.flexEnd;
      case 'center':
        return AlignItems.center;
      case 'baseline':
        return AlignItems.baseline;
      case 'stretch':
        return AlignItems.stretch;
      default:
        return null;
    }
  }
}
