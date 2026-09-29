import 'package:docx_creator/docx_creator.dart';
import 'package:html/dom.dart' as dom;

import 'block_parser.dart';
import 'color_utils.dart';
import 'inline_parser.dart';
import 'parser_context.dart';

/// Parses HTML table elements.
class HtmlTableParser {
  final HtmlParserContext context;
  final HtmlInlineParser inlineParser;
  HtmlBlockParser? blockParser;

  HtmlTableParser(this.context, this.inlineParser);

  void setBlockParser(HtmlBlockParser parser) {
    blockParser = parser;
  }

  /// Parse a table element.
  Future<DocxTable> parseTable(dom.Element element) async {
    final rows = <DocxTableRow>[];

    for (var child in element.children) {
      final childTag = child.localName?.toLowerCase();

      if (childTag == 'tbody' || childTag == 'thead' || childTag == 'tfoot') {
        final isHeaderSection = childTag == 'thead';
        for (var tr in child.children) {
          if (tr.localName?.toLowerCase() == 'tr') {
            final row =
                await _parseTableRow(tr, isHeaderSection: isHeaderSection);
            if (row != null) rows.add(row);
          }
        }
      } else if (childTag == 'tr') {
        final row = await _parseTableRow(child);
        if (row != null) rows.add(row);
      }
    }

    // Parse table style (borders)
    final styleStr =
        context.mergeStyles(element.attributes['style'], element.classes);

    DocxBorder border = DocxBorder.none;
    if (styleStr.contains('border')) {
      if (styleStr.contains('solid')) border = DocxBorder.single;
    }
    if (element.attributes.containsKey('border')) {
      if (element.attributes['border'] != '0') border = DocxBorder.single;
    }

    return DocxTable(
      rows: rows,
      style: DocxTableStyle(
        borderTop: ColorUtils.parseCssBorderProperty(styleStr, 'border-top') ??
            ColorUtils.parseCssBorderProperty(styleStr, 'border') ??
            (border != DocxBorder.none ? DocxBorderSide(style: border) : null),
        borderBottom: ColorUtils.parseCssBorderProperty(
                styleStr, 'border-bottom') ??
            ColorUtils.parseCssBorderProperty(styleStr, 'border') ??
            (border != DocxBorder.none ? DocxBorderSide(style: border) : null),
        borderLeft: ColorUtils.parseCssBorderProperty(
                styleStr, 'border-left') ??
            ColorUtils.parseCssBorderProperty(styleStr, 'border') ??
            (border != DocxBorder.none ? DocxBorderSide(style: border) : null),
        borderRight: ColorUtils.parseCssBorderProperty(
                styleStr, 'border-right') ??
            ColorUtils.parseCssBorderProperty(styleStr, 'border') ??
            (border != DocxBorder.none ? DocxBorderSide(style: border) : null),
      ),
    );
  }

  Future<DocxTableRow?> _parseTableRow(
    dom.Element tr, {
    bool isHeaderSection = false,
  }) async {
    final rowStyle = context.mergeStyles(tr.attributes['style'], tr.classes);
    final rowShadingFill =
        ColorUtils.parseCssColorProperty(rowStyle, 'background-color');
    final rowColorHex = ColorUtils.parseCssColorProperty(rowStyle, 'color');

    final cells = <DocxTableCell>[];
    for (var child in tr.children) {
      final tag = child.localName?.toLowerCase();
      if (tag == 'td' || tag == 'th') {
        final cell = await _parseTableCell(
          child,
          isHeader: isHeaderSection || tag == 'th',
          rowShadingFill: rowShadingFill,
          rowColorHex: rowColorHex,
        );
        cells.add(cell);
      }
    }

    if (cells.isEmpty) return null;
    return DocxTableRow(cells: cells, isHeader: isHeaderSection);
  }

  Future<DocxTableCell> _parseTableCell(
    dom.Element td, {
    bool isHeader = false,
    String? rowShadingFill,
    String? rowColorHex,
  }) async {
    final style = context.mergeStyles(td.attributes['style'], td.classes);

    // A cell's own background wins over its row's, which wins over the
    // default header shading.
    final shadingFill =
        ColorUtils.parseCssColorProperty(style, 'background-color') ??
            rowShadingFill ??
            (isHeader ? 'E0E0E0' : null);
    final colorHex =
        ColorUtils.parseCssColorProperty(style, 'color') ?? rowColorHex;

    final colSpan = int.tryParse(td.attributes['colspan'] ?? '1') ?? 1;
    final rowSpan = int.tryParse(td.attributes['rowspan'] ?? '1') ?? 1;

    final content = await _parseCellContent(
      td.nodes,
      isHeader: isHeader,
      colorHex: colorHex,
    );

    // Cell text-align (CSS or legacy `align`) applies to paragraphs that
    // don't set their own; header cells are centered like in browsers.
    final alignValue = RegExp(r'text-align\s*:\s*(\w+)', caseSensitive: false)
            .firstMatch(style)
            ?.group(1)
            ?.toLowerCase() ??
        td.attributes['align']?.toLowerCase() ??
        (td.localName == 'th' ? 'center' : null);
    final cellAlign = switch (alignValue) {
      'center' => DocxAlign.center,
      'right' || 'end' => DocxAlign.right,
      'justify' => DocxAlign.justify,
      _ => null,
    };
    final alignedContent = cellAlign == null
        ? content
        : content
            .map((b) => b is DocxParagraph && b.align == DocxAlign.left
                ? b.copyWith(align: cellAlign)
                : b)
            .toList();

    final valign = (RegExp(r'vertical-align\s*:\s*(\w+)', caseSensitive: false)
                .firstMatch(style)
                ?.group(1) ??
            td.attributes['valign'])
        ?.toLowerCase();
    final verticalAlign = switch (valign) {
      'top' => DocxVerticalAlign.top,
      'bottom' => DocxVerticalAlign.bottom,
      _ => DocxVerticalAlign.center,
    };

    return DocxTableCell(
      children: alignedContent,
      verticalAlign: verticalAlign,
      colSpan: colSpan,
      rowSpan: rowSpan,
      shadingFill: shadingFill,
      borderTop: ColorUtils.parseCssBorderProperty(style, 'border-top') ??
          ColorUtils.parseCssBorderProperty(style, 'border'),
      borderBottom: ColorUtils.parseCssBorderProperty(style, 'border-bottom') ??
          ColorUtils.parseCssBorderProperty(style, 'border'),
      borderLeft: ColorUtils.parseCssBorderProperty(style, 'border-left') ??
          ColorUtils.parseCssBorderProperty(style, 'border'),
      borderRight: ColorUtils.parseCssBorderProperty(style, 'border-right') ??
          ColorUtils.parseCssBorderProperty(style, 'border'),
      marginLeft: _lengthPropertyTwips(style, 'padding-left') ??
          _lengthPropertyTwips(style, 'margin-left'),
      marginRight: _lengthPropertyTwips(style, 'padding-right') ??
          _lengthPropertyTwips(style, 'margin-right'),
    );
  }

  /// Reads a CSS length property (e.g. `padding-left: 10px`) and converts
  /// it to twips (1/20th of a point), or null if not present.
  int? _lengthPropertyTwips(String style, String property) {
    final match = RegExp(
      '$property\\s*:\\s*(-?[\\d.]+\\s*(?:px|pt|em|rem|%)?)',
      caseSensitive: false,
    ).firstMatch(style);
    if (match == null) return null;
    final points = ColorUtils.parseCssLengthToPoints(match.group(1)!);
    return points != null ? (points * 20).round() : null;
  }

  Future<List<DocxBlock>> _parseCellContent(
    List<dom.Node> nodes, {
    bool isHeader = false,
    String? colorHex,
  }) async {
    if (blockParser != null) {
      // Seed the row/cell's own text color and header weight as inherited
      // style, the same way a nested <span style="..."> would inherit from
      // an ancestor, so it reaches text nodes even when the cell has no
      // per-run style of its own.
      final seedContext = HtmlStyleContext(
        colorHex: colorHex,
        fontWeight: isHeader ? DocxFontWeight.bold : DocxFontWeight.normal,
      );
      final results =
          await blockParser!.parseChildren(nodes, styleContext: seedContext);
      return results.whereType<DocxBlock>().toList();
    }
    final blocks = <DocxBlock>[];
    final inlines = <DocxInline>[];
    final color = colorHex != null ? DocxColor(colorHex) : null;

    void flushInlines() {
      if (inlines.isNotEmpty) {
        blocks.add(DocxParagraph(children: List.from(inlines)));
        inlines.clear();
      }
    }

    for (var node in nodes) {
      if (node is dom.Text) {
        final text = node.text.trim();
        if (text.isNotEmpty) {
          inlines.add(isHeader
              ? DocxText.bold(text, color: color)
              : DocxText(text, color: color));
        }
      } else if (node is dom.Element) {
        final tag = node.localName?.toLowerCase();

        if (tag == 'table') {
          flushInlines();
          // Recursively parse nested table
          final nestedTable = await parseTable(node);
          blocks.add(nestedTable);
        } else if (_isBlockTag(tag)) {
          flushInlines();
          // Parse as paragraph
          final nodeInlines = await inlineParser.parseInlines(node.nodes);
          if (nodeInlines.isNotEmpty) {
            blocks.add(DocxParagraph(children: nodeInlines));
          }
        } else {
          inlines.addAll(await inlineParser.parseInline(node));
        }
      }
    }

    flushInlines();

    if (blocks.isEmpty) {
      blocks.add(DocxParagraph(children: []));
    }

    return blocks;
  }

  bool _isBlockTag(String? tag) {
    if (tag == null) return false;
    return [
      'p',
      'div',
      'table',
      'ul',
      'ol',
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
