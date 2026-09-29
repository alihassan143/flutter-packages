import '../../core/enums.dart';
import 'color_utils.dart';

/// Style context for inline text formatting inheritance.
///
/// Tracks accumulated styles as we descend through HTML elements.
class HtmlStyleContext {
  final String? colorHex;
  final double? fontSize;
  final DocxFontWeight fontWeight;
  final DocxFontStyle fontStyle;
  final List<DocxTextDecoration> decorations;
  final DocxHighlight highlight;
  final String? shadingFill;
  final String? href;
  final bool isLink;
  final bool isSuperscript;
  final bool isSubscript;
  final bool isAllCaps;
  final bool isSmallCaps;
  final bool isDoubleStrike;
  final bool isOutline;
  final bool isShadow;
  final bool isEmboss;
  final bool isImprint;

  /// Depth of current list nesting.
  final int listLevel;

  /// Inherited CSS `text-align` (null = not set by any ancestor).
  final DocxAlign? textAlign;

  /// CSS `text-transform` that must rewrite the text itself (`lowercase`,
  /// `capitalize`); DOCX has no run property for these, unlike uppercase
  /// ([isAllCaps]).
  final String? textTransform;

  const HtmlStyleContext({
    this.colorHex,
    this.fontSize,
    this.fontWeight = DocxFontWeight.normal,
    this.fontStyle = DocxFontStyle.normal,
    this.decorations = const [],
    this.highlight = DocxHighlight.none,
    this.shadingFill,
    this.href,
    this.isLink = false,
    this.isSuperscript = false,
    this.isSubscript = false,
    this.isAllCaps = false,
    this.isSmallCaps = false,
    this.isDoubleStrike = false,
    this.isOutline = false,
    this.isShadow = false,
    this.isEmboss = false,
    this.isImprint = false,
    this.listLevel = -1,
    this.textAlign,
    this.textTransform,
  });

  HtmlStyleContext copyWith({
    String? colorHex,
    double? fontSize,
    DocxFontWeight? fontWeight,
    DocxFontStyle? fontStyle,
    List<DocxTextDecoration>? decorations,
    DocxHighlight? highlight,
    String? shadingFill,
    String? href,
    bool? isLink,
    bool? isSuperscript,
    bool? isSubscript,
    bool? isAllCaps,
    bool? isSmallCaps,
    bool? isDoubleStrike,
    bool? isOutline,
    bool? isShadow,
    bool? isEmboss,
    bool? isImprint,
    int? listLevel,
    DocxAlign? textAlign,
    String? textTransform,
  }) {
    return HtmlStyleContext(
      colorHex: colorHex ?? this.colorHex,
      fontSize: fontSize ?? this.fontSize,
      fontWeight: fontWeight ?? this.fontWeight,
      fontStyle: fontStyle ?? this.fontStyle,
      decorations: decorations ?? this.decorations,
      highlight: highlight ?? this.highlight,
      shadingFill: shadingFill ?? this.shadingFill,
      href: href ?? this.href,
      isLink: isLink ?? this.isLink,
      isSuperscript: isSuperscript ?? this.isSuperscript,
      isSubscript: isSubscript ?? this.isSubscript,
      isAllCaps: isAllCaps ?? this.isAllCaps,
      isSmallCaps: isSmallCaps ?? this.isSmallCaps,
      isDoubleStrike: isDoubleStrike ?? this.isDoubleStrike,
      isOutline: isOutline ?? this.isOutline,
      isShadow: isShadow ?? this.isShadow,
      isEmboss: isEmboss ?? this.isEmboss,
      isImprint: isImprint ?? this.isImprint,
      listLevel: listLevel ?? this.listLevel,
      textAlign: textAlign ?? this.textAlign,
      textTransform: textTransform ?? this.textTransform,
    );
  }

  /// Merge style context with tag-based and CSS style updates.
  HtmlStyleContext mergeWith(
      String? tag, String style, String? Function(String) colorParser) {
    if ((tag == null || tag.isEmpty) && style.isEmpty) return this;

    var ctx = this;

    // Tag based updates
    if (tag != null) {
      switch (tag) {
        case 'b':
        case 'strong':
          ctx = ctx.copyWith(fontWeight: DocxFontWeight.bold);
          break;
        case 'i':
        case 'em':
          ctx = ctx.copyWith(fontStyle: DocxFontStyle.italic);
          break;
        case 'u':
          if (!ctx.decorations.contains(DocxTextDecoration.underline)) {
            ctx = ctx.copyWith(decorations: [
              ...ctx.decorations,
              DocxTextDecoration.underline
            ]);
          }
          break;
        case 's':
        case 'del':
        case 'strike':
          if (!ctx.decorations.contains(DocxTextDecoration.strikethrough)) {
            ctx = ctx.copyWith(decorations: [
              ...ctx.decorations,
              DocxTextDecoration.strikethrough
            ]);
          }
          break;
        case 'sup':
          ctx = ctx.copyWith(isSuperscript: true);
          break;
        case 'sub':
          ctx = ctx.copyWith(isSubscript: true);
          break;
        case 'mark':
          ctx = ctx.copyWith(highlight: DocxHighlight.yellow);
          break;
        case 'a':
          if (!ctx.decorations.contains(DocxTextDecoration.underline)) {
            ctx = ctx.copyWith(decorations: [
              ...ctx.decorations,
              DocxTextDecoration.underline
            ]);
          }
          break;
      }
    }

    // Style attribute based updates. Property lookups below are all
    // case-insensitive with flexible whitespace around ':' so minified or
    // uppercase CSS (e.g. "FONT-WEIGHT:BOLD") is recognized, not just the
    // exact lowercase "property: value" form.
    if (style.isNotEmpty) {
      final fontWeightMatch =
          RegExp(r'font-weight\s*:\s*([a-z0-9]+)', caseSensitive: false)
              .firstMatch(style);
      if (fontWeightMatch != null) {
        final value = fontWeightMatch.group(1)!.toLowerCase();
        final numericWeight = int.tryParse(value);
        // Word (and browsers) render 600+ as visually bold.
        final isBold =
            value == 'bold' || (numericWeight != null && numericWeight >= 600);
        if (isBold) ctx = ctx.copyWith(fontWeight: DocxFontWeight.bold);
      }

      if (RegExp(r'font-style\s*:\s*italic', caseSensitive: false)
          .hasMatch(style)) {
        ctx = ctx.copyWith(fontStyle: DocxFontStyle.italic);
      }

      if (RegExp(r'text-decoration\s*:\s*[a-z\s]*underline',
              caseSensitive: false)
          .hasMatch(style)) {
        if (!ctx.decorations.contains(DocxTextDecoration.underline)) {
          ctx = ctx.copyWith(
              decorations: [...ctx.decorations, DocxTextDecoration.underline]);
        }
      }

      if (RegExp(r'text-decoration\s*:\s*[a-z\s]*line-through',
              caseSensitive: false)
          .hasMatch(style)) {
        if (!ctx.decorations.contains(DocxTextDecoration.strikethrough)) {
          ctx = ctx.copyWith(decorations: [
            ...ctx.decorations,
            DocxTextDecoration.strikethrough
          ]);
        }
      }

      final sizeMatch = RegExp(
              r'font-size\s*:\s*([\d.]+\s*(?:px|pt|em|rem|%)?)',
              caseSensitive: false)
          .firstMatch(style);
      if (sizeMatch != null) {
        final fs = ColorUtils.parseCssLengthToPoints(sizeMatch.group(1)!);
        if (fs != null) ctx = ctx.copyWith(fontSize: fs);
      }

      // Color parsing
      final colorMatch = RegExp(
              r"(?<![-a-zA-Z])color:\s*['\x22]?(#[A-Fa-f0-9]{3,6}|rgba?\([0-9.,\s]+\)|hsla?\([0-9.,%\s]+\)|[a-zA-Z]+)['\x22]?",
              caseSensitive: false)
          .firstMatch(style);
      if (colorMatch != null) {
        final val = colorMatch.group(1);
        if (val != null) {
          final hex = colorParser(val);
          if (hex != null) ctx = ctx.copyWith(colorHex: hex);
        }
      }

      final transform =
          RegExp(r'text-transform\s*:\s*([a-z-]+)', caseSensitive: false)
              .firstMatch(style)
              ?.group(1)
              ?.toLowerCase();
      if (transform == 'uppercase') {
        ctx = ctx.copyWith(isAllCaps: true, textTransform: 'none');
      } else if (transform == 'lowercase' || transform == 'capitalize') {
        ctx = ctx.copyWith(isAllCaps: false, textTransform: transform);
      } else if (transform == 'none') {
        ctx = ctx.copyWith(isAllCaps: false, textTransform: 'none');
      }

      final align = RegExp(r'text-align\s*:\s*([a-z]+)', caseSensitive: false)
          .firstMatch(style)
          ?.group(1)
          ?.toLowerCase();
      final parsedAlign = switch (align) {
        'left' || 'start' => DocxAlign.left,
        'center' => DocxAlign.center,
        'right' || 'end' => DocxAlign.right,
        'justify' => DocxAlign.justify,
        _ => null,
      };
      if (parsedAlign != null) ctx = ctx.copyWith(textAlign: parsedAlign);
      if (RegExp(r'font-variant\s*:\s*small-caps', caseSensitive: false)
          .hasMatch(style)) {
        ctx = ctx.copyWith(isSmallCaps: true);
      }

      // Background Color (Shading)
      final bgMatch = RegExp(
              r"background-color:\s*['\x22]?(#[A-Fa-f0-9]{3,6}|rgba?\([0-9.,\s]+\)|hsla?\([0-9.,%\s]+\)|[a-zA-Z]+)['\x22]?",
              caseSensitive: false)
          .firstMatch(style);
      if (bgMatch != null) {
        final bgVal = bgMatch.group(1)?.toLowerCase();
        if (bgVal != null) {
          final hex = colorParser(bgVal);
          if (hex != null) ctx = ctx.copyWith(shadingFill: hex);
        }
      }
    }

    return ctx;
  }

  /// Reset background color (for inheritance boundaries).
  /// NOTE: copyWith(shadingFill: null) doesn't work because null means "keep original".
  /// We need to explicitly create a new context without the shadingFill.
  HtmlStyleContext resetBackground() {
    return HtmlStyleContext(
      colorHex: colorHex,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      decorations: decorations,
      highlight: highlight,
      shadingFill: null, // Explicitly cleared
      href: href,
      isLink: isLink,
      isSuperscript: isSuperscript,
      isSubscript: isSubscript,
      isAllCaps: isAllCaps,
      isSmallCaps: isSmallCaps,
      isDoubleStrike: isDoubleStrike,
      isOutline: isOutline,
      isShadow: isShadow,
      isEmboss: isEmboss,
      isImprint: isImprint,
      listLevel: listLevel,
      textAlign: textAlign,
      textTransform: textTransform,
    );
  }
}

/// Parsed block-level styles (alignment, borders, shading, indentation).
class HtmlBlockStyles {
  final String? shadingFill;
  final String? colorHex;
  final DocxAlign align;
  final DocxBorderSide? borderTop;
  final DocxBorderSide? borderBottom;
  final DocxBorderSide? borderLeft;
  final DocxBorderSide? borderRight;

  /// Left indentation in twips, from CSS `margin-left`/`padding-left`.
  final int? indentLeft;

  /// Right indentation in twips, from CSS `margin-right`/`padding-right`.
  final int? indentRight;

  /// First-line indentation in twips, from CSS `text-indent`.
  final int? indentFirstLine;

  /// Space before/after in twips, from CSS `margin-top`/`margin-bottom`.
  final int? spacingBefore;
  final int? spacingAfter;

  /// Line spacing (`w:spacing w:line`/`w:lineRule`) from CSS `line-height`.
  final int? lineSpacing;
  final String? lineRule;

  HtmlBlockStyles({
    this.spacingBefore,
    this.spacingAfter,
    this.lineSpacing,
    this.lineRule,
    this.shadingFill,
    this.colorHex,
    this.align = DocxAlign.left,
    this.borderTop,
    this.borderBottom,
    this.borderLeft,
    this.borderRight,
    this.indentLeft,
    this.indentRight,
    this.indentFirstLine,
  });
}
