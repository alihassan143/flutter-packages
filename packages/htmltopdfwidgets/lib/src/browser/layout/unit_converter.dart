class UnitConverter {
  /// Base references
  /// 1 inch = 72 pt
  /// 1 inch = 96 px (standard CSS density)
  /// 1 px = 72 / 96 = 0.75 pt

  static const double pxToPtRatio = 0.75;
  static const double inToPtRatio = 72.0;
  static const double defaultBaseFontSizePt = 12.0;

  /// Parse a length string from CSS and convert it strictly to points (pt).
  ///
  /// Examples: "16px", "12pt", "1em", "1.5rem", "100%", "2in"
  static double? parseAndConvertToPt(String? value,
      {double? parentFontSize, double? elementFontSize, double? parentWidth}) {
    if (value == null || value.isEmpty) return null;

    final val = value.trim().toLowerCase();

    // Check for rem first to avoid matching em
    if (val.endsWith('rem')) {
      final number = double.tryParse(val.replaceAll('rem', ''));
      return (number != null) ? (number * defaultBaseFontSizePt) : null;
    } else if (val.endsWith('em')) {
      final number = double.tryParse(val.replaceAll('em', ''));
      final base = elementFontSize ?? defaultBaseFontSizePt;
      return (number != null) ? (number * base) : null;
    } else if (val.endsWith('px')) {
      final number = double.tryParse(val.replaceAll('px', ''));
      return (number != null) ? (number * pxToPtRatio) : null;
    } else if (val.endsWith('pt')) {
      return double.tryParse(val.replaceAll('pt', ''));
    } else if (val.endsWith('mm')) {
      final number = double.tryParse(val.replaceAll('mm', ''));
      return (number != null) ? (number * inToPtRatio / 25.4) : null;
    } else if (val.endsWith('cm')) {
      final number = double.tryParse(val.replaceAll('cm', ''));
      return (number != null) ? (number * inToPtRatio / 2.54) : null;
    } else if (val.endsWith('pc')) {
      final number = double.tryParse(val.replaceAll('pc', ''));
      return (number != null) ? (number * 12) : null;
    } else if (val.endsWith('ex') || val.endsWith('ch')) {
      final number = double.tryParse(val.substring(0, val.length - 2));
      final base = elementFontSize ?? defaultBaseFontSizePt;
      return (number != null) ? (number * base * 0.5) : null;
    } else if (val.endsWith('in')) {
      final number = double.tryParse(val.replaceAll('in', ''));
      return (number != null) ? (number * inToPtRatio) : null;
    } else if (val.endsWith('%')) {
      final number = double.tryParse(val.replaceAll('%', ''));
      if (number != null && parentWidth != null) {
        return (number / 100.0) * parentWidth;
      }
      return null;
    }

    // Fallback: If it's just a number, we assume it's px or pt based on typical CSS/HTML behavior.
    final rawNumber = double.tryParse(val);
    if (rawNumber != null) {
      return rawNumber * pxToPtRatio;
    }

    return null;
  }
}
