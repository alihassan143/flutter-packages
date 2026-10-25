import 'package:docx_creator/docx_creator.dart';
import 'package:docx_file_viewer/src/search/docx_search_controller.dart';
import 'package:docx_file_viewer/src/utils/block_index_counter.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../docx_view_config.dart';
import '../theme/docx_view_theme.dart';

import '../rendering/docx_paragraph_render_widget.dart';
import '../utils/docx_units.dart';
import '../widgets/drop_cap_text.dart';

/// Builds Flutter widgets from [DocxParagraph] elements.
class ParagraphBuilder {
  final DocxViewTheme theme;
  final DocxViewConfig config;
  final DocxTheme? docxTheme;
  final DocxSearchController? searchController;
  final void Function(int id)? onFootnoteTap;
  final void Function(int id)? onEndnoteTap;

  // Used for search highlighting

  ParagraphBuilder({
    required this.theme,
    required this.config,
    this.searchController,
    this.onFootnoteTap,
    this.onEndnoteTap,
    this.docxTheme,
  });

  /// Build a widget from a [DocxParagraph].
  Widget build(DocxParagraph paragraph, {BlockIndexCounter? counter}) {
    List<SearchMatch>? matches;
    Key? key;

    if (counter != null && searchController != null) {
      final blockIndex = counter.value;
      matches = searchController!.matches
          .where((m) => m.blockIndex == blockIndex)
          .toList();

      if (matches.isNotEmpty) {
        key = counter.registerKey(blockIndex);
      }

      counter.increment();
    }

    return _buildNativeParagraph(paragraph, matches: matches, key: key);
  }

  /// Build a paragraph widget, excluding specific floating images.
  /// Used when specific floats are being handled separately at the block level.
  Widget buildExcludingFloats(
      DocxParagraph paragraph, Set<DocxInline> excludedFloats,
      {BlockIndexCounter? counter}) {
    List<SearchMatch>? matches;
    Key? key;

    if (counter != null && searchController != null) {
      final blockIndex = counter.value;
      matches = searchController!.matches
          .where((m) => m.blockIndex == blockIndex)
          .toList();

      if (matches.isNotEmpty) {
        key = counter.registerKey(blockIndex);
      }

      counter.increment();
    }

    return _buildNativeParagraph(paragraph,
        excludedFloats: excludedFloats, matches: matches, key: key);
  }

  /// Native Flutter builder for standard paragraphs.
  Widget _buildNativeParagraph(DocxParagraph paragraph,
      {Set<DocxInline>? excludedFloats, List<SearchMatch>? matches, Key? key}) {
    List<(DocxInline, DocxAlign?)> textChildren = [];

    // Separate content
    for (var child in paragraph.children) {
      bool isFloating = false;
      DocxAlign align = DocxAlign.left; // Default logic

      if (child is DocxInlineImage &&
          child.positionMode == DocxDrawingPosition.floating) {
        if (excludedFloats?.contains(child) ?? false) {
          continue; // Skip specific excluded float
        }
        isFloating = true;
        if (child.hAlign == DrawingHAlign.center) {
          align = DocxAlign.center;
        } else {
          align = child.hAlign == DrawingHAlign.right
              ? DocxAlign.right
              : DocxAlign.left;
        }
      } else if (child is DocxShape &&
          child.position == DocxDrawingPosition.floating) {
        if (excludedFloats?.contains(child) ?? false) {
          continue; // Skip specific excluded float
        }
        isFloating = true;
        if (child.horizontalAlign == DrawingHAlign.center) {
          align = DocxAlign.center;
        } else {
          align = child.horizontalAlign == DrawingHAlign.right
              ? DocxAlign.right
              : DocxAlign.left;
        }
      }

      textChildren.add((child, isFloating ? align : null));
    }

    // List of block-level widgets (rows or center blocks)
    final List<Widget> columnChildren = [];

    // Buffers for the current "Row" context
    List<DocxInline> currentLeftFloats = [];
    List<DocxInline> currentRightFloats = [];
    List<DocxInline> currentInlines = [];

    final lineHeightScale = resolveLineHeightScale(paragraph);
    final textAlign = _convertAlign(paragraph.align);

    // Track current text offset for highlighting
    int currentTextOffset = 0;

    // First-line indent (w:firstLine > 0).
    // Hanging indent (w:hanging) = negative indentFirstLine: the container is
    // already shifted left by _wrapWithParagraphStyle; body lines (non-first)
    // need a positive spacer of the same magnitude to align them at indentLeft.
    final int rawFirstLine = paragraph.indentFirstLine ?? 0;
    final double firstLineIndentPx =
        rawFirstLine > 0 ? (rawFirstLine / 15.0).clamp(0.0, 300.0) : 0.0;
    final double bodyLineIndentPx =
        rawFirstLine < 0 ? ((-rawFirstLine) / 15.0).clamp(0.0, 300.0) : 0.0;
    bool isFirstFlush = true;

    // Helper to flush current buffers into a single layout row
    void flushBuffer() {
      if (currentInlines.isEmpty &&
          currentLeftFloats.isEmpty &&
          currentRightFloats.isEmpty) {
        return;
      }

      final spans = buildInlineSpans(
        currentInlines,
        lineHeight: lineHeightScale,
        matches: matches,
        startOffset: currentTextOffset,
        firstLineIndentPx: isFirstFlush ? firstLineIndentPx : bodyLineIndentPx,
      );
      isFirstFlush = false;

      // Update offset
      for (final inline in currentInlines) {
        if (inline is DocxText) {
          currentTextOffset += inline.content.length;
        } else if (inline is DocxTab) {
          currentTextOffset += 4; // '    '.length
        } else if (inline is DocxLineBreak) {
          currentTextOffset += 1;
        } else if (inline is DocxCheckbox) {
          currentTextOffset += 2; // '☒ '
        }
      }

      final fullTextSpan =
          TextSpan(style: theme.defaultTextStyle, children: spans);

      Widget rowWidget;

      // If we have any floating elements, we MUST use the floating layout (Row)
      // to ensure they sit side-by-side with text.
      if (currentLeftFloats.isNotEmpty || currentRightFloats.isNotEmpty) {
        // Create copies to separate from buffer
        final lefts = List<DocxInline>.from(currentLeftFloats);
        final rights = List<DocxInline>.from(currentRightFloats);

        rowWidget = _buildFloatingLayout(
          textSpan: fullTextSpan,
          leftElements: lefts,
          rightElements: rights,
          textAlign: textAlign,
          lineHeightScale: lineHeightScale,
        );
      } else {
        // Standard text layout for efficiency if no floats
        if (config.enableSelection) {
          // OS-level text selection stays on SelectableText.rich for now -
          // the custom render object below doesn't do its own selection UI
          // yet (an editor built on it will manage selection itself rather
          // than wanting the OS's), so migrating this path is future work.
          rowWidget = SelectableText.rich(
            fullTextSpan,
            textAlign: textAlign,
          );
        } else if (!_containsWidgetSpan(fullTextSpan)) {
          // The custom RenderDocxParagraph core (see lib/src/rendering/):
          // one render object, one hit-testing API, under our control -
          // instead of RichText/RenderParagraph here. Only safe for spans
          // with no WidgetSpan child (inline image/shape/math, or the
          // first-line-indent spacer) - RenderDocxParagraph is a true leaf
          // with no child render objects; a row containing one of those
          // still falls back to RichText just below.
          rowWidget = DocxParagraphRenderWidget(
            text: fullTextSpan,
            textAlign: textAlign,
          );
        } else {
          rowWidget = RichText(
            text: fullTextSpan,
            textAlign: textAlign,
          );
        }
        // Ensure it takes width to respect alignment
        rowWidget = SizedBox(width: double.infinity, child: rowWidget);
      }

      columnChildren.add(rowWidget);

      currentLeftFloats.clear();
      currentRightFloats.clear();
      currentInlines.clear();
    }

    // Iterate through children and bucket them into Rows
    for (var child in paragraph.children) {
      if (excludedFloats?.contains(child) ?? false) {
        continue; // Skip specific excluded float
      }
      DocxAlign? align;
      if (child is DocxInlineImage) {
        if (child.positionMode == DocxDrawingPosition.floating) {
          align = child.hAlign == DrawingHAlign.left
              ? DocxAlign.left
              : (child.hAlign == DrawingHAlign.right
                  ? DocxAlign.right
                  : DocxAlign.center);
        }
      } else if (child is DocxShape) {
        if (child.position == DocxDrawingPosition.floating) {
          align = child.horizontalAlign == DrawingHAlign.left
              ? DocxAlign.left
              : (child.horizontalAlign == DrawingHAlign.right
                  ? DocxAlign.right
                  : DocxAlign.center);
        }
      }

      if (align == DocxAlign.center) {
        // A Center float breaks the current Row.
        flushBuffer();

        Widget centerWidget;
        if (child is DocxInlineImage) {
          centerWidget = Image.memory(
            child.bytes,
            width: DocxUnits.pointsToPixels(child.width),
            height: DocxUnits.pointsToPixels(child.height),
            fit: BoxFit.contain,
          );
        } else if (child is DocxShape) {
          centerWidget = _buildInlineShape(child);
        } else {
          centerWidget = const SizedBox.shrink();
        }
        columnChildren.add(Center(child: centerWidget));
      } else if (align == DocxAlign.left) {
        currentLeftFloats.add(child);
      } else if (align == DocxAlign.right) {
        currentRightFloats.add(child);
      } else {
        currentInlines.add(child);
      }
    }

    // Flush any remaining content
    flushBuffer();

    // Final Assembly
    Widget finalContent;
    if (columnChildren.isEmpty) {
      finalContent = const SizedBox();
    } else if (columnChildren.length == 1) {
      finalContent = columnChildren.first;
    } else {
      finalContent = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: columnChildren
            .map((w) => Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: w,
                ))
            .toList(),
      );
    }

    return _wrapWithParagraphStyle(paragraph, finalContent, key: key);
  }

  /// Builds a layout that wraps text around left and/or right floating elements.
  ///
  /// Uses IntrinsicHeight with Row for proper alignment of floating images and text.
  Widget _buildFloatingLayout({
    required TextSpan textSpan,
    List<DocxInline> leftElements = const [],
    List<DocxInline> rightElements = const [],
    required TextAlign textAlign,
    double? lineHeightScale,
  }) {
    const double floatSpacing = 12.0;

    // Helper to build the widget for a floating element
    Widget? buildFloatWidget(DocxInline? element) {
      if (element == null) return null;
      if (element is DocxInlineImage) {
        return Image.memory(
          element.bytes,
          width: DocxUnits.pointsToPixels(element.width),
          height: DocxUnits.pointsToPixels(element.height),
          fit: BoxFit.contain,
        );
      } else if (element is DocxShape) {
        return _buildInlineShape(element);
      }
      return null;
    }

    // Build a column of floating elements
    Widget buildFloatColumn(List<DocxInline> elements) {
      if (elements.isEmpty) return const SizedBox.shrink();
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: elements.map((e) {
          final widget = buildFloatWidget(e) ?? const SizedBox.shrink();
          final index = elements.indexOf(e);
          if (index < elements.length - 1) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: widget,
            );
          }
          return widget;
        }).toList(),
      );
    }

    // Build the text widget
    Widget textWidget = config.enableSelection
        ? SelectableText.rich(textSpan, textAlign: textAlign)
        : RichText(text: textSpan, textAlign: textAlign);

    // Use IntrinsicHeight to allow text to wrap naturally beside floats
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (leftElements.isNotEmpty) ...[
            buildFloatColumn(leftElements),
            const SizedBox(width: floatSpacing),
          ],
          Expanded(child: textWidget),
          if (rightElements.isNotEmpty) ...[
            const SizedBox(width: floatSpacing),
            buildFloatColumn(rightElements),
          ],
        ],
      ),
    );
  }

  /// Helper to apply paragraph decorations (indent, padding, shading, borders)
  Widget _wrapWithParagraphStyle(DocxParagraph paragraph, Widget content,
      {Key? key}) {
    // Apply paragraph styling from DocxParagraph properties
    const double twipsToPixels = 1 / 15.0;

    // Clamp all padding values to non-negative to prevent assertion errors
    double leftPadding =
        ((paragraph.indentLeft ?? 0) * twipsToPixels).clamp(0, double.infinity);
    // Hanging indent (w:hanging): negative indentFirstLine pulls the first line
    // to the left of the body text. Approximate by reducing the container's left
    // edge to the hanging position; all lines sit at the same widget position.
    if ((paragraph.indentFirstLine ?? 0) < 0) {
      final hangingPx = ((-paragraph.indentFirstLine!) * twipsToPixels)
          .clamp(0.0, leftPadding);
      leftPadding = (leftPadding - hangingPx).clamp(0.0, double.infinity);
    }
    double rightPadding = ((paragraph.indentRight ?? 0) * twipsToPixels)
        .clamp(0, double.infinity);
    double topPadding = ((paragraph.spacingBefore ?? 80) * twipsToPixels)
        .clamp(0, double.infinity);
    double bottomPadding = ((paragraph.spacingAfter ?? 80) * twipsToPixels)
        .clamp(0, double.infinity);

    // Heading detection
    if (paragraph.children.isNotEmpty) {
      final first = paragraph.children.first;
      if (first is DocxText &&
          first.fontSize != null &&
          first.fontSize! >= 20) {
        topPadding = topPadding.clamp(16, double.infinity);
        bottomPadding = bottomPadding.clamp(8, double.infinity);
      }
    }

    BoxDecoration? decoration = _buildParagraphDecoration(paragraph);

    // Page break
    if (paragraph.pageBreakBefore) {
      return Column(
        key: key,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 32, thickness: 2),
          Container(
            padding: EdgeInsets.only(
              left: leftPadding,
              right: rightPadding,
              top: topPadding,
              bottom: bottomPadding,
            ),
            decoration: decoration,
            child: content,
          ),
        ],
      );
    }

    return Container(
      key: key,
      padding: EdgeInsets.only(
        left: leftPadding,
        right: rightPadding,
        top: topPadding,
        bottom: bottomPadding,
      ),
      decoration: decoration,
      child: content,
    );
  }

  /// Build box decoration for paragraph with shading and borders.
  BoxDecoration? _buildParagraphDecoration(DocxParagraph paragraph) {
    Color? backgroundColor;
    if (paragraph.shadingFill != null) {
      backgroundColor = _parseHexColor(paragraph.shadingFill!);
    }

    // Build borders from DocxBorderSide properties
    BorderSide? topBorder;
    BorderSide? bottomBorder;
    BorderSide? leftBorder;
    BorderSide? rightBorder;

    if (paragraph.borderTop != null) {
      topBorder = _buildBorderSide(paragraph.borderTop!);
    }

    // Choose the most specific bottom border available
    // Prioritize borderBottomSide (DocxBorderSide)
    final bottomSpec = paragraph.borderBottomSide ?? paragraph.borderBetween;

    if (bottomSpec != null) {
      bottomBorder = _buildBorderSide(bottomSpec);
    }

    if (paragraph.borderLeft != null) {
      leftBorder = _buildBorderSide(paragraph.borderLeft!);
    }
    if (paragraph.borderRight != null) {
      rightBorder = _buildBorderSide(paragraph.borderRight!);
    }

    final hasBorder = topBorder != null ||
        bottomBorder != null ||
        leftBorder != null ||
        rightBorder != null;

    if (backgroundColor == null && !hasBorder) {
      return null;
    }

    return BoxDecoration(
      color: backgroundColor,
      border: hasBorder
          ? Border(
              top: topBorder ?? BorderSide.none,
              bottom: bottomBorder ?? BorderSide.none,
              left: leftBorder ?? BorderSide.none,
              right: rightBorder ?? BorderSide.none,
            )
          : null,
    );
  }

  /// Convert DocxBorderSide to Flutter BorderSide.
  BorderSide _buildBorderSide(DocxBorderSide side) {
    if (side.style == DocxBorder.none) {
      return BorderSide.none;
    }

    // Convert size from eighths of a point to pixels
    final width = (side.size / 8.0).clamp(0.5, 10.0);
    final color = _resolveColor(
            side.color.hex, side.themeColor, side.themeTint, side.themeShade) ??
        Colors.black;

    // Flutter's Border/BorderSide only supports solid or none - there is no
    // native dotted/dashed line style. Any DOCX border style other than
    // "none" (dotted, dashed, double, etc.) is drawn as solid rather than
    // silently disappearing, which is the closer approximation of the two.
    return BorderSide(color: color, width: width, style: BorderStyle.solid);
  }

  /// Build TextSpans from inline elements.
  ///
  /// [firstLineIndentPx] prepends a zero-height spacer to simulate `w:firstLine` indent.
  List<InlineSpan> buildInlineSpans(
    List<DocxInline> inlines, {
    double? lineHeight,
    List<SearchMatch>? matches,
    int startOffset = 0,
    double firstLineIndentPx = 0.0,
  }) {
    final spans = <InlineSpan>[];

    if (firstLineIndentPx > 0) {
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: SizedBox(width: firstLineIndentPx, height: 0),
      ));
    }

    int currentOffset = startOffset;

    for (final inline in inlines) {
      if (inline is DocxText) {
        spans.addAll(_buildTextSpan(
          inline,
          lineHeight: lineHeight,
          matches: matches,
          offset: currentOffset,
        ));
        currentOffset += inline.content.length;
      } else if (inline is DocxLineBreak) {
        spans.add(const TextSpan(text: '\n'));
        currentOffset += 1;
      } else if (inline is DocxTab) {
        // Better tab rendering - use 4 spaces worth of fixed width
        spans.add(const TextSpan(text: '    '));
        currentOffset += 4;
      } else if (inline is DocxCheckbox) {
        // Render checkbox as unicode character with styling
        spans.add(_buildCheckboxSpan(inline, lineHeight: lineHeight));
        currentOffset += 2;
      } else if (inline is DocxInlineImage) {
        // Inline images with proper vertical alignment
        final imageWidth = DocxUnits.pointsToPixels(inline.width);
        final imageHeight = DocxUnits.pointsToPixels(inline.height);
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Image.memory(
            inline.bytes,
            width: imageWidth,
            height: imageHeight,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => Container(
              width: imageWidth,
              height: imageHeight,
              color: Colors.grey.shade200,
              child: const Icon(Icons.broken_image, size: 24),
            ),
          ),
        ));
      } else if (inline is DocxShape) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _buildInlineShape(inline),
        ));
      } else if (inline is DocxFootnoteRef) {
        spans.add(_buildFootnoteRef(inline));
      } else if (inline is DocxEndnoteRef) {
        spans.add(_buildEndnoteRef(inline));
      } else if (inline is DocxMath) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _buildMathWidget(inline),
        ));
      }
    }

    return spans;
  }

  /// Build a TextSpan for a DocxCheckbox.
  TextSpan _buildCheckboxSpan(DocxCheckbox checkbox, {double? lineHeight}) {
    final content = checkbox.isChecked ? '☒ ' : '☐ ';

    FontWeight fontWeight = checkbox.fontWeight == DocxFontWeight.bold
        ? FontWeight.bold
        : FontWeight.normal;

    FontStyle fontStyle = checkbox.fontStyle == DocxFontStyle.italic
        ? FontStyle.italic
        : FontStyle.normal;

    Color? textColor;
    if (checkbox.color != null) {
      textColor = _parseHexColor(checkbox.color!.hex);
    }

    return TextSpan(
      text: content,
      style: TextStyle(
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        color: textColor ?? theme.defaultTextStyle.color,
        fontSize: checkbox.fontSize ?? theme.defaultTextStyle.fontSize,
        height: lineHeight ?? theme.defaultTextStyle.height,
      ),
    );
  }

  /// Build a TextSpan from a [DocxText] element.
  /// Returns a list because one DocxText might be split into multiple spans for search highlights.
  List<InlineSpan> _buildTextSpan(
    DocxText text, {
    double? lineHeight,
    List<SearchMatch>? matches,
    int offset = 0,
  }) {
    // Transform content based on text effects
    String content = text.content;
    if (text.isAllCaps) {
      content = content.toUpperCase();
    } else if (text.isSmallCaps) {
      content = content.toUpperCase();
    }

    // Determine text style (common for all segments)
    FontWeight fontWeight = text.fontWeight == DocxFontWeight.bold
        ? FontWeight.bold
        : FontWeight.normal;

    FontStyle fontStyle = text.fontStyle == DocxFontStyle.italic
        ? FontStyle.italic
        : FontStyle.normal;

    // Handle multiple text decorations
    TextDecoration decoration = TextDecoration.none;
    final decorations = <TextDecoration>[];

    if (text.decoration == DocxTextDecoration.underline) {
      decorations.add(TextDecoration.underline);
    }
    if (text.decoration == DocxTextDecoration.strikethrough ||
        text.isDoubleStrike) {
      decorations.add(TextDecoration.lineThrough);
    }

    if (decorations.isNotEmpty) {
      decoration = TextDecoration.combine(decorations);
    }

    Color? textColor;
    if (text.color != null) {
      textColor = _resolveColor(
        text.color!.hex,
        text.themeColor ?? text.color!.themeColor,
        text.themeTint ?? text.color!.themeTint,
        text.themeShade ?? text.color!.themeShade,
      );
    }

    Color? backgroundColor;
    if (text.shadingFill != null || text.themeFill != null) {
      backgroundColor = _resolveColor(
        text.shadingFill,
        text.themeFill,
        text.themeFillTint,
        text.themeFillShade,
      );
    }

    if (backgroundColor == null && text.highlight != DocxHighlight.none) {
      backgroundColor = _highlightToColor(text.highlight);
    }

    double? fontSize = text.fontSize;
    if (fontSize != null) {
      fontSize = fontSize * 1.333;
    } else {
      fontSize = theme.defaultTextStyle.fontSize;
    }

    String? fontFamily; // Start with null to prioritize granular resolution

    // Resolve Theme Font if applicable
    if (docxTheme != null) {
      String? themeFontName;
      if (text.fonts?.asciiTheme != null) {
        themeFontName = text.fonts!.asciiTheme;
      } else if (text.fonts?.hAnsiTheme != null) {
        themeFontName = text.fonts!.hAnsiTheme;
      } else if (text.fonts?.eastAsiaTheme != null) {
        themeFontName = text.fonts!.eastAsiaTheme;
      }

      if (themeFontName != null) {
        final resolved = docxTheme!.fonts.getFont(themeFontName);
        if (resolved != null) {
          fontFamily = resolved;
        }
      }
    }

    // granular fonts override theme or base family
    if (text.fonts?.ascii != null) {
      fontFamily = text.fonts!.ascii;
    } else if (text.fonts?.hAnsi != null) {
      fontFamily = text.fonts!.hAnsi;
    } else if (text.fonts?.family != null) {
      fontFamily = text.fonts!.family;
    }

    // Fallback to basic fontFamily property if still null
    fontFamily ??= text.fontFamily;

    // Apply font fallbacks
    if (fontFamily == null && config.customFontFallbacks.isNotEmpty) {
      fontFamily = config.customFontFallbacks.first;
    }

    if (text.isSuperscript || text.isSubscript) {
      fontSize = (fontSize ?? 14) * 0.7;
    }

    if (text.isSmallCaps && !text.isAllCaps) {
      fontSize = (fontSize ?? 14) * 0.85;
    }

    // ... (Shadows/Emboss/Imprint etc logic reused) ...
    List<Shadow>? shadows;
    if (text.isShadow) {
      shadows = [
        Shadow(
          color: Colors.black.withValues(alpha: 0.3),
          offset: const Offset(1, 1),
          blurRadius: 2,
        ),
      ];
    } else if (text.isEmboss) {
      shadows = [
        Shadow(
          color: Colors.white.withValues(alpha: 0.7),
          offset: const Offset(-1, -1),
          blurRadius: 1,
        ),
        Shadow(
          color: Colors.black.withValues(alpha: 0.3),
          offset: const Offset(1, 1),
          blurRadius: 1,
        ),
      ];
    } else if (text.isImprint) {
      shadows = [
        Shadow(
          color: Colors.black.withValues(alpha: 0.3),
          offset: const Offset(-1, -1),
          blurRadius: 1,
        ),
        Shadow(
          color: Colors.white.withValues(alpha: 0.5),
          offset: const Offset(1, 1),
          blurRadius: 1,
        ),
      ];
    }

    Paint? foreground;
    if (text.isOutline) {
      foreground = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5
        ..color = textColor ?? Colors.black;
      textColor = null;
    }

    final baseStyle = TextStyle(
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      decoration: decoration,
      decorationStyle: text.isDoubleStrike
          ? TextDecorationStyle.double
          : TextDecorationStyle.solid,
      color: foreground == null
          ? (textColor ?? theme.defaultTextStyle.color)
          : null,
      foreground: foreground,
      backgroundColor: backgroundColor,
      letterSpacing:
          text.characterSpacing != null ? text.characterSpacing! / 20.0 : null,
      fontSize: fontSize,
      fontFamily: fontFamily,
      fontFamilyFallback: config.customFontFallbacks,
      height: lineHeight ?? theme.defaultTextStyle.height,
      shadows: shadows,
      fontFeatures: (text.isSuperscript || text.isSubscript)
          ? [
              if (text.isSuperscript) const FontFeature.superscripts(),
              if (text.isSubscript) const FontFeature.subscripts(),
            ]
          : null,
    );

    // Tap handler
    TapGestureRecognizer? tapRecognizer;
    Color? linkColor;
    TextDecoration? linkDecoration;

    if (text.href != null && text.href!.isNotEmpty) {
      linkColor = theme.linkStyle.color;
      linkDecoration = TextDecoration.underline;
      tapRecognizer = TapGestureRecognizer()
        ..onTap = () {
          _launchUrl(text.href!);
        };
    }

    // Split text based on matches
    if (matches == null || matches.isEmpty) {
      // Normal case
      // Check for TextBorder
      if (text.textBorder != null) {
        final side = _buildBorderSide(text.textBorder!);
        if (side != BorderSide.none) {
          final textBorder = Border.all(
              color: side.color, width: side.width, style: side.style);
          return [
            WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
                  decoration: BoxDecoration(
                    border: textBorder,
                    color: backgroundColor,
                  ),
                  child: Text(content,
                      style: baseStyle.copyWith(
                        color: linkColor ?? baseStyle.color,
                        decoration: linkDecoration ?? baseStyle.decoration,
                        backgroundColor: null, // moved to container
                      )),
                ))
          ];
        }
      }

      return [
        TextSpan(
          text: content,
          style: baseStyle.copyWith(
            color: linkColor ?? baseStyle.color,
            decoration: linkDecoration ?? baseStyle.decoration,
          ),
          recognizer: tapRecognizer,
        )
      ];
    }

    // Splitting logic
    final resultSpans = <InlineSpan>[];
    int currentLocalIndex = 0;
    final int textLength = content.length;
    final int globalStart = offset;
    final int globalEnd = offset + textLength;

    // Filter matches that overlap with this text node
    final relevantMatches = matches
        .where((m) => m.endOffset > globalStart && m.startOffset < globalEnd)
        .toList();

    // Sort matches (should be sorted but ensure)
    relevantMatches.sort((a, b) => a.startOffset.compareTo(b.startOffset));

    for (final match in relevantMatches) {
      // Calculate overlap
      int matchStartInNode = match.startOffset - globalStart;
      int matchEndInNode = match.endOffset - globalStart;

      // Clamp to node bounds
      if (matchStartInNode < 0) matchStartInNode = 0;
      if (matchEndInNode > textLength) matchEndInNode = textLength;

      if (matchStartInNode > currentLocalIndex) {
        // Unmatched segment before
        resultSpans.add(TextSpan(
          text: content.substring(currentLocalIndex, matchStartInNode),
          style: baseStyle.copyWith(
            color: linkColor ?? baseStyle.color,
            decoration: linkDecoration ?? baseStyle.decoration,
          ),
          recognizer: tapRecognizer,
        ));
      }

      // Matched segment
      if (matchEndInNode > matchStartInNode) {
        bool isCurrent = false;
        if (searchController != null) {
          // Check if this match is the currently selected one
          final currentMatchIndex = searchController!.currentMatchIndex;
          if (currentMatchIndex >= 0 &&
              currentMatchIndex < searchController!.matches.length) {
            isCurrent = match == searchController!.matches[currentMatchIndex];
          }
        }

        resultSpans.add(TextSpan(
          text: content.substring(matchStartInNode, matchEndInNode),
          style: baseStyle.copyWith(
            color: linkColor ?? baseStyle.color,
            decoration: linkDecoration ?? baseStyle.decoration,
            backgroundColor:
                isCurrent ? Colors.orange.shade300 : Colors.yellow.shade200,
          ),
          recognizer: tapRecognizer,
        ));
      }
      currentLocalIndex = matchEndInNode;
    }

    // Remaining text
    if (currentLocalIndex < textLength) {
      resultSpans.add(TextSpan(
        text: content.substring(currentLocalIndex),
        style: baseStyle.copyWith(
          color: linkColor ?? baseStyle.color,
          decoration: linkDecoration ?? baseStyle.decoration,
        ),
        recognizer: tapRecognizer,
      ));
    }

    return resultSpans;
  }

  /// Resolve color from hex or theme properties.
  Color? _resolveColor(
      String? hex, String? themeColor, String? themeTint, String? themeShade) {
    Color? baseColor;

    if (themeColor != null && docxTheme != null) {
      final themeHex = docxTheme!.colors.getColor(themeColor);
      if (themeHex != null) {
        baseColor = _parseHexColor(themeHex);
      }
    }

    if (baseColor == null && hex != null && hex != 'auto') {
      baseColor = _parseHexColor(hex);
    }

    if (baseColor == null) return null;

    if (themeTint != null) {
      final tintVal = int.tryParse(themeTint, radix: 16);
      if (tintVal != null) {
        final factor = tintVal / 255.0;
        baseColor = Color.alphaBlend(
            Colors.white.withValues(alpha: 1 - factor), baseColor);
      }
    }

    if (themeShade != null) {
      final shadeVal = int.tryParse(themeShade, radix: 16);
      if (shadeVal != null) {
        final factor = shadeVal / 255.0;
        baseColor = Color.alphaBlend(
            Colors.black.withValues(alpha: 1 - factor), baseColor);
      }
    }

    return baseColor;
  }

  /// Resolves the TextStyle line-height scale from [DocxParagraph.lineSpacing]
  /// and [DocxParagraph.lineRule].
  ///
  /// - `'auto'` (default): `lineSpacing / 240` where 240 twips = one standard line.
  /// - `'exact'`: lineSpacing is an absolute height; normalised against the same baseline.
  /// - `'atLeast'`: minimum spacing — clamped to ≥ 1.0 so lines never collapse.
  double? resolveLineHeightScale(DocxParagraph paragraph) {
    if (paragraph.lineSpacing == null) return null;
    final spacing = paragraph.lineSpacing!;
    switch (paragraph.lineRule ?? 'auto') {
      case 'exact':
      case 'atLeast':
        // TextStyle.height is relative to the rendered font size, so dividing
        // by the fixed 240-twip baseline (12pt) produces an incorrect scale for
        // any font other than 12pt. Normalize against the theme default instead.
        final baseFontSizePx = theme.defaultTextStyle.fontSize ?? 16.0;
        final baseHeightTwips = baseFontSizePx * 15.0;
        final scale = spacing / baseHeightTwips;
        return (paragraph.lineRule == 'exact')
            ? scale.clamp(0.5, 10.0)
            : scale.clamp(1.0, 10.0);
      default:
        return spacing / 240.0;
    }
  }

  /// Build a widget for a paragraph with a drop cap.
  Widget buildDropCap(DocxDropCap dropCap) {
    const pointToPx = 1.333;
    final defaultFontSize = theme.defaultTextStyle.fontSize ?? 14.0;

    double fontSizePx;
    if (dropCap.fontSize != null) {
      fontSizePx = dropCap.fontSize! * pointToPx;
    } else {
      fontSizePx = dropCap.lines * defaultFontSize * 1.2;
    }

    final color = theme.defaultTextStyle.color ?? Colors.black;
    final fontFamily = dropCap.fontFamily ?? theme.defaultTextStyle.fontFamily;

    final dropCapStyle = TextStyle(
        fontSize: fontSizePx,
        color: color,
        fontFamily: fontFamily,
        height: 1.0,
        fontWeight: FontWeight.bold);

    final painter = TextPainter(
      text: TextSpan(text: dropCap.letter, style: dropCapStyle),
      textDirection: TextDirection.ltr,
    )..layout();

    final dcWidth = painter.width;
    final dcHeight = painter.height;

    // Use theme defaults for the body text of the drop cap paragraph
    final bodyStyle = TextStyle(
      fontSize: defaultFontSize,
      color: theme.defaultTextStyle.color,
      fontFamily: theme.defaultTextStyle.fontFamily,
      height: theme.defaultTextStyle.height,
    );

    final spans = buildInlineSpans(dropCap.restOfParagraph);
    final fullTextSpan = TextSpan(children: spans, style: bodyStyle);

    String restPlainText = '';
    for (final inline in dropCap.restOfParagraph) {
      if (inline is DocxText) {
        restPlainText += inline.content;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: DropCapText(
        restPlainText, // Only the rest of paragraph text, matching textSpan
        textSpan: fullTextSpan,
        dropCap: DropCap(
          width: dcWidth,
          height: dcHeight,
          child: Text(dropCap.letter, style: dropCapStyle),
        ),
        mode: DropCapMode.inside,
        forceNoDescent: true,
        dropCapLines: dropCap.lines,
        dropCapPadding:
            EdgeInsets.only(right: (dropCap.hSpace / 20.0).clamp(4.0, 20.0)),
      ),
    );
  }

  TextSpan _buildFootnoteRef(DocxFootnoteRef ref) {
    return TextSpan(
      text: '${ref.footnoteId}',
      style: TextStyle(
        fontSize: (theme.defaultTextStyle.fontSize ?? 14) * 0.6,
        color: theme.linkStyle.color,
        fontFeatures: const [FontFeature.superscripts()],
      ),
      recognizer: TapGestureRecognizer()
        ..onTap = () {
          onFootnoteTap?.call(ref.footnoteId);
        },
    );
  }

  TextSpan _buildEndnoteRef(DocxEndnoteRef ref) {
    return TextSpan(
      text: '${ref.endnoteId}',
      style: TextStyle(
        fontSize: (theme.defaultTextStyle.fontSize ?? 14) * 0.6,
        color: theme.linkStyle.color,
        fontFeatures: const [FontFeature.superscripts()],
      ),
      recognizer: TapGestureRecognizer()
        ..onTap = () {
          onEndnoteTap?.call(ref.endnoteId);
        },
    );
  }

  /// Basic-fidelity rendering of a [DocxMath] equation: each top-level node
  /// gets real visual structure (a fraction bar, a raised superscript, a
  /// radical sign); the content *inside* a fraction/superscript/radical is
  /// rendered as flattened plain text rather than recursed into further
  /// nested layout — mirrors the PDF exporter's `_drawMath` for the same
  /// reason (see [DocxMath] class doc): a bounded "basic equation" renderer,
  /// not a full typesetting engine.
  Widget _buildMathWidget(DocxMath math) {
    final style = theme.defaultTextStyle;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (final node in math.children) _buildMathNodeWidget(node, style),
      ],
    );
  }

  Widget _buildMathNodeWidget(DocxMathNode node, TextStyle style) {
    if (node is DocxMathText) {
      return Text(node.text, style: style);
    } else if (node is DocxMathFraction) {
      final partStyle = style.copyWith(
          fontSize: (style.fontSize ?? 14) * 0.8, height: 1.1);
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(flattenNodes(node.numerator), style: partStyle),
          Container(
              height: 1,
              color: style.color ?? Colors.black,
              margin: const EdgeInsets.symmetric(vertical: 1)),
          Text(flattenNodes(node.denominator), style: partStyle),
        ],
      );
    } else if (node is DocxMathSuperscript) {
      final supStyle = style.copyWith(
          fontSize: (style.fontSize ?? 14) * 0.6, height: 1.1);
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(flattenNodes(node.base), style: style),
          Transform.translate(
            offset: Offset(0, -(style.fontSize ?? 14) * 0.3),
            child: Text(flattenNodes(node.superscript), style: supStyle),
          ),
        ],
      );
    } else if (node is DocxMathSubscript) {
      final subStyle = style.copyWith(
          fontSize: (style.fontSize ?? 14) * 0.6, height: 1.1);
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(flattenNodes(node.base), style: style),
          Transform.translate(
            offset: Offset(0, (style.fontSize ?? 14) * 0.15),
            child: Text(flattenNodes(node.subscript), style: subStyle),
          ),
        ],
      );
    } else if (node is DocxMathRadical) {
      final degStyle =
          style.copyWith(fontSize: (style.fontSize ?? 14) * 0.5, height: 1.1);
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (node.degree != null)
            Text(flattenNodes(node.degree!), style: degStyle),
          Text('√', style: style),
          Container(
            decoration: BoxDecoration(
              border: Border(
                  top: BorderSide(color: style.color ?? Colors.black)),
            ),
            padding: const EdgeInsets.only(left: 2),
            child: Text(flattenNodes(node.radicand), style: style),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildInlineShape(DocxShape shape) {
    return Container(
      width: DocxUnits.pointsToPixels(shape.width),
      height: DocxUnits.pointsToPixels(shape.height),
      decoration: BoxDecoration(
        color: _resolveColor(shape.fillColor?.hex, shape.fillColor?.themeColor,
            shape.fillColor?.themeTint, shape.fillColor?.themeShade),
        border: shape.outlineColor != null
            ? Border.all(
                color: _resolveColor(
                        shape.outlineColor!.hex,
                        shape.outlineColor!.themeColor,
                        shape.outlineColor!.themeTint,
                        shape.outlineColor!.themeShade) ??
                    Colors.black,
                width: shape.outlineWidth)
            : null,
      ),
    );
  }

  TextAlign _convertAlign(DocxAlign align) {
    switch (align) {
      case DocxAlign.left:
        return TextAlign.left;
      case DocxAlign.center:
        return TextAlign.center;
      case DocxAlign.right:
        return TextAlign.right;
      case DocxAlign.justify:
        return TextAlign.justify;
    }
  }

  Color? _parseHexColor(String hex) {
    if (hex == 'auto') return theme.defaultTextStyle.color;
    try {
      final buffer = StringBuffer();
      if (hex.length == 6 || hex.length == 8) {
        if (hex.length == 6) buffer.write('ff');
        buffer.write(hex);
        final color = Color(int.parse(buffer.toString(), radix: 16));

        // Smart inversion for dark mode:
        // If background is dark and text is dark (black), invert text to white.
        // Leaves other colors (red, green, etc.) untouched.
        final bg = theme.backgroundColor;
        if (bg != null && bg.computeLuminance() < 0.5) {
          if (color.computeLuminance() < 0.179) {
            return Colors.white;
          }
        }
        return color;
      }
    } catch (_) {}
    return null;
  }

  Color? _highlightToColor(DocxHighlight highlight) {
    switch (highlight) {
      case DocxHighlight.black:
        return Colors.black;
      case DocxHighlight.blue:
        return Colors.blue;
      case DocxHighlight.cyan:
        return Colors.cyan;
      case DocxHighlight.green:
        return Colors.green;
      case DocxHighlight.magenta:
        return const Color(0xFFFF00FF);
      case DocxHighlight.red:
        return Colors.red;
      case DocxHighlight.yellow:
        return Colors.yellow;
      case DocxHighlight.white:
        return Colors.white;
      case DocxHighlight.darkBlue:
        return Colors.blue.shade900;
      case DocxHighlight.darkCyan:
        return Colors.cyan.shade900;
      case DocxHighlight.darkGreen:
        return Colors.green.shade900;
      case DocxHighlight.darkMagenta:
        return Colors.purple.shade900;
      case DocxHighlight.darkRed:
        return Colors.red.shade900;
      case DocxHighlight.darkYellow:
        return Colors.yellow.shade800;
      case DocxHighlight.darkGray:
        return Colors.grey.shade700;
      case DocxHighlight.lightGray:
        return Colors.grey.shade300;
      case DocxHighlight.none:
        return null;
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
}

/// True if [span] or any descendant is a [WidgetSpan] - the case
/// [DocxParagraphRenderWidget]'s leaf render object can't handle.
bool _containsWidgetSpan(InlineSpan span) {
  if (span is WidgetSpan) return true;
  if (span is TextSpan) {
    final children = span.children;
    if (children == null) return false;
    for (final child in children) {
      if (_containsWidgetSpan(child)) return true;
    }
  }
  return false;
}
