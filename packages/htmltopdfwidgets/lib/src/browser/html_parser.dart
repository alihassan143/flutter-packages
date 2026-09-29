import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:htmltopdfwidgets/src/browser/render_node.dart';
import 'package:pdf/pdf.dart'; // For PdfColors
import 'package:pdf/widgets.dart'; // For FontWeight, etc.

import '../htmltagstyles.dart';
import 'css_style.dart';
import 'css_stylesheet.dart';
import 'css_values.dart';

/// [HtmlParser] parses HTML strings into a tree of [RenderNode]s.
///
/// It handles:
/// - Parsing HTML using the `html` package.
/// - Applying default (browser-like) styles for HTML tags.
/// - `<style>` blocks with descendant/child/sibling combinators, attribute
///   and structural pseudo-class selectors, specificity and `!important`.
/// - Parsing inline CSS styles (e.g., `style="color: red"`).
/// - Parsing legacy HTML attributes (e.g., `width="100"`, `align="center"`).
/// - Merging custom [HtmlTagStyle] provided by the user.
class HtmlParser {
  /// The HTML string to parse.
  final String htmlString;

  /// The base style to apply to the root of the document.
  final CSSStyle baseStyle;

  /// Custom styles for specific HTML tags provided by the user.
  final HtmlTagStyle tagStyle;

  final CssStylesheet _stylesheet = CssStylesheet();

  /// Creates an instance of [HtmlParser].
  ///
  /// [htmlString] is the HTML content to parse.
  /// [baseStyle] is the default style for the document root.
  /// [tagStyle] allows overriding default styles for specific tags.
  HtmlParser({
    required this.htmlString,
    this.baseStyle = const CSSStyle(
      fontSize: 12.0,
      color: PdfColors.black,
      fontFamily: 'Roboto',
      fontWeight: FontWeight.normal,
      fontStyle: FontStyle.normal,
      textDecoration: TextDecoration.none,
    ),
    this.tagStyle = const HtmlTagStyle(),
  });

  static const _skippedTags = {
    'script',
    'style',
    'head',
    'title',
    'meta',
    'link',
    'template',
    'noscript',
  };

  /// Parses the HTML string and returns the root [RenderNode].
  RenderNode parse() {
    final document = html_parser.parse(htmlString);

    for (final styleTag in document.getElementsByTagName('style')) {
      _stylesheet.addSource(styleTag.text);
    }

    final body = document.body;

    if (body == null) {
      return RenderNode(tagName: 'body', style: baseStyle);
    }

    return _parseElement(body, baseStyle);
  }

  /// Recursively parses a DOM element into a [RenderNode].
  ///
  /// [element] is the DOM element to parse.
  /// [parentStyle] is the computed style of the parent node, used for inheritance.
  RenderNode _parseElement(dom.Element element, CSSStyle parentStyle) {
    final tag = (element.localName ?? '').toLowerCase();
    final parentFontSize = parentStyle.fontSize ?? baseFontSize;

    // Cascade: inherited -> tag defaults -> presentational attributes ->
    // <style> rules (by specificity/order) -> inline style -> !important.
    var computedStyle = const CSSStyle().inheritFrom(parentStyle);
    var listDepth = 0;
    for (var a = element.parent; a != null; a = a.parent) {
      final name = a.localName?.toLowerCase();
      if (name == 'ul' || name == 'ol' || name == 'menu') listDepth++;
    }
    computedStyle = computedStyle.merge(_getDefaultStyleForTag(
        tag, parentFontSize,
        parentTag: (element.parent?.localName ?? '').toLowerCase(),
        listDepth: listDepth));

    final declarations = <String, String>{};
    void put(Map<String, String> source) {
      source.forEach((k, v) {
        declarations.remove(k); // re-insert so later wins in parse order
        declarations[k] = v;
      });
    }

    put(_attributesToDeclarations(tag, element.attributes));
    final matched = _stylesheet.matching(element);
    for (final rule in matched) {
      put(rule.declarations);
    }
    put(_parseInlineDeclarations(element.attributes['style'] ?? ''));
    for (final rule in matched) {
      put(rule.importantDeclarations);
    }

    if (declarations.isNotEmpty) {
      computedStyle = computedStyle.merge(CSSStyle.fromDeclarations(
          declarations,
          parentFontSize: parentFontSize));
    }

    if (element.attributes.containsKey('hidden')) {
      computedStyle =
          computedStyle.merge(const CSSStyle(display: Display.none));
    }

    final preserveWhitespace = computedStyle.whiteSpace == WhiteSpace.pre ||
        computedStyle.whiteSpace == WhiteSpace.preWrap ||
        computedStyle.whiteSpace == WhiteSpace.preLine;

    final children = <RenderNode>[];

    for (var node in element.nodes) {
      if (node is dom.Element) {
        if (_skippedTags.contains(node.localName?.toLowerCase())) continue;
        children.add(_parseElement(node, computedStyle));
      } else if (node is dom.Text) {
        var text = node.text;
        if (text.isEmpty) continue;
        if (!preserveWhitespace && RegExp(r'^[ \t\n\r\f]*$').hasMatch(text)) {
          // Whitespace between elements is significant inline (it separates
          // words); the builder drops it at line starts/ends and between
          // blocks.
          text = ' ';
        } else {
          text = _sanitizeText(text);
        }

        children.add(RenderNode(
          tagName: '#text',
          style: computedStyle,
          text: text,
        ));
      }
    }

    return RenderNode(
      tagName: tag.isEmpty ? 'div' : tag,
      style: computedStyle,
      attributes: element.attributes
          .map((key, value) => MapEntry(key.toString(), value)),
      children: children,
    );
  }

  double get baseFontSize => baseStyle.fontSize ?? 12.0;

  Map<String, String> _parseInlineDeclarations(String css) {
    if (css.trim().isEmpty) return const {};
    final out = <String, String>{};
    var depth = 0;
    final buf = StringBuffer();
    void flush() {
      final decl = buf.toString();
      buf.clear();
      final idx = decl.indexOf(':');
      if (idx <= 0) return;
      final prop = decl.substring(0, idx).trim().toLowerCase();
      final value = decl
          .substring(idx + 1)
          .trim()
          .replaceAll(RegExp(r'!\s*important$'), '')
          .trim();
      if (prop.isNotEmpty && value.isNotEmpty) out[prop] = value;
    }

    for (final ch in css.split('')) {
      if (ch == '(') depth++;
      if (ch == ')' && depth > 0) depth--;
      if (ch == ';' && depth == 0) {
        flush();
      } else {
        buf.write(ch);
      }
    }
    flush();
    return out;
  }

  /// Sanitizes text to avoid crashes with unsupported glyphs.
  /// Replaces problematic characters with safe alternatives.
  String _sanitizeText(String text) {
    return text
        .replaceAll('\u2011', '-') // Non-breaking hyphen
        .replaceAll('\u200B', '') // Zero width space
        .replaceAll('\u200C', '') // Zero width non-joiner
        .replaceAll('\u200D', '') // Zero width joiner
        .replaceAll('\u202F', '\u00A0') // Narrow no-break space
        .replaceAll('\uFEFF', ''); // Byte order mark
  }

  EdgeInsets _vMargin(double top, double bottom) =>
      EdgeInsets.only(top: top, bottom: bottom);

  /// Returns the default [CSSStyle] for a given HTML tag, modelled on the
  /// browser user-agent stylesheet (sizes are relative to the parent font
  /// size, so `defaultFontSize` scales everything consistently).
  ///
  /// This method also applies overrides from [tagStyle].
  CSSStyle _getDefaultStyleForTag(String tagName, double parentFontSize,
      {String parentTag = '', int listDepth = 0}) {
    final em = parentFontSize;
    CSSStyle style;
    switch (tagName) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        final level = int.parse(tagName.substring(1));
        const scales = [2.0, 1.5, 1.17, 1.0, 0.83, 0.67];
        const margins = [0.67, 0.83, 1.0, 1.33, 1.67, 2.33];
        final size = em * scales[level - 1];
        final margin = size * margins[level - 1];
        style = CSSStyle(
            fontSize: size,
            fontWeight: FontWeight.bold,
            display: Display.block,
            margin: _vMargin(margin, margin));
        if (tagStyle.headingStyle != null) {
          style =
              style.merge(_convertTextStyleToCSSStyle(tagStyle.headingStyle!));
        }
        final specific = [
          tagStyle.h1Style,
          tagStyle.h2Style,
          tagStyle.h3Style,
          tagStyle.h4Style,
          tagStyle.h5Style,
          tagStyle.h6Style,
        ][level - 1];
        if (specific != null) {
          style = style.merge(_convertTextStyleToCSSStyle(specific));
        }
        if (tagStyle.headingMargins != null &&
            tagStyle.headingMargins!.containsKey(level)) {
          style =
              style.merge(CSSStyle(margin: tagStyle.headingMargins![level]));
        }
        return style;
      case 'p':
        style = CSSStyle(display: Display.block, margin: _vMargin(em, em));
        if (tagStyle.paragraphStyle != null) {
          style = style
              .merge(_convertTextStyleToCSSStyle(tagStyle.paragraphStyle!));
        }
        if (tagStyle.paragraphMargin != null) {
          style = style.merge(CSSStyle(margin: tagStyle.paragraphMargin));
        }
        return style;
      case 'b':
      case 'strong':
        style = const CSSStyle(
            fontWeight: FontWeight.bold, display: Display.inline);
        if (tagStyle.boldStyle != null) {
          style = style.merge(_convertTextStyleToCSSStyle(tagStyle.boldStyle!));
        }
        return style;
      case 'i':
      case 'em':
      case 'cite':
      case 'dfn':
      case 'var':
        style = const CSSStyle(
            fontStyle: FontStyle.italic, display: Display.inline);
        if (tagStyle.italicStyle != null) {
          style =
              style.merge(_convertTextStyleToCSSStyle(tagStyle.italicStyle!));
        }
        return style;
      case 'u':
      case 'ins':
        return const CSSStyle(
            textDecoration: TextDecoration.underline, display: Display.inline);
      case 'a':
        style = const CSSStyle(
            textDecoration: TextDecoration.underline,
            color: PdfColor.fromInt(0xFF0000EE), // browser link blue
            display: Display.inline);
        if (tagStyle.linkStyle != null) {
          style = style.merge(_convertTextStyleToCSSStyle(tagStyle.linkStyle!));
        }
        return style;
      case 'ul':
      case 'ol':
      case 'menu':
        final nested = parentTag == 'li' ||
            parentTag == 'ul' ||
            parentTag == 'ol' ||
            parentTag == 'dd';
        style = CSSStyle(
            display: Display.block,
            // Explicit per-list default so a parent list's type doesn't
            // leak in through inheritance (like the UA stylesheet).
            listStyleType: tagName == 'ol'
                ? 'decimal'
                : const ['disc', 'circle', 'square'][listDepth % 3],
            margin: nested ? _vMargin(0, 0) : _vMargin(em, em),
            padding: const EdgeInsets.only(left: 30.0)); // 40px
        if (tagStyle.listMargin != null) {
          style = style.merge(CSSStyle(margin: tagStyle.listMargin));
        }
        return style;
      case 'li':
        return const CSSStyle(display: Display.block);
      case 'dl':
        return CSSStyle(display: Display.block, margin: _vMargin(em, em));
      case 'dt':
        return const CSSStyle(display: Display.block);
      case 'dd':
        return const CSSStyle(
            display: Display.block,
            margin: EdgeInsets.only(left: 30.0),
            marginMask: EdgeMask.left);
      case 'div':
      case 'header':
      case 'footer':
      case 'main':
      case 'nav':
      case 'section':
      case 'article':
      case 'aside':
      case 'figcaption':
      case 'details':
      case 'summary':
      case 'form':
      case 'fieldset':
        return const CSSStyle(display: Display.block);
      case 'address':
        return const CSSStyle(
            display: Display.block, fontStyle: FontStyle.italic);
      case 'center':
        return const CSSStyle(
            display: Display.block, textAlign: TextAlign.center);
      case 'figure':
        return CSSStyle(
            display: Display.block,
            margin: EdgeInsets.symmetric(vertical: em, horizontal: 30));
      case 'span':
      case 'abbr':
      case 'acronym':
      case 'time':
      case 'q':
        return const CSSStyle(display: Display.inline);
      case 'small':
        return CSSStyle(display: Display.inline, fontSize: em * 0.83);
      case 'big':
        return CSSStyle(display: Display.inline, fontSize: em * 1.2);
      case 'sup':
        return CSSStyle(
            display: Display.inline,
            fontSize: em * 0.83,
            baselineShift: BaselineShift.superscript);
      case 'sub':
        return CSSStyle(
            display: Display.inline,
            fontSize: em * 0.83,
            baselineShift: BaselineShift.subscript);
      case 'blockquote':
        // Browsers draw no bar; a left rule is kept as the package's
        // long-standing (and Markdown-friendly) quote style.
        return CSSStyle(
            display: Display.block,
            margin: EdgeInsets.symmetric(vertical: em, horizontal: 30.0),
            padding: const EdgeInsets.only(left: 10),
            paddingMask: EdgeMask.left,
            borderLeft: Border(
                left: BorderSide(
                    color: tagStyle.quoteBarColor ?? PdfColors.grey400,
                    width: 3)));
      case 'pre':
        style = CSSStyle(
            display: Display.block,
            fontFamily: 'Courier',
            fontSize: em * 0.875,
            whiteSpace: WhiteSpace.pre,
            margin: _vMargin(em, em),
            backgroundColor:
                tagStyle.codeDecoration?.color ?? tagStyle.codeblockColor,
            padding: const EdgeInsets.all(8.0));
        if (tagStyle.codeStyle != null) {
          style = style.merge(_convertTextStyleToCSSStyle(tagStyle.codeStyle!));
        }
        return style;
      case 'code':
      case 'kbd':
      case 'samp':
      case 'tt':
        style = CSSStyle(
            display: Display.inline,
            fontFamily: 'Courier',
            fontSize: parentTag == 'pre' ? null : em * 0.875,
            backgroundColor:
                parentTag == 'pre' ? null : tagStyle.codeBlockBackgroundColor);
        if (tagStyle.codeStyle != null) {
          style = style.merge(_convertTextStyleToCSSStyle(tagStyle.codeStyle!));
        }
        return style;
      case 'hr':
        return CSSStyle(
            display: Display.block,
            margin: _vMargin(em * 0.5, em * 0.5),
            borderBottom: Border(
                bottom: BorderSide(
                    width: tagStyle.dividerthickness,
                    color: tagStyle.dividerColor,
                    style: tagStyle.dividerBorderStyle ?? BorderStyle.solid)));
      case 'del':
      case 's':
      case 'strike':
        style = const CSSStyle(
            textDecoration: TextDecoration.lineThrough,
            display: Display.inline);
        if (tagStyle.strikeThrough != null) {
          style =
              style.merge(_convertTextStyleToCSSStyle(tagStyle.strikeThrough!));
        }

        return style;
      case 'mark':
        return const CSSStyle(
            backgroundColor: PdfColors.yellow, display: Display.inline);
      case 'br':
        return const CSSStyle(
            display: Display.inline); // Handled specially in builder/text
      case 'img':
        return const CSSStyle(display: Display.block);
      case 'input':
        // Checkboxes and other inputs should be block so PdfBuilder handles them
        return const CSSStyle(display: Display.block);
      case 'label':
        return const CSSStyle(display: Display.inline);
      case 'table':
        return const CSSStyle(display: Display.table);
      case 'tr':
        return const CSSStyle(display: Display.tableRow);
      case 'th':
        return const CSSStyle(
            display: Display.tableCell,
            fontWeight: FontWeight.bold,
            textAlign: TextAlign.center);
      case 'td':
        return const CSSStyle(display: Display.tableCell);
      case 'caption':
        return const CSSStyle(
            display: Display.block, textAlign: TextAlign.center);
      default:
        return const CSSStyle();
    }
  }

  /// Converts a [TextStyle] to a [CSSStyle].
  CSSStyle _convertTextStyleToCSSStyle(TextStyle textStyle) {
    return CSSStyle(
      color: textStyle.color,
      fontSize: textStyle.fontSize,
      fontWeight: textStyle.fontWeight,
      fontStyle: textStyle.fontStyle,
      textDecoration: textStyle.decoration,
      textDecorationColor: textStyle.decorationColor,
      textDecorationStyle: textStyle.decorationStyle,
      letterSpacing: textStyle.letterSpacing,
      backgroundColor: textStyle.background is BoxDecoration
          ? (textStyle.background as BoxDecoration).color
          : null,
    );
  }

  /// Maps presentational HTML attributes (width, height, align, bgcolor,
  /// color, face, size, valign, border, dir) to CSS declarations. They are
  /// applied before author CSS, as browsers do.
  Map<String, String> _attributesToDeclarations(
      String tag, Map<Object, String> attributes) {
    final out = <String, String>{};

    String? length(String? raw) {
      if (raw == null) return null;
      final v = raw.trim();
      if (v.endsWith('%')) return v;
      final n = double.tryParse(v.replaceAll('px', ''));
      return n == null ? null : '${n}px';
    }

    final width = length(attributes['width']);
    if (width != null) out['width'] = width;
    final height = length(attributes['height']);
    if (height != null) out['height'] = height;

    final align = attributes['align']?.toLowerCase();
    if (align != null) {
      if (tag == 'table' || tag == 'img') {
        if (align == 'center') out['margin'] = '0 auto';
      } else {
        out['text-align'] = align;
      }
    }

    final valign = attributes['valign'];
    if (valign != null) out['vertical-align'] = valign;

    final border = attributes['border'];
    if (border != null && (tag == 'table' || tag == 'img')) {
      final w = double.tryParse(border) ?? 1.0;
      out['border'] = w > 0 ? '${w}px solid black' : 'none';
    }

    final bgcolor = attributes['bgcolor'];
    if (bgcolor != null) out['background-color'] = _legacyColor(bgcolor);

    final color = attributes['color'];
    if (color != null) out['color'] = _legacyColor(color);
    // MathML presentation color (inherits like CSS color).
    final mathColor = attributes['mathcolor'];
    if (mathColor != null) out['color'] = mathColor;

    if (tag == 'font') {
      final face = attributes['face'];
      if (face != null) out['font-family'] = face;
      final size = attributes['size'];
      if (size != null) {
        const sizes = ['x-small', 'small', 'medium', 'large', 'x-large'];
        const sizesPx = [
          '10px',
          '13px',
          '16px',
          '18px',
          '24px',
          '32px',
          '48px'
        ];
        var n = int.tryParse(size.replaceAll('+', '').replaceAll('-', ''));
        if (n != null) {
          if (size.startsWith('+')) n = 3 + n;
          if (size.startsWith('-')) n = 3 - n;
          out['font-size'] = sizesPx[(n - 1).clamp(0, 6)];
        } else if (sizes.contains(size)) {
          out['font-size'] = size;
        }
      }
    }

    final dir = attributes['dir'];
    if (dir == 'rtl' || dir == 'ltr') out['direction'] = dir!;

    if (tag == 'ol' && attributes['type'] != null) {
      switch (attributes['type']) {
        case 'a':
          out['list-style-type'] = 'lower-alpha';
          break;
        case 'A':
          out['list-style-type'] = 'upper-alpha';
          break;
        case 'i':
          out['list-style-type'] = 'lower-roman';
          break;
        case 'I':
          out['list-style-type'] = 'upper-roman';
          break;
        case '1':
          out['list-style-type'] = 'decimal';
          break;
      }
    }
    if (tag == 'ul' && attributes['type'] != null) {
      out['list-style-type'] = attributes['type']!.toLowerCase();
    }

    return out;
  }

  /// Legacy color attributes allow bare hex without `#` (`bgcolor="ff0000"`).
  String _legacyColor(String value) {
    final v = value.trim();
    if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(v) &&
        CssValues.parseColor(v) == null) {
      return '#$v';
    }
    return v;
  }
}
