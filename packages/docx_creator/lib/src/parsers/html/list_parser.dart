import 'package:docx_creator/docx_creator.dart';
import 'package:html/dom.dart' as dom;

import 'block_parser.dart';
import 'inline_parser.dart';
import 'parser_context.dart';

/// Parses HTML list elements (ul, ol).
class HtmlListParser {
  final HtmlParserContext context;
  final HtmlInlineParser inlineParser;
  HtmlBlockParser? blockParser;

  HtmlListParser(this.context, this.inlineParser);

  void setBlockParser(HtmlBlockParser parser) {
    blockParser = parser;
  }

  /// Parse a list element (ul or ol).
  Future<DocxList> parseList(
    dom.Element element, {
    required bool ordered,
    int level = 0,
    HtmlStyleContext? styleContext,
  }) async {
    final items = <DocxListItem>[];
    final currentLevel = (styleContext != null && styleContext.listLevel >= 0)
        ? styleContext.listLevel
        : level;
    final startIndex = int.tryParse(element.attributes['start'] ?? '') ?? 1;

    // A nested sublist's own bullet/numbered style so it can be applied as
    // a per-item override once flattened below (DocxListItem has no way to
    // carry a nested DocxList directly - list items only hold inline
    // content - so the nested list's items are flattened into this one,
    // stamped with an override so at least their indentation/bullet glyph
    // still reflects their own type. See docx_creator/CLAUDE.md-style note:
    // full per-item numbering-format switching within a single numId would
    // require the abstract numbering definition to vary by level, which
    // this exporter doesn't currently support.
    DocxListStyle nestedOverrideStyle(DocxList nested) {
      // Keep an explicitly typed nested list's own style (e.g. `type="a"`).
      if (nested.style.numberFormat != DocxNumberFormat.decimal ||
          nested.style.bullet != const DocxListStyle().bullet) {
        return nested.style;
      }
      return nested.isOrdered ? DocxListStyle.decimal : DocxListStyle.disc;
    }

    for (var child in element.children) {
      if (child.localName == 'li') {
        if (blockParser != null) {
          final results = await blockParser!.parseChildren(child.nodes,
              styleContext: (styleContext ?? const HtmlStyleContext())
                  .copyWith(listLevel: currentLevel));
          for (var result in results) {
            if (result is DocxParagraph) {
              items.add(DocxListItem(result.children, level: currentLevel));
            } else if (result is DocxList) {
              for (var nestedItem in result.items) {
                items.add(nestedItem.copyWith(
                  overrideStyle:
                      nestedItem.overrideStyle ?? nestedOverrideStyle(result),
                ));
              }
            }
          }
          continue;
        }

        final inlines = <DocxInline>[];
        final nestedLists = <DocxList>[];

        for (var node in child.nodes) {
          if (node is dom.Element) {
            if (node.localName == 'ul') {
              nestedLists.add(await parseList(node,
                  ordered: false,
                  level: currentLevel + 1,
                  styleContext:
                      styleContext?.copyWith(listLevel: currentLevel + 1)));
              continue;
            } else if (node.localName == 'ol') {
              nestedLists.add(await parseList(node,
                  ordered: true,
                  level: currentLevel + 1,
                  styleContext:
                      styleContext?.copyWith(listLevel: currentLevel + 1)));
              continue;
            }
          }
          inlines.addAll(
              await inlineParser.parseInline(node, context: styleContext));
        }

        // Add current item
        if (inlines.isNotEmpty) {
          items.add(DocxListItem(inlines, level: currentLevel));
        }

        // Flatten nested items into this list, stamped with an override
        // reflecting the nested list's own type (see note above).
        for (var nested in nestedLists) {
          for (var nestedItem in nested.items) {
            items.add(nestedItem.copyWith(
              overrideStyle:
                  nestedItem.overrideStyle ?? nestedOverrideStyle(nested),
            ));
          }
        }
      }
    }

    return DocxList(
      items: items,
      isOrdered: ordered,
      startIndex: startIndex,
      style: _listStyleFor(element, ordered),
    );
  }

  /// Maps `type="a|A|i|I|1"` and CSS `list-style-type` to a list style.
  DocxListStyle _listStyleFor(dom.Element element, bool ordered) {
    final css =
        context.mergeStyles(element.attributes['style'], element.classes);
    final cssType =
        RegExp(r'list-style(?:-type)?\s*:\s*([^;]+)', caseSensitive: false)
            .firstMatch(css)
            ?.group(1)
            ?.toLowerCase();
    String? type = cssType;
    final attr = element.attributes['type'];
    if (type == null && attr != null) {
      type = switch (attr) {
        'a' => 'lower-alpha',
        'A' => 'upper-alpha',
        'i' => 'lower-roman',
        'I' => 'upper-roman',
        '1' => 'decimal',
        _ => attr.toLowerCase(),
      };
    }
    if (type == null) return const DocxListStyle();
    if (type.contains('lower-alpha') || type.contains('lower-latin')) {
      return DocxListStyle.lowerAlpha;
    }
    if (type.contains('upper-alpha') || type.contains('upper-latin')) {
      return DocxListStyle.upperAlpha;
    }
    if (type.contains('lower-roman')) return DocxListStyle.lowerRoman;
    if (type.contains('upper-roman')) return DocxListStyle.upperRoman;
    if (!ordered) {
      if (type.contains('circle')) return DocxListStyle.circle;
      if (type.contains('square')) return DocxListStyle.square;
    }
    return const DocxListStyle();
  }
}
