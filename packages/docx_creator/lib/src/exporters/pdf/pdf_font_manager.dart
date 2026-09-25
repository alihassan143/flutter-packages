import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'fonts/fallback_font_data.dart';
import 'pdf_document_writer.dart';
import 'ttf_parser.dart';

/// Represents an embedded TrueType font.
class EmbeddedFont {
  final String name;
  final Uint8List ttfData;
  final TtfParser metrics;
  final String fontRef;

  EmbeddedFont({
    required this.name,
    required this.ttfData,
    required this.metrics,
    required this.fontRef,
  });

  /// Gets width of a character in font units (scaled to 1000).
  int getCharWidth(int unicode) {
    return (metrics.getCharWidth(unicode) * 1000.0 / metrics.unitsPerEm)
        .round();
  }

  /// Measures text width in points.
  ///
  /// Iterates Unicode code points ([String.runes]), not UTF-16 code units -
  /// a character outside the Basic Multilingual Plane (most emoji, some
  /// rare CJK) is one rune but two UTF-16 code units, and iterating code
  /// units would measure it as two separate (invalid) glyphs.
  double measureText(String text, double fontSize) {
    var width = 0.0;
    for (final code in text.runes) {
      final charWidth = getCharWidth(code);
      width += charWidth * fontSize / 1000.0;
    }
    return width;
  }
}

/// Manages font resources and text encoding for PDF export.
///
/// Handles WinAnsi encoding, font selection, and embedded fonts.
class PdfFontManager {
  /// Standard PDF Type1 fonts
  static const String helvetica = 'Helvetica';
  static const String helveticaBold = 'Helvetica-Bold';
  static const String helveticaOblique = 'Helvetica-Oblique';
  static const String helveticaBoldOblique = 'Helvetica-BoldOblique';
  static const String courier = 'Courier';

  /// Font references used in content streams
  static const String fontRegular = '/F1';
  static const String fontBold = '/F2';
  static const String fontItalic = '/F3';
  static const String fontMono = '/F4';

  /// Bold+italic together. Named apart from the `/F1`-`/F4` standard refs
  /// and the embedded-font series (which starts at `/F5`) so adding it
  /// doesn't renumber anything.
  static const String fontBoldItalic = '/FBI';

  /// Average character width as fraction of font size (fallback for unknown chars)
  static const double avgCharWidth = 0.5;

  /// Helvetica character widths as fraction of font size (1000 units = 1.0)
  /// Based on standard Helvetica font metrics
  static const Map<int, double> _charWidths = {
    // Space and punctuation
    32: 0.278, // space
    33: 0.278, // !
    34: 0.355, // "
    35: 0.556, // #
    36: 0.556, // $
    37: 0.889, // %
    38: 0.667, // &
    39: 0.191, // '
    40: 0.333, // (
    41: 0.333, // )
    42: 0.389, // *
    43: 0.584, // +
    44: 0.278, // ,
    45: 0.333, // -
    46: 0.278, // .
    47: 0.278, // /
    // Numbers
    48: 0.556, // 0
    49: 0.556, // 1
    50: 0.556, // 2
    51: 0.556, // 3
    52: 0.556, // 4
    53: 0.556, // 5
    54: 0.556, // 6
    55: 0.556, // 7
    56: 0.556, // 8
    57: 0.556, // 9
    // Punctuation continued
    58: 0.278, // :
    59: 0.278, // ;
    60: 0.584, // <
    61: 0.584, // =
    62: 0.584, // >
    63: 0.556, // ?
    64: 1.015, // @
    // Uppercase letters
    65: 0.667, // A
    66: 0.667, // B
    67: 0.722, // C
    68: 0.722, // D
    69: 0.667, // E
    70: 0.611, // F
    71: 0.778, // G
    72: 0.722, // H
    73: 0.278, // I
    74: 0.500, // J
    75: 0.667, // K
    76: 0.556, // L
    77: 0.833, // M
    78: 0.722, // N
    79: 0.778, // O
    80: 0.667, // P
    81: 0.778, // Q
    82: 0.722, // R
    83: 0.667, // S
    84: 0.611, // T
    85: 0.722, // U
    86: 0.667, // V
    87: 0.944, // W
    88: 0.667, // X
    89: 0.667, // Y
    90: 0.611, // Z
    // Brackets and symbols
    91: 0.278, // [
    92: 0.278, // \
    93: 0.278, // ]
    94: 0.469, // ^
    95: 0.556, // _
    96: 0.333, // `
    // Lowercase letters
    97: 0.556, // a
    98: 0.556, // b
    99: 0.500, // c
    100: 0.556, // d
    101: 0.556, // e
    102: 0.278, // f
    103: 0.556, // g
    104: 0.556, // h
    105: 0.222, // i
    106: 0.222, // j
    107: 0.500, // k
    108: 0.222, // l
    109: 0.833, // m
    110: 0.556, // n
    111: 0.556, // o
    112: 0.556, // p
    113: 0.556, // q
    114: 0.333, // r
    115: 0.500, // s
    116: 0.278, // t
    117: 0.556, // u
    118: 0.500, // v
    119: 0.722, // w
    120: 0.500, // x
    121: 0.500, // y
    122: 0.500, // z
    123: 0.334, // {
    124: 0.260, // |
    125: 0.334, // }
    126: 0.584, // ~
  };

  /// Helvetica-Bold character widths as fraction of font size (1000 units = 1.0)
  /// These are noticeably wider than regular Helvetica
  static const Map<int, double> _charWidthsBold = {
    // Space and punctuation
    32: 0.278, // space
    33: 0.333, // !
    34: 0.474, // "
    35: 0.556, // #
    36: 0.556, // $
    37: 0.889, // %
    38: 0.722, // &
    39: 0.238, // '
    40: 0.333, // (
    41: 0.333, // )
    42: 0.389, // *
    43: 0.584, // +
    44: 0.278, // ,
    45: 0.333, // -
    46: 0.278, // .
    47: 0.278, // /
    // Numbers
    48: 0.556, // 0
    49: 0.556, // 1
    50: 0.556, // 2
    51: 0.556, // 3
    52: 0.556, // 4
    53: 0.556, // 5
    54: 0.556, // 6
    55: 0.556, // 7
    56: 0.556, // 8
    57: 0.556, // 9
    // Punctuation continued
    58: 0.333, // :
    59: 0.333, // ;
    60: 0.584, // <
    61: 0.584, // =
    62: 0.584, // >
    63: 0.611, // ?
    64: 0.975, // @
    // Uppercase letters - significantly wider in bold
    65: 0.722, // A
    66: 0.722, // B
    67: 0.722, // C
    68: 0.722, // D
    69: 0.667, // E
    70: 0.611, // F
    71: 0.778, // G
    72: 0.722, // H
    73: 0.278, // I
    74: 0.556, // J
    75: 0.722, // K
    76: 0.611, // L
    77: 0.833, // M
    78: 0.722, // N
    79: 0.778, // O
    80: 0.667, // P
    81: 0.778, // Q
    82: 0.722, // R
    83: 0.667, // S
    84: 0.611, // T
    85: 0.722, // U
    86: 0.667, // V
    87: 0.944, // W
    88: 0.667, // X
    89: 0.667, // Y
    90: 0.611, // Z
    // Brackets and symbols
    91: 0.333, // [
    92: 0.278, // \
    93: 0.333, // ]
    94: 0.584, // ^
    95: 0.556, // _
    96: 0.333, // `
    // Lowercase letters - also wider in bold
    97: 0.556, // a
    98: 0.611, // b
    99: 0.556, // c
    100: 0.611, // d
    101: 0.556, // e
    102: 0.333, // f
    103: 0.611, // g
    104: 0.611, // h
    105: 0.278, // i
    106: 0.278, // j
    107: 0.556, // k
    108: 0.278, // l
    109: 0.889, // m
    110: 0.611, // n
    111: 0.611, // o
    112: 0.611, // p
    113: 0.611, // q
    114: 0.389, // r
    115: 0.556, // s
    116: 0.333, // t
    117: 0.611, // u
    118: 0.556, // v
    119: 0.778, // w
    120: 0.556, // x
    121: 0.556, // y
    122: 0.500, // z
    123: 0.389, // {
    124: 0.280, // |
    125: 0.389, // }
    126: 0.584, // ~
  };

  /// Bold font width scaling factor - no longer needed with separate table
  @Deprecated('Use _charWidthsBold instead')
  static const double boldWidthFactor = 1.05;

  /// Embedded fonts
  final List<EmbeddedFont> _embeddedFonts = [];

  /// Gets the list of embedded fonts.
  List<EmbeddedFont> get embeddedFonts => List.unmodifiable(_embeddedFonts);

  /// Embeds a TrueType font and returns its font reference.
  String embedFont(String name, Uint8List ttfData) {
    // Check if already embedded
    for (final font in _embeddedFonts) {
      if (font.name == name) return font.fontRef;
    }

    final parser = TtfParser(ttfData)..parse();
    final fontRef = '/F${5 + _embeddedFonts.length}';
    _embeddedFonts.add(EmbeddedFont(
      name: name,
      ttfData: ttfData,
      metrics: parser,
      fontRef: fontRef,
    ));
    return fontRef;
  }

  /// Registers a custom font for use in the PDF.
  ///
  /// [fontFamily] is the name used to reference the font (e.g., "Roboto").
  /// [bytes] is the raw TTF/OTF data.
  void registerFont(String fontFamily, Uint8List bytes) {
    embedFont(fontFamily, bytes);
  }

  /// Gets an embedded font by its reference.
  EmbeddedFont? getEmbeddedFont(String fontRef) {
    for (final font in _embeddedFonts) {
      if (font.fontRef == fontRef) return font;
    }
    return null;
  }

  /// True if [text] contains a character with no WinAnsi representation -
  /// one that a standard PDF font can't render and [escapeText] would
  /// otherwise have to substitute with '?'.
  bool needsUnicodeFallback(String text) {
    for (final code in text.runes) {
      if (code >= 32 && code <= 255) continue;
      if (_unicodeToWinAnsi(code) != null) continue;
      return true;
    }
    return false;
  }

  String? _fallbackFontRef;

  /// Lazily embeds the bundled Unicode-broad fallback font (DejaVu Sans,
  /// Bitstream Vera License - see `fonts/DEJAVU_SANS_LICENSE.txt`) the
  /// first time it's actually needed, and returns its font reference.
  ///
  /// This exists so that text using a script the standard PDF fonts can't
  /// represent (Cyrillic, Greek, Vietnamese, and other scripts DejaVu Sans
  /// covers - not CJK or Arabic, which need dedicated shaping-aware fonts
  /// far larger than is reasonable to bundle unconditionally) still
  /// renders correctly by default, without the caller having to call
  /// `addFont` themselves. Embedding only happens on first use, so
  /// documents that don't need it pay no size/processing cost for it.
  String get fallbackUnicodeFontRef {
    return _fallbackFontRef ??=
        embedFont(_kFallbackFontName, base64Decode(kFallbackUnicodeFontBase64));
  }

  static const _kFallbackFontName = 'DejaVu Sans (docx_creator fallback)';

  /// Selects the appropriate font reference based on text properties.
  String selectFont({
    bool isBold = false,
    bool isItalic = false,
    bool isMono = false,
    String? fontFamily,
  }) {
    // Check for embedded font by family name
    if (fontFamily != null) {
      for (final font in _embeddedFonts) {
        if (font.name == fontFamily ||
            (font.name.toLowerCase() == fontFamily.toLowerCase())) {
          return font.fontRef;
        }
      }
    }

    if (isMono) return fontMono;
    if (isBold && isItalic) return fontBoldItalic;
    if (isBold) return fontBold;
    if (isItalic) return fontItalic;
    return fontRegular;
  }

  /// Measures the width of text in points using per-character widths.
  /// [isBold] uses Helvetica-Bold width table for accurate measurement.
  /// [fontRef] uses embedded font metrics if available.
  double measureText(String text, double fontSize,
      {bool isBold = false, String? fontRef}) {
    // Use embedded font metrics if available
    if (fontRef != null) {
      final embedded = getEmbeddedFont(fontRef);
      if (embedded != null) {
        return embedded.measureText(text, fontSize);
      }
    }

    // Select appropriate width table
    final widths = isBold ? _charWidthsBold : _charWidths;

    var width = 0.0;
    for (final code in text.runes) {
      // Use character-specific width or fallback to average
      final charWidth = widths[code] ?? avgCharWidth;
      width += charWidth * fontSize;
    }
    return width;
  }

  /// Escapes text for PDF string literals using WinAnsi encoding.
  ///
  /// Handles special characters and converts Unicode where possible. A
  /// standard PDF font (this method's only caller path - embedded fonts use
  /// [escapeTextHex] instead) has no glyphs outside WinAnsi at all, so a
  /// character with no mapping is substituted with '?' rather than
  /// silently vanishing from the output - callers who need the character
  /// to actually render should embed a font covering it via `addFont`.
  ///
  /// Iterates Unicode code points ([String.runes]), not UTF-16 code units,
  /// so a character outside the Basic Multilingual Plane is treated as one
  /// (unsupported, substituted) character rather than two stray ones.
  String escapeText(String text) {
    final buffer = StringBuffer();

    for (final code in text.runes) {
      // Handle special PDF characters
      switch (code) {
        case 0x5C: // backslash
          buffer.write('\\\\');
          break;
        case 0x28: // (
          buffer.write('\\(');
          break;
        case 0x29: // )
          buffer.write('\\)');
          break;
        default:
          // Check for common Unicode -> WinAnsi mappings
          final winAnsi = _unicodeToWinAnsi(code);
          if (winAnsi != null) {
            buffer.write('\\${winAnsi.toRadixString(8).padLeft(3, '0')}');
          } else if (code >= 32 && code <= 126) {
            // Standard ASCII printable
            buffer.writeCharCode(code);
          } else if (code >= 128 && code <= 255) {
            // Extended ASCII (WinAnsi range)
            buffer.write('\\${code.toRadixString(8).padLeft(3, '0')}');
          } else {
            // No WinAnsi representation for this character.
            buffer.write('?');
          }
      }
    }

    return buffer.toString();
  }

  /// Escapes text as hex string for embedded fonts (Hex encoded glyph IDs).
  ///
  /// For embedded fonts (Identity-H), we must map Unicode to Glyph IDs.
  /// Iterates Unicode code points ([String.runes]) so characters outside
  /// the Basic Multilingual Plane map to a single glyph lookup, not two.
  String escapeTextHex(String text, String fontRef) {
    final font = getEmbeddedFont(fontRef);
    if (font == null) return '';

    final sb = StringBuffer();
    for (final code in text.runes) {
      final gid = font.metrics.getGlyphId(code);
      sb.write(gid.toRadixString(16).padLeft(4, '0').toUpperCase());
    }
    return sb.toString();
  }

  /// Renders a char-code-32..126-indexed `/Widths` array (in 1000-unit
  /// glyph space) from one of the [_charWidths] / [_charWidthsBold] tables.
  String _widthsArrayString(Map<int, double> widths) {
    final buf = StringBuffer('[');
    for (var code = 32; code <= 126; code++) {
      final w = ((widths[code] ?? avgCharWidth) * 1000).round();
      buf.write(code == 32 ? '$w' : ' $w');
    }
    buf.write(']');
    return buf.toString();
  }

  /// Writes all font objects to the PDF document.
  ///
  /// Returns a map of font references to their object IDs.
  Map<String, int> writeFonts(PdfDocumentWriter writer) {
    final fontIds = <String, int>{};

    // 1. Write standard fonts (backward compatibility if needed, but we use them mostly as fallback)
    // We actually re-create them here to be clean.

    // Helper to write standard font. [widthsTable] picks the correct AFM
    // widths for the variant being declared (regular vs. bold have
    // meaningfully different advance widths); Courier is monospace so it
    // omits /Widths entirely and relies on the standard 14 font metrics.
    int writeStandardFont(
        String baseFont, String ref, Map<int, double>? widthsTable) {
      final widthsClause = widthsTable == null
          ? ''
          : '/FirstChar 32 /LastChar 126 /Widths ${_widthsArrayString(widthsTable)}';
      final dict = '<< /Type /Font /Subtype /Type1 /BaseFont /$baseFont '
          '/Encoding /WinAnsiEncoding $widthsClause >>';

      final id = writer.createObject(dict);
      fontIds[ref] = id;
      return id;
    }

    writeStandardFont('Helvetica', fontRegular, _charWidths);
    writeStandardFont('Helvetica-Bold', fontBold, _charWidthsBold);
    writeStandardFont('Helvetica-Oblique', fontItalic, _charWidths);
    // Bold-Oblique shares Bold's advance widths (real fonts, not scaled).
    writeStandardFont(helveticaBoldOblique, fontBoldItalic, _charWidthsBold);
    writeStandardFont('Courier', fontMono, null);

    // 2. Write embedded fonts
    for (final font in _embeddedFonts) {
      // A. Font File Stream
      // We wrap TTF in stream.
      // Filter can be FlateDecode for size.
      final fontStreamId = writer.createObject(_createFontStream(font.ttfData));

      final pdfName = _pdfNameFor(font.name);

      // B. Font Descriptor
      final bbox = font.metrics.getScaledBbox();
      final flags = font.metrics.flags;
      final descriptorId = writer.createObject('<< /Type /FontDescriptor\n'
          '/FontName /$pdfName\n'
          '/Flags $flags\n'
          '/FontBBox [${bbox[0]} ${bbox[1]} ${bbox[2]} ${bbox[3]}]\n'
          '/ItalicAngle ${font.metrics.italicAngle}\n'
          '/Ascent ${font.metrics.getScaledAscent()}\n'
          '/Descent ${font.metrics.getScaledDescent()}\n'
          '/CapHeight ${font.metrics.getScaledCapHeight()}\n'
          '/StemV 80\n' // Approximated
          '/FontFile2 $fontStreamId 0 R\n'
          '>>');

      // C. CID System Info
      const cidSystemInfo =
          '<< /Registry (Adobe) /Ordering (Identity) /Supplement 0 >>';

      // D. CIDFont Type 2. /W gives per-glyph advance widths indexed by GID
      // (Identity-H maps content-stream codes directly to GIDs); without it,
      // every glyph falls back to /DW and text renders with wrong spacing.
      final wArray = font.metrics.generateWidthsArray();

      final cidFontId =
          writer.createObject('<< /Type /Font /Subtype /CIDFontType2\n'
              '/BaseFont /$pdfName\n'
              '/CIDSystemInfo $cidSystemInfo\n'
              '/FontDescriptor $descriptorId 0 R\n'
              '/DW 1000\n'
              '/W $wArray\n'
              '>>');

      // E. ToUnicode CMap
      final cmap = font.metrics.generateToUnicodeCMap();
      final cmapId = writer.createObject(
          '<< /Length ${cmap.length} >>\nstream\n$cmap\nendstream');

      // F. Type0 Font (The one referenced in content)
      final type0Id = writer
          .createObject('<< /Type /Font /Subtype /Type0\n' // Composite font
              '/BaseFont /$pdfName\n'
              '/Encoding /Identity-H\n'
              '/DescendantFonts [$cidFontId 0 R]\n'
              '/ToUnicode $cmapId 0 R\n'
              '>>');

      fontIds[font.fontRef] = type0Id;
    }

    return fontIds;
  }

  /// Turns an arbitrary font name (e.g. the bundled fallback font's
  /// `'DejaVu Sans (docx_creator fallback)'`, or whatever a caller passes to
  /// `addFont`/`registerFont`) into a syntactically valid PDF name object.
  ///
  /// PDF name syntax (spec 7.3.5) forbids whitespace and the delimiter
  /// characters `( ) < > [ ] { } / %` appearing literally in a name - they
  /// must be written as `#XX` hex escapes instead. The previous
  /// implementation only stripped spaces, so a name containing parentheses
  /// (like the fallback font's) was written straight through as e.g.
  /// `/DejaVuSans(docx_creatorfallback)`: to a PDF parser that's the name
  /// `/DejaVuSans` followed by a *stray literal string* `(docx_creatorfallback)`
  /// sitting where the next dictionary key was expected, corrupting the
  /// rest of that dictionary. Viewers that recover from the resulting parse
  /// error typically can't resolve the font at all and fall back to
  /// rendering the raw character/glyph codes with a substitute font -
  /// producing wrong/garbled glyphs instead of the intended text, even
  /// though the font is otherwise correctly embedded and referenced.
  String _pdfNameFor(String name) {
    final buffer = StringBuffer();
    for (final byte in utf8.encode(name)) {
      final isRegular = byte > 0x20 &&
          byte < 0x7F &&
          byte != 0x23 && // # itself must always be escaped
          !'()<>[]{}/%'.codeUnits.contains(byte);
      if (isRegular) {
        buffer.writeCharCode(byte);
      } else {
        buffer.write('#${byte.toRadixString(16).padLeft(2, '0').toUpperCase()}');
      }
    }
    return buffer.toString();
  }

  /// Maps common Unicode code points to WinAnsi octal codes.
  int? _unicodeToWinAnsi(int unicode) {
    const mapping = <int, int>{
      0x2022: 0x95, // • Bullet
      0x2013: 0x96, // – En dash
      0x2014: 0x97, // — Em dash
      0x2018: 0x91, // ' Left single quote
      0x2019: 0x92, // ' Right single quote
      0x201C: 0x93, // " Left double quote
      0x201D: 0x94, // " Right double quote
      0x2026: 0x85, // … Ellipsis
      0x20AC: 0x80, // € Euro
      0x2122: 0x99, // ™ Trademark
      0x00A9: 0xA9, // © Copyright
      0x00AE: 0xAE, // ® Registered
    };
    return mapping[unicode];
  }

  dynamic _createFontStream(Uint8List data) {
    // Simply return bytes, let writer handle compression if it wants
    // But writer expects "dictionary + stream" or just bytes?
    // createObject detects list<int>.
    // We need to wrap it with dict.
    final compressed = ZLibEncoder().encode(data);
    final dict =
        '<< /Length ${compressed.length} /Filter /FlateDecode /Length1 ${data.length} >>\nstream\n';
    final builder = BytesBuilder();
    builder.add(utf8.encode(dict));
    builder.add(Uint8List.fromList(compressed));
    builder.add(utf8.encode('\nendstream'));
    return builder.toBytes();
  }
}
