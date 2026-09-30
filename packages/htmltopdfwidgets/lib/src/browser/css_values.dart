import 'dart:math' as math;

import 'package:pdf/pdf.dart';

/// Helpers for parsing raw CSS value strings (colors, token lists).
class CssValues {
  CssValues._();

  /// Splits a CSS value on whitespace, keeping parenthesised groups such as
  /// `rgb(1, 2, 3)` intact.
  static List<String> splitTokens(String value) {
    final tokens = <String>[];
    final buf = StringBuffer();
    var depth = 0;
    for (final ch in value.trim().split('')) {
      if (ch == '(') depth++;
      if (ch == ')' && depth > 0) depth--;
      if (depth == 0 && (ch == ' ' || ch == '\t' || ch == '\n')) {
        if (buf.isNotEmpty) {
          tokens.add(buf.toString());
          buf.clear();
        }
      } else {
        buf.write(ch);
      }
    }
    if (buf.isNotEmpty) tokens.add(buf.toString());
    return tokens;
  }

  /// Returns true if [value] can be parsed as a color (including
  /// `transparent`, which parses to null in [parseColor]).
  static bool isColor(String value) {
    final v = value.trim().toLowerCase();
    return v == 'transparent' || v == 'currentcolor' || parseColor(v) != null;
  }

  /// Parses any CSS color: `#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`,
  /// `rgb()`/`rgba()` (comma or space syntax, numbers or percentages),
  /// `hsl()`/`hsla()` and all 148 CSS named colors. Returns null for
  /// `transparent` and anything unrecognised.
  static PdfColor? parseColor(String value) {
    final v = value.trim().toLowerCase();
    if (v.isEmpty || v == 'transparent' || v == 'none') return null;

    if (v.startsWith('#')) return _parseHex(v.substring(1));

    final fn = RegExp(r'^(rgba?|hsla?)\((.*)\)$').firstMatch(v);
    if (fn != null) {
      final name = fn.group(1)!;
      final args = fn
          .group(2)!
          .replaceAll('/', ' ')
          .replaceAll(',', ' ')
          .split(RegExp(r'\s+'))
          .where((s) => s.isNotEmpty)
          .toList();
      if (args.length < 3) return null;
      final alpha = args.length > 3 ? _parseAlpha(args[3]) : 1.0;
      if (name.startsWith('rgb')) {
        final r = _parseChannel(args[0]);
        final g = _parseChannel(args[1]);
        final b = _parseChannel(args[2]);
        if (r == null || g == null || b == null) return null;
        return PdfColor(r, g, b, alpha);
      }
      final h = double.tryParse(args[0].replaceAll('deg', ''));
      final s = _parsePercent(args[1]);
      final l = _parsePercent(args[2]);
      if (h == null || s == null || l == null) return null;
      return _hslToColor(h, s, l, alpha);
    }

    final hex = _named[v];
    if (hex != null) return _parseHex(hex);
    return null;
  }

  static PdfColor? _parseHex(String hex) {
    var h = hex;
    if (h.length == 3 || h.length == 4) {
      h = h.split('').map((c) => '$c$c').join();
    }
    if (h.length != 6 && h.length != 8) return null;
    final n = int.tryParse(h, radix: 16);
    if (n == null) return null;
    if (h.length == 6) {
      return PdfColor(
          ((n >> 16) & 0xFF) / 255, ((n >> 8) & 0xFF) / 255, (n & 0xFF) / 255);
    }
    return PdfColor(((n >> 24) & 0xFF) / 255, ((n >> 16) & 0xFF) / 255,
        ((n >> 8) & 0xFF) / 255, (n & 0xFF) / 255);
  }

  static double? _parseChannel(String s) {
    if (s.endsWith('%')) {
      final p = double.tryParse(s.substring(0, s.length - 1));
      return p == null ? null : (p / 100).clamp(0.0, 1.0);
    }
    final n = double.tryParse(s);
    return n == null ? null : (n / 255).clamp(0.0, 1.0);
  }

  static double _parseAlpha(String s) {
    if (s.endsWith('%')) {
      return ((double.tryParse(s.substring(0, s.length - 1)) ?? 100) / 100)
          .clamp(0.0, 1.0);
    }
    return (double.tryParse(s) ?? 1.0).clamp(0.0, 1.0);
  }

  static double? _parsePercent(String s) {
    final n = double.tryParse(s.replaceAll('%', ''));
    return n == null ? null : (n / 100).clamp(0.0, 1.0);
  }

  static PdfColor _hslToColor(double h, double s, double l, double a) {
    final hue = ((h % 360) + 360) % 360 / 360;
    if (s == 0) return PdfColor(l, l, l, a);
    final q = l < 0.5 ? l * (1 + s) : l + s - l * s;
    final p = 2 * l - q;
    double f(double t) {
      var tt = t;
      if (tt < 0) tt += 1;
      if (tt > 1) tt -= 1;
      if (tt < 1 / 6) return p + (q - p) * 6 * tt;
      if (tt < 1 / 2) return q;
      if (tt < 2 / 3) return p + (q - p) * (2 / 3 - tt) * 6;
      return p;
    }

    return PdfColor(
      math.max(0, math.min(1, f(hue + 1 / 3))),
      math.max(0, math.min(1, f(hue))),
      math.max(0, math.min(1, f(hue - 1 / 3))),
      a,
    );
  }

  static const Map<String, String> _named = {
    'aliceblue': 'f0f8ff',
    'antiquewhite': 'faebd7',
    'aqua': '00ffff',
    'aquamarine': '7fffd4',
    'azure': 'f0ffff',
    'beige': 'f5f5dc',
    'bisque': 'ffe4c4',
    'black': '000000',
    'blanchedalmond': 'ffebcd',
    'blue': '0000ff',
    'blueviolet': '8a2be2',
    'brown': 'a52a2a',
    'burlywood': 'deb887',
    'cadetblue': '5f9ea0',
    'chartreuse': '7fff00',
    'chocolate': 'd2691e',
    'coral': 'ff7f50',
    'cornflowerblue': '6495ed',
    'cornsilk': 'fff8dc',
    'crimson': 'dc143c',
    'cyan': '00ffff',
    'darkblue': '00008b',
    'darkcyan': '008b8b',
    'darkgoldenrod': 'b8860b',
    'darkgray': 'a9a9a9',
    'darkgreen': '006400',
    'darkgrey': 'a9a9a9',
    'darkkhaki': 'bdb76b',
    'darkmagenta': '8b008b',
    'darkolivegreen': '556b2f',
    'darkorange': 'ff8c00',
    'darkorchid': '9932cc',
    'darkred': '8b0000',
    'darksalmon': 'e9967a',
    'darkseagreen': '8fbc8f',
    'darkslateblue': '483d8b',
    'darkslategray': '2f4f4f',
    'darkslategrey': '2f4f4f',
    'darkturquoise': '00ced1',
    'darkviolet': '9400d3',
    'deeppink': 'ff1493',
    'deepskyblue': '00bfff',
    'dimgray': '696969',
    'dimgrey': '696969',
    'dodgerblue': '1e90ff',
    'firebrick': 'b22222',
    'floralwhite': 'fffaf0',
    'forestgreen': '228b22',
    'fuchsia': 'ff00ff',
    'gainsboro': 'dcdcdc',
    'ghostwhite': 'f8f8ff',
    'gold': 'ffd700',
    'goldenrod': 'daa520',
    'gray': '808080',
    'green': '008000',
    'greenyellow': 'adff2f',
    'grey': '808080',
    'honeydew': 'f0fff0',
    'hotpink': 'ff69b4',
    'indianred': 'cd5c5c',
    'indigo': '4b0082',
    'ivory': 'fffff0',
    'khaki': 'f0e68c',
    'lavender': 'e6e6fa',
    'lavenderblush': 'fff0f5',
    'lawngreen': '7cfc00',
    'lemonchiffon': 'fffacd',
    'lightblue': 'add8e6',
    'lightcoral': 'f08080',
    'lightcyan': 'e0ffff',
    'lightgoldenrodyellow': 'fafad2',
    'lightgray': 'd3d3d3',
    'lightgreen': '90ee90',
    'lightgrey': 'd3d3d3',
    'lightpink': 'ffb6c1',
    'lightsalmon': 'ffa07a',
    'lightseagreen': '20b2aa',
    'lightskyblue': '87cefa',
    'lightslategray': '778899',
    'lightslategrey': '778899',
    'lightsteelblue': 'b0c4de',
    'lightyellow': 'ffffe0',
    'lime': '00ff00',
    'limegreen': '32cd32',
    'linen': 'faf0e6',
    'magenta': 'ff00ff',
    'maroon': '800000',
    'mediumaquamarine': '66cdaa',
    'mediumblue': '0000cd',
    'mediumorchid': 'ba55d3',
    'mediumpurple': '9370db',
    'mediumseagreen': '3cb371',
    'mediumslateblue': '7b68ee',
    'mediumspringgreen': '00fa9a',
    'mediumturquoise': '48d1cc',
    'mediumvioletred': 'c71585',
    'midnightblue': '191970',
    'mintcream': 'f5fffa',
    'mistyrose': 'ffe4e1',
    'moccasin': 'ffe4b5',
    'navajowhite': 'ffdead',
    'navy': '000080',
    'oldlace': 'fdf5e6',
    'olive': '808000',
    'olivedrab': '6b8e23',
    'orange': 'ffa500',
    'orangered': 'ff4500',
    'orchid': 'da70d6',
    'palegoldenrod': 'eee8aa',
    'palegreen': '98fb98',
    'paleturquoise': 'afeeee',
    'palevioletred': 'db7093',
    'papayawhip': 'ffefd5',
    'peachpuff': 'ffdab9',
    'peru': 'cd853f',
    'pink': 'ffc0cb',
    'plum': 'dda0dd',
    'powderblue': 'b0e0e6',
    'purple': '800080',
    'rebeccapurple': '663399',
    'red': 'ff0000',
    'rosybrown': 'bc8f8f',
    'royalblue': '4169e1',
    'saddlebrown': '8b4513',
    'salmon': 'fa8072',
    'sandybrown': 'f4a460',
    'seagreen': '2e8b57',
    'seashell': 'fff5ee',
    'sienna': 'a0522d',
    'silver': 'c0c0c0',
    'skyblue': '87ceeb',
    'slateblue': '6a5acd',
    'slategray': '708090',
    'slategrey': '708090',
    'snow': 'fffafa',
    'springgreen': '00ff7f',
    'steelblue': '4682b4',
    'tan': 'd2b48c',
    'teal': '008080',
    'thistle': 'd8bfd8',
    'tomato': 'ff6347',
    'turquoise': '40e0d0',
    'violet': 'ee82ee',
    'wheat': 'f5deb3',
    'white': 'ffffff',
    'whitesmoke': 'f5f5f5',
    'yellow': 'ffff00',
    'yellowgreen': '9acd32',
  };
}
