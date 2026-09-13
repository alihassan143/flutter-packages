import 'package:flutter/material.dart';

import 'theme/docx_view_theme.dart';

/// Defines the layout rendering mode.
enum DocxPageMode {
  /// Renders content in a single continuous scroll view (standard web/mobile style).
  continuous,

  /// Renders content in distinct page blocks (print layout style).
  paged,
}

/// Configuration for [DocxView] widget.
class DocxViewConfig {
  /// Enable search functionality with highlighting.
  final bool enableSearch;

  /// Enable pinch-to-zoom functionality.
  final bool enableZoom;

  /// Enable text selection for copy/paste.
  final bool enableSelection;

  /// Minimum zoom scale.
  final double minScale;

  /// Maximum zoom scale.
  final double maxScale;

  /// Font fallbacks when embedded fonts are unavailable.
  final List<String> customFontFallbacks;

  /// Theme for styling the document view.
  final DocxViewTheme? theme;

  /// Padding around the document content.
  final EdgeInsets padding;

  /// Background color for the viewer.
  final Color? backgroundColor;

  /// Show page breaks as visual separators.
  final bool showPageBreaks;

  /// Show debug info for unsupported elements (development mode).
  final bool showDebugInfo;

  /// Highlight color for search matches.
  final Color searchHighlightColor;

  /// Current search match highlight color.
  final Color currentSearchHighlightColor;

  /// Optional fixed page width to simulate print layout (e.g. 793 for A4).
  /// If null, content fills the available width (web/mobile responsive style).
  final double? pageWidth;

  /// The layout mode of the document (continuous or paged).
  final DocxPageMode pageMode;

  /// Optional fixed page height for paged mode (e.g. 1123 for A4 at 794 width).
  /// If null, defaults to page width * 1.414 (A4 ratio).
  final double? pageHeight;

  /// Whether to render the footnotes section at the bottom of the document.
  /// Also controls whether footnote reference marks are tappable.
  /// Defaults to true.
  final bool showFootnotes;

  /// Whether to render the endnotes section at the bottom of the document.
  /// Also controls whether endnote reference marks are tappable.
  /// Defaults to true.
  final bool showEndnotes;

  const DocxViewConfig({
    this.enableSearch = true,
    this.enableZoom = true,
    this.enableSelection = true,
    this.minScale = 0.5,
    this.maxScale = 4.0,
    this.customFontFallbacks = const ['Roboto', 'Arial', 'Helvetica'],
    this.theme,
    this.padding = const EdgeInsets.all(16.0),
    this.backgroundColor,
    this.showPageBreaks = true,
    this.showDebugInfo = false,
    this.searchHighlightColor = const Color(0xFFFFEB3B),
    this.currentSearchHighlightColor = const Color(0xFFFF9800),
    this.pageWidth,
    this.pageHeight,
    this.pageMode = DocxPageMode.paged,
    this.showFootnotes = true,
    this.showEndnotes = true,
  });

  DocxViewConfig copyWith({
    bool? enableSearch,
    bool? enableZoom,
    bool? enableSelection,
    double? minScale,
    double? maxScale,
    List<String>? customFontFallbacks,
    DocxViewTheme? theme,
    EdgeInsets? padding,
    Color? backgroundColor,
    bool? showPageBreaks,
    bool? showDebugInfo,
    Color? searchHighlightColor,
    Color? currentSearchHighlightColor,
    double? pageWidth,
    bool? showFootnotes,
    bool? showEndnotes,
  }) {
    return DocxViewConfig(
      enableSearch: enableSearch ?? this.enableSearch,
      enableZoom: enableZoom ?? this.enableZoom,
      enableSelection: enableSelection ?? this.enableSelection,
      minScale: minScale ?? this.minScale,
      maxScale: maxScale ?? this.maxScale,
      customFontFallbacks: customFontFallbacks ?? this.customFontFallbacks,
      theme: theme ?? this.theme,
      padding: padding ?? this.padding,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      showPageBreaks: showPageBreaks ?? this.showPageBreaks,
      showDebugInfo: showDebugInfo ?? this.showDebugInfo,
      searchHighlightColor: searchHighlightColor ?? this.searchHighlightColor,
      currentSearchHighlightColor:
          currentSearchHighlightColor ?? this.currentSearchHighlightColor,
      pageWidth: pageWidth ?? this.pageWidth,
      showFootnotes: showFootnotes ?? this.showFootnotes,
      showEndnotes: showEndnotes ?? this.showEndnotes,
    );
  }
}
