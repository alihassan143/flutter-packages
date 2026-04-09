// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'package:htmltopdfwidgets/htmltopdfwidgets.dart';

/// Builder function type for creating custom checkbox widgets.
/// [isChecked] indicates whether the checkbox is checked.
/// Return a [Widget] to render as the checkbox.
typedef CheckboxBuilder = Widget Function(bool isChecked);

class InlineTagStyle {
  final PdfColor? textColor;
  final PdfColor? backgroundColor;
  final PdfColor? borderColor;
  final double borderWidth;
  final double padding;

  const InlineTagStyle({
    this.textColor,
    this.backgroundColor,
    this.borderColor,
    this.borderWidth = 1.0,
    this.padding = 2.0,
  });
}


class BlockTagStyle {
  final PdfColor? textColor;
  final PdfColor? backgroundColor;
  final PdfColor? borderColor;
  final double borderWidth;
  final double? padding;
  final double? margin;
  final double? borderRadius;
  final FontWeight? fontWeight;
  final FontStyle? fontStyle;
  final double? fontSize;
  final TextAlign? textAlign;
  final double? lineHeight;

  const BlockTagStyle({
    this.textColor,
    this.backgroundColor,
    this.borderColor,
    this.borderWidth = 1.0,
    this.padding,
    this.margin,
    this.borderRadius,
    this.fontWeight,
    this.fontStyle,
    this.fontSize,
    this.textAlign,
    this.lineHeight,
  });
}

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

  /// The background color of the code block.
  ///
  /// This color is used as the background for code blocks in the PDF.
  final PdfColor codeBlockBackgroundColor;

  /// The color of the code block text.
  ///
  /// This color is used for the text within code blocks in the PDF.
  final PdfColor codeblockColor;
  // The decoration style that will merge with default style
  final BoxDecoration? codeDecoration;
  // Inline code background color
  final PdfColor? inlineCodeBackgroundColor;
  // Inline code border color
  final PdfColor? inlineCodeBorderColor;
  // Inline code border width
  final double inlineCodeBorderWidth;
  // Inline code padding
  final double inlineCodePadding;
  // Inline class-based styles (applies to span with class)
  final Map<String, InlineTagStyle> inlineClassStyles;
  // Block class-based styles (applies to any element with class)
  final Map<String, BlockTagStyle> blockClassStyles;
  // Inline button text color
  final PdfColor? inlineButtonTextColor;
  // Inline button background color
  final PdfColor? inlineButtonBackgroundColor;
  // Inline button border color
  final PdfColor? inlineButtonBorderColor;
  // Inline button border width
  final double inlineButtonBorderWidth;
  // Inline button padding
  final double inlineButtonPadding;

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
    this.codeBlockBackgroundColor = PdfColors.red,
    this.codeblockColor = PdfColors.grey,
    this.codeDecoration,
    this.inlineCodeBackgroundColor,
    this.inlineCodeBorderColor,
    this.inlineCodeBorderWidth = 1.0,
    this.inlineCodePadding = 2.0,
    this.inlineClassStyles = const {},
    this.blockClassStyles = const {},
    this.inlineButtonTextColor,
    this.inlineButtonBackgroundColor,
    this.inlineButtonBorderColor,
    this.inlineButtonBorderWidth = 1.0,
    this.inlineButtonPadding = 2.0,
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
