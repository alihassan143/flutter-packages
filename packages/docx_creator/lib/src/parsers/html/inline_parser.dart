import 'package:docx_creator/docx_creator.dart';
import 'package:html/dom.dart' as dom;

import '../../utils/document_builder.dart';
import 'color_utils.dart';
import 'image_parser.dart';
import 'parser_context.dart';

/// Parses HTML inline elements (text, links, formatting).
class HtmlInlineParser {
  final HtmlParserContext context;
  final HtmlImageParser _imageParser = HtmlImageParser();

  HtmlInlineParser(this.context);

  /// Parse inline children with async image support.
  Future<List<DocxInline>> parseInlines(List<dom.Node> nodes,
      {HtmlStyleContext? context}) async {
    final results = <DocxInline>[];
    for (var node in nodes) {
      results.addAll(await parseInline(node, context: context));
    }
    return results;
  }

  /// Parse inline content synchronously (no async image fetching).
  /// Deprecated: prefer parseInlines for full feature support.
  List<DocxInline> parseInlinesSync(List<dom.Node> nodes,
      {HtmlStyleContext? context}) {
    final results = <DocxInline>[];
    for (var node in nodes) {
      // Note: This will miss async features like images
      results.addAll(_parseInlineSync(node, context: context));
    }
    return results;
  }

  /// Internal sync parser for backward compatibility
  List<DocxInline> _parseInlineSync(dom.Node node,
      {HtmlStyleContext? context}) {
    final ctx = context ?? const HtmlStyleContext();
    if (node is dom.Text) {
      return _parseTextNode(node.text, ctx);
    }
    if (node is dom.Element) {
      final tag = node.localName?.toLowerCase();
      final combinedStyle =
          this.context.mergeStyles(node.attributes['style'], node.classes);
      final newCtx = ctx.mergeWith(tag, combinedStyle, ColorUtils.parseColor);

      switch (tag) {
        case 'br':
          return [DocxLineBreak()];
        case 'a':
          final href = node.attributes['href'];
          // Links are blue unless the author styled their colour (browsers
          // and Word both override the inherited text colour for links).
          final linkColor =
              ColorUtils.parseCssColorProperty(combinedStyle, 'color') ??
                  (href != null ? '0563C1' : null);
          // Sync version can't handle nested async stuff well, but we do our best
          return parseInlinesSync(node.nodes,
              context: newCtx.copyWith(
                  href: href ?? '#', isLink: true, colorHex: linkColor));
        case 'input':
          return _parseInput(node, newCtx);
        case 'code':
          return _parseCode(node, newCtx);
        case 'img':
          // Sync version can't fetch images
          return [];
        default:
          return parseInlinesSync(node.nodes, context: newCtx);
      }
    }
    return [];
  }

  /// Parse a single inline node.
  Future<List<DocxInline>> parseInline(dom.Node node,
      {HtmlStyleContext? context}) async {
    final ctx = context ?? const HtmlStyleContext();

    if (node is dom.Text) {
      return _parseTextNode(node.text, ctx);
    }

    if (node is dom.Element) {
      final tag = node.localName?.toLowerCase();
      final combinedStyle =
          this.context.mergeStyles(node.attributes['style'], node.classes);
      final newCtx = ctx.mergeWith(tag, combinedStyle, ColorUtils.parseColor);

      switch (tag) {
        case 'br':
          return [DocxLineBreak()];
        case 'a':
          final href = node.attributes['href'];
          // Links are blue unless the author styled their colour (browsers
          // and Word both override the inherited text colour for links).
          final linkColor =
              ColorUtils.parseCssColorProperty(combinedStyle, 'color') ??
                  (href != null ? '0563C1' : null);
          return await parseInlines(node.nodes,
              context: newCtx.copyWith(
                  href: href ?? '#', isLink: true, colorHex: linkColor));
        case 'img':
          final img = await _imageParser.parseInlineImage(node);
          return img != null ? [img] : [];
        case 'input':
          return _parseInput(node, newCtx);
        case 'code':
          return _parseCode(node, newCtx);
        default:
          return await parseInlines(node.nodes, context: newCtx);
      }
    }
    return [];
  }

  List<DocxInline> _parseTextNode(String text, HtmlStyleContext ctx) {
    // HTML collapses runs of whitespace (including newlines from
    // pretty-printed markup) into a single space; only whitespace-only
    // text nodes (indentation between sibling tags) are dropped entirely.
    final collapsed = collapseHtmlWhitespace(text);
    if (collapsed.trim().isEmpty) return [];

    // Check for checkbox patterns (allow leading whitespace collapsed
    // above from e.g. indentation before the marker).
    final leftTrimmed = collapsed.trimLeft();
    if (leftTrimmed.startsWith('[ ] ')) {
      return [
        DocumentBuilder.buildCheckbox(
          isChecked: false,
          fontSize: ctx.fontSize,
          fontWeight: ctx.fontWeight,
          fontStyle: ctx.fontStyle,
          color: ctx.colorHex != null ? DocxColor(ctx.colorHex!) : null,
        ),
        createText(leftTrimmed.substring(4), ctx)
      ];
    } else if (leftTrimmed.startsWith('[x] ') ||
        leftTrimmed.startsWith('[X] ')) {
      return [
        DocumentBuilder.buildCheckbox(
          isChecked: true,
          fontSize: ctx.fontSize,
          fontWeight: ctx.fontWeight,
          fontStyle: ctx.fontStyle,
          color: ctx.colorHex != null ? DocxColor(ctx.colorHex!) : null,
        ),
        createText(leftTrimmed.substring(4), ctx)
      ];
    }

    return [createText(collapsed, ctx)];
  }

  List<DocxInline> _parseInput(dom.Element node, HtmlStyleContext newCtx) {
    final type = node.attributes['type']?.toLowerCase();
    if (type == 'checkbox') {
      return [
        DocumentBuilder.buildCheckbox(
          isChecked: node.attributes.containsKey('checked'),
          fontSize: newCtx.fontSize,
          fontWeight: newCtx.fontWeight,
          fontStyle: newCtx.fontStyle,
          color: newCtx.colorHex != null ? DocxColor(newCtx.colorHex!) : null,
        )
      ];
    }
    return [];
  }

  List<DocxInline> _parseCode(dom.Element node, HtmlStyleContext ctx) {
    final text = _getText(node);
    final lines = text.split('\n');
    final results = <DocxInline>[];

    for (var i = 0; i < lines.length; i++) {
      results.add(DocxText.code(lines[i],
          fontSize: ctx.fontSize,
          shadingFill: ctx.shadingFill,
          color: ctx.colorHex != null
              ? DocxColor(ctx.colorHex!)
              : DocxColor.black));
      if (i < lines.length - 1) {
        results.add(DocxLineBreak());
      }
    }
    return results;
  }

  DocxText createText(String text, HtmlStyleContext ctx) {
    return DocxText(
      text,
      fontWeight: ctx.fontWeight,
      fontStyle: ctx.fontStyle,
      decorations: ctx.decorations,
      color: ctx.colorHex != null ? DocxColor(ctx.colorHex!) : DocxColor.black,
      fontSize: ctx.fontSize,
      highlight: ctx.highlight,
      shadingFill: ctx.shadingFill,
      href: ctx.href,
      isSuperscript: ctx.isSuperscript,
      isSubscript: ctx.isSubscript,
      isAllCaps: ctx.isAllCaps,
      isSmallCaps: ctx.isSmallCaps,
      isDoubleStrike: ctx.isDoubleStrike,
      isOutline: ctx.isOutline,
      isShadow: ctx.isShadow,
      isEmboss: ctx.isEmboss,
      isImprint: ctx.isImprint,
    );
  }

  String _getText(dom.Node node) {
    if (node is dom.Text) return node.text;
    if (node is dom.Element) return node.text;
    return '';
  }
}
