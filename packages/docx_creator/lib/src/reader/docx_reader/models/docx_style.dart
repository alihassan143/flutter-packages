import 'package:xml/xml.dart';

import '../../../../docx_creator.dart';

/// Represents parsed style properties from styles.xml.
///
/// Combines both paragraph (pPr) and run (rPr) properties into a single
/// object for easier merging and application.
class DocxStyle {
  final String id;
  final String? type;
  final String? basedOn;

  // Paragraph Properties
  final String? pStyleId;
  final DocxAlign? align;
  final String? shadingFill;
  final String? themeFill;
  final String? themeFillTint;
  final String? themeFillShade;
  final int? numId;
  final int? ilvl;
  final int? spacingAfter;
  final int? spacingBefore;
  final int? lineSpacing;
  final String? lineRule; // 'auto', 'exact', 'atLeast'
  final int? indentLeft;
  final int? indentRight;
  final int? indentFirstLine;
  final DocxBorderSide? borderTop;
  final DocxBorderSide? borderBottomSide;
  final DocxBorderSide? borderLeft;
  final DocxBorderSide? borderRight;
  final DocxBorderSide? borderBetween;
  final DocxBorder? borderBottom;
  final bool? keepNext;
  final bool? keepLines;

  // Run Properties
  final DocxFontWeight? fontWeight;
  final DocxFontStyle? fontStyle;
  final List<DocxTextDecoration> decorations;
  final DocxColor? color;
  final double? fontSize;
  final DocxFont? fonts;
  String? get fontFamily => fonts?.family;
  final DocxHighlight? highlight;
  final bool? isSuperscript;
  final bool? isSubscript;
  final bool? isAllCaps;
  final bool? isSmallCaps;
  final bool? isDoubleStrike;
  final bool? isOutline;
  final bool? isShadow;
  final bool? isEmboss;
  final bool? isImprint;
  final DocxBorderSide? textBorder; // w:bdr element - border around text
  final double?
      characterSpacing; // w:spacing w:val - character spacing in twips

  // Table Cell Properties (for Table Styles)
  final DocxVerticalAlign? verticalAlign;
  final Map<String, DocxStyle> tableConditionals;

  const DocxStyle({
    required this.id,
    this.type,
    this.basedOn,
    this.pStyleId,
    this.align,
    this.shadingFill,
    this.themeFill,
    this.themeFillTint,
    this.themeFillShade,
    this.numId,
    this.ilvl,
    this.spacingAfter,
    this.spacingBefore,
    this.lineSpacing,
    this.lineRule,
    this.indentLeft,
    this.indentRight,
    this.indentFirstLine,
    this.borderTop,
    this.borderBottomSide,
    this.borderLeft,
    this.borderRight,
    this.borderBetween,
    this.borderBottom,
    this.keepNext,
    this.keepLines,
    this.fontWeight,
    this.fontStyle,
    this.decorations = const [],
    this.color,
    this.fontSize,
    this.fonts,
    this.highlight,
    this.isSuperscript,
    this.isSubscript,
    this.isAllCaps,
    this.isSmallCaps,
    this.isDoubleStrike,
    this.isOutline,
    this.isShadow,
    this.isEmboss,
    this.isImprint,
    this.textBorder,
    this.characterSpacing,
    this.verticalAlign,
    this.tableConditionals = const {},
  });

  /// Creates an empty style with no properties set.
  factory DocxStyle.empty() => const DocxStyle(id: 'empty');

  /// Parse a style element from styles.xml.
  factory DocxStyle.fromXml(
    String id, {
    String? type,
    String? basedOn,
    XmlElement? pPr,
    XmlElement? rPr,
    XmlElement? tcPr,
    Map<String, DocxStyle>? tableConditionals,
  }) {
    final pProps = _parseParagraphProperties(pPr);
    final rProps = _parseRunProperties(rPr, tcPr);

    return DocxStyle(
      id: id,
      type: type,
      basedOn: basedOn,
      // P props
      pStyleId: pProps.pStyleId,
      align: pProps.align,
      shadingFill: pProps.shadingFill ?? rProps.shadingFill,
      themeFill: pProps.themeFill ?? rProps.themeFill,
      themeFillTint: pProps.themeFillTint ?? rProps.themeFillTint,
      themeFillShade: pProps.themeFillShade ?? rProps.themeFillShade,
      numId: pProps.numId,
      ilvl: pProps.ilvl,
      spacingAfter: pProps.spacingAfter,
      spacingBefore: pProps.spacingBefore,
      lineSpacing: pProps.lineSpacing,
      lineRule: pProps.lineRule,
      indentLeft: pProps.indentLeft,
      indentRight: pProps.indentRight,
      indentFirstLine: pProps.indentFirstLine,
      borderTop: pProps.borderTop ?? rProps.borderTop,
      borderBottomSide: pProps.borderBottomSide ?? rProps.borderBottomSide,
      borderLeft: pProps.borderLeft ?? rProps.borderLeft,
      borderRight: pProps.borderRight ?? rProps.borderRight,
      borderBetween: pProps.borderBetween,
      borderBottom: pProps.borderBottom,
      keepNext: pProps.keepNext,
      keepLines: pProps.keepLines,
      // R Props (merged)
      fontWeight: rProps.fontWeight,
      fontStyle: rProps.fontStyle,
      decorations: rProps.decorations,
      color: rProps.color,
      fontSize: rProps.fontSize,
      fonts: rProps.fonts,
      highlight: rProps.highlight,
      isSuperscript: rProps.isSuperscript,
      isSubscript: rProps.isSubscript,
      isAllCaps: rProps.isAllCaps,
      isSmallCaps: rProps.isSmallCaps,
      isDoubleStrike: rProps.isDoubleStrike,
      isOutline: rProps.isOutline,
      isShadow: rProps.isShadow,
      isEmboss: rProps.isEmboss,
      isImprint: rProps.isImprint,
      textBorder: rProps.textBorder,
      // Table Props
      verticalAlign: rProps.verticalAlign,
      tableConditionals: tableConditionals ?? const {},
    );
  }

  /// Merge this style (as base) with override properties from another style.
  DocxStyle merge(DocxStyle other) {
    return DocxStyle(
      id: other.id == 'temp' || other.id == 'empty' ? id : other.id,
      type: type,
      basedOn: basedOn,
      // P props
      align: other.align ?? align,
      shadingFill: other.shadingFill ?? shadingFill,
      themeFill: other.themeFill ?? themeFill,
      themeFillTint: other.themeFillTint ?? themeFillTint,
      themeFillShade: other.themeFillShade ?? themeFillShade,
      numId: other.numId ?? numId,
      ilvl: other.ilvl ?? ilvl,
      spacingAfter: other.spacingAfter ?? spacingAfter,
      spacingBefore: other.spacingBefore ?? spacingBefore,
      lineSpacing: other.lineSpacing ?? lineSpacing,
      lineRule: other.lineRule ?? lineRule,
      indentLeft: other.indentLeft ?? indentLeft,
      indentRight: other.indentRight ?? indentRight,
      indentFirstLine: other.indentFirstLine ?? indentFirstLine,
      borderTop: other.borderTop ?? borderTop,
      borderBottomSide: other.borderBottomSide ?? borderBottomSide,
      borderLeft: other.borderLeft ?? borderLeft,
      borderRight: other.borderRight ?? borderRight,
      borderBetween: other.borderBetween ?? borderBetween,
      borderBottom: other.borderBottom ?? borderBottom,
      keepNext: other.keepNext ?? keepNext,
      keepLines: other.keepLines ?? keepLines,
      // R props
      fontWeight: other.fontWeight ?? fontWeight,
      fontStyle: other.fontStyle ?? fontStyle,
      decorations:
          other.decorations.isNotEmpty ? other.decorations : decorations,
      color: other.color ?? color,
      fontSize: other.fontSize ?? fontSize,
      fonts: fonts?.merge(other.fonts) ?? other.fonts,
      highlight: other.highlight ?? highlight,
      isSuperscript: other.isSuperscript ?? isSuperscript,
      isSubscript: other.isSubscript ?? isSubscript,
      isAllCaps: other.isAllCaps ?? isAllCaps,
      isSmallCaps: other.isSmallCaps ?? isSmallCaps,
      isDoubleStrike: other.isDoubleStrike ?? isDoubleStrike,
      isOutline: other.isOutline ?? isOutline,
      isShadow: other.isShadow ?? isShadow,
      isEmboss: other.isEmboss ?? isEmboss,
      isImprint: other.isImprint ?? isImprint,
      textBorder: other.textBorder ?? textBorder,
      characterSpacing: other.characterSpacing ?? characterSpacing,
      verticalAlign: other.verticalAlign ?? verticalAlign,
      tableConditionals: other.tableConditionals.isNotEmpty
          ? other.tableConditionals
          : tableConditionals,
    );
  }

  // ============================================================
  // PARAGRAPH PROPERTIES PARSER
  // ============================================================

  static DocxStyle _parseParagraphProperties(XmlElement? pPr) {
    if (pPr == null) return const DocxStyle(id: 'temp');

    DocxAlign? align;
    String? shadingFill;
    String? themeFill;
    String? themeFillTint;
    String? themeFillShade;
    int? numId;
    int? ilvl;
    int? spacingAfter;
    int? spacingBefore;
    int? lineSpacing;
    String? lineRule;
    int? indentLeft;
    int? indentRight;
    int? indentFirstLine;
    DocxBorderSide? borderTop;
    DocxBorderSide? borderBottomSide;
    DocxBorderSide? borderLeft;
    DocxBorderSide? borderRight;
    DocxBorderSide? borderBetween;
    bool? keepNext;
    bool? keepLines;

    // Style ID
    String? styleId;
    final pStyle = pPr.getElement('w:pStyle');
    if (pStyle != null) {
      styleId = pStyle.getAttribute('w:val');
    }

    // Alignment
    final jcElem = pPr.getElement('w:jc');
    if (jcElem != null) {
      final val = jcElem.getAttribute('w:val');
      if (val == 'center') align = DocxAlign.center;
      if (val == 'right' || val == 'end') align = DocxAlign.right;
      if (val == 'both' || val == 'distribute') align = DocxAlign.justify;
      if (val == 'left' || val == 'start') align = DocxAlign.left;
    }

    // Spacing
    final spacingElem = pPr.getElement('w:spacing');
    if (spacingElem != null) {
      final after = spacingElem.getAttribute('w:after');
      if (after != null) spacingAfter = int.tryParse(after);

      final before = spacingElem.getAttribute('w:before');
      if (before != null) spacingBefore = int.tryParse(before);

      final line = spacingElem.getAttribute('w:line');
      if (line != null) lineSpacing = int.tryParse(line);

      final rule = spacingElem.getAttribute('w:lineRule');
      if (rule != null) lineRule = rule;
    }

    // Indentation
    final indElem = pPr.getElement('w:ind');
    if (indElem != null) {
      final left =
          indElem.getAttribute('w:left') ?? indElem.getAttribute('w:start');
      if (left != null) indentLeft = int.tryParse(left);

      final right =
          indElem.getAttribute('w:right') ?? indElem.getAttribute('w:end');
      if (right != null) indentRight = int.tryParse(right);

      final firstLine = indElem.getAttribute('w:firstLine');
      if (firstLine != null) {
        indentFirstLine = int.tryParse(firstLine);
      } else {
        final hanging = indElem.getAttribute('w:hanging');
        if (hanging != null) {
          final hVal = int.tryParse(hanging);
          if (hVal != null) indentFirstLine = -hVal;
        }
      }
    }

    // Shading
    final shdElem = pPr.getElement('w:shd');
    if (shdElem != null) {
      shadingFill = shdElem.getAttribute('w:fill');
      if (shadingFill == 'auto') shadingFill = null;

      themeFill = shdElem.getAttribute('w:themeFill');
      themeFillTint = shdElem.getAttribute('w:themeFillTint');
      themeFillShade = shdElem.getAttribute('w:themeFillShade');
    }

    // Numbering/Lists
    final numPr = pPr.getElement('w:numPr');
    if (numPr != null) {
      final numIdElem = numPr.getElement('w:numId');
      final ilvlElem = numPr.getElement('w:ilvl');

      if (numIdElem != null) {
        numId = int.tryParse(numIdElem.getAttribute('w:val') ?? '');
      }
      if (ilvlElem != null) {
        ilvl = int.tryParse(ilvlElem.getAttribute('w:val') ?? '');
      }
    }

    // Borders
    final pBdr = pPr.getElement('w:pBdr');
    if (pBdr != null) {
      borderTop = _parseBorderSide(pBdr.getElement('w:top'));
      borderBottomSide = _parseBorderSide(pBdr.getElement('w:bottom'));
      borderLeft = _parseBorderSide(pBdr.getElement('w:left'));
      borderRight = _parseBorderSide(pBdr.getElement('w:right'));
      borderBetween = _parseBorderSide(pBdr.getElement('w:between'));
    }

    // Keep-with-next / keep-lines-together: OOXML on/off elements, only
    // set here when present at all - absence means "inherit from basedOn",
    // not "explicitly off" (there's no per-style way to force it off).
    final keepNextElem = pPr.getElement('w:keepNext');
    if (keepNextElem != null) keepNext = _onOffElement(keepNextElem);
    final keepLinesElem = pPr.getElement('w:keepLines');
    if (keepLinesElem != null) keepLines = _onOffElement(keepLinesElem);

    return DocxStyle(
      id: 'temp',
      pStyleId: styleId,
      align: align,
      shadingFill: shadingFill,
      themeFill: themeFill,
      themeFillTint: themeFillTint,
      themeFillShade: themeFillShade,
      numId: numId,
      ilvl: ilvl,
      spacingAfter: spacingAfter,
      spacingBefore: spacingBefore,
      lineSpacing: lineSpacing,
      lineRule: lineRule,
      indentLeft: indentLeft,
      indentRight: indentRight,
      indentFirstLine: indentFirstLine,
      borderTop: borderTop,
      borderBottomSide: borderBottomSide,
      borderLeft: borderLeft,
      borderRight: borderRight,
      borderBetween: borderBetween,
      keepNext: keepNext,
      keepLines: keepLines,
    );
  }

  /// OOXML on/off element: present and not explicitly `w:val="0"/"false"/"off"`.
  static bool _onOffElement(XmlElement? el) {
    if (el == null) return false;
    final val = el.getAttribute('w:val');
    return val == null || !['0', 'false', 'off'].contains(val.toLowerCase());
  }

  // ============================================================
  // RUN PROPERTIES PARSER
  // ============================================================

  static DocxStyle _parseRunProperties(XmlElement? rPr, XmlElement? tcPr) {
    // if (rPr == null) return const DocxStyle(id: 'temp'); // This line was removed by the instruction.
    // The instruction implies that rPr can be null, but tcPr might be present.
    // So, we should not return early if rPr is null.

    DocxFontWeight? fontWeight;
    DocxFontStyle? fontStyle;
    List<DocxTextDecoration> decorations = [];
    DocxColor? color;
    String? shadingFill;
    double? fontSize;
    DocxFont? fonts;
    DocxHighlight? highlight;
    bool? isSuperscript;
    bool? isSubscript;
    bool? isAllCaps;
    bool? isSmallCaps;
    bool? isDoubleStrike;
    bool? isOutline;
    bool? isShadow;
    bool? isEmboss;
    bool? isImprint;
    DocxVerticalAlign? verticalAlign; // Added for tcPr parsing
    DocxBorderSide? borderTop;
    DocxBorderSide? borderBottomSide;
    DocxBorderSide? borderLeft;
    DocxBorderSide? borderRight;

    // Added shading theme props
    String? themeFill;
    String? themeFillTint;
    String? themeFillShade;
    double? characterSpacing;

    if (rPr != null) {
      if (rPr.getElement('w:b') != null) fontWeight = DocxFontWeight.bold;
      if (rPr.getElement('w:i') != null) fontStyle = DocxFontStyle.italic;
      if (rPr.getElement('w:u') != null) {
        decorations.add(DocxTextDecoration.underline);
      }
      if (rPr.getElement('w:strike') != null) {
        decorations.add(DocxTextDecoration.strikethrough);
      }

      final colorElem = rPr.getElement('w:color');
      if (colorElem != null) {
        final val = colorElem.getAttribute('w:val');
        if (val != null) {
          color = DocxColor(
            val,
            themeColor: colorElem.getAttribute('w:themeColor'),
            themeTint: colorElem.getAttribute('w:themeTint'),
            themeShade: colorElem.getAttribute('w:themeShade'),
          );
        }
      }

      final shdElem = rPr.getElement('w:shd');
      if (shdElem != null) {
        shadingFill = shdElem.getAttribute('w:fill');
        if (shadingFill == 'auto') shadingFill = null;
        themeFill = shdElem.getAttribute('w:themeFill');
        themeFillTint = shdElem.getAttribute('w:themeFillTint');
        themeFillShade = shdElem.getAttribute('w:themeFillShade');
      }

      final spacingElem = rPr.getElement('w:spacing');
      if (spacingElem != null) {
        final val = spacingElem.getAttribute('w:val');
        if (val != null) {
          characterSpacing = int.tryParse(val)?.toDouble();
        }
      }

      final szElem = rPr.getElement('w:sz');
      if (szElem != null) {
        final val = szElem.getAttribute('w:val');
        if (val != null) {
          final halfPoints = int.tryParse(val);
          if (halfPoints != null) fontSize = halfPoints / 2.0;
        }
      }

      final rFonts = rPr.getElement('w:rFonts');
      if (rFonts != null) {
        fonts = DocxFont(
          ascii: rFonts.getAttribute('w:ascii'),
          hAnsi: rFonts.getAttribute('w:hAnsi'),
          cs: rFonts.getAttribute('w:cs'),
          eastAsia: rFonts.getAttribute('w:eastAsia'),
          hint: rFonts.getAttribute('w:hint'),
          asciiTheme: rFonts.getAttribute('w:asciiTheme'),
          hAnsiTheme: rFonts.getAttribute('w:hAnsiTheme'),
          csTheme: rFonts.getAttribute('w:csTheme'),
          eastAsiaTheme: rFonts.getAttribute('w:eastAsiaTheme'),
        );
      }

      final highlightElem = rPr.getElement('w:highlight');
      if (highlightElem != null) {
        final val = highlightElem.getAttribute('w:val');
        if (val != null) {
          for (var h in DocxHighlight.values) {
            if (h.name == val) {
              highlight = h;
              break;
            }
          }
        }
      }

      if (rPr.getElement('w:caps') != null) isAllCaps = true;
      if (rPr.getElement('w:smallCaps') != null) isSmallCaps = true;
      if (rPr.getElement('w:dstrike') != null) isDoubleStrike = true;
      if (rPr.getElement('w:outline') != null) isOutline = true;
      if (rPr.getElement('w:shadow') != null) isShadow = true;
      if (rPr.getElement('w:emboss') != null) isEmboss = true;
      if (rPr.getElement('w:imprint') != null) isImprint = true;

      final vertAlignElem = rPr.getElement('w:vertAlign');
      if (vertAlignElem != null) {
        final val = vertAlignElem.getAttribute('w:val');
        if (val == 'superscript') isSuperscript = true;
        if (val == 'subscript') isSubscript = true;
      }
    }

    // Parse text border (w:bdr)
    DocxBorderSide? textBorder;
    final bdr = rPr?.getElement('w:bdr');
    if (bdr != null) {
      textBorder = _parseBorderSide(bdr);
    }

    // Parse Cell Properties
    if (tcPr != null) {
      // Shading (Cell shading overrides paragraph shading if present)
      final tcShd = tcPr.getElement('w:shd');
      if (tcShd != null) {
        final fill = tcShd.getAttribute('w:fill');
        if (fill != null && fill != 'auto') {
          // Normalize hex
          if (fill.length == 6 && RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(fill)) {
            shadingFill = '#$fill';
          } else {
            shadingFill = fill;
          }
        }
      }

      final vAlignElem = tcPr.getElement('w:vAlign');
      if (vAlignElem != null) {
        final val = vAlignElem.getAttribute('w:val');
        if (val == 'top') verticalAlign = DocxVerticalAlign.top;
        if (val == 'center') verticalAlign = DocxVerticalAlign.center;
        if (val == 'bottom') verticalAlign = DocxVerticalAlign.bottom;
      }

      final tcBorders = tcPr.getElement('w:tcBorders');
      if (tcBorders != null) {
        borderTop = _parseBorderSide(tcBorders.getElement('w:top'));
        borderBottomSide = _parseBorderSide(tcBorders.getElement('w:bottom'));
        borderLeft = _parseBorderSide(tcBorders.getElement('w:left'));
        borderRight = _parseBorderSide(tcBorders.getElement('w:right'));
      }
    }

    return DocxStyle(
      id: 'temp',
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      decorations: decorations,
      color: color,
      shadingFill: shadingFill,
      themeFill: themeFill,
      themeFillTint: themeFillTint,
      themeFillShade: themeFillShade,
      fontSize: fontSize,
      fonts: fonts,
      highlight: highlight,
      characterSpacing: characterSpacing,
      isSuperscript: isSuperscript,
      isSubscript: isSubscript,
      isAllCaps: isAllCaps,
      isSmallCaps: isSmallCaps,
      isDoubleStrike: isDoubleStrike,
      isOutline: isOutline,
      isShadow: isShadow,
      isEmboss: isEmboss,
      isImprint: isImprint,
      textBorder: textBorder,
      verticalAlign: verticalAlign,
      borderTop: borderTop,
      borderBottomSide: borderBottomSide,
      borderLeft: borderLeft,
      borderRight: borderRight,
    );
  }

  // ============================================================
  // BORDER PARSER HELPER
  // ============================================================

  static DocxBorderSide? _parseBorderSide(XmlElement? el) {
    if (el == null) return null;
    final val = el.getAttribute('w:val');
    if (val == null || val == 'none' || val == 'nil') return null;

    int size = 4;
    final szAttr = el.getAttribute('w:sz');
    if (szAttr != null) {
      final s = int.tryParse(szAttr);
      if (s != null) size = s;
    }

    var color = DocxColor.black;
    final colorAttr = el.getAttribute('w:color');
    if (colorAttr != null && colorAttr != 'auto') {
      color = DocxColor(colorAttr);
    }

    var style = DocxBorder.single;
    for (var b in DocxBorder.values) {
      if (b.xmlValue == val) {
        style = b;
        break;
      }
    }

    return DocxBorderSide(style: style, size: size, color: color);
  }
}
