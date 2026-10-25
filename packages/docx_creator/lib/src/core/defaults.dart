/// Smart default values for document generation.
///
/// These defaults follow Microsoft Word's standard settings
/// to ensure documents look professional out of the box.
library;

// ============================================================
// PAGE DEFAULTS
// ============================================================

/// Default page width in twips (1/20th of a point).
/// US Letter width: 8.5 inches = 12240 twips.
const int kDefaultPageWidth = 12240;

/// Default page height in twips.
/// US Letter height: 11 inches = 15840 twips.
const int kDefaultPageHeight = 15840;

/// Default page margins in twips.
/// 1 inch = 1440 twips.
const int kDefaultMarginTop = 1440;
const int kDefaultMarginBottom = 1440;
const int kDefaultMarginLeft = 1440;
const int kDefaultMarginRight = 1440;

/// Default header distance from top edge in twips.
const int kDefaultHeaderDistance = 720; // 0.5 inch

/// Default footer distance from bottom edge in twips.
const int kDefaultFooterDistance = 720; // 0.5 inch

/// Default gap between text columns in twips (`w:cols w:space`), matching
/// Word's own default. 0.5 inch.
const int kDefaultColumnSpacing = 720;

// ============================================================
// FONT DEFAULTS
// ============================================================

/// Default font family.
const String kDefaultFontFamily = 'Calibri';

/// Default font size in points.
const double kDefaultFontSize = 11.0;

/// Default heading font family.
const String kDefaultHeadingFontFamily = 'Calibri Light';

/// Default line spacing (single = 240, 1.5 = 360, double = 480).
const int kDefaultLineSpacing = 240;

/// Default spacing after paragraph in twips.
const int kDefaultSpacingAfter = 200; // ~8pt

/// Default spacing before paragraph in twips.
const int kDefaultSpacingBefore = 0;

// ============================================================
// TABLE DEFAULTS
// ============================================================

/// Default table border width in eighths of a point.
/// 4 = 0.5pt, 8 = 1pt.
const int kDefaultTableBorderWidth = 4;

/// Default table cell padding in twips.
const int kDefaultCellPadding = 115; // ~0.08 inch

// ============================================================
// IMAGE DEFAULTS
// ============================================================

/// Default image width in points.
const double kDefaultImageWidth = 200.0;

/// Default image height in points.
const double kDefaultImageHeight = 150.0;

// ============================================================
// STYLE IDS
// ============================================================

/// Word's built-in style IDs.
class DocxStyleIds {
  DocxStyleIds._();

  static const String normal = 'Normal';
  static const String heading1 = 'Heading1';
  static const String heading2 = 'Heading2';
  static const String heading3 = 'Heading3';
  static const String heading4 = 'Heading4';
  static const String heading5 = 'Heading5';
  static const String heading6 = 'Heading6';
  static const String title = 'Title';
  static const String subtitle = 'Subtitle';
  static const String quote = 'Quote';
  static const String code = 'CodeChar';
  static const String noSpacing = 'NoSpacing';
  static const String tableGrid = 'TableGrid';
}
