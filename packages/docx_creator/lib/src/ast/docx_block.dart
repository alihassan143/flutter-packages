import 'package:xml/xml.dart';

import '../core/defaults.dart';
import '../core/enums.dart';
import '../core/xml_extension.dart';
import 'docx_inline.dart';
import 'docx_node.dart';

/// A paragraph containing styled text and inline elements.
///
/// [DocxParagraph] is the primary block-level element for text content.
/// It can contain multiple [DocxText] runs with different formatting.
///
/// ## Basic Usage
/// ```dart
/// DocxParagraph(children: [
///   DocxText('Hello, '),
///   DocxText.bold('World'),
///   DocxText('!'),
/// ])
/// ```
///
/// ## Heading Shortcut
/// ```dart
/// DocxParagraph.heading1('Chapter 1: Introduction')
/// DocxParagraph.heading2('Section 1.1')
/// ```
///
/// ## Simple Text Shortcut
/// ```dart
/// DocxParagraph.text('A simple paragraph with just text.')
/// ```
///
/// ## Fluent API
/// ```dart
/// DocxParagraph()
///   .add(DocxText('Hello'))
///   .add(DocxText.bold(' World'))
///   .align(DocxAlign.center)
/// ```
class DocxParagraph extends DocxBlock {
  /// Child elements (typically [DocxText] runs).
  final List<DocxInline> children;

  /// Alignment for the paragraph (left, center, right, justify)
  final DocxAlign align;

  /// Vertical text alignment within the paragraph line (e.g. relative to an inline image).
  final DocxTextAlignment? textAlignment;

  /// Style ID (e.g., 'Normal', 'Heading1').
  final String? styleId;

  /// Spacing after paragraph in twips.
  final int? spacingAfter;

  /// Spacing before paragraph in twips.
  final int? spacingBefore;

  /// Line spacing in twips (240 = single, 360 = 1.5, 480 = double).
  final int? lineSpacing;

  /// Line spacing rule ('auto', 'exact', 'atLeast').
  final String? lineRule;

  /// Left indentation in twips.
  final int? indentLeft;

  /// Right indentation in twips.
  final int? indentRight;

  /// First line indentation in twips (can be negative for hanging indent).
  final int? indentFirstLine;

  /// Detailed border overrides.
  final DocxBorderSide? borderTop;
  final DocxBorderSide? borderBottomSide;
  final DocxBorderSide? borderLeft;
  final DocxBorderSide? borderRight;
  final DocxBorderSide? borderBetween;

  /// Padding in twips (1/20th of a point).
  final int? paddingTop;
  final int? paddingBottom;
  final int? paddingLeft;
  final int? paddingRight;

  /// Border radius (Note: Not natively supported by standard Word paragraphs).
  final int? borderRadius;

  /// Background shading color hex.
  final String? shadingFill;

  /// Theme fill color reference.
  final String? themeFill;

  /// Theme fill tint.
  final String? themeFillTint;

  /// Theme fill shade.
  final String? themeFillShade;

  /// Outline level for TOC (0-8, null for body text).
  final int? outlineLevel;

  /// Whether to insert a page break before this paragraph.
  final bool pageBreakBefore;

  /// Whether this paragraph must stay on the same page as the next one
  /// (Word's `w:keepNext` — e.g. a heading glued to its first body line).
  final bool keepNext;

  /// Whether every line of this paragraph must stay on the same page
  /// (Word's `w:keepLines`).
  final bool keepLines;

  /// Numbering ID for list items.
  final int? numId;

  /// Indentation level for list items (0-based).
  final int? ilvl;

  /// Conditional formatting style flags for table paragraphs.
  final String? cnfStyle;

  /// Creates a paragraph with specified children and formatting.
  const DocxParagraph({
    this.children = const [],
    this.align = DocxAlign.left,
    this.textAlignment,
    this.styleId,
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
    this.paddingTop,
    this.paddingBottom,
    this.paddingLeft,
    this.paddingRight,
    this.borderRadius,
    this.shadingFill,
    this.themeFill,
    this.themeFillTint,
    this.themeFillShade,
    this.outlineLevel,
    this.pageBreakBefore = false,
    this.keepNext = false,
    this.keepLines = false,
    this.numId,
    this.ilvl,
    this.cnfStyle,
    super.id,
  });

  // ============================================================
  // CONVENIENCE CONSTRUCTORS
  // ============================================================

  /// Creates a simple paragraph with plain text.
  ///
  /// ```dart
  /// DocxParagraph.text('This is a simple paragraph.')
  /// ```
  factory DocxParagraph.text(
    String text, {
    DocxAlign align = DocxAlign.left,
    DocxTextAlignment? textAlignment,
    double? fontSize,
    String? fontFamily,
    DocxBorderSide? borderBottom,
  }) {
    return DocxParagraph(
      align: align,
      textAlignment: textAlignment,
      children: [DocxText(text, fontSize: fontSize, fontFamily: fontFamily)],
      borderBottomSide: borderBottom,
    );
  }

  /// Creates a heading paragraph.
  ///
  /// ```dart
  /// DocxParagraph.heading(DocxHeadingLevel.h1, 'Main Title')
  /// ```
  factory DocxParagraph.heading(
    DocxHeadingLevel level,
    String text, {
    DocxAlign align = DocxAlign.left,
    DocxTextAlignment? textAlignment,
  }) {
    return DocxParagraph(
      styleId: level.styleId,
      align: align,
      textAlignment: textAlignment,
      children: [
        DocxText(text),
      ],
    );
  }

  /// Creates an H1 heading.
  factory DocxParagraph.heading1(
    String text, {
    DocxAlign align = DocxAlign.left,
    DocxTextAlignment? textAlignment,
  }) =>
      DocxParagraph.heading(DocxHeadingLevel.h1, text,
          align: align, textAlignment: textAlignment);

  /// Creates an H2 heading.
  factory DocxParagraph.heading2(
    String text, {
    DocxAlign align = DocxAlign.left,
    DocxTextAlignment? textAlignment,
  }) =>
      DocxParagraph.heading(DocxHeadingLevel.h2, text,
          align: align, textAlignment: textAlignment);

  /// Creates an H3 heading.
  factory DocxParagraph.heading3(
    String text, {
    DocxAlign align = DocxAlign.left,
    DocxTextAlignment? textAlignment,
  }) =>
      DocxParagraph.heading(DocxHeadingLevel.h3, text,
          align: align, textAlignment: textAlignment);

  /// Creates an H4 heading.
  factory DocxParagraph.heading4(
    String text, {
    DocxAlign align = DocxAlign.left,
    DocxTextAlignment? textAlignment,
  }) =>
      DocxParagraph.heading(DocxHeadingLevel.h4, text,
          align: align, textAlignment: textAlignment);

  /// Creates an H5 heading.
  factory DocxParagraph.heading5(
    String text, {
    DocxAlign align = DocxAlign.left,
    DocxTextAlignment? textAlignment,
  }) =>
      DocxParagraph.heading(DocxHeadingLevel.h5, text,
          align: align, textAlignment: textAlignment);

  /// Creates an H6 heading.
  factory DocxParagraph.heading6(
    String text, {
    DocxAlign align = DocxAlign.left,
    DocxTextAlignment? textAlignment,
  }) =>
      DocxParagraph.heading(DocxHeadingLevel.h6, text,
          align: align, textAlignment: textAlignment);

  /// Creates a blockquote paragraph.
  factory DocxParagraph.quote(String text, {DocxTextAlignment? textAlignment}) {
    return DocxParagraph(
      indentLeft: 720, // 0.5 inch
      styleId: DocxStyleIds.quote,
      textAlignment: textAlignment,
      children: [DocxText.italic(text)],
    );
  }

  /// Creates a code block paragraph.
  factory DocxParagraph.code(String code, {DocxTextAlignment? textAlignment}) {
    return DocxParagraph(
      shadingFill: 'F5F5F5',
      textAlignment: textAlignment,
      children: [DocxText.code(code)],
    );
  }

  // ============================================================
  // FLUENT API
  // ============================================================

  /// Returns a copy with the specified child added.
  DocxParagraph add(DocxInline child) {
    return copyWith(children: [...children, child]);
  }

  /// Returns a copy with the specified alignment.
  DocxParagraph aligned(DocxAlign newAlign) {
    return copyWith(align: newAlign);
  }

  /// Returns a copy with the specified style.
  DocxParagraph styled(String newStyleId) {
    return copyWith(styleId: newStyleId);
  }

  /// Returns a copy with specified modifications.
  DocxParagraph copyWith({
    List<DocxInline>? children,
    DocxAlign? align,
    DocxTextAlignment? textAlignment,
    String? styleId,
    int? spacingAfter,
    int? spacingBefore,
    int? lineSpacing,
    String? lineRule,
    int? indentLeft,
    int? indentRight,
    int? indentFirstLine,
    DocxBorder? borderBottom,
    DocxBorderSide? borderTop,
    DocxBorderSide? borderBottomSide,
    DocxBorderSide? borderLeft,
    DocxBorderSide? borderRight,
    DocxBorderSide? borderBetween,
    int? paddingTop,
    int? paddingBottom,
    int? paddingLeft,
    int? paddingRight,
    String? shadingFill,
    String? themeFill,
    String? themeFillTint,
    String? themeFillShade,
    int? outlineLevel,
    bool? pageBreakBefore,
    bool? keepNext,
    bool? keepLines,
    int? numId,
    int? ilvl,
    String? cnfStyle,
  }) {
    return DocxParagraph(
      children: children ?? this.children,
      align: align ?? this.align,
      textAlignment: textAlignment ?? this.textAlignment,
      styleId: styleId ?? this.styleId,
      spacingAfter: spacingAfter ?? this.spacingAfter,
      spacingBefore: spacingBefore ?? this.spacingBefore,
      lineSpacing: lineSpacing ?? this.lineSpacing,
      lineRule: lineRule ?? this.lineRule,
      indentLeft: indentLeft ?? this.indentLeft,
      indentRight: indentRight ?? this.indentRight,
      indentFirstLine: indentFirstLine ?? this.indentFirstLine,
      borderTop: borderTop ?? this.borderTop,
      borderBottomSide: borderBottomSide ?? this.borderBottomSide,
      borderLeft: borderLeft ?? this.borderLeft,
      borderRight: borderRight ?? this.borderRight,
      borderBetween: borderBetween ?? this.borderBetween,
      paddingTop: paddingTop ?? this.paddingTop,
      paddingBottom: paddingBottom ?? this.paddingBottom,
      paddingLeft: paddingLeft ?? this.paddingLeft,
      paddingRight: paddingRight ?? this.paddingRight,
      shadingFill: shadingFill ?? this.shadingFill,
      themeFill: themeFill ?? this.themeFill,
      themeFillTint: themeFillTint ?? this.themeFillTint,
      themeFillShade: themeFillShade ?? this.themeFillShade,
      outlineLevel: outlineLevel ?? this.outlineLevel,
      pageBreakBefore: pageBreakBefore ?? this.pageBreakBefore,
      keepNext: keepNext ?? this.keepNext,
      keepLines: keepLines ?? this.keepLines,
      numId: numId ?? this.numId,
      ilvl: ilvl ?? this.ilvl,
      cnfStyle: cnfStyle ?? this.cnfStyle,
      id: id,
    );
  }

  // ============================================================
  // AST VISITOR
  // ============================================================

  @override
  void accept(DocxVisitor visitor) {
    visitor.visitParagraph(this);
  }

  // ============================================================
  // XML GENERATION
  // ============================================================

  @override
  void buildXml(XmlBuilder builder) {
    builder.element(
      'w:p',
      nest: () {
        // Paragraph properties
        if (_hasProperties) {
          builder.element(
            'w:pPr',
            nest: () {
              // 1. pStyle
              if (styleId != null) {
                builder.element('w:pStyle', nest: () {
                  builder.attribute('w:val', styleId!);
                });
              }

              // 2. pageBreakBefore
              if (pageBreakBefore) {
                builder.element('w:pageBreakBefore');
              }

              // 2b. keepNext / keepLines
              if (keepNext) {
                builder.element('w:keepNext');
              }
              if (keepLines) {
                builder.element('w:keepLines');
              }

              // 3. numPr
              if (numId != null) {
                builder.element('w:numPr', nest: () {
                  builder.element('w:ilvl', nest: () {
                    builder.attribute('w:val', (ilvl ?? 0).toString());
                  });
                  builder.element('w:numId', nest: () {
                    builder.attribute('w:val', numId.toString());
                  });
                });
              }

              // 4. pBdr (Borders & Padding)
              if (borderTop != null ||
                  borderBottomSide != null ||
                  borderLeft != null ||
                  borderRight != null ||
                  borderBetween != null ||
                  paddingTop != null ||
                  paddingBottom != null ||
                  paddingLeft != null ||
                  paddingRight != null) {
                builder.element(
                  'w:pBdr',
                  nest: () {
                    void buildSide(
                        String tag, DocxBorderSide? side, int? padding) {
                      if (side != null) {
                        // Override space if padding is present (convert twips to points)
                        final space =
                            padding != null ? (padding / 20).round() : null;
                        _buildBorder(builder, tag, side, spaceOverride: space);
                      } else if (padding != null) {
                        // Create visible border to force padding spacing
                        final space = (padding / 20).round();
                        final color = shadingFill ?? 'auto';
                        builder.element(tag, nest: () {
                          builder.attribute('w:val', 'nil');
                          builder.attribute('w:sz', '0');
                          builder.attribute('w:space', space.toString());
                          builder.attribute('w:color', color);
                        });
                      }
                    }

                    buildSide('w:top', borderTop, paddingTop);
                    buildSide('w:left', borderLeft, paddingLeft);
                    buildSide('w:bottom', borderBottomSide, paddingBottom);
                    buildSide('w:right', borderRight, paddingRight);

                    if (borderBetween != null) {
                      _buildBorder(builder, 'w:between', borderBetween!);
                    }
                  },
                );
              }

              // 5. shd (Shading)
              writeShading(
                builder,
                fill: shadingFill,
                themeFill: themeFill,
                themeFillTint: themeFillTint,
                themeFillShade: themeFillShade,
              );

              // 6. spacing
              if (spacingAfter != null ||
                  spacingBefore != null ||
                  lineSpacing != null ||
                  lineRule != null) {
                builder.element('w:spacing', nest: () {
                  if (spacingAfter != null) {
                    builder.attribute('w:after', spacingAfter.toString());
                  }
                  if (spacingBefore != null) {
                    builder.attribute('w:before', spacingBefore.toString());
                  }
                  if (lineSpacing != null) {
                    builder.attribute('w:line', lineSpacing.toString());
                  }
                  if (lineRule != null) {
                    builder.attribute('w:lineRule', lineRule!);
                  }
                });
              }

              // 7. ind (Indentation)
              if (indentLeft != null ||
                  indentRight != null ||
                  indentFirstLine != null) {
                builder.element('w:ind', nest: () {
                  if (indentLeft != null) {
                    builder.attribute('w:left', indentLeft.toString());
                  }
                  if (indentRight != null) {
                    builder.attribute('w:right', indentRight.toString());
                  }
                  if (indentFirstLine != null) {
                    builder.attribute(
                        'w:firstLine', indentFirstLine.toString());
                  }
                });
              }

              // 8. jc (Alignment)
              builder.element('w:jc', nest: () {
                builder.attribute('w:val', align.xmlValue);
              });

              // 8.5 textAlignment
              if (textAlignment != null) {
                builder.element('w:textAlignment', nest: () {
                  builder.attribute('w:val', textAlignment!.xmlValue);
                });
              }

              // 9. outlineLvl
              if (outlineLevel != null) {
                builder.element('w:outlineLvl', nest: () {
                  builder.attribute('w:val', outlineLevel.toString());
                });
              }

              // 10. cnfStyle
              if (cnfStyle != null) {
                builder.element('w:cnfStyle', nest: () {
                  builder.attribute('w:val', cnfStyle!);
                });
              }
            },
          );
        }

        // Child runs
        for (var child in children) {
          child.buildXml(builder);
        }
      },
    );
  }

  bool get _hasProperties => true;

  void _buildBorder(XmlBuilder builder, String tag, DocxBorderSide side,
      {int? spaceOverride}) {
    builder.element(tag, nest: () {
      builder.attribute('w:val', side.xmlStyle);
      builder.attribute('w:sz', side.size.toString());
      builder.attribute('w:space', (spaceOverride ?? side.space).toString());
      if (side.color != DocxColor.auto) {
        builder.attribute('w:color', side.color.hex);
      } else {
        builder.attribute('w:color', 'auto');
      }
      if (side.themeColor != null) {
        builder.attribute('w:themeColor', side.themeColor!);
      }
      if (side.themeTint != null) {
        builder.attribute('w:themeTint', side.themeTint!);
      }
      if (side.themeShade != null) {
        builder.attribute('w:themeShade', side.themeShade!);
      }
    });
  }
}
