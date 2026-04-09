import 'package:csslib/parser.dart' as css_parser;
import 'package:csslib/visitor.dart' as css;
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:htmltopdfwidgets/src/browser/render_node.dart';
import 'package:pdf/pdf.dart'; // For PdfColors
import 'package:pdf/widgets.dart'; // For FontWeight, etc.

import '../htmltagstyles.dart';
import 'css_style.dart';

/// [HtmlParser] parses HTML strings into a tree of [RenderNode]s.
///
/// It handles:
/// - Parsing HTML using the `html` package.
/// - Applying default styles for HTML tags (e.g., h1, p, b).
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

  /// Parsed CSS rules from <style> tags
  final List<css.RuleSet> _styleRules = [];

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

  /// Parses the HTML string and returns the root [RenderNode].
  RenderNode parse() {
    final document = html_parser.parse(htmlString);

    // Parse <style> tags
    _parseStyleTags(document);

    final body = document.body;

    if (body == null) {
      return RenderNode(tagName: 'body', style: baseStyle);
    }

    return _parseElement(body, baseStyle);
  }

  void _parseStyleTags(dom.Document document) {
    final styleTags = document.getElementsByTagName('style');
    for (var styleTag in styleTags) {
      if (styleTag.text.isNotEmpty) {
        try {
          final stylesheet = css_parser.parse(styleTag.text);
          for (var rule in stylesheet.topLevels) {
            if (rule is css.RuleSet) {
              _styleRules.add(rule);
            }
          }
        } catch (e) {
          // Ignore invalid CSS
          print('Error parsing CSS: $e');
        }
      }
    }
  }

  /// Recursively parses a DOM element into a [RenderNode].
  ///
  /// [element] is the DOM element to parse.
  /// [parentStyle] is the computed style of the parent node, used for inheritance.
  RenderNode _parseElement(dom.Element element, CSSStyle parentStyle) {
    // 1. Get default style for this tag
    final tagDefaultStyle = _getDefaultStyleForTag(element.localName ?? '');

    // 2. Parse inline style
    final inlineStyleString = element.attributes['style'] ?? '';
    final inlineStyle = CSSStyle.parse(inlineStyleString);

    // 3. Compute final style: parent -> tagDefault -> matchedCSS -> attributes -> inline
    // Start with empty style that inherits only inheritable properties from parent
    // This ensures backgroundColor (non-inherited in CSS) is NOT passed to children
    var computedStyle = const CSSStyle().inheritFrom(parentStyle);
    computedStyle = computedStyle.merge(tagDefaultStyle);

    // 3.1 Apply matched CSS rules from <style> blocks
    final matchedRules = _matchRules(element);
    for (var declarationGroup in matchedRules) {
      final ruleStyle = _styleFromDeclaration(declarationGroup);
      computedStyle = computedStyle.merge(ruleStyle);
    }

    // 3.1.1 Apply block class-based styles from tagStyle
    final classAttr = element.attributes['class'];
    if (classAttr != null && classAttr.isNotEmpty && tagStyle.blockClassStyles.isNotEmpty) {
      for (final className in classAttr.split(RegExp(r'\s+'))) {
        if (className.isEmpty) continue;
        final classStyle = tagStyle.blockClassStyles[className];
        if (classStyle != null) {
          computedStyle = computedStyle.merge(_convertBlockTagStyleToCSSStyle(classStyle));
        }
      }
    }

    // 3.2 Map HTML attributes to CSS styles (Legacy compatibility)
    final attributeStyle = _parseAttributesToStyle(element.attributes);
    computedStyle = computedStyle.merge(attributeStyle);

    computedStyle = computedStyle.merge(inlineStyle);

    final children = <RenderNode>[];

    for (var node in element.nodes) {
      if (node is dom.Element) {
        children.add(_parseElement(node, computedStyle));
      } else if (node is dom.Text) {
        var text = node.text;
        if (text.trim().isNotEmpty) {
          text = _sanitizeText(text);

          children.add(RenderNode(
            tagName: '#text',
            style: computedStyle,
            text: text,
          ));
        }
      }
    }

    return RenderNode(
      tagName: element.localName ?? 'div',
      style: computedStyle,
      attributes: element.attributes
          .map((key, value) => MapEntry(key.toString(), value)),
      children: children,
    );
  }

  /// Sanitizes text to avoid crashes with unsupported glyphs.
  /// Replaces problematic characters with safe alternatives.
  String _sanitizeText(String text) {
    return text
        .replaceAll('\u2011', '-') // Non-breaking hyphen
        .replaceAll('\u00A0', ' ') // Non-breaking space
        .replaceAll('\u200B', '') // Zero width space
        .replaceAll('\u200C', '') // Zero width non-joiner
        .replaceAll('\u200D', '') // Zero width joiner
        .replaceAll('\u202F', ' ') // Narrow no-break space
        .replaceAll('\uFEFF', ''); // Byte order mark
  }

  /// Returns the default [CSSStyle] for a given HTML tag.
  ///
  /// This method also applies overrides from [tagStyle].
  CSSStyle _getDefaultStyleForTag(String tagName) {
    CSSStyle style;
    switch (tagName.toLowerCase()) {
      case 'h1':
        style = const CSSStyle(
            fontSize: 24.0,
            fontWeight: FontWeight.bold,
            display: Display.block,
            margin: EdgeInsets.only(bottom: 8.0));
        if (tagStyle.h1Style != null) {
          style = style.merge(_convertTextStyleToCSSStyle(tagStyle.h1Style!));
        }
        if (tagStyle.headingMargins != null &&
            tagStyle.headingMargins!.containsKey(1)) {
          style = style.merge(CSSStyle(margin: tagStyle.headingMargins![1]));
        }
        return style;
      case 'h2':
        style = const CSSStyle(
            fontSize: 18.0,
            fontWeight: FontWeight.bold,
            display: Display.block,
            margin: EdgeInsets.only(bottom: 6.0));
        if (tagStyle.h2Style != null) {
          style = style.merge(_convertTextStyleToCSSStyle(tagStyle.h2Style!));
        }
        if (tagStyle.headingMargins != null &&
            tagStyle.headingMargins!.containsKey(2)) {
          style = style.merge(CSSStyle(margin: tagStyle.headingMargins![2]));
        }
        return style;
      case 'h3':
        style = const CSSStyle(
            fontSize: 16.0,
            fontWeight: FontWeight.bold,
            display: Display.block,
            margin: EdgeInsets.only(bottom: 5.0));
        if (tagStyle.h3Style != null) {
          style = style.merge(_convertTextStyleToCSSStyle(tagStyle.h3Style!));
        }
        if (tagStyle.headingMargins != null &&
            tagStyle.headingMargins!.containsKey(3)) {
          style = style.merge(CSSStyle(margin: tagStyle.headingMargins![3]));
        }
        return style;
      case 'h4':
        style = const CSSStyle(
            fontSize: 14.0,
            fontWeight: FontWeight.bold,
            display: Display.block,
            margin: EdgeInsets.only(bottom: 4.0));
        if (tagStyle.h4Style != null) {
          style = style.merge(_convertTextStyleToCSSStyle(tagStyle.h4Style!));
        }
        if (tagStyle.headingMargins != null &&
            tagStyle.headingMargins!.containsKey(4)) {
          style = style.merge(CSSStyle(margin: tagStyle.headingMargins![4]));
        }
        return style;
      case 'h5':
        style = const CSSStyle(
            fontSize: 12.0,
            fontWeight: FontWeight.bold,
            display: Display.block,
            margin: EdgeInsets.only(bottom: 3.0));
        if (tagStyle.h5Style != null) {
          style = style.merge(_convertTextStyleToCSSStyle(tagStyle.h5Style!));
        }
        if (tagStyle.headingMargins != null &&
            tagStyle.headingMargins!.containsKey(5)) {
          style = style.merge(CSSStyle(margin: tagStyle.headingMargins![5]));
        }
        return style;
      case 'h6':
        style = const CSSStyle(
            fontSize: 10.0,
            fontWeight: FontWeight.bold,
            display: Display.block,
            margin: EdgeInsets.only(bottom: 2.0));
        if (tagStyle.h6Style != null) {
          style = style.merge(_convertTextStyleToCSSStyle(tagStyle.h6Style!));
        }
        if (tagStyle.headingMargins != null &&
            tagStyle.headingMargins!.containsKey(6)) {
          style = style.merge(CSSStyle(margin: tagStyle.headingMargins![6]));
        }
        return style;
      case 'p':
        style = const CSSStyle(
            display: Display.block, margin: EdgeInsets.only(bottom: 4.0));
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
        style = const CSSStyle(
            fontStyle: FontStyle.italic, display: Display.inline);
        if (tagStyle.italicStyle != null) {
          style =
              style.merge(_convertTextStyleToCSSStyle(tagStyle.italicStyle!));
        }
        return style;
      case 'u':
        return const CSSStyle(
            textDecoration: TextDecoration.underline, display: Display.inline);
      case 'a':
        style = const CSSStyle(
            textDecoration: TextDecoration.underline,
            color: PdfColors.blue,
            display: Display.inline);
        if (tagStyle.linkStyle != null) {
          style = style.merge(_convertTextStyleToCSSStyle(tagStyle.linkStyle!));
        }
        return style;
      case 'ul':
      case 'ol':
        style = const CSSStyle(
            display: Display.block,
            margin: EdgeInsets.only(bottom: 4.0),
            padding: EdgeInsets.only(left: 20.0));
        if (tagStyle.listMargin != null) {
          style = style.merge(CSSStyle(margin: tagStyle.listMargin));
        }
        return style;
      case 'li':
        return const CSSStyle(display: Display.block);
      case 'div':
      case 'header':
      case 'footer':
      case 'main':
      case 'nav':
      case 'section':
      case 'article':
      case 'aside':
        return const CSSStyle(display: Display.block);
      case 'span':
        return const CSSStyle(display: Display.inline);
      case 'blockquote':
        style = const CSSStyle(
            display: Display.block,
            margin: EdgeInsets.symmetric(vertical: 4.0, horizontal: 20.0),
            fontStyle: FontStyle.italic);
        if (tagStyle.quoteBarColor != null) {
          // We can't easily pass quoteBarColor to CSSStyle as it's specific to the blockquote border
          // But we can use it for border color if we map it
          style = style.merge(CSSStyle(
              borderLeft: Border(
                  left: BorderSide(color: tagStyle.quoteBarColor!, width: 3))));
        }
        return style;
      case 'pre':
        style = const CSSStyle(
            display: Display.block,
            fontFamily: 'Courier',
            margin: EdgeInsets.only(bottom: 4.0),
            backgroundColor: PdfColors.grey200,
            padding: EdgeInsets.all(8.0));
        style = style.merge(
            CSSStyle(backgroundColor: tagStyle.codeBlockBackgroundColor));
        return style;
      case 'code':
        style = const CSSStyle(
            display: Display.inline,
            fontFamily: 'Courier',
            backgroundColor: PdfColors.grey200);
        if (tagStyle.codeStyle != null) {
          style = style.merge(_convertTextStyleToCSSStyle(tagStyle.codeStyle!));
        }

        style = style.merge(
            CSSStyle(backgroundColor: tagStyle.codeBlockBackgroundColor));
        return style;
      case 'hr':
        style = const CSSStyle(
            display: Display.block,
            margin: EdgeInsets.symmetric(vertical: 4.0),
            borderBottom: Border(
                bottom: BorderSide(width: 1.0, color: PdfColors.grey400)));
        style = style.merge(CSSStyle(
            borderBottom: Border(
                bottom: BorderSide(
                    width: tagStyle.dividerthickness,
                    color: tagStyle.dividerColor))));
        return style;
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
        style = const CSSStyle(
            display: Display.block, margin: EdgeInsets.only(bottom: 4.0));
        return style;
      case 'input':
        // Checkboxes and other inputs should be block so PdfBuilder handles them
        return const CSSStyle(display: Display.block);
      case 'label':
        return const CSSStyle(display: Display.inline);
      default:
        return const CSSStyle();
    }
  }

  CSSStyle _convertBlockTagStyleToCSSStyle(BlockTagStyle blockStyle) {
    return CSSStyle(
      color: blockStyle.textColor,
      backgroundColor: blockStyle.backgroundColor,
      fontSize: blockStyle.fontSize,
      fontWeight: blockStyle.fontWeight,
      fontStyle: blockStyle.fontStyle,
      textAlign: blockStyle.textAlign,
      lineHeight: blockStyle.lineHeight,
      padding: blockStyle.padding != null
          ? EdgeInsets.all(blockStyle.padding!)
          : null,
      margin: blockStyle.margin != null
          ? EdgeInsets.all(blockStyle.margin!)
          : null,
      border: blockStyle.borderColor != null && blockStyle.borderWidth > 0
          ? Border.all(color: blockStyle.borderColor!, width: blockStyle.borderWidth)
          : null,
      borderRadius: blockStyle.borderRadius,
    );
  }

  /// Converts a [TextStyle] to a [CSSStyle].
  CSSStyle _convertTextStyleToCSSStyle(TextStyle textStyle) {
    return CSSStyle(
      color: textStyle.color,
      fontSize: textStyle.fontSize,
      fontWeight: textStyle.fontWeight,
      fontStyle: textStyle.fontStyle,
      textDecoration: textStyle.decoration,
      // fontFamily: textStyle.fontFamily, // Not available in pdf package TextStyle
      // TextStyle doesn't have margin/padding/display, so we only map text properties
    );
  }

  /// Parses HTML attributes (width, height, align, border, bgcolor, color) into CSSStyle.
  /// This provides compatibility with legacy HTML that uses attributes instead of CSS.
  CSSStyle _parseAttributesToStyle(Map<Object, String> attributes) {
    double? width;
    double? height;
    TextAlign? textAlign;
    Border? border;
    PdfColor? backgroundColor;
    PdfColor? color;

    // Parse width attribute
    final widthAttr = attributes['width'];
    if (widthAttr != null) {
      // Handle percentage widths (we'll just parse the number for now)
      final widthValue = widthAttr.replaceAll('%', '').replaceAll('px', '');
      width = double.tryParse(widthValue);
    }

    // Parse height attribute
    final heightAttr = attributes['height'];
    if (heightAttr != null) {
      final heightValue = heightAttr.replaceAll('%', '').replaceAll('px', '');
      height = double.tryParse(heightValue);
    }

    // Parse align attribute
    final alignAttr = attributes['align'];
    if (alignAttr != null) {
      switch (alignAttr.toLowerCase()) {
        case 'left':
          textAlign = TextAlign.left;
          break;
        case 'right':
          textAlign = TextAlign.right;
          break;
        case 'center':
          textAlign = TextAlign.center;
          break;
        case 'justify':
          textAlign = TextAlign.justify;
          break;
      }
    }

    // Parse border attribute (used in tables)
    final borderAttr = attributes['border'];
    if (borderAttr != null) {
      final borderWidth = double.tryParse(borderAttr) ?? 1.0;
      if (borderWidth > 0) {
        border = Border.all(width: borderWidth, color: PdfColors.black);
      }
    }

    // Parse bgcolor attribute
    final bgcolorAttr = attributes['bgcolor'];
    if (bgcolorAttr != null) {
      backgroundColor = _parseColorValue(bgcolorAttr);
    }

    // Parse color attribute
    final colorAttr = attributes['color'];
    if (colorAttr != null) {
      color = _parseColorValue(colorAttr);
    }

    return CSSStyle(
      width: width,
      height: height,
      textAlign: textAlign,
      border: border,
      backgroundColor: backgroundColor,
      color: color,
    );
  }

  /// Parses a color value (hex, named colors, rgb/rgba)
  PdfColor? _parseColorValue(String value) {
    final trimmed = value.trim().toLowerCase();

    // Handle hex colors
    if (trimmed.startsWith('#')) {
      return PdfColor.fromHex(trimmed);
    }

    // Handle rgb/rgba
    if (trimmed.startsWith('rgb')) {
      final match = RegExp(
              r'rgba?\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)(?:\s*,\s*([\d.]+))?\s*\)')
          .firstMatch(trimmed);
      if (match != null) {
        final r = int.tryParse(match.group(1) ?? '0') ?? 0;
        final g = int.tryParse(match.group(2) ?? '0') ?? 0;
        final b = int.tryParse(match.group(3) ?? '0') ?? 0;
        final a = double.tryParse(match.group(4) ?? '1') ?? 1.0;
        return PdfColor(r / 255, g / 255, b / 255, a);
      }
    }

    // Handle named colors
    switch (trimmed) {
      case 'red':
        return PdfColors.red;
      case 'green':
        return PdfColors.green;
      case 'blue':
        return PdfColors.blue;
      case 'black':
        return PdfColors.black;
      case 'white':
        return PdfColors.white;
      case 'grey':
      case 'gray':
        return PdfColors.grey;
      case 'yellow':
        return PdfColors.yellow;
      case 'cyan':
        return PdfColors.cyan;
      case 'magenta':
      case 'purple':
        return PdfColors.purple;
      case 'orange':
        return PdfColors.orange;
      case 'pink':
        return PdfColors.pink;
      case 'brown':
        return PdfColors.brown;
      case 'lime':
        return PdfColors.lime;
      case 'teal':
        return PdfColors.teal;
      case 'indigo':
        return PdfColors.indigo;
      case 'navy':
        return PdfColors.blueGrey800;
      case 'maroon':
        return PdfColors.red800;
      case 'olive':
        return PdfColors.lime800;
      case 'aqua':
        return PdfColors.cyan;
      case 'fuchsia':
        return PdfColors.pink;
      case 'silver':
        return PdfColors.grey400;
      default:
        return null;
    }
  }

  /// Matches CSS rules to the given element.
  List<css.DeclarationGroup> _matchRules(dom.Element element) {
    final matchedDeclarations = <css.DeclarationGroup>[];

    for (var ruleSet in _styleRules) {
      for (var selectorGroup in ruleSet.selectorGroup!.selectors) {
        if (_matchesSelector(element, selectorGroup)) {
          matchedDeclarations.add(ruleSet.declarationGroup);
          break; // Apply same rule set only once per element
        }
      }
    }
    return matchedDeclarations;
  }

  /// Checks if a selector matches an element.
  /// Only basic selectors are supported: Tag, Class, ID.
  bool _matchesSelector(dom.Element element, css.Selector selector) {
    for (var simpleSelector in selector.simpleSelectorSequences) {
      if (!_matchesSimpleSelector(element, simpleSelector.simpleSelector)) {
        return false;
      }
    }
    return true;
  }

  bool _matchesSimpleSelector(
      dom.Element element, css.SimpleSelector selector) {
    if (selector is css.ElementSelector) {
      return selector.name.toLowerCase() == element.localName?.toLowerCase();
    } else if (selector is css.ClassSelector) {
      return element.classes.contains(selector.name);
    } else if (selector is css.IdSelector) {
      return element.id == selector.name;
    }
    // Universal selector (*) or others - treat as no match or handle if needed
    // For now, simple support
    return false;
  }

  /// Converts CSS declaration group to [CSSStyle].
  CSSStyle _styleFromDeclaration(css.DeclarationGroup declarationGroup) {
    var style = CSSStyle();
    for (var declaration in declarationGroup.declarations) {
      if (declaration is css.Declaration) {
        final property = declaration.property;
        final value = declaration.expression;
        if (value is css.Expressions) {
          style = style.merge(_cssPropertyToStyle(property, value));
        }
      }
    }
    return style;
  }

  CSSStyle _cssPropertyToStyle(String property, css.Expressions value) {
    // Helper to get text from expression
    String getValueText() {
      return value.expressions.map((e) {
        if (e is css.LiteralTerm) return e.text;
        if (e is css.NumberTerm) return e.text;
        if (e is css.HexColorTerm) return '#${e.text}';
        return e.toString();
      }).join(' ');
    }

    final textValue = getValueText();

    switch (property) {
      case 'color':
        return CSSStyle(color: _parseColorValue(textValue));
      case 'background-color':
      case 'background': // Partial support
        return CSSStyle(backgroundColor: _parseColorValue(textValue));
      case 'font-size':
        final size = double.tryParse(textValue
            .replaceAll('px', '')
            .replaceAll('pt', '')); // Basic parsing
        return CSSStyle(fontSize: size);
      case 'font-weight':
        if (textValue == 'bold' ||
            textValue == '700' ||
            textValue == '800' ||
            textValue == '900') {
          return const CSSStyle(fontWeight: FontWeight.bold);
        }
        return const CSSStyle(fontWeight: FontWeight.normal);
      case 'font-style':
        if (textValue == 'italic') {
          return const CSSStyle(fontStyle: FontStyle.italic);
        }
        return const CSSStyle(fontStyle: FontStyle.normal);
      case 'text-decoration':
        if (textValue.contains('underline')) {
          return const CSSStyle(textDecoration: TextDecoration.underline);
        }
        if (textValue.contains('line-through')) {
          return const CSSStyle(textDecoration: TextDecoration.lineThrough);
        }
        return const CSSStyle(textDecoration: TextDecoration.none);
      case 'text-align':
        if (textValue == 'center') {
          return const CSSStyle(textAlign: TextAlign.center);
        }
        if (textValue == 'right') {
          return const CSSStyle(textAlign: TextAlign.right);
        }
        if (textValue == 'justify') {
          return const CSSStyle(textAlign: TextAlign.justify);
        }
        return const CSSStyle(textAlign: TextAlign.left);
      case 'display':
        if (textValue == 'none') return const CSSStyle(display: Display.none);
        if (textValue == 'inline') {
          return const CSSStyle(display: Display.inline);
        }
        if (textValue == 'block') return const CSSStyle(display: Display.block);
        return const CSSStyle();
      case 'margin':
        // Simplified margin parsing (one value for all)
        // Improvements can be made to support 2 or 4 values
        final val = double.tryParse(textValue.replaceAll('px', '')) ?? 0;
        return CSSStyle(margin: EdgeInsets.all(val));
      case 'padding':
        final val = double.tryParse(textValue.replaceAll('px', '')) ?? 0;
        return CSSStyle(padding: EdgeInsets.all(val));
      case 'border':
        // Basic border parsing: "1px solid color"
        // We assume if border is present, it's valid for now or try to parse color
        if (textValue.contains('solid')) {
          final parts = textValue.split(' ');
          PdfColor color = PdfColors.black;
          double width = 1.0;
          for (var part in parts) {
            final c = _parseColorValue(part);
            if (c != null) color = c;
            if (part.endsWith('px')) {
              width = double.tryParse(part.replaceAll('px', '')) ?? 1.0;
            }
          }
          return CSSStyle(border: Border.all(color: color, width: width));
        }
        return const CSSStyle();
      case 'border-radius':
        final val = double.tryParse(textValue.replaceAll('px', '')) ?? 0;
        return CSSStyle(borderRadius: val);
      // Add more properties as needed
      default:
        return const CSSStyle();
    }
  }
}
