import '../../core/enums.dart';

/// Utility functions for parsing CSS colors and borders.
class ColorUtils {
  ColorUtils._();

  /// Parse a CSS color value to hex string (without #).
  /// Supports: hex, rgb(), rgba(), and 141 CSS named colors.
  static String? parseColor(String val) {
    final trimmed = val.trim().toLowerCase();

    // Handle hex colors
    if (trimmed.startsWith('#')) {
      var hex = trimmed.substring(1).toUpperCase();
      if (hex.length == 3) {
        hex = '${hex[0]}${hex[0]}${hex[1]}${hex[1]}${hex[2]}${hex[2]}';
      }
      return hex.length == 6 ? hex : null;
    }

    // Handle rgb/rgba
    if (trimmed.startsWith('rgb')) {
      final match = RegExp(
              r'rgba?\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)(?:\s*,\s*[\d.]+)?\s*\)')
          .firstMatch(trimmed);
      if (match != null) {
        final r = int.tryParse(match.group(1) ?? '0') ?? 0;
        final g = int.tryParse(match.group(2) ?? '0') ?? 0;
        final b = int.tryParse(match.group(3) ?? '0') ?? 0;
        return '${toHex(r)}${toHex(g)}${toHex(b)}';
      }
    }

    // Handle hsl/hsla
    if (trimmed.startsWith('hsl')) {
      final match = RegExp(
              r'hsla?\s*\(\s*([\d.]+)\s*,\s*([\d.]+)%\s*,\s*([\d.]+)%(?:\s*,\s*[\d.]+)?\s*\)')
          .firstMatch(trimmed);
      if (match != null) {
        final h = double.tryParse(match.group(1) ?? '0') ?? 0;
        final s = double.tryParse(match.group(2) ?? '0') ?? 0;
        final l = double.tryParse(match.group(3) ?? '0') ?? 0;
        final rgb = _hslToRgb(h, s / 100, l / 100);
        return '${toHex(rgb[0])}${toHex(rgb[1])}${toHex(rgb[2])}';
      }
    }

    // CSS named colors lookup
    final namedColor = _cssColors[trimmed];
    if (namedColor != null) return namedColor;

    // Try raw hex without #
    if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(trimmed)) {
      return trimmed.toUpperCase();
    }

    return null;
  }

  /// Convert int to 2-digit hex string.
  static String toHex(int val) {
    return val.toRadixString(16).padLeft(2, '0').toUpperCase();
  }

  /// Default font size (points) used as the base for relative CSS length
  /// units (`em`, `rem`, `%`) when no better context is available.
  static const double defaultBaseFontSizePt = 12;

  /// Converts a CSS length value (e.g. `16px`, `1.2em`, `12pt`, `150%`) to
  /// points. Relative units (`em`/`rem`/`%`) resolve against
  /// [defaultBaseFontSizePt], since this parser doesn't track a full CSS
  /// cascade of computed font sizes.
  ///
  /// Returns null if [value] isn't a recognizable CSS length.
  static double? parseCssLengthToPoints(String value) {
    final match =
        RegExp(r'^(-?[\d.]+)\s*(px|pt|em|rem|%)?$').firstMatch(value.trim());
    if (match == null) return null;
    final number = double.tryParse(match.group(1)!);
    if (number == null) return null;

    switch (match.group(2)) {
      case 'pt':
      case null: // Bare numbers are historically treated as points here.
        return number;
      case 'px':
        return number * 0.75; // 96px == 1in == 72pt
      case 'em':
      case 'rem':
        return number * defaultBaseFontSizePt;
      case '%':
        return number / 100 * defaultBaseFontSizePt;
      default:
        return null;
    }
  }

  /// Converts HSL (hue in degrees, saturation/lightness as 0-1 fractions)
  /// to an `[r, g, b]` triple of 0-255 integers.
  static List<int> _hslToRgb(double h, double s, double l) {
    if (s == 0) {
      final gray = (l * 255).round();
      return [gray, gray, gray];
    }

    double hueToRgb(double p, double q, double t) {
      var tt = t;
      if (tt < 0) tt += 1;
      if (tt > 1) tt -= 1;
      if (tt < 1 / 6) return p + (q - p) * 6 * tt;
      if (tt < 1 / 2) return q;
      if (tt < 2 / 3) return p + (q - p) * (2 / 3 - tt) * 6;
      return p;
    }

    final q = l < 0.5 ? l * (1 + s) : l + s - l * s;
    final p = 2 * l - q;
    final hNorm = (h % 360) / 360;

    return [
      (hueToRgb(p, q, hNorm + 1 / 3) * 255).round(),
      (hueToRgb(p, q, hNorm) * 255).round(),
      (hueToRgb(p, q, hNorm - 1 / 3) * 255).round(),
    ];
  }

  /// Parse CSS border property value.
  static DocxBorderSide? parseCssBorder(String value) {
    if (value.contains('none') || value.contains('hidden')) return null;

    // Parse width
    int size = 4;
    if (value.contains('px')) {
      final wMatch = RegExp(r'(\d+)px').firstMatch(value);
      if (wMatch != null) {
        final px = int.tryParse(wMatch.group(1) ?? '1') ?? 1;
        size = (px * 6).toInt();
      }
    }

    // Parse color & style
    DocxColor color = DocxColor.black;
    DocxBorder borderStyle = DocxBorder.single;

    final parts = value.split(RegExp(r'\s+'));
    for (var part in parts) {
      final parsedColor = parseColor(part);
      if (parsedColor != null) {
        color = DocxColor(parsedColor);
        continue;
      }

      if (part == 'solid') {
        borderStyle = DocxBorder.single;
      } else if (part == 'double') {
        borderStyle = DocxBorder.double;
      } else if (part == 'dotted') {
        borderStyle = DocxBorder.dotted;
      } else if (part == 'dashed') {
        borderStyle = DocxBorder.dashed;
      } else if (part == 'thick') {
        borderStyle = DocxBorder.thick;
      }
    }

    return DocxBorderSide(style: borderStyle, size: size, color: color);
  }

  /// Parse a specific CSS border property from a style string.
  static DocxBorderSide? parseCssBorderProperty(String style, String property) {
    final regex = RegExp('$property:\\s*([^;]+)(?:;|\$)', caseSensitive: false);
    final match = regex.firstMatch(style);
    if (match != null) {
      return parseCssBorder(match.group(1)!);
    }
    return null;
  }

  /// Extracts a color-valued CSS property (e.g. `color`, `background-color`)
  /// from a style string and resolves it to a hex string via [parseColor],
  /// so named colors (`lightgreen`), `rgb()`/`rgba()`, and 3-digit hex are
  /// all recognized — not just literal 6-digit hex.
  ///
  /// The negative lookbehind on [property] avoids `color` matching inside
  /// `background-color`.
  static String? parseCssColorProperty(String style, String property) {
    final regex = RegExp(
      '(?<![-a-zA-Z])$property:\\s*[\'"]?'
      r"(#[A-Fa-f0-9]{3,8}|rgba?\([0-9.,\s]+\)|hsla?\([0-9.,%\s]+\)|[a-zA-Z]+)"
      '[\'"]?',
      caseSensitive: false,
    );
    final match = regex.firstMatch(style);
    if (match == null) return null;
    return parseColor(match.group(1)!);
  }

  /// W3C CSS3 Extended Color Keywords (141 named colors).
  static const _cssColors = <String, String>{
    // Basic colors
    'black': '000000',
    'white': 'FFFFFF',
    'red': 'FF0000',
    'green': '008000',
    'blue': '0000FF',
    'yellow': 'FFFF00',
    'cyan': '00FFFF',
    'magenta': 'FF00FF',
    'aqua': '00FFFF',
    'fuchsia': 'FF00FF',
    'lime': '00FF00',
    'maroon': '800000',
    'navy': '000080',
    'olive': '808000',
    'purple': '800080',
    'silver': 'C0C0C0',
    'teal': '008080',
    // Gray variations
    'gray': '808080',
    'grey': '808080',
    'darkgray': 'A9A9A9',
    'darkgrey': 'A9A9A9',
    'dimgray': '696969',
    'dimgrey': '696969',
    'lightgray': 'D3D3D3',
    'lightgrey': 'D3D3D3',
    'gainsboro': 'DCDCDC',
    'slategray': '708090',
    'slategrey': '708090',
    'lightslategray': '778899',
    'lightslategrey': '778899',
    'darkslategray': '2F4F4F',
    'darkslategrey': '2F4F4F',
    // Reds
    'indianred': 'CD5C5C',
    'lightcoral': 'F08080',
    'salmon': 'FA8072',
    'darksalmon': 'E9967A',
    'lightsalmon': 'FFA07A',
    'crimson': 'DC143C',
    'firebrick': 'B22222',
    'darkred': '8B0000',
    // Oranges
    'coral': 'FF7F50',
    'tomato': 'FF6347',
    'orangered': 'FF4500',
    'darkorange': 'FF8C00',
    'orange': 'FFA500',
    // Yellows
    'gold': 'FFD700',
    'lightyellow': 'FFFFE0',
    'lemonchiffon': 'FFFACD',
    'lightgoldenrodyellow': 'FAFAD2',
    'papayawhip': 'FFEFD5',
    'moccasin': 'FFE4B5',
    'peachpuff': 'FFDAB9',
    'palegoldenrod': 'EEE8AA',
    'khaki': 'F0E68C',
    'darkkhaki': 'BDB76B',
    // Greens
    'lawngreen': '7CFC00',
    'chartreuse': '7FFF00',
    'limegreen': '32CD32',
    'forestgreen': '228B22',
    'darkgreen': '006400',
    'greenyellow': 'ADFF2F',
    'yellowgreen': '9ACD32',
    'springgreen': '00FF7F',
    'mediumspringgreen': '00FA9A',
    'lightgreen': '90EE90',
    'palegreen': '98FB98',
    'darkseagreen': '8FBC8F',
    'mediumseagreen': '3CB371',
    'seagreen': '2E8B57',
    'olivedrab': '6B8E23',
    'darkolivegreen': '556B2F',
    // Blues
    'lightcyan': 'E0FFFF',
    'paleturquoise': 'AFEEEE',
    'aquamarine': '7FFFD4',
    'turquoise': '40E0D0',
    'mediumturquoise': '48D1CC',
    'darkturquoise': '00CED1',
    'cadetblue': '5F9EA0',
    'steelblue': '4682B4',
    'lightsteelblue': 'B0C4DE',
    'powderblue': 'B0E0E6',
    'lightblue': 'ADD8E6',
    'skyblue': '87CEEB',
    'lightskyblue': '87CEFA',
    'deepskyblue': '00BFFF',
    'dodgerblue': '1E90FF',
    'cornflowerblue': '6495ED',
    'royalblue': '4169E1',
    'mediumblue': '0000CD',
    'darkblue': '00008B',
    'midnightblue': '191970',
    // Purples
    'lavender': 'E6E6FA',
    'thistle': 'D8BFD8',
    'plum': 'DDA0DD',
    'violet': 'EE82EE',
    'orchid': 'DA70D6',
    'mediumorchid': 'BA55D3',
    'mediumpurple': '9370DB',
    'rebeccapurple': '663399',
    'blueviolet': '8A2BE2',
    'darkviolet': '9400D3',
    'darkorchid': '9932CC',
    'darkmagenta': '8B008B',
    'indigo': '4B0082',
    'slateblue': '6A5ACD',
    'darkslateblue': '483D8B',
    'mediumslateblue': '7B68EE',
    // Pinks
    'pink': 'FFC0CB',
    'lightpink': 'FFB6C1',
    'hotpink': 'FF69B4',
    'deeppink': 'FF1493',
    'mediumvioletred': 'C71585',
    'palevioletred': 'DB7093',
    // Browns
    'cornsilk': 'FFF8DC',
    'blanchedalmond': 'FFEBCD',
    'bisque': 'FFE4C4',
    'navajowhite': 'FFDEAD',
    'wheat': 'F5DEB3',
    'burlywood': 'DEB887',
    'tan': 'D2B48C',
    'rosybrown': 'BC8F8F',
    'sandybrown': 'F4A460',
    'goldenrod': 'DAA520',
    'darkgoldenrod': 'B8860B',
    'peru': 'CD853F',
    'chocolate': 'D2691E',
    'saddlebrown': '8B4513',
    'sienna': 'A0522D',
    'brown': 'A52A2A',
    // Whites
    'snow': 'FFFAFA',
    'honeydew': 'F0FFF0',
    'mintcream': 'F5FFFA',
    'azure': 'F0FFFF',
    'aliceblue': 'F0F8FF',
    'ghostwhite': 'F8F8FF',
    'whitesmoke': 'F5F5F5',
    'seashell': 'FFF5EE',
    'beige': 'F5F5DC',
    'oldlace': 'FDF5E6',
    'floralwhite': 'FFFAF0',
    'ivory': 'FFFFF0',
    'antiquewhite': 'FAEBD7',
    'linen': 'FAF0E6',
    'lavenderblush': 'FFF0F5',
    'mistyrose': 'FFE4E1',
  };
}
