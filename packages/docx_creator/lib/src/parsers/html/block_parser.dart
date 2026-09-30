import 'package:html/dom.dart' as dom;

import '../../../docx_creator.dart';
import '../../utils/document_builder.dart';
import 'color_utils.dart';
import 'image_parser.dart';
import 'inline_parser.dart';
import 'list_parser.dart';
import 'parser_context.dart';
import 'style_context.dart';
import 'table_parser.dart';

/// Parses HTML block-level elements.
class HtmlBlockParser {
  final HtmlParserContext context;
  late final HtmlInlineParser _inlineParser;
  late final HtmlTableParser _tableParser;
  late final HtmlListParser _listParser;
  late final HtmlImageParser _imageParser;

  HtmlBlockParser(this.context) {
    _inlineParser = HtmlInlineParser(context);
    _tableParser = HtmlTableParser(context, _inlineParser);
    _listParser = HtmlListParser(context, _inlineParser);
    _imageParser = HtmlImageParser();

    _tableParser.setBlockParser(this);
    _listParser.setBlockParser(this);
  }

  /// Parse child nodes into DocxNode elements.
  ///
  /// Consecutive siblings that don't produce a block of their own — text
  /// nodes and inline elements like `<span>`/`<b>` sitting directly next to
  /// a block sibling (e.g. `<div><p>A</p>loose <span>text</span></div>`) —
  /// are accumulated and merged into a single paragraph, the same way a
  /// browser lays them out on one line, instead of each becoming its own
  /// separate paragraph.
  Future<List<DocxNode>> parseChildren(List<dom.Node> nodes,
      {HtmlStyleContext? styleContext}) async {
    final ctx = styleContext ?? const HtmlStyleContext();
    final results = <DocxNode>[];
    final inlineBuffer = <DocxInline>[];

    void flushInlineBuffer() {
      if (inlineBuffer.isEmpty) return;
      results.add(DocxParagraph(
          children: List.of(inlineBuffer),
          align: ctx.textAlign ?? DocxAlign.left));
      inlineBuffer.clear();
    }

    for (var node in nodes) {
      final isLooseInline = node is dom.Text ||
          (node is dom.Element && !isBlockTag(node.localName?.toLowerCase()));

      if (isLooseInline) {
        inlineBuffer
            .addAll(await _inlineParser.parseInline(node, context: ctx));
        continue;
      }

      flushInlineBuffer();
      results.addAll(await parseNode(node, styleContext: styleContext));
    }
    flushInlineBuffer();

    return results;
  }

  /// Parse a single DOM node in isolation (i.e. not as part of a run of
  /// sibling inline content — see [parseChildren] for that merging).
  Future<List<DocxNode>> parseNode(dom.Node node,
      {HtmlStyleContext? styleContext}) async {
    if (node is dom.Text) {
      final text = collapseHtmlWhitespace(node.text).trim();
      if (text.isEmpty) return [];
      final built = DocumentBuilder.buildBlockElement(
        tag: 'p',
        children: [
          _inlineParser.createText(
              text, styleContext ?? const HtmlStyleContext())
        ],
      );
      final align = styleContext?.textAlign;
      if (built is DocxParagraph && align != null) {
        return [built.copyWith(align: align)];
      }
      return built != null ? [built] : [];
    }
    if (node is dom.Element) {
      return parseElement(node, styleContext: styleContext);
    }
    return [];
  }

  /// Parse an HTML element.
  Future<List<DocxNode>> parseElement(dom.Element element,
      {HtmlStyleContext? styleContext}) async {
    final tag = element.localName?.toLowerCase();
    if (tag == null) return [];

    var styleStr =
        context.mergeStyles(element.attributes['style'], element.classes);
    // Legacy `align="center"` behaves like a low-priority text-align.
    final alignAttr = element.attributes['align'];
    if (alignAttr != null) styleStr = '$styleStr;text-align:$alignAttr';
    final parentCtx = styleContext ?? const HtmlStyleContext();
    final currentCtx =
        parentCtx.mergeWith(tag, styleStr, ColorUtils.parseColor);

    // Check if this element should be treated as a container of blocks
    bool hasBlockChildren = false;
    for (var node in element.nodes) {
      if (node is dom.Element && isBlockTag(node.localName?.toLowerCase())) {
        hasBlockChildren = true;
        break;
      }
    }

    // If it has block children and is a container-like tag, recurse
    if (hasBlockChildren &&
        ![
          'p',
          'h1',
          'h2',
          'h3',
          'h4',
          'h5',
          'h6',
          'table',
          'ul',
          'ol',
          'img',
          'pre',
          'code'
        ].contains(tag)) {
      return parseChildren(element.nodes, styleContext: currentCtx);
    }

    final blockContext = currentCtx.resetBackground();

    // Parse inline children
    final children =
        await _inlineParser.parseInlines(element.nodes, context: blockContext);

    final built = DocumentBuilder.buildBlockElement(
      tag: tag,
      children: children,
      textContent: _getText(element),
    );

    if (built != null &&
        tag != 'p' &&
        tag != 'div' &&
        tag != 'span' &&
        tag != 'pre' &&
        !tag.startsWith('h')) {
      return [built];
    }

    // Vertical margins resolve in declaration order, class rules first
    // and inline style last (mergeStyles puts inline first for its
    // first-match lookups, so it can't be scanned in order).
    final classMargins =
        _orderedVerticalMargins(context.mergeStyles(null, element.classes));
    final inlineMargins =
        _orderedVerticalMargins(element.attributes['style'] ?? '');
    final blockStyles = _parseBlockStyles(
      styleStr,
      inheritedAlign: parentCtx.textAlign,
      spacingBefore: inlineMargins.$1 ?? classMargins.$1,
      spacingAfter: inlineMargins.$2 ?? classMargins.$2,
    );

    switch (tag) {
      case 'p':
      case 'div':
      case 'span':
        if (children.isEmpty) return [];
        return [
          DocxParagraph(
            children: children,
            shadingFill: blockStyles.shadingFill,
            align: blockStyles.align,
            borderTop: blockStyles.borderTop,
            borderBottomSide: blockStyles.borderBottom,
            borderLeft: blockStyles.borderLeft,
            borderRight: blockStyles.borderRight,
            indentLeft: blockStyles.indentLeft,
            indentRight: blockStyles.indentRight,
            indentFirstLine: blockStyles.indentFirstLine,
            spacingBefore: blockStyles.spacingBefore,
            spacingAfter: blockStyles.spacingAfter,
            lineSpacing: blockStyles.lineSpacing,
            lineRule: blockStyles.lineRule,
          )
        ];

      case 'ul':
        final list = await _listParser.parseList(element,
            ordered: false,
            styleContext:
                currentCtx.copyWith(listLevel: currentCtx.listLevel + 1));
        return [list];
      case 'ol':
        final list = await _listParser.parseList(element,
            ordered: true,
            styleContext:
                currentCtx.copyWith(listLevel: currentCtx.listLevel + 1));
        return [list];

      case 'table':
        final table = await _tableParser.parseTable(element);
        return [table];

      case 'dl':
        return _parseDefinitionList(element, blockContext);

      case 'img':
        final img = await _imageParser.parseBlockImage(element);
        return img != null ? [img] : [];

      case 'pre':
      case 'code':
        return [_parseCodeBlock(element, blockStyles.align)];

      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
      case 'blockquote':
      case 'hr':
        if (built is DocxParagraph) {
          return [
            built.copyWith(
              shadingFill: blockStyles.shadingFill ?? built.shadingFill,
              align: blockStyles.align,
              borderTop: blockStyles.borderTop,
              borderBottomSide: blockStyles.borderBottom,
              borderLeft: blockStyles.borderLeft,
              borderRight: blockStyles.borderRight,
              indentLeft: blockStyles.indentLeft ?? built.indentLeft,
              indentRight: blockStyles.indentRight ?? built.indentRight,
              indentFirstLine:
                  blockStyles.indentFirstLine ?? built.indentFirstLine,
              spacingBefore: blockStyles.spacingBefore,
              spacingAfter: blockStyles.spacingAfter,
              lineSpacing: blockStyles.lineSpacing,
              lineRule: blockStyles.lineRule,
            )
          ];
        }
        return built != null ? [built] : [];

      default:
        if (children.isEmpty) return [];
        return [
          DocxParagraph(
            children: children,
            shadingFill: blockStyles.shadingFill,
            align: blockStyles.align,
            indentLeft: blockStyles.indentLeft,
            indentRight: blockStyles.indentRight,
            indentFirstLine: blockStyles.indentFirstLine,
            spacingBefore: blockStyles.spacingBefore,
            spacingAfter: blockStyles.spacingAfter,
            lineSpacing: blockStyles.lineSpacing,
            lineRule: blockStyles.lineRule,
          )
        ];
    }
  }

  /// Parses a definition list (`<dl>`) into one paragraph per `<dt>`/`<dd>`
  /// (bold term, indented definition), since docx_creator has no dedicated
  /// definition-list AST node. Previously `<dt>`/`<dd>` fell through to
  /// plain inline pass-through with no separator, garbling
  /// "<dt>Term</dt><dd>Definition</dd>" into a single "TermDefinition" run.
  Future<List<DocxNode>> _parseDefinitionList(
      dom.Element element, HtmlStyleContext context) async {
    final paragraphs = <DocxNode>[];
    for (var child in element.children) {
      final tag = child.localName?.toLowerCase();
      if (tag != 'dt' && tag != 'dd') continue;

      final inlines =
          await _inlineParser.parseInlines(child.nodes, context: context);
      if (inlines.isEmpty) continue;

      if (tag == 'dt') {
        paragraphs.add(DocxParagraph(
          children: inlines
              .map((i) => i is DocxText
                  ? i.copyWith(fontWeight: DocxFontWeight.bold)
                  : i)
              .toList(),
        ));
      } else {
        paragraphs.add(DocxParagraph(children: inlines, indentLeft: 360));
      }
    }
    return paragraphs;
  }

  DocxParagraph _parseCodeBlock(dom.Element element, DocxAlign align) {
    final text = _getText(element);
    final lines = text.split('\n');
    final codeChildren = <DocxInline>[];

    for (var i = 0; i < lines.length; i++) {
      codeChildren.add(DocxText.code(lines[i], color: DocxColor.black));
      if (i < lines.length - 1) {
        codeChildren.add(DocxLineBreak());
      }
    }

    return DocxParagraph(
      shadingFill: 'F5F5F5',
      children: codeChildren,
      align: align,
    );
  }

  HtmlBlockStyles _parseBlockStyles(
    String style, {
    DocxAlign? inheritedAlign,
    int? spacingBefore,
    int? spacingAfter,
  }) {
    String? shadingFill;
    final lineHeight = _parseLineHeight(style);
    // text-align is inherited: a paragraph without its own uses the
    // nearest ancestor's.
    DocxAlign align = inheritedAlign ?? DocxAlign.left;

    final bgMatch = RegExp(
            r"background-color:\s*['\x22]?(#[A-Fa-f0-9]{3,6}|rgba?\([0-9.,\s]+\)|hsla?\([0-9.,%\s]+\)|[a-zA-Z]+)['\x22]?",
            caseSensitive: false)
        .firstMatch(style);
    if (bgMatch != null) {
      final val = bgMatch.group(1);
      if (val != null) {
        shadingFill = ColorUtils.parseColor(val);
      }
    }

    // `background: #eee url(...) no-repeat` shorthand: use its color.
    if (shadingFill == null) {
      final shorthand = RegExp(r'(?<![-a-zA-Z])background\s*:\s*([^;]+)',
              caseSensitive: false)
          .firstMatch(style)
          ?.group(1);
      if (shorthand != null) {
        for (final token in shorthand
            .replaceAll(RegExp(r'url\([^)]*\)'), ' ')
            .split(RegExp(r'\s+(?![^(]*\))'))) {
          final hex = token.isEmpty ? null : ColorUtils.parseColor(token);
          if (hex != null) {
            shadingFill = hex;
            break;
          }
        }
      }
    }

    final alignMatch = RegExp(r'text-align\s*:\s*(\w+)', caseSensitive: false)
        .firstMatch(style);
    switch (alignMatch?.group(1)?.toLowerCase()) {
      case 'left':
      case 'start':
        align = DocxAlign.left;
        break;
      case 'center':
        align = DocxAlign.center;
        break;
      case 'right':
        align = DocxAlign.right;
        break;
      case 'justify':
        align = DocxAlign.justify;
        break;
    }

    return HtmlBlockStyles(
      shadingFill: shadingFill,
      align: align,
      borderTop: ColorUtils.parseCssBorderProperty(style, 'border-top') ??
          ColorUtils.parseCssBorderProperty(style, 'border'),
      borderBottom: ColorUtils.parseCssBorderProperty(style, 'border-bottom') ??
          ColorUtils.parseCssBorderProperty(style, 'border'),
      borderLeft: ColorUtils.parseCssBorderProperty(style, 'border-left') ??
          ColorUtils.parseCssBorderProperty(style, 'border'),
      borderRight: ColorUtils.parseCssBorderProperty(style, 'border-right') ??
          ColorUtils.parseCssBorderProperty(style, 'border'),
      indentLeft: _lengthPropertyTwips(style, 'margin-left') ??
          _lengthPropertyTwips(style, 'padding-left'),
      indentRight: _lengthPropertyTwips(style, 'margin-right') ??
          _lengthPropertyTwips(style, 'padding-right'),
      indentFirstLine: _lengthPropertyTwips(style, 'text-indent'),
      spacingBefore: spacingBefore,
      spacingAfter: spacingAfter,
      lineSpacing: lineHeight?.$1,
      lineRule: lineHeight?.$2,
    );
  }

  /// Space before/after (twips) from `margin`, `margin-top` and
  /// `margin-bottom`, applied in declaration order so a later shorthand
  /// overrides an earlier longhand and vice versa.
  (int?, int?) _orderedVerticalMargins(String css) {
    int? before;
    int? after;
    int? twips(String value) {
      final v = value.trim().toLowerCase();
      if (v == 'auto') return 0;
      final points = ColorUtils.parseCssLengthToPoints(v);
      return points != null ? (points * 20).round() : null;
    }

    for (final decl in css.split(';')) {
      final idx = decl.indexOf(':');
      if (idx <= 0) continue;
      final prop = decl.substring(0, idx).trim().toLowerCase();
      final value = decl
          .substring(idx + 1)
          .replaceAll(RegExp(r'!\s*important'), '')
          .trim();
      if (prop == 'margin') {
        final parts = value.split(RegExp(r'\s+'));
        before = twips(parts[0]) ?? before;
        after = twips(parts.length >= 3 ? parts[2] : parts[0]) ?? after;
      } else if (prop == 'margin-top') {
        before = twips(value) ?? before;
      } else if (prop == 'margin-bottom') {
        after = twips(value) ?? after;
      }
    }
    return (before, after);
  }

  /// CSS `line-height` as DOCX line spacing: unitless/percent values are
  /// proportional (`auto`, 240 = single), lengths are a minimum height.
  (int, String)? _parseLineHeight(String style) {
    final match = RegExp(r'line-height\s*:\s*([\d.]+)\s*(px|pt|em|rem|%)?',
            caseSensitive: false)
        .firstMatch(style);
    if (match == null) return null;
    final number = double.tryParse(match.group(1)!);
    if (number == null || number <= 0) return null;
    final unit = match.group(2)?.toLowerCase();
    if (unit == null) return ((number * 240).round(), 'auto');
    if (unit == '%') return ((number / 100 * 240).round(), 'auto');
    if (unit == 'em' || unit == 'rem') return ((number * 240).round(), 'auto');
    final points = ColorUtils.parseCssLengthToPoints('$number$unit');
    if (points == null) return null;
    return ((points * 20).round(), 'atLeast');
  }

  /// Reads a CSS length property (e.g. `margin-left: 40px`) and converts it
  /// to twips (1/20th of a point), or null if the property isn't present.
  int? _lengthPropertyTwips(String style, String property) {
    final match = RegExp(
      '$property\\s*:\\s*(-?[\\d.]+\\s*(?:px|pt|em|rem|%)?)',
      caseSensitive: false,
    ).firstMatch(style);
    if (match == null) return null;
    final points = ColorUtils.parseCssLengthToPoints(match.group(1)!);
    return points != null ? (points * 20).round() : null;
  }

  String _getText(dom.Node node) {
    if (node is dom.Text) return node.text;
    if (node is dom.Element) return node.text;
    return '';
  }

  /// Check if a tag is a block-level element.
  static bool isBlockTag(String? tag) {
    if (tag == null) return false;
    return [
      'p',
      'div',
      'table',
      'ul',
      'ol',
      'dl',
      'blockquote',
      'pre',
      'hr',
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
      'img'
    ].contains(tag);
  }
}
