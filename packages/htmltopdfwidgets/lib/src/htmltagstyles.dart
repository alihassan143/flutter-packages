// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'package:htmltopdfwidgets/htmltopdfwidgets.dart';

/// Builder function type for creating custom checkbox widgets.
/// [isChecked] indicates whether the checkbox is checked.
/// Return a [Widget] to render as the checkbox.
typedef CheckboxBuilder = Widget Function(bool isChecked);

//apply custom styles to html stylee
class HtmlTagStyle {
  //bold  style that will merge with default style
  final TextStyle? boldStyle;
  //italic style that will merge with default style
  final TextStyle? italicStyle;
  //h1 tag style that will merge with default style
  final TextStyle? h1Style;
  //h2 tag style that will merge with default style
  final TextStyle? h2Style;
  //h3 tag style that will merge with default style
  final TextStyle? h3Style;
  //h4 tag style that will merge with default style
  final TextStyle? h4Style;
  //h5 tag style that will merge with default style
  final TextStyle? h5Style;
  //h6 tag style that will merge with default style
  final TextStyle? h6Style;
  //strike through style that will merge with default style
  final TextStyle? strikeThrough;
  //image alignment style that will merge with default style
  final Alignment imageAlignment;
  //paragraph style style that will merge with default style
  final TextStyle? paragraphStyle;
  //code tag style that will merge with default style
  final TextStyle? codeStyle;
  //heading style style that will merge with default style
  final TextStyle? headingStyle;
  //list index style style that will merge with default style
  final TextStyle? listIndexStyle;
  //href link style style that will merge with default style
  final TextStyle? linkStyle;
  //quote bar style that will merge with default style
  final PdfColor? quoteBarColor;
  //bullet list style style that will merge with default style
  /// The color of the bullet list icon in a PDF document.
  final PdfColor? bulletListIconColor;

  /// The color of the divider in a PDF document.
  final PdfColor dividerColor;

  /// The border style of the divider in a PDF document.
  final BorderStyle? dividerBorderStyle;

  /// The thickness of the divider in a PDF document.
  /// The thickness of the divider line.
  ///
  /// This value determines how thick the divider line will be.
  final double dividerthickness;

  /// The background color of inline `<code>` spans.
  final PdfColor codeBlockBackgroundColor;

  /// The background color of `<pre>` code blocks (ignored when
  /// [codeDecoration] is set).
  final PdfColor codeblockColor;
  // The decoration style that will merge with default style
  final BoxDecoration? codeDecoration;

  /// The height of the divider in a PDF document.
  final double dividerHight;

  /// Enable browser-standard default styles (margins, padding, etc.)
  final bool useDefaultStyles;

  /// Custom default paragraph margin (overrides browser defaults if set)
  final EdgeInsets? paragraphMargin;

  /// Custom default heading margins by level (overrides browser defaults if set)
  final Map<int, EdgeInsets>? headingMargins;

  /// Custom default list margin (overrides browser defaults if set)
  final EdgeInsets? listMargin;

  /// Custom table cell padding (overrides browser defaults if set)
  final EdgeInsets? tableCellPadding;

  /// Custom table header cell padding (overrides browser defaults if set)
  final EdgeInsets? tableHeaderPadding;

  /// Custom checkbox builder function for complete control over checkbox rendering.
  /// Takes precedence over [checkedIconSvg] and [uncheckedIconSvg].
  final CheckboxBuilder? checkboxBuilder;

  /// SVG string for the checked checkbox icon.
  /// Used when [checkboxBuilder] is not provided.
  final String? checkedIconSvg;

  /// SVG string for the unchecked checkbox icon.
  /// Used when [checkboxBuilder] is not provided.
  final String? uncheckedIconSvg;

  /// Size of the checkbox icon in points.
  final double checkboxSize;

  /// Color for the checked checkbox icon (used when rendering default or SVG).
  final PdfColor? checkedIconColor;

  /// Color for the unchecked checkbox icon (used when rendering default or SVG).
  final PdfColor? uncheckedIconColor;

  const HtmlTagStyle({
    this.boldStyle,
    this.italicStyle,
    this.h1Style,
    this.h2Style,
    this.h3Style,
    this.imageAlignment = Alignment.center,
    this.h4Style,
    this.h5Style,
    this.h6Style,
    this.strikeThrough,
    this.paragraphStyle,
    this.codeStyle,
    this.headingStyle,
    this.listIndexStyle,
    this.linkStyle,
    this.quoteBarColor,
    this.bulletListIconColor,
    this.dividerBorderStyle,
    this.dividerHight = 0.5,
    this.codeBlockBackgroundColor = PdfColors.grey200,
    this.codeblockColor = PdfColors.grey200,
    this.codeDecoration,
    this.dividerthickness = 1.0,
    this.dividerColor = PdfColors.grey,
    this.useDefaultStyles = true,
    this.paragraphMargin,
    this.headingMargins,
    this.listMargin,
    this.tableCellPadding,
    this.tableHeaderPadding,
    this.checkboxBuilder,
    this.checkedIconSvg,
    this.uncheckedIconSvg,
    this.checkboxSize = 14.0,
    this.checkedIconColor,
    this.uncheckedIconColor,
  });
}
