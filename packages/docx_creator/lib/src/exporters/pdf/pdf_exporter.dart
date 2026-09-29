import 'dart:math' as math;
import 'dart:math' show pi, cos, sin;
import 'dart:typed_data';

import '../../../docx_creator.dart';
import '../../utils/file_saver.dart';
import '../../utils/image_resolver.dart';
import 'pdf_content_builder.dart';
import 'pdf_document_writer.dart';
import 'pdf_font_manager.dart';
import 'pdf_layout_engine.dart';

/// Exports [DocxBuiltDocument] to PDF format.
///
/// Uses a modular architecture with separate components for:
/// - Layout and measurement ([PdfLayoutEngine])
/// - Content stream building ([PdfContentBuilder])
/// - Low-level PDF structure ([PdfDocumentWriter])
class PdfExporter implements PdfBlockMeasurer {
  /// Default page width (Letter: 8.5 inches = 612 points)
  final double pageWidth;

  /// Default page height (Letter: 11 inches = 792 points)
  final double pageHeight;

  /// Default margins (1 inch = 72 points)
  final double marginTop;
  final double marginBottom;
  final double marginLeft;
  final double marginRight;

  final int fontSize;

  /// Whether to compress content streams (reduces file size but makes text unreadable in raw bytes)
  final bool compressContent;

  // State for current export
  PdfDocumentWriter? _writer;
  final _pageImages = <String, int>{};
  var _imageCount = 0;
  final _pageLinks = <_PendingLink>[];
  late final PdfFontManager _fontManager;

  /// Fully-rendered pages awaiting finalization - see [exportToBytes] for
  /// why page content is rendered in one pass and only turned into actual
  /// PDF page objects in a second pass afterwards.
  final _pendingPages = <_PendingPage>[];

  /// Creates a PDF exporter with configurable defaults.
  PdfExporter({
    this.pageWidth = 612.0,
    this.pageHeight = 792.0,
    this.marginTop = 72.0,
    this.marginBottom = 72.0,
    this.marginLeft = 72.0,
    this.marginRight = 72.0,
    this.fontSize = 12,
    this.compressContent = true,
  }) {
    _fontManager = PdfFontManager();
  }

  /// Registers a custom font for use in the export.
  void registerFont(String fontFamily, Uint8List bytes) {
    _fontManager.registerFont(fontFamily, bytes);
  }

  /// Exports the document to a file.
  Future<void> exportToFile(DocxBuiltDocument doc, String filePath) async {
    final bytes = exportToBytes(doc);
    await FileSaver.save(filePath, bytes);
  }

  /// Reads the .docx file at [docxFilePath] and returns it converted to PDF
  /// bytes. Convenience wrapper around [DocxReader.load] + [exportToBytes]
  /// for the common "just give me a PDF" case.
  static Future<Uint8List> convertDocxFileToPdfBytes(
      String docxFilePath) async {
    final doc = await DocxReader.load(docxFilePath);
    return PdfExporter().exportToBytes(doc);
  }

  /// Exports the document to bytes.
  ///
  /// Rendering happens in two passes. Pass one (the `_processSection` calls
  /// below) builds every page's content stream and collects them into
  /// [_pendingPages] *without* creating PDF page objects yet. Fonts used
  /// only via automatic fallback (e.g. [PdfFontManager.fallbackUnicodeFontRef],
  /// embedded the first time a character needs it) are embedded lazily
  /// during this pass, as content is generated - so which fonts end up
  /// used is only fully known once every page has been rendered.
  ///
  /// Pass two writes the font objects (`_fontManager.writeFonts`) now that
  /// the full set is known, then turns each pending page into an actual PDF
  /// page object referencing them. Previously fonts were written *before*
  /// rendering, so any font embedded lazily during rendering (the Unicode
  /// fallback font being the common case - anything outside WinAnsi, e.g.
  /// an emoji, triggers it) was never included in the `/Resources /Font`
  /// dictionary of any page: its object was never even written, and every
  /// page's font list had already been serialized without it. The content
  /// stream would still reference it via a `Tf` operator pointing at an
  /// undefined resource, which viewers handle by falling back to
  /// substituting a default font using the raw character codes - silently
  /// turning readable text using that font into garbled/wrong glyphs.
  Uint8List exportToBytes(DocxBuiltDocument doc) {
    _writer = PdfDocumentWriter();
    _pendingPages.clear();
    final sections = _splitSections(doc);

    final footnotesById = <int, DocxFootnote>{
      for (final f in doc.footnotes ?? const <DocxFootnote>[]) f.footnoteId: f,
    };

    for (final section in sections) {
      _processSection(section, footnotesById);
    }

    final endnotes = doc.endnotes;
    if (endnotes != null && endnotes.isNotEmpty) {
      final lastSection = sections.last;
      final endnoteSection = _SectionData(
        width: lastSection.width,
        height: lastSection.height,
        marginTop: lastSection.marginTop,
        marginBottom: lastSection.marginBottom,
        marginLeft: lastSection.marginLeft,
        marginRight: lastSection.marginRight,
        nodes: _buildEndnoteNodes(endnotes),
      );
      _processSection(endnoteSection, const {});
    }

    // Every page's content has now been rendered, so every font that will
    // ever be needed - standard, custom (`registerFont`), and lazily
    // auto-embedded fallback fonts alike - has been embedded. Only now is
    // it safe to write the font objects and materialize page objects that
    // reference them.
    final fontIds = _fontManager.writeFonts(_writer!);

    for (final pending in _pendingPages) {
      final pageId = _writer!.addPage(
        contentStream: pending.content,
        width: pending.width,
        height: pending.height,
        xObjectIds: pending.xObjectIds,
        fonts: fontIds,
        extGStateIds: pending.extGStateIds,
        compress: compressContent,
      );

      for (final link in pending.links) {
        _writer!.addLinkAnnotation(
          x: link.x,
          y: link.y,
          width: link.width,
          height: link.height,
          uri: link.uri,
          pageId: pageId,
        );
      }
    }

    return _writer!.save();
  }

  /// Builds a trailing "Endnotes" heading followed by one paragraph per
  /// [DocxEndnote], each prefixed with its `endnoteId` — mirrors how
  /// [_renderFootnoteArea] prefixes the first paragraph of a footnote with
  /// its ID. Rendered as its own synthetic section (see [exportToBytes]) so
  /// it reuses the normal pagination/render pipeline instead of a bespoke one.
  List<DocxNode> _buildEndnoteNodes(List<DocxEndnote> endnotes) {
    final nodes = <DocxNode>[DocxParagraph.heading1('Endnotes')];
    for (final note in endnotes) {
      var isFirstBlock = true;
      for (final block in note.content) {
        if (block is! DocxParagraph) continue;
        final content = isFirstBlock
            ? [DocxText('${note.endnoteId}. '), ...block.children]
            : block.children;
        isFirstBlock = false;
        nodes.add(block.copyWith(children: content));
      }
    }
    return nodes;
  }

  void _processSection(
      _SectionData section, Map<int, DocxFootnote> footnotesById) {
    final layout = PdfLayoutEngine(
      pageWidth: section.width,
      pageHeight: section.height,
      marginTop: section.marginTop,
      marginBottom: section.marginBottom,
      marginLeft: section.marginLeft,
      marginRight: section.marginRight,
      baseFontSize: fontSize.toDouble(),
      fontManager: _fontManager,
      footnotesById: footnotesById,
      measurer: this,
    );
    _layoutEngine = layout;

    final paginationResult = layout.paginateWithFootnotes(section.nodes);
    final pages = paginationResult.pages;

    // Background image bytes (and its opacity ExtGState, if translucent)
    // are registered once per section rather than once per page, same
    // rationale as the font dedup above.
    int? bgImageId;
    int? bgExtGStateId;
    final bgImage = section.backgroundImage;
    if (bgImage != null) {
      final intrinsic = ImageResolver.intrinsicSizePt(bgImage.bytes);
      bgImageId = _writer!.addImage(
        bytes: bgImage.bytes,
        width: (intrinsic?.$1 ?? section.width).round(),
        height: (intrinsic?.$2 ?? section.height).round(),
      );
      if (bgImage.opacity < 1.0) {
        bgExtGStateId = _writer!.addExtGState(bgImage.opacity);
      }
    }

    for (var pageIndex = 0; pageIndex < pages.length; pageIndex++) {
      final pageNodes = pages[pageIndex];

      const bgImageName = '/BgImg';
      const bgGStateName = '/BgGS';
      if (bgImageId != null) _pageImages[bgImageName] = bgImageId;

      final content = _renderPage(
        pageNodes,
        layout,
        header: section.header,
        footer: section.footer,
        footnoteIds: paginationResult.footnoteIdsPerPage[pageIndex],
        backgroundColor: section.backgroundColor,
        backgroundImage: bgImage,
        backgroundImageXObjectName: bgImageId != null ? bgImageName : null,
        backgroundExtGStateName: bgExtGStateId != null ? bgGStateName : null,
      );

      // Defer actually creating the PDF page object - and, by extension,
      // finalizing which fonts its /Resources dict lists - until every
      // page across every section has been rendered. See [exportToBytes].
      _pendingPages.add(_PendingPage(
        content: content,
        width: section.width,
        height: section.height,
        xObjectIds: Map.from(_pageImages),
        extGStateIds:
            bgExtGStateId != null ? {bgGStateName: bgExtGStateId} : null,
        links: List.of(_pageLinks),
      ));

      _pageImages.clear();
      _imageCount = 0;
      _pageLinks.clear();
    }
  }

  String _renderPage(
    List<DocxNode> nodes,
    PdfLayoutEngine layout, {
    DocxNode? header,
    DocxNode? footer,
    List<int> footnoteIds = const [],
    DocxColor? backgroundColor,
    DocxBackgroundImage? backgroundImage,
    String? backgroundImageXObjectName,
    String? backgroundExtGStateName,
  }) {
    final builder = PdfContentBuilder(fontManager: _fontManager);
    var cursorY = layout.contentTop;

    _renderSectionBackground(
      builder,
      layout,
      backgroundColor,
      backgroundImage,
      backgroundImageXObjectName,
      backgroundExtGStateName,
    );

    // Render header. DocxHeader/DocxFooter are wrappers around a block list
    // (not DocxParagraph themselves), so their children are rendered one by
    // one with an advancing cursor, same as body content.
    if (header is DocxHeader) {
      var headerY = layout.pageHeight - 36;
      for (final block in header.children) {
        headerY =
            _renderNode(block, builder, layout.marginLeft, headerY, layout);
      }
    }

    // Render footer
    if (footer is DocxFooter) {
      var footerY = 36.0;
      for (final block in footer.children) {
        footerY =
            _renderNode(block, builder, layout.marginLeft, footerY, layout);
      }
    }

    // Render body content
    for (final node in nodes) {
      cursorY = _renderNode(node, builder, layout.marginLeft, cursorY, layout);
    }

    _renderFootnoteArea(footnoteIds, builder, layout);

    return builder.content;
  }

  /// Paints the section's background color and/or background image for one
  /// page, before any header/footer/body content is drawn on top of it.
  void _renderSectionBackground(
    PdfContentBuilder builder,
    PdfLayoutEngine layout,
    DocxColor? backgroundColor,
    DocxBackgroundImage? backgroundImage,
    String? imageXObjectName,
    String? extGStateName,
  ) {
    if (backgroundColor != null) {
      builder.saveState();
      builder.setFillColorHex(backgroundColor.hex);
      builder.fillRect(0, 0, layout.pageWidth, layout.pageHeight);
      builder.restoreState();
    }

    if (backgroundImage == null || imageXObjectName == null) return;

    final intrinsic = ImageResolver.intrinsicSizePt(backgroundImage.bytes);
    final iw = intrinsic?.$1 ?? layout.pageWidth;
    final ih = intrinsic?.$2 ?? layout.pageHeight;

    builder.saveState();
    if (extGStateName != null) builder.setAlpha(extGStateName);

    switch (backgroundImage.fillMode) {
      case DocxBackgroundFillMode.stretch:
        builder.drawImage(
            imageXObjectName, 0, 0, layout.pageWidth, layout.pageHeight);
      case DocxBackgroundFillMode.fit:
        final scale = (layout.pageWidth / iw < layout.pageHeight / ih)
            ? layout.pageWidth / iw
            : layout.pageHeight / ih;
        final w = iw * scale;
        final h = ih * scale;
        builder.drawImage(imageXObjectName, (layout.pageWidth - w) / 2,
            (layout.pageHeight - h) / 2, w, h);
      case DocxBackgroundFillMode.center:
        builder.drawImage(imageXObjectName, (layout.pageWidth - iw) / 2,
            (layout.pageHeight - ih) / 2, iw, ih);
      case DocxBackgroundFillMode.tile:
        for (var ty = 0.0; ty < layout.pageHeight; ty += ih) {
          for (var tx = 0.0; tx < layout.pageWidth; tx += iw) {
            builder.drawImage(imageXObjectName, tx, ty, iw, ih);
          }
        }
    }

    builder.restoreState();
  }

  /// Renders the footnotes referenced on this page at the bottom of the
  /// content area (above the footer), separated from the body by a short
  /// rule line. [PdfLayoutEngine.paginateWithFootnotes] already reserved
  /// this vertical space, using the same [PdfLayoutEngine.measureFootnotesHeight]
  /// this method relies on to position itself, so the two can't drift apart.
  void _renderFootnoteArea(
    List<int> footnoteIds,
    PdfContentBuilder builder,
    PdfLayoutEngine layout,
  ) {
    if (footnoteIds.isEmpty) return;

    final areaHeight = layout.measureFootnotesHeight(footnoteIds);
    final areaTop = layout.contentBottom + areaHeight;

    builder.saveState();
    builder.setStrokeColor(0, 0, 0);
    builder.drawLine(
        layout.marginLeft, areaTop, layout.marginLeft + 108, areaTop,
        lineWidth: 0.5);
    builder.restoreState();

    var y = areaTop - 10;
    for (final footnoteId in footnoteIds) {
      final footnote = layout.footnotesById[footnoteId];
      if (footnote == null) continue;

      var isFirstBlock = true;
      for (final block in footnote.content) {
        if (block is! DocxParagraph) continue;
        final content = isFirstBlock
            ? [DocxText('$footnoteId. ', fontSize: 9), ...block.children]
            : block.children;
        isFirstBlock = false;
        final synthetic = block.copyWith(children: content);
        y = _renderParagraph(synthetic, builder, layout.marginLeft, y, layout);
      }
    }
  }

  double _renderNode(
    DocxNode node,
    PdfContentBuilder builder,
    double x,
    double y,
    PdfLayoutEngine layout,
  ) {
    if (node is DocxParagraph) {
      return _renderParagraph(node, builder, x, y, layout);
    } else if (node is DocxTable) {
      return _renderTable(node, builder, x, y, layout);
    } else if (node is DocxList) {
      return _renderList(node, builder, x, y, layout);
    } else if (node is DocxImage) {
      return _renderImage(node, builder, x, y, layout);
    } else if (node is DocxShapeBlock) {
      return _renderShapeBlock(node, builder, x, y, layout);
    } else if (node is DocxDropCap) {
      return _renderDropCap(node, builder, x, y, layout);
    } else if (node is DocxTableOfContents) {
      var tocY = y;
      for (final block in node.cachedContent) {
        tocY = _renderNode(block, builder, x, tocY, layout);
      }
      return tocY;
    }
    return y;
  }

  /// Renders a drop cap with true wrap-around: the letter is drawn once at
  /// large size spanning `dropCap.lines` lines, and `restOfParagraph` flows
  /// through a narrower column to its right for those lines, then returns to
  /// full paragraph width — unlike Word's `w:framePr`-floated letter, PDF has
  /// no native float primitive, so this hand-flows lines through variable
  /// per-line widths ([_flowLines]) instead of the earlier approach of
  /// concatenating letter + text into one oversized paragraph.
  double _renderDropCap(
    DocxDropCap dropCap,
    PdfContentBuilder builder,
    double x,
    double y,
    PdfLayoutEngine layout,
  ) {
    final baseFontSize = layout.getFontSize(null);
    final dropCapFontSize = dropCap.fontSize ?? (baseFontSize * dropCap.lines);
    final dropCapFontRef =
        _fontManager.selectFont(isBold: true, fontFamily: dropCap.fontFamily);
    final dropCapWidth = builder.measureText(dropCap.letter, dropCapFontSize,
        isBold: true, fontRef: dropCapFontRef, fontManager: _fontManager);
    final hGap =
        dropCap.hSpace > 0 ? dropCap.hSpace / 20.0 : baseFontSize * 0.3;

    final maxWidth = layout.contentWidth;
    final narrowWidth = (maxWidth - dropCapWidth - hGap).clamp(0.0, maxWidth);
    final dropCapLineHeight = baseFontSize * 1.4;
    final dropCapBlockHeight = dropCap.lines * dropCapLineHeight;

    final words =
        _collectWords(dropCap.restOfParagraph, baseFontSize, register: true);
    // Split against the narrower of the two widths so a long word can never
    // overflow either the column beside the drop cap letter or the
    // full-width lines below it.
    final splitWidth = narrowWidth > 0 ? narrowWidth : maxWidth;
    final splitWords = _splitOverlongWords(words, splitWidth, baseFontSize);
    final lines = _flowLines(
        splitWords, (i) => i < dropCap.lines ? narrowWidth : maxWidth);
    for (final line in lines) {
      _measureLine(line, baseFontSize, const DocxParagraph(children: []));
    }

    // Draw the drop cap letter so its glyph roughly fills the block of
    // lines it displaces, baseline near the bottom of that block.
    builder.beginText();
    builder.setTextMatrix(x, y - dropCapBlockHeight * 0.92);
    builder.setFont(dropCapFontRef, dropCapFontSize);
    builder.setFillColorHex('000000');
    builder.showText(dropCap.letter);
    builder.endText();

    final decorations = <_TextDecoration>[];
    var lineTop = y;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.words.isNotEmpty) {
        final narrow = i < dropCap.lines;
        _drawWordLine(
          builder: builder,
          line: line,
          startX: narrow ? x + dropCapWidth + hGap : x,
          lineMaxWidth: narrow ? narrowWidth : maxWidth,
          y: lineTop - line.baseline,
          align: DocxAlign.left,
          justify: false,
          decorations: decorations,
        );
      }
      lineTop -= line.height;
    }

    _strokeDecorations(builder, decorations);

    final dropCapBottom = y - dropCapBlockHeight;
    final finalY = lineTop < dropCapBottom ? lineTop : dropCapBottom;
    return finalY - baseFontSize * 0.5;
  }

  double _renderShapeBlock(
    DocxShapeBlock shapeBlock,
    PdfContentBuilder builder,
    double startX,
    double startY,
    PdfLayoutEngine layout,
  ) {
    final shape = shapeBlock.shape;
    final maxWidth = layout.contentWidth;

    // Calculate X position based on alignment
    var x = startX;
    if (shapeBlock.align == DocxAlign.center) {
      x = startX + (maxWidth - shape.width) / 2;
    } else if (shapeBlock.align == DocxAlign.right) {
      x = startX + maxWidth - shape.width;
    }

    // Y position (PDF Y is from bottom)
    final y = startY - shape.height;

    _drawShape(builder, shape, x, y);

    return y - 10; // Return new cursor position with spacing
  }

  void _drawShape(
      PdfContentBuilder builder, DocxShape shape, double x, double y) {
    builder.saveState();

    // Set colors
    if (shape.fillColor != null) {
      builder.setFillColorHex(shape.fillColor!.hex);
    }
    if (shape.outlineColor != null) {
      builder.setStrokeColorHex(shape.outlineColor!.hex);
      builder.setLineWidth(shape.outlineWidth);
    }

    final w = shape.width;
    final h = shape.height;
    final hasFill = shape.fillColor != null;
    final hasStroke = shape.outlineColor != null;

    switch (shape.preset) {
      case DocxShapePreset.rect:
        builder.fillStrokeRect(x, y, w, h, lineWidth: shape.outlineWidth);

      case DocxShapePreset.roundRect:
        final r = (w < h ? w : h) * 0.15;
        builder.drawRoundedRect(x, y, w, h, r,
            stroke: hasStroke, fill: hasFill);

      case DocxShapePreset.ellipse:
        builder.drawEllipse(x + w / 2, y + h / 2, w / 2, h / 2,
            stroke: hasStroke, fill: hasFill);

      case DocxShapePreset.triangle:
        builder.drawPolygon([
          [x + w / 2, y + h], // Top
          [x, y], // Bottom left
          [x + w, y], // Bottom right
        ], stroke: hasStroke, fill: hasFill);

      case DocxShapePreset.diamond:
        builder.drawPolygon([
          [x + w / 2, y + h], // Top
          [x, y + h / 2], // Left
          [x + w / 2, y], // Bottom
          [x + w, y + h / 2], // Right
        ], stroke: hasStroke, fill: hasFill);

      case DocxShapePreset.rightArrow:
        _drawArrow(builder, x, y, w, h, 'right', hasFill, hasStroke);

      case DocxShapePreset.leftArrow:
        _drawArrow(builder, x, y, w, h, 'left', hasFill, hasStroke);

      case DocxShapePreset.upArrow:
        _drawArrow(builder, x, y, w, h, 'up', hasFill, hasStroke);

      case DocxShapePreset.downArrow:
        _drawArrow(builder, x, y, w, h, 'down', hasFill, hasStroke);

      case DocxShapePreset.star5:
        _drawStar(builder, x + w / 2, y + h / 2, w / 2, 5, hasFill, hasStroke);

      case DocxShapePreset.star4:
        _drawStar(builder, x + w / 2, y + h / 2, w / 2, 4, hasFill, hasStroke);

      case DocxShapePreset.star6:
        _drawStar(builder, x + w / 2, y + h / 2, w / 2, 6, hasFill, hasStroke);

      case DocxShapePreset.line:
        builder.drawLine(x, y + h / 2, x + w, y + h / 2,
            lineWidth: shape.outlineWidth);

      case DocxShapePreset.hexagon:
        _drawRegularPolygon(
            builder, x + w / 2, y + h / 2, w / 2, 6, hasFill, hasStroke);

      case DocxShapePreset.octagon:
        _drawRegularPolygon(
            builder, x + w / 2, y + h / 2, w / 2, 8, hasFill, hasStroke);

      case DocxShapePreset.pentagon:
        _drawRegularPolygon(
            builder, x + w / 2, y + h / 2, w / 2, 5, hasFill, hasStroke);

      default:
        // Fallback to rectangle for unsupported shapes
        builder.fillStrokeRect(x, y, w, h, lineWidth: shape.outlineWidth);
    }

    // Draw text inside shape if present
    if (shape.text != null && shape.text!.isNotEmpty) {
      builder.drawText(
        shape.text!,
        x + w / 2 - shape.text!.length * 3,
        y + h / 2 - 4,
        fontSize: 10,
        colorHex: '000000',
      );
    }

    builder.restoreState();
  }

  void _drawArrow(PdfContentBuilder builder, double x, double y, double w,
      double h, String direction, bool fill, bool stroke) {
    final points = <List<double>>[];
    final headSize = 0.4;
    final shaftWidth = 0.3;

    switch (direction) {
      case 'right':
        points.addAll([
          [x, y + h * (0.5 - shaftWidth / 2)],
          [x + w * (1 - headSize), y + h * (0.5 - shaftWidth / 2)],
          [x + w * (1 - headSize), y],
          [x + w, y + h / 2],
          [x + w * (1 - headSize), y + h],
          [x + w * (1 - headSize), y + h * (0.5 + shaftWidth / 2)],
          [x, y + h * (0.5 + shaftWidth / 2)],
        ]);
      case 'left':
        points.addAll([
          [x + w, y + h * (0.5 - shaftWidth / 2)],
          [x + w * headSize, y + h * (0.5 - shaftWidth / 2)],
          [x + w * headSize, y],
          [x, y + h / 2],
          [x + w * headSize, y + h],
          [x + w * headSize, y + h * (0.5 + shaftWidth / 2)],
          [x + w, y + h * (0.5 + shaftWidth / 2)],
        ]);
      case 'up':
        points.addAll([
          [x + w * (0.5 - shaftWidth / 2), y],
          [x + w * (0.5 - shaftWidth / 2), y + h * (1 - headSize)],
          [x, y + h * (1 - headSize)],
          [x + w / 2, y + h],
          [x + w, y + h * (1 - headSize)],
          [x + w * (0.5 + shaftWidth / 2), y + h * (1 - headSize)],
          [x + w * (0.5 + shaftWidth / 2), y],
        ]);
      case 'down':
        points.addAll([
          [x + w * (0.5 - shaftWidth / 2), y + h],
          [x + w * (0.5 - shaftWidth / 2), y + h * headSize],
          [x, y + h * headSize],
          [x + w / 2, y],
          [x + w, y + h * headSize],
          [x + w * (0.5 + shaftWidth / 2), y + h * headSize],
          [x + w * (0.5 + shaftWidth / 2), y + h],
        ]);
    }

    builder.drawPolygon(points, stroke: stroke, fill: fill);
  }

  void _drawStar(PdfContentBuilder builder, double cx, double cy, double r,
      int points, bool fill, bool stroke) {
    final innerR = r * 0.4;
    final vertices = <List<double>>[];

    for (var i = 0; i < points * 2; i++) {
      final angle = (i * pi / points) - pi / 2;
      final radius = i.isEven ? r : innerR;
      vertices.add([cx + radius * cos(angle), cy + radius * sin(angle)]);
    }

    builder.drawPolygon(vertices, stroke: stroke, fill: fill);
  }

  void _drawRegularPolygon(PdfContentBuilder builder, double cx, double cy,
      double r, int sides, bool fill, bool stroke) {
    final vertices = <List<double>>[];

    for (var i = 0; i < sides; i++) {
      final angle = (i * 2 * pi / sides) - pi / 2;
      vertices.add([cx + r * cos(angle), cy + r * sin(angle)]);
    }

    builder.drawPolygon(vertices, stroke: stroke, fill: fill);
  }

  // ===========================================================================
  // Paragraph layout
  //
  // Measuring (pagination) and drawing share [_layoutParagraph], so a
  // paragraph always occupies exactly the height pagination reserved for it.
  // ===========================================================================

  /// Lays out [paragraph] in a box [boxWidth] points wide (before the
  /// paragraph's own indents/padding). [kind] picks the default spacing
  /// used when the paragraph doesn't specify any. With [register] false,
  /// inline images are measured but not added to the PDF (dry run).
  _ParaLayout _layoutParagraph(
    DocxParagraph paragraph,
    double boxWidth, {
    _ParaKind kind = _ParaKind.body,
    double? fontSizeOverride,
    bool register = false,
  }) {
    final layout = _layoutEngine;
    final fontSize =
        fontSizeOverride ?? layout?.getFontSize(paragraph.styleId) ?? fontSize0;
    final isHeading = paragraph.styleId?.startsWith('Heading') ?? false;

    final indentLeft = (paragraph.indentLeft ?? 0) / 20.0;
    final indentRight = (paragraph.indentRight ?? 0) / 20.0;
    final firstLine = (paragraph.indentFirstLine ?? 0) / 20.0;
    final padLeft = (paragraph.paddingLeft ?? 0) / 20.0;
    final padRight = (paragraph.paddingRight ?? 0) / 20.0;
    final padTop = (paragraph.paddingTop ?? 0) / 20.0;
    final padBottom = (paragraph.paddingBottom ?? 0) / 20.0;
    final textWidth =
        math.max(1.0, boxWidth - indentLeft - indentRight - padLeft - padRight);

    double spaceBefore;
    double spaceAfter;
    if (paragraph.spacingBefore != null) {
      spaceBefore = paragraph.spacingBefore! / 20.0;
    } else {
      // Headings get a little room above them, like Word's heading styles.
      spaceBefore = kind == _ParaKind.body && isHeading ? fontSize * 0.5 : 0;
    }
    if (paragraph.spacingAfter != null) {
      spaceAfter = paragraph.spacingAfter! / 20.0;
    } else {
      switch (kind) {
        case _ParaKind.body:
          spaceAfter = isHeading ? fontSize * 0.8 : fontSize * 0.5;
        case _ParaKind.cell:
          spaceAfter = 0;
        case _ParaKind.listItem:
          spaceAfter = fontSize * 0.25;
      }
    }

    var words = _collectWords(paragraph.children, fontSize,
        forceBold: isHeading, register: register);
    words = _splitOverlongWords(
        words, textWidth - math.max(0, firstLine), fontSize);
    final lines =
        _flowLines(words, (i) => i == 0 ? textWidth - firstLine : textWidth);
    for (final line in lines) {
      _measureLine(line, fontSize, paragraph);
    }

    return _ParaLayout(
      paragraph: paragraph,
      fontSize: fontSize,
      lines: lines,
      spaceBefore: spaceBefore,
      spaceAfter: spaceAfter,
      padTop: padTop,
      padBottom: padBottom,
      padLeft: padLeft,
      padRight: padRight,
      indentLeft: indentLeft,
      firstLineIndent: firstLine,
      textWidth: textWidth,
    );
  }

  /// Draws a laid-out paragraph whose box's top-left is at ([x], [yTop]);
  /// returns the y just below it (after its spacing).
  double _drawParagraph(
      _ParaLayout pl, PdfContentBuilder builder, double x, double yTop) {
    final paragraph = pl.paragraph;
    final boxTop = yTop - pl.spaceBefore;
    final boxHeight = pl.padTop + pl.linesHeight + pl.padBottom;
    final boxLeft = x + pl.indentLeft;
    final boxWidth = pl.textWidth + pl.padLeft + pl.padRight;

    if (paragraph.shadingFill != null && paragraph.shadingFill != 'auto') {
      builder.saveState();
      builder.setFillColorHex(paragraph.shadingFill!);
      builder.fillRect(boxLeft, boxTop - boxHeight, boxWidth, boxHeight);
      builder.restoreState();
    }

    // Paragraph borders (e.g. <hr>/blockquote/code-block rules).
    if (paragraph.borderTop != null ||
        paragraph.borderBottomSide != null ||
        paragraph.borderLeft != null ||
        paragraph.borderRight != null) {
      final boxRight = boxLeft + boxWidth;
      final boxBottom = boxTop - boxHeight;

      void drawSide(
          DocxBorderSide? side, double x1, double y1, double x2, double y2) {
        if (side == null || side.style == DocxBorder.none) return;
        builder.saveState();
        builder.setStrokeColorHex(
            side.color == DocxColor.auto ? '000000' : side.color.hex);
        builder.drawLine(x1, y1, x2, y2, lineWidth: side.size / 8.0);
        builder.restoreState();
      }

      drawSide(paragraph.borderTop, boxLeft, boxTop, boxRight, boxTop);
      drawSide(
          paragraph.borderBottomSide, boxLeft, boxBottom, boxRight, boxBottom);
      drawSide(paragraph.borderLeft, boxLeft, boxTop, boxLeft, boxBottom);
      drawSide(paragraph.borderRight, boxRight, boxTop, boxRight, boxBottom);
    }

    final decorations = <_TextDecoration>[];
    var lineTop = boxTop - pl.padTop;
    for (var i = 0; i < pl.lines.length; i++) {
      final line = pl.lines[i];
      if (line.words.isNotEmpty) {
        final first = i == 0 ? pl.firstLineIndent : 0.0;
        // Justified text leaves the paragraph's last line and lines ended
        // by a hard break ragged, like Word.
        final isLast = i == pl.lines.length - 1 || pl.lines[i + 1].afterBreak;
        _drawWordLine(
          builder: builder,
          line: line,
          startX: boxLeft + pl.padLeft + first,
          lineMaxWidth: pl.textWidth - first,
          y: lineTop - line.baseline,
          align: paragraph.align,
          justify: paragraph.align == DocxAlign.justify && !isLast,
          decorations: decorations,
        );
      }
      lineTop -= line.height;
    }
    _strokeDecorations(builder, decorations);

    return boxTop - boxHeight - pl.spaceAfter;
  }

  double _renderParagraph(
    DocxParagraph paragraph,
    PdfContentBuilder builder,
    double startX,
    double startY,
    PdfLayoutEngine layout,
  ) {
    final pl = _layoutParagraph(paragraph, layout.contentWidth, register: true);
    return _drawParagraph(pl, builder, startX, startY);
  }

  /// Computes a line's height and baseline offset from the fonts, inline
  /// media and the paragraph's line-spacing rule (`w:spacing w:line`).
  void _measureLine(_Line line, double paraFontSize, DocxParagraph paragraph) {
    var maxFont = 0.0;
    var maxMedia = 0.0;
    for (final word in line.words) {
      if (word.isImage) {
        maxMedia = math.max(maxMedia, word.imageHeight);
      } else if (word.isShape) {
        maxMedia = math.max(maxMedia, word.shape!.height);
      } else if (!word.isTab && !word.isBreak) {
        maxFont = math.max(maxFont, word.fontSize ?? paraFontSize);
      }
    }
    if (maxFont == 0) maxFont = paraFontSize;

    // Single spacing is ~1.22em for the fonts Word uses; the package's
    // DOCX default (and a paragraph with no explicit rule) is 1.15 lines.
    final single = maxFont * 1.22;
    final rule = paragraph.lineRule ?? 'auto';
    final value = paragraph.lineSpacing;
    double height;
    var exact = false;
    if (value == null || value <= 0) {
      height = single * 1.15;
    } else if (rule == 'exact') {
      height = value / 20.0;
      exact = true;
    } else if (rule == 'atLeast') {
      height = math.max(value / 20.0, single);
    } else {
      height = single * value / 240.0;
    }

    var baseline = maxFont * 0.9;
    if (maxMedia > 0) {
      baseline = math.max(baseline, maxMedia);
      if (!exact) height = math.max(height, maxMedia + maxFont * 0.3);
    }
    if (exact) baseline = math.min(baseline, height * 0.8);
    line.height = height;
    line.baseline = baseline;
  }

  /// Draws an invisible space glyph at [x] so a text extractor sees a word
  /// boundary between a non-text element (checkbox, image, shape) and the
  /// word before/after it, not just a positional gap. A blank [fontRef]
  /// (line breaks, images and shapes, which have no real font of their
  /// own) has nothing sensible to draw with and is a no-op.
  void _drawGapSpace(PdfContentBuilder builder, double x, double y,
      String fontRef, double fontSize) {
    if (fontRef.isEmpty) return;
    builder.beginText();
    builder.setTextMatrix(x, y);
    builder.setFont(fontRef, fontSize);
    builder.showText(' ');
    builder.endText();
  }

  /// Strokes underline/strikethrough rules collected by [_drawWordLine]
  /// while drawing a paragraph/list item/cell's lines. Must run after the
  /// text is drawn - a line can't be stroked inside a PDF text object.
  void _strokeDecorations(
      PdfContentBuilder builder, List<_TextDecoration> decorations) {
    for (final dec in decorations) {
      builder.saveState();
      builder.setStrokeColorHex(dec.color);
      builder.drawLine(dec.x, dec.y, dec.x + dec.width, dec.y,
          lineWidth: dec.thickness);
      builder.restoreState();
    }
  }

  /// Draws one already-flowed line of words (text, images, shapes,
  /// checkboxes) with its baseline at [y], resolving [align] against
  /// [lineMaxWidth] to find the line's starting x.
  void _drawWordLine({
    required PdfContentBuilder builder,
    required _Line line,
    required double startX,
    required double lineMaxWidth,
    required double y,
    required DocxAlign align,
    required bool justify,
    required List<_TextDecoration> decorations,
  }) {
    final words = line.words;
    var maxFontInLine = 0.0;
    for (final word in words) {
      if (word.isImage || word.isShape || word.isTab) continue;
      maxFontInLine = math.max(maxFontInLine, word.fontSize ?? fontSize0);
    }
    if (maxFontInLine == 0) maxFontInLine = fontSize0;

    final lead =
        line.afterBreak && words.isNotEmpty ? words.first.lineStartGap : 0.0;
    double gapBefore(int k) => k == 0 ? lead : words[k].gap;

    var lineWidth = 0.0;
    for (var j = 0; j < words.length; j++) {
      lineWidth += gapBefore(j) + words[j].width;
    }

    var x = startX;
    var extraPerGap = 0.0;
    if (align == DocxAlign.center) {
      x += (lineMaxWidth - lineWidth) / 2;
    } else if (align == DocxAlign.right) {
      x += lineMaxWidth - lineWidth;
    } else if (justify) {
      var gaps = 0;
      for (var j = 1; j < words.length; j++) {
        if (words[j].gap > 0) gaps++;
      }
      final slack = lineMaxWidth - lineWidth;
      if (gaps > 0 && slack > 0) extraPerGap = slack / gaps;
    }

    // Resolve every word's x first; spaces between two words that share an
    // underline/highlight/link are covered too, as in Word and browsers.
    final xs = List<double>.filled(words.length, 0);
    var cursor = x;
    for (var k = 0; k < words.length; k++) {
      final g = gapBefore(k);
      cursor += g + (k > 0 && words[k].gap > 0 ? extraPerGap : 0);
      xs[k] = cursor;
      cursor += words[k].width;
    }
    double spanTo(int k) =>
        k + 1 < words.length ? xs[k + 1] : xs[k] + words[k].width;

    // Backgrounds (highlight/shading) behind text.
    for (var k = 0; k < words.length; k++) {
      final word = words[k];
      if (word.isTab || word.backgroundColor == null) continue;
      final wordFontSize = word.fontSize ?? fontSize0;
      final continues = k + 1 < words.length &&
          words[k + 1].backgroundColor == word.backgroundColor;
      final right = continues ? spanTo(k) : xs[k] + word.width;
      builder.saveState();
      builder.setFillColorHex(word.backgroundColor!);
      builder.fillRect(
          xs[k], y - wordFontSize * 0.22, right - xs[k], wordFontSize * 1.15);
      builder.restoreState();
    }

    for (var k = 0; k < words.length; k++) {
      final word = words[k];
      final textX = xs[k];
      final hasNext = k < words.length - 1 && words[k + 1].gap > 0;

      if (word.isTab) {
        continue;
      } else if (word.isImage) {
        if (word.imageXObjectName != null) {
          builder.drawImage(
              word.imageXObjectName!, textX, y, word.width, word.imageHeight);
          _drawImageBorder(builder, word.imageBorder, textX, y, word.width,
              word.imageHeight);
        }
        if (hasNext) {
          _drawGapSpace(builder, textX + word.width, y,
              PdfFontManager.fontRegular, maxFontInLine);
        }
      } else if (word.isShape) {
        _drawShape(builder, word.shape!, textX, y);
        if (hasNext) {
          _drawGapSpace(builder, textX + word.width, y,
              PdfFontManager.fontRegular, maxFontInLine);
        }
      } else if (word.isCheckbox) {
        builder.saveState();
        final checkboxFontSize = word.fontSize ?? fontSize0;
        final boxSize = checkboxFontSize * 0.8;
        final boxY = y - boxSize * 0.1;

        builder.setStrokeColorHex(word.color);
        builder.setLineWidth(1);
        builder.strokeRect(textX, boxY, boxSize, boxSize);

        if (word.checkboxType == 1 || word.checkboxType == 2) {
          builder.moveTo(textX, boxY);
          builder.lineTo(textX + boxSize, boxY + boxSize);
          builder.moveTo(textX + boxSize, boxY);
          builder.lineTo(textX, boxY + boxSize);
          builder.strokePath();
        }
        builder.restoreState();

        if (hasNext) {
          _drawGapSpace(
              builder, textX + word.width, y, word.fontRef, checkboxFontSize);
        }
      } else {
        var effFontSize = word.fontSize ?? fontSize0;
        var yPos = y;
        if (word.isSuperscript) {
          effFontSize *= 0.6;
          yPos = y + maxFontInLine * 0.35;
        } else if (word.isSubscript) {
          effFontSize *= 0.6;
          yPos = y - maxFontInLine * 0.15;
        }

        builder.beginText();
        builder.setTextMatrix(textX, yPos);
        builder.setFont(word.fontRef, effFontSize);
        builder.setFillColorHex(word.color);
        builder.showText(word.text);
        // Every word gets its own absolutely-positioned Tj, so a text
        // extractor sees no natural glyph advance to infer a word boundary
        // from - draw an actual space glyph between words, or adjacent
        // words silently run together when extracted/searched.
        if (hasNext) {
          builder.setTextMatrix(textX + word.width, yPos);
          builder.showText(' ');
        }
        builder.endText();

        bool sameDecoration(bool Function(_Word w) test) =>
            k + 1 < words.length &&
            test(words[k + 1]) &&
            words[k + 1].color == word.color &&
            !words[k + 1].isImage;
        final thickness = math.max(0.5, effFontSize / 24);
        if (word.isUnderline) {
          decorations.add(_TextDecoration(
            x: textX,
            y: yPos - effFontSize * 0.12,
            width: (sameDecoration((w) => w.isUnderline)
                    ? spanTo(k)
                    : textX + word.width) -
                textX,
            color: word.color,
            thickness: thickness,
          ));
        }
        if (word.isStrike) {
          decorations.add(_TextDecoration(
            x: textX,
            y: yPos + effFontSize * 0.28,
            width: (sameDecoration((w) => w.isStrike)
                    ? spanTo(k)
                    : textX + word.width) -
                textX,
            color: word.color,
            thickness: thickness,
          ));
        }

        if (word.href != null) {
          final linked = k + 1 < words.length && words[k + 1].href == word.href;
          _pageLinks.add(_PendingLink(
            x: textX,
            y: yPos - effFontSize * 0.22,
            width: (linked ? spanTo(k) : textX + word.width) - textX,
            height: effFontSize * 1.15,
            uri: word.href!,
          ));
        }
      }
    }
  }

  /// Falls back to the bundled Unicode-broad font when [content] has a
  /// character [selectedFontRef] (a standard font, or an embedded font
  /// that doesn't happen to cover it) can't render. An explicit
  /// [fontFamily] request always wins - this only fills the gap left when
  /// the caller didn't ask for a specific font and would otherwise silently
  /// lose (standard font) or mis-render (an unrelated embedded font)
  /// characters like Cyrillic/Greek/Vietnamese text.
  String _withUnicodeFallback(
      String selectedFontRef, String content, String? fontFamily) {
    if (fontFamily != null &&
        _fontManager.getEmbeddedFont(selectedFontRef) != null) {
      return selectedFontRef;
    }
    if (!_fontManager.needsUnicodeFallback(content)) return selectedFontRef;
    return _fontManager.fallbackUnicodeFontRef;
  }

  bool _isBoldRef(String fontRef) =>
      fontRef == PdfFontManager.fontBold ||
      fontRef == PdfFontManager.fontBoldItalic;

  double _measure(String text, double size, String fontRef) => _fontManager
      .measureText(text, size, isBold: _isBoldRef(fontRef), fontRef: fontRef);

  /// Turns a run of inline nodes into flat [_Word]s for [_flowLines].
  ///
  /// Whitespace is tracked across run boundaries: two runs with no space
  /// between them (`Word<b>glued</b>`, `H<sub>2</sub>O`) stay glued and are
  /// kept on one line, and runs of several spaces (code, DOCX text) keep
  /// their width instead of collapsing to one.
  List<_Word> _collectWords(List<DocxInline> children, double fontSize,
      {bool forceBold = false, bool register = false}) {
    final words = <_Word>[];
    var pendingGap = 0.0; // whitespace seen since the last word
    var pendingSpaces = 0;

    bool atLineStart() => words.isEmpty || words.last.isBreak;

    void addWord(_Word word) {
      words.add(word);
      pendingGap = 0;
      pendingSpaces = 0;
    }

    for (var i = 0; i < children.length; i++) {
      final child = children[i];
      if (child is DocxText) {
        final isBold = child.isBold || forceBold;
        final fontRef = _withUnicodeFallback(
          _fontManager.selectFont(
            isBold: isBold,
            isItalic: child.isItalic,
            fontFamily: child.fontFamily,
          ),
          child.content,
          child.fontFamily,
        );
        final color = child.effectiveColorHex ??
            (child.href != null ? '0563C1' : '000000');

        String? backgroundColor;
        if (child.highlight != DocxHighlight.none) {
          backgroundColor = _highlightToHex(child.highlight);
        } else if (child.shadingFill != null && child.shadingFill != 'auto') {
          backgroundColor = child.shadingFill;
        }

        final runFontSize = (child.fontSize ?? fontSize).toDouble();
        var effFontSize = runFontSize;
        if (child.isSuperscript || child.isSubscript) effFontSize *= 0.6;
        final spaceWidth = _measure(' ', effFontSize, fontRef);

        final text = PdfContentBuilder.decodeHtmlEntities(child.content)
            .replaceAll('\r\n', '\n')
            .replaceAll('\t', '    ');
        final token = RegExp(r'\n|[  ]+|[^  \n]+');
        for (final m in token.allMatches(text)) {
          final part = m.group(0)!;
          if (part == '\n') {
            words.add(_Word.lineBreak(srcIndex: i, srcOffset: m.start));
            pendingGap = 0;
            pendingSpaces = 0;
            continue;
          }
          if (part.trim().isEmpty && !part.contains(RegExp(r'[^  ]'))) {
            pendingGap += spaceWidth * part.length;
            pendingSpaces += part.length;
            continue;
          }

          int? checkboxType;
          if (part == '☐') checkboxType = 0;
          if (part == '☑') checkboxType = 1;
          if (part == '☒') checkboxType = 2;
          final isCheckbox = checkboxType != null;

          final lineStart = atLineStart();
          final shown =
              child.isAllCaps || child.isSmallCaps ? part.toUpperCase() : part;
          addWord(_Word(
            shown,
            fontRef,
            color,
            isCheckbox ? effFontSize : _measure(shown, effFontSize, fontRef),
            gap: lineStart ? 0 : pendingGap,
            // Leading indentation (2+ spaces) at a line start is kept, e.g.
            // code blocks; a single leading space is not.
            lineStartGap: lineStart && pendingSpaces > 1 ? pendingGap : 0,
            noBreakBefore: !lineStart && pendingSpaces == 0,
            isUnderline: child.isUnderline,
            isStrike: child.isStrike,
            backgroundColor: backgroundColor,
            fontSize: runFontSize,
            isSuperscript: child.isSuperscript,
            isSubscript: child.isSubscript,
            isCheckbox: isCheckbox,
            checkboxType: checkboxType,
            href: child.href,
            srcIndex: i,
            srcOffset: m.start,
          ));
        }
      } else if (child is DocxLineBreak) {
        words.add(_Word.lineBreak(srcIndex: i, isChildBreak: true));
        pendingGap = 0;
        pendingSpaces = 0;
      } else if (child is DocxTab) {
        addWord(_Word.tab(srcIndex: i));
      } else if (child is DocxInlineImage) {
        final gap = atLineStart() ? 0.0 : pendingGap;
        addWord(_inlineImageWord(child, register, i, gap));
      } else if (child is DocxShape) {
        final gap = atLineStart() ? 0.0 : pendingGap;
        addWord(_Word.shapeWord(child, child.width, gap: gap, srcIndex: i));
      } else if (child is DocxFootnoteRef || child is DocxEndnoteRef) {
        // The reference itself is just a small superscript number glued to
        // the preceding word; the note content is rendered separately.
        final markerId = child is DocxFootnoteRef
            ? child.footnoteId
            : (child as DocxEndnoteRef).endnoteId;
        final marker = '$markerId';
        final markerFontRef = _fontManager.selectFont();
        final lineStart = atLineStart();
        addWord(_Word(
          marker,
          markerFontRef,
          '000000',
          _measure(marker, fontSize * 0.6, markerFontRef),
          gap: lineStart ? 0 : pendingGap,
          noBreakBefore: !lineStart && pendingSpaces == 0,
          fontSize: fontSize,
          isSuperscript: true,
          srcIndex: i,
        ));
      }
    }
    return words;
  }

  /// Converts DocxHighlight enum to hex color
  String? _highlightToHex(DocxHighlight highlight) {
    switch (highlight) {
      case DocxHighlight.yellow:
        return 'FFFF00';
      case DocxHighlight.green:
        return '00FF00';
      case DocxHighlight.cyan:
        return '00FFFF';
      case DocxHighlight.magenta:
        return 'FF00FF';
      case DocxHighlight.red:
        return 'FF0000';
      case DocxHighlight.blue:
        return '0000FF';
      case DocxHighlight.darkBlue:
        return '00008B';
      case DocxHighlight.darkCyan:
        return '008B8B';
      case DocxHighlight.darkGreen:
        return '006400';
      case DocxHighlight.darkMagenta:
        return '8B008B';
      case DocxHighlight.darkRed:
        return '8B0000';
      case DocxHighlight.darkYellow:
        return '808000';
      case DocxHighlight.lightGray:
        return 'D3D3D3';
      case DocxHighlight.darkGray:
        return 'A9A9A9';
      case DocxHighlight.black:
        return '000000';
      case DocxHighlight.white:
        return 'FFFFFF';
      case DocxHighlight.none:
        return null;
    }
  }

  /// Default tab stops every half inch, as in Word.
  static const double _tabStop = 36.0;

  /// Greedy line packing. The available width can differ per line
  /// (`widthForLine(lineIndex)`) for first-line indents and drop caps.
  /// Glued words (no whitespace between them in the source) move to the
  /// next line together rather than being split mid-word.
  List<_Line> _flowLines(
      List<_Word> words, double Function(int lineIndex) widthForLine) {
    final lines = <_Line>[];
    var current = _Line(afterBreak: true, srcIndex: 0, srcOffset: 0);
    var width = 0.0;

    double gapFor(_Word w, _Line line) =>
        line.words.isEmpty ? (line.afterBreak ? w.lineStartGap : 0) : w.gap;

    for (final word in words) {
      if (word.isBreak) {
        lines.add(current);
        current = _Line(
            afterBreak: true,
            srcIndex: word.srcIndex,
            srcOffset: word.srcOffset + 1,
            srcAfterChild: word.srcOffset == 0 && word.isChildBreak);
        width = 0;
        continue;
      }
      final maxWidth = widthForLine(lines.length);

      var placed = word;
      if (word.isTab) {
        final pos = width;
        final next = ((pos / _tabStop).floor() + 1) * _tabStop;
        placed = word.withWidth(math.max(next - pos, 1));
      }

      final gap = gapFor(placed, current);
      if (current.words.isNotEmpty && width + gap + placed.width > maxWidth) {
        // Carry a glued tail (e.g. "Word" + "glued") to the next line.
        final tail = <_Word>[];
        if (placed.noBreakBefore) {
          while (current.words.isNotEmpty) {
            final last = current.words.removeLast();
            tail.insert(0, last);
            if (!last.noBreakBefore) break;
          }
          if (current.words.isEmpty) {
            // The whole line is one glued group: break inside it instead.
            current.words.addAll(tail);
            tail.clear();
          }
        }
        lines.add(current);
        final first = tail.isNotEmpty ? tail.first : placed;
        current = _Line(
            afterBreak: false,
            srcIndex: first.srcIndex,
            srcOffset: first.srcOffset);
        width = 0;
        for (final w in [...tail, placed]) {
          var p = w;
          if (w.isTab) {
            final next = ((width / _tabStop).floor() + 1) * _tabStop;
            p = w.withWidth(math.max(next - width, 1));
          }
          width += gapFor(p, current) + p.width;
          current.words.add(p);
        }
      } else {
        width += gap + placed.width;
        current.words.add(placed);
      }
    }

    lines.add(current);
    return lines;
  }

  /// Breaks any word wider than [maxWidth] into smaller glued chunks that
  /// each individually fit, so a long word or URL with no natural break
  /// point no longer draws past the right margin unbroken. Words that
  /// already fit, and non-text words (tabs, images, shapes, checkboxes),
  /// pass through unchanged.
  List<_Word> _splitOverlongWords(
      List<_Word> words, double maxWidth, double defaultFontSize) {
    if (maxWidth <= 0) return words;

    final result = <_Word>[];
    for (final word in words) {
      final canSplit = !word.isTab &&
          !word.isBreak &&
          !word.isImage &&
          !word.isShape &&
          !word.isCheckbox &&
          word.width > maxWidth &&
          word.text.runes.length > 1;
      if (!canSplit) {
        result.add(word);
        continue;
      }

      var effFontSize = word.fontSize ?? defaultFontSize;
      if (word.isSuperscript || word.isSubscript) effFontSize *= 0.6;
      final runes = word.text.runes.toList();

      // Measure each rune's width once and accumulate a running sum while
      // extending a chunk, instead of re-measuring the whole growing
      // substring per character (which is quadratic in the word's length).
      final runeWidths = List<double>.generate(
        runes.length,
        (i) =>
            _measure(String.fromCharCode(runes[i]), effFontSize, word.fontRef),
      );

      var start = 0;
      var offset = word.srcOffset;
      while (start < runes.length) {
        var end = start + 1;
        var chunkWidth = runeWidths[start];
        while (end < runes.length && chunkWidth + runeWidths[end] <= maxWidth) {
          chunkWidth += runeWidths[end];
          end++;
        }
        final chunkText = String.fromCharCodes(runes, start, end);
        final isFirst = start == 0;
        result.add(word.copyWithText(
          chunkText,
          chunkWidth,
          gap: isFirst ? word.gap : 0,
          noBreakBefore: isFirst ? word.noBreakBefore : false,
          srcOffset: offset,
        ));
        offset += chunkText.length;
        start = end;
      }
    }
    return result;
  }

  // ===========================================================================
  // Pagination measurement (PdfBlockMeasurer)
  // ===========================================================================

  /// The layout engine of the section currently being processed.
  PdfLayoutEngine? _layoutEngine;

  double get fontSize0 => fontSize.toDouble();

  @override
  double measureParagraph(DocxParagraph paragraph, double width) =>
      _layoutParagraph(paragraph, width).height;

  @override
  List<DocxParagraph> splitParagraph(
      DocxParagraph paragraph, double width, double availableHeight) {
    final pl = _layoutParagraph(paragraph, width);
    var used = pl.spaceBefore + pl.padTop;
    var fit = 0;
    for (final line in pl.lines) {
      if (used + line.height + pl.padBottom > availableHeight + 0.01) break;
      used += line.height;
      fit++;
    }
    final empty = paragraph.copyWith(children: const []);
    if (fit == 0) return [empty, paragraph];
    if (fit >= pl.lines.length) return [paragraph, empty];

    final splitLine = pl.lines[fit];
    final children = paragraph.children;
    final fitted = <DocxInline>[];
    final rest = <DocxInline>[];
    final si = splitLine.srcIndex.clamp(0, children.length);
    fitted.addAll(children.take(si));
    if (si < children.length) {
      final child = children[si];
      if (child is DocxText &&
          splitLine.srcOffset > 0 &&
          !splitLine.srcAfterChild) {
        final text = PdfContentBuilder.decodeHtmlEntities(child.content)
            .replaceAll('\r\n', '\n')
            .replaceAll('\t', '    ');
        final offset = splitLine.srcOffset.clamp(0, text.length);
        final head = text.substring(0, offset);
        var tail = text.substring(offset);
        if (!splitLine.afterBreak) tail = tail.trimLeft();
        if (head.trim().isNotEmpty || head.contains('\n')) {
          fitted.add(child.copyWith(content: head.trimRight()));
        }
        if (tail.isNotEmpty) rest.add(child.copyWith(content: tail));
        rest.addAll(children.skip(si + 1));
      } else if (splitLine.srcAfterChild) {
        fitted.add(child);
        rest.addAll(children.skip(si + 1));
      } else {
        rest.addAll(children.skip(si));
      }
    }
    if (rest.isEmpty) return [paragraph, empty];
    return [
      paragraph.copyWith(children: fitted, spacingAfter: 0),
      paragraph.copyWith(
          children: rest,
          spacingBefore: 0,
          indentFirstLine: 0,
          pageBreakBefore: false),
    ];
  }

  @override
  double measureList(DocxList list, double width) {
    final items = _layoutList(list, width, register: false);
    return items.fold<double>(0, (sum, i) => sum + i.layout.height) +
        fontSize0 * 0.5;
  }

  @override
  List<DocxList> splitList(
      DocxList list, double width, double availableHeight) {
    final items = _layoutList(list, width, register: false);
    var used = fontSize0 * 0.5;
    var fit = 0;
    for (final item in items) {
      if (used + item.layout.height > availableHeight) break;
      used += item.layout.height;
      fit++;
    }
    if (fit >= list.items.length) {
      return [list, list.copyWith(items: const [])];
    }
    // Continue numbering in the remainder by carrying the top-level count.
    final nextTop = fit == 0 ? list.startIndex : items[fit - 1].nextTopLevel;
    return [
      list.copyWith(items: list.items.take(fit).toList()),
      list.copyWith(items: list.items.skip(fit).toList(), startIndex: nextTop),
    ];
  }

  @override
  double measureCell(DocxTableCell cell, double width) =>
      _cellPadding(cell).vertical +
      _measureBlocks(cell.children, width - _cellPadding(cell).horizontal);

  /// Height of a sequence of blocks laid out in a table cell.
  double _measureBlocks(List<DocxBlock> blocks, double width) {
    var height = 0.0;
    for (final block in blocks) {
      if (block is DocxParagraph) {
        height += _layoutParagraph(block, width, kind: _ParaKind.cell).height;
      } else if (block is DocxList) {
        height += measureList(block, width);
      } else if (block is DocxTable) {
        height += _measureNestedTable(block, width);
      } else if (block is DocxImage) {
        height += math.min(block.height, 10000) + 4;
      }
    }
    return height;
  }

  double _measureNestedTable(DocxTable table, double width) {
    final colWidths = _proportionalColumnWidths(table, width);
    var height = 0.0;
    for (final row in table.rows) {
      height += _rowHeight(row, colWidths);
    }
    return height + 4;
  }

  double _rowHeight(DocxTableRow row, List<double> colWidths) {
    var maxHeight = (row.height ?? 0) / 20.0;
    var col = 0;
    for (final cell in row.cells) {
      var w = 0.0;
      for (var j = 0; j < cell.colSpan && col + j < colWidths.length; j++) {
        w += colWidths[col + j];
      }
      maxHeight = math.max(maxHeight, measureCell(cell, w));
      col += cell.colSpan;
    }
    return maxHeight;
  }

  /// Cell padding: the cell's own left/right margins, else the table-wide
  /// cell padding, else Word's defaults (0.08" left/right).
  _Insets _cellPadding(DocxTableCell cell) {
    final left = (cell.marginLeft ?? _currentCellPadding ?? 115) / 20.0;
    final right = (cell.marginRight ?? _currentCellPadding ?? 115) / 20.0;
    return _Insets(left, 3, right, 3);
  }

  int? _currentCellPadding;

  // ===========================================================================
  // Tables
  // ===========================================================================

  /// Renders a table with real column widths (from
  /// [DocxTable.resolvedGridColumns]), colSpan/rowSpan-aware cell placement,
  /// per-cell/table border and style resolution, cell vertical alignment and
  /// nested list/table content in cells. [availableWidth] lets nested
  /// tables (rendered inside a cell) use the cell's width instead of the
  /// full page content width; pagination itself is handled ahead of time by
  /// `PdfLayoutEngine.paginate`, which splits tables by row so they never
  /// overflow the bottom margin.
  double _renderTable(
    DocxTable table,
    PdfContentBuilder builder,
    double startX,
    double startY,
    PdfLayoutEngine layout, {
    double? availableWidth,
  }) {
    if (table.rows.isEmpty) return startY;

    final colWidths = availableWidth != null
        ? _proportionalColumnWidths(table, availableWidth)
        : layout.tableColumnWidths(table);
    if (colWidths.isEmpty) return startY;
    final previousPadding = _currentCellPadding;
    _currentCellPadding = table.style.cellPadding;

    final originX = availableWidth == null
        ? startX + layout.tableOffset(table, colWidths)
        : startX;
    final colX = List<double>.filled(colWidths.length + 1, originX);
    for (var i = 0; i < colWidths.length; i++) {
      colX[i + 1] = colX[i] + colWidths[i];
    }

    var y = startY;
    // Columns still occupied by a rowSpan cell that started on an earlier
    // row: column index -> rows remaining (including the current one).
    final activeSpans = <int, int>{};

    for (final row in table.rows) {
      final rowHeight = _rowHeight(row, colWidths);

      // Map this row's cells onto grid columns, skipping columns currently
      // occupied by a taller cell spanning down from a previous row. This
      // assumes rows omit cells for spanned columns (the convention the
      // DOCX writer itself follows).
      final placements = <_CellPlacement>[];
      var colIndex = 0;
      for (final cell in row.cells) {
        while (
            colIndex < colWidths.length && (activeSpans[colIndex] ?? 0) > 0) {
          colIndex++;
        }
        if (colIndex >= colWidths.length) break;

        var spanWidth = 0.0;
        for (var j = 0;
            j < cell.colSpan && colIndex + j < colWidths.length;
            j++) {
          spanWidth += colWidths[colIndex + j];
        }
        placements
            .add(_CellPlacement(cell, colIndex, colX[colIndex], spanWidth));
        if (cell.rowSpan > 1) {
          for (var j = 0; j < cell.colSpan; j++) {
            activeSpans[colIndex + j] = cell.rowSpan - 1;
          }
        }
        colIndex += cell.colSpan;
      }

      // Backgrounds
      for (final p in placements) {
        final fill = p.cell.shadingFill;
        if (fill != null && fill != 'auto') {
          builder.saveState();
          builder.setFillColorHex(fill.replaceAll('#', ''));
          builder.fillRect(p.x, y - rowHeight, p.width, rowHeight);
          builder.restoreState();
        }
      }

      // Borders: cell-level override wins, else the table's uniform style
      // (honoring DocxTableStyle.plain / DocxBorder.none as "no border").
      for (final p in placements) {
        _drawCellBorders(builder, table, p, y, rowHeight);
      }

      // Content, vertically aligned within the row.
      for (final p in placements) {
        final pad = _cellPadding(p.cell);
        final innerWidth = p.width - pad.horizontal;
        final contentHeight = _measureBlocks(p.cell.children, innerWidth);
        final slack = rowHeight - pad.vertical - contentHeight;
        var offset = 0.0;
        if (slack > 0) {
          if (p.cell.verticalAlign == DocxVerticalAlign.center) {
            offset = slack / 2;
          } else if (p.cell.verticalAlign == DocxVerticalAlign.bottom) {
            offset = slack;
          }
        }
        final cellX = p.x + pad.left;
        var cellY = y - pad.top - offset;
        for (final block in p.cell.children) {
          if (block is DocxParagraph) {
            final pl = _layoutParagraph(block, innerWidth,
                kind: _ParaKind.cell, register: true);
            cellY = _drawParagraph(pl, builder, cellX, cellY);
          } else if (block is DocxList) {
            cellY = _drawList(block, builder, cellX, cellY, innerWidth);
          } else if (block is DocxTable) {
            cellY = _renderTable(block, builder, cellX, cellY, layout,
                    availableWidth: innerWidth) +
                6;
          } else if (block is DocxImage) {
            cellY = _renderImage(block, builder, cellX, cellY, layout,
                    availableWidth: innerWidth) +
                6;
          }
        }
      }

      // Age spans that were already active going into this row; ones that
      // just started here already have `rowSpan - 1` remaining rows AFTER
      // this one, so they're left untouched.
      final startedHere = <int>{
        for (final p in placements)
          for (var j = 0; j < p.cell.colSpan; j++) p.colIndex + j
      };
      for (final key in activeSpans.keys.toList()) {
        if (startedHere.contains(key)) continue;
        final remaining = activeSpans[key]! - 1;
        if (remaining <= 0) {
          activeSpans.remove(key);
        } else {
          activeSpans[key] = remaining;
        }
      }

      y -= rowHeight;
    }

    _currentCellPadding = previousPadding;
    return y - (availableWidth == null ? 10 : 4);
  }

  /// Same as [PdfLayoutEngine.tableColumnWidths] but scaled to an explicit
  /// width instead of the page's content width, for tables nested in cells.
  List<double> _proportionalColumnWidths(
      DocxTable table, double availableWidth) {
    final gridColumns = table.resolvedGridColumns;
    if (gridColumns.isEmpty) return const [];
    final totalGridTwips = gridColumns.fold<int>(0, (a, b) => a + b);
    if (totalGridTwips <= 0) {
      final n = gridColumns.length;
      return List<double>.filled(n, availableWidth / n);
    }
    return gridColumns.map((w) => w / totalGridTwips * availableWidth).toList();
  }

  /// Resolves a cell border side to a drawable color/width, or null if that
  /// side should not be drawn at all (e.g. `DocxTableStyle.plain`).
  _ResolvedBorder? _resolveCellBorder(
      DocxTable table, DocxBorderSide? cellSide) {
    if (cellSide != null) {
      if (cellSide.style == DocxBorder.none) return null;
      final hex =
          cellSide.color == DocxColor.auto ? '000000' : cellSide.color.hex;
      return _ResolvedBorder(hex, cellSide.size / 8.0);
    }
    if (table.style.border == DocxBorder.none) return null;
    final hex = table.style.borderColor == 'auto'
        ? '000000'
        : table.style.borderColor.replaceAll('#', '');
    return _ResolvedBorder(hex, table.style.borderWidth / 8.0);
  }

  void _drawCellBorders(PdfContentBuilder builder, DocxTable table,
      _CellPlacement p, double y, double rowHeight) {
    final top = _resolveCellBorder(table, p.cell.borderTop);
    final bottom = _resolveCellBorder(table, p.cell.borderBottom);
    final left = _resolveCellBorder(table, p.cell.borderLeft);
    final right = _resolveCellBorder(table, p.cell.borderRight);
    if (top == null && bottom == null && left == null && right == null) {
      return;
    }

    final boxTop = y;
    final boxBottom = y - rowHeight;
    final boxLeft = p.x;
    final boxRight = p.x + p.width;

    builder.saveState();
    if (top != null) {
      builder.setStrokeColorHex(top.colorHex);
      builder.drawLine(boxLeft, boxTop, boxRight, boxTop,
          lineWidth: top.widthPt);
    }
    if (bottom != null) {
      builder.setStrokeColorHex(bottom.colorHex);
      builder.drawLine(boxLeft, boxBottom, boxRight, boxBottom,
          lineWidth: bottom.widthPt);
    }
    if (left != null) {
      builder.setStrokeColorHex(left.colorHex);
      builder.drawLine(boxLeft, boxTop, boxLeft, boxBottom,
          lineWidth: left.widthPt);
    }
    if (right != null) {
      builder.setStrokeColorHex(right.colorHex);
      builder.drawLine(boxRight, boxTop, boxRight, boxBottom,
          lineWidth: right.widthPt);
    }
    builder.restoreState();
  }

  // ===========================================================================
  // Lists
  // ===========================================================================

  static const _defaultListStyle = DocxListStyle();
  static const _defaultBullets = ['•', '○', '▪'];
  static const _defaultNumberFormats = [
    DocxNumberFormat.decimal,
    DocxNumberFormat.lowerAlpha,
    DocxNumberFormat.lowerRoman,
  ];

  /// Mirrors the DOCX numbering the package writes: a list using the
  /// default style cycles bullets (•, ○, ▪) or formats (1, a, i) by level;
  /// a customised style applies its own bullet/format at every level.
  bool _isCustomListStyle(DocxListStyle style, bool isOrdered) {
    const ref = _defaultListStyle;
    final custom = style.fontFamily != null ||
        style.fontSize != null ||
        style.fontWeight != ref.fontWeight ||
        style.color != ref.color ||
        style.indentPerLevel != ref.indentPerLevel ||
        style.hangingIndent != ref.hangingIndent;
    return isOrdered
        ? custom || style.numberFormat != ref.numberFormat
        : custom || style.bullet != ref.bullet;
  }

  /// Lays out every item of [list]: marker text plus a paragraph layout
  /// indented like the DOCX numbering (`w:ind left=(lvl+1)*indent`).
  List<_ListItemLayout> _layoutList(DocxList list, double width,
      {required bool register}) {
    final result = <_ListItemLayout>[];
    final counters = <int, int>{};

    for (final item in list.items) {
      final style = item.overrideStyle ?? list.style;
      final custom = _isCustomListStyle(style, list.isOrdered);
      final level = item.level.clamp(0, 8);
      counters.removeWhere((l, _) => l > level);

      String marker;
      if (list.isOrdered) {
        final start = level == 0 ? list.startIndex : 1;
        final next = (counters[level] ?? (start - 1)) + 1;
        counters[level] = next;
        final format =
            custom ? style.numberFormat : _defaultNumberFormats[level % 3];
        marker = '${_formatListNumber(format, next)}.';
      } else {
        marker = custom ? style.bullet : _defaultBullets[level % 3];
      }

      final itemFontSize = style.fontSize ?? fontSize0;
      final indentTwips = style.indentPerLevel * (level + 1);
      final synthetic = DocxParagraph(
        children: item.children,
        indentLeft: indentTwips,
      );
      final pl = _layoutParagraph(synthetic, width,
          kind: _ParaKind.listItem,
          fontSizeOverride: itemFontSize,
          register: register);
      result.add(_ListItemLayout(
        layout: pl,
        marker: marker,
        markerX: (indentTwips - style.hangingIndent) / 20.0,
        markerColor:
            style.color == DocxColor.black || style.color == DocxColor.auto
                ? '000000'
                : style.color.hex,
        markerBold: style.fontWeight == DocxFontWeight.bold,
        fontSize: itemFontSize,
        nextTopLevel: (counters[0] ?? (list.startIndex - 1)) + 1,
      ));
    }
    return result;
  }

  String _formatListNumber(DocxNumberFormat format, int n) {
    switch (format) {
      case DocxNumberFormat.lowerAlpha:
        return _alpha(n).toLowerCase();
      case DocxNumberFormat.upperAlpha:
        return _alpha(n);
      case DocxNumberFormat.lowerRoman:
        return _roman(n).toLowerCase();
      case DocxNumberFormat.upperRoman:
        return _roman(n);
      default:
        return '$n';
    }
  }

  static String _alpha(int n) {
    if (n <= 0) return '$n';
    var value = n;
    final buf = StringBuffer();
    while (value > 0) {
      value--;
      buf.write(String.fromCharCode(65 + value % 26));
      value ~/= 26;
    }
    return buf.toString().split('').reversed.join();
  }

  static String _roman(int n) {
    if (n <= 0 || n >= 4000) return '$n';
    const values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1];
    const symbols = [
      'M',
      'CM',
      'D',
      'CD',
      'C',
      'XC',
      'L',
      'XL',
      'X',
      'IX',
      'V',
      'IV',
      'I'
    ];
    var value = n;
    final buf = StringBuffer();
    for (var i = 0; i < values.length; i++) {
      while (value >= values[i]) {
        buf.write(symbols[i]);
        value -= values[i];
      }
    }
    return buf.toString();
  }

  double _renderList(
    DocxList list,
    PdfContentBuilder builder,
    double startX,
    double startY,
    PdfLayoutEngine layout,
  ) {
    return _drawList(list, builder, startX, startY, layout.contentWidth) -
        fontSize0 * 0.5;
  }

  /// Draws [list] in a box [width] wide at ([startX], [startY]); returns
  /// the y below its last item.
  double _drawList(DocxList list, PdfContentBuilder builder, double startX,
      double startY, double width) {
    var y = startY;
    for (final item in _layoutList(list, width, register: true)) {
      final pl = item.layout;
      if (pl.lines.isNotEmpty) {
        final baseline =
            y - pl.spaceBefore - pl.padTop - pl.lines.first.baseline;
        final markerFont = _withUnicodeFallback(
            _fontManager.selectFont(isBold: item.markerBold),
            item.marker,
            null);
        builder.beginText();
        builder.setTextMatrix(startX + math.max(0, item.markerX), baseline);
        builder.setFont(markerFont, item.fontSize);
        builder.setFillColorHex(item.markerColor);
        builder.showText(item.marker);
        builder.endText();
      }
      y = _drawParagraph(pl, builder, startX, y);
    }
    return y;
  }

  double _renderImage(
    DocxImage image,
    PdfContentBuilder builder,
    double x,
    double y,
    PdfLayoutEngine layout, {
    double? availableWidth,
  }) {
    final writer = _writer;
    final bytes = image.bytes;
    if (writer == null) return y;

    // Register image with writer
    final imageId = writer.addImage(
      bytes: bytes,
      width: image.width.toInt(),
      height: image.height.toInt(),
    );

    final imageName = '/Im${++_imageCount}';
    _pageImages[imageName] = imageId;

    // Images wider than the available width are scaled down to fit,
    // keeping their aspect ratio (see PdfLayoutEngine.measureNode).
    final maxWidth = availableWidth ?? layout.contentWidth;
    final scale = image.width > maxWidth && image.width > 0
        ? maxWidth / image.width
        : 1.0;
    final renderWidth = image.width * scale;
    final renderHeight = image.height * scale;

    // Calculate X position based on alignment (mirrors _renderShapeBlock).
    var drawX = x;
    if (image.align == DocxAlign.center) {
      drawX = x + (maxWidth - renderWidth) / 2;
    } else if (image.align == DocxAlign.right) {
      drawX = x + maxWidth - renderWidth;
    }

    // PDF coordinates are bottom-up: draw with the image's top at y.
    builder.drawImage(
        imageName, drawX, y - renderHeight, renderWidth, renderHeight);
    _drawImageBorder(builder, image.border, drawX, y - renderHeight,
        renderWidth, renderHeight);

    return y - renderHeight - 10;
  }

  /// Draws a uniform rectangular border (all four sides the same style)
  /// around an already-drawn image, matching what `DocxImage`/
  /// `DocxInlineImage.border` produces in DOCX. No-op when [border] is null
  /// or `DocxBorder.none`.
  void _drawImageBorder(PdfContentBuilder builder, DocxBorderSide? border,
      double x, double y, double width, double height) {
    if (border == null || border.style == DocxBorder.none) return;
    builder.saveState();
    builder.setStrokeColorHex(
        border.color == DocxColor.auto ? '000000' : border.color.hex);
    builder.strokeRect(x, y, width, height, lineWidth: border.size / 8.0);
    builder.restoreState();
  }

  /// Returns a placeholder "word" for a [DocxInlineImage] so it flows into
  /// the surrounding text like any other word. With [register] the image
  /// is also added to the PDF as a page XObject; measurement-only layout
  /// passes skip that so pagination doesn't embed images twice.
  _Word _inlineImageWord(
      DocxInlineImage image, bool register, int srcIndex, double gap) {
    String? imageName;
    final writer = _writer;
    if (register && writer != null) {
      final imageId = writer.addImage(
        bytes: image.bytes,
        width: image.width.toInt(),
        height: image.height.toInt(),
      );
      imageName = '/Im${++_imageCount}';
      _pageImages[imageName] = imageId;
    }
    return _Word.image(imageName, image.width, image.height,
        border: image.border, gap: gap, srcIndex: srcIndex);
  }

  List<_SectionData> _splitSections(DocxBuiltDocument doc) {
    final result = <_SectionData>[];
    var currentNodes = <DocxNode>[];

    var currentDef = doc.section ??
        DocxSectionDef(
          pageSize: DocxPageSize.letter,
          marginTop: (marginTop * 20).toInt(),
          marginBottom: (marginBottom * 20).toInt(),
          marginLeft: (marginLeft * 20).toInt(),
          marginRight: (marginRight * 20).toInt(),
        );

    for (final node in doc.elements) {
      if (node is DocxSectionBreakBlock) {
        result.add(_SectionData.fromDef(node.section, currentNodes));
        currentNodes = [];
        currentDef = doc.section ?? currentDef;
      } else {
        currentNodes.add(node);
      }
    }

    if (currentNodes.isNotEmpty) {
      result.add(_SectionData.fromDef(currentDef, currentNodes));
    }

    if (result.isEmpty) {
      result.add(_SectionData.fromDef(currentDef, []));
    }

    return result;
  }
}

class _SectionData {
  final double width;
  final double height;
  final double marginTop;
  final double marginBottom;
  final double marginLeft;
  final double marginRight;
  final List<DocxNode> nodes;
  final DocxNode? header;
  final DocxNode? footer;
  final DocxColor? backgroundColor;
  final DocxBackgroundImage? backgroundImage;

  _SectionData({
    required this.width,
    required this.height,
    required this.marginTop,
    required this.marginBottom,
    required this.marginLeft,
    required this.marginRight,
    required this.nodes,
    this.header,
    this.footer,
    this.backgroundColor,
    this.backgroundImage,
  });

  factory _SectionData.fromDef(DocxSectionDef def, List<DocxNode> nodes) {
    return _SectionData(
      width: def.effectiveWidth / 20.0,
      height: def.effectiveHeight / 20.0,
      marginTop: def.marginTop / 20.0,
      marginBottom: def.marginBottom / 20.0,
      marginLeft: def.marginLeft / 20.0,
      marginRight: def.marginRight / 20.0,
      nodes: nodes,
      header: def.header,
      footer: def.footer,
      backgroundColor: def.backgroundColor,
      backgroundImage: def.backgroundImage,
    );
  }
}

/// A table cell resolved to its grid position and pixel geometry for one
/// rendering pass of `PdfExporter._renderTable`.
class _CellPlacement {
  final DocxTableCell cell;
  final int colIndex;
  final double x;
  final double width;

  const _CellPlacement(this.cell, this.colIndex, this.x, this.width);
}

/// A drawable border side: color plus stroke width in points.
class _ResolvedBorder {
  final String colorHex;
  final double widthPt;

  const _ResolvedBorder(this.colorHex, this.widthPt);
}

/// One flowable unit of a line: a word of text, a checkbox, an inline
/// image/shape, a tab, or a hard line break.
class _Word {
  final String text;
  final String fontRef;
  final String color;
  final double width;
  final bool isTab;
  final bool isBreak;

  /// Whitespace width before this word when it isn't first on its line
  /// (0 when glued to the previous word).
  final double gap;

  /// Leading indentation kept when this word starts a line after a hard
  /// break (e.g. indented code).
  final double lineStartGap;

  /// True when no whitespace separates this word from the previous one in
  /// the source (`Word<b>glued</b>`, a split chunk excluded): the line
  /// breaker keeps the two together.
  final bool noBreakBefore;

  // Text decorations
  final bool isUnderline;
  final bool isStrike;

  // Background color (from highlight or shadingFill)
  final String? backgroundColor;

  // Font adjustments (run font size before any sub/superscript scaling)
  final double? fontSize;
  final bool isSuperscript;
  final bool isSubscript;

  // Custom rendering
  final bool isCheckbox;
  final int? checkboxType; // 0=unchecked, 1=checked, 2=crossed

  // Hyperlink target, if this word came from a DocxText with an href.
  final String? href;

  // Inline image, if this "word" is actually a DocxInlineImage. The
  // XObject name is null during measurement-only layout.
  final bool isImage;
  final String? imageXObjectName;
  final double imageHeight;
  final DocxBorderSide? imageBorder;

  // Inline shape, if this "word" is actually a DocxShape.
  final bool isShape;
  final DocxShape? shape;

  /// Source position (paragraph child index and character offset in the
  /// run's text), used to split a paragraph exactly at a line boundary.
  final int srcIndex;
  final int srcOffset;

  /// True for a break produced by a [DocxLineBreak] child (as opposed to a
  /// newline inside a run's text).
  final bool isChildBreak;

  const _Word(
    this.text,
    this.fontRef,
    this.color,
    this.width, {
    this.gap = 0,
    this.lineStartGap = 0,
    this.noBreakBefore = false,
    this.isUnderline = false,
    this.isStrike = false,
    this.backgroundColor,
    this.fontSize,
    this.isSuperscript = false,
    this.isSubscript = false,
    this.isCheckbox = false,
    this.checkboxType,
    this.href,
    this.srcIndex = 0,
    this.srcOffset = 0,
    this.isTab = false,
    this.isBreak = false,
    this.isImage = false,
    this.imageXObjectName,
    this.imageHeight = 0,
    this.imageBorder,
    this.isShape = false,
    this.shape,
    this.isChildBreak = false,
  });

  static _Word tab({int srcIndex = 0}) =>
      _Word('', '', '', 0, isTab: true, srcIndex: srcIndex);

  static _Word lineBreak(
          {int srcIndex = 0, int srcOffset = 0, bool isChildBreak = false}) =>
      _Word('', '', '', 0,
          isBreak: true,
          srcIndex: srcIndex,
          srcOffset: srcOffset,
          isChildBreak: isChildBreak);

  static _Word image(String? name, double width, double height,
          {DocxBorderSide? border, double gap = 0, int srcIndex = 0}) =>
      _Word('', '', '', width,
          isImage: true,
          imageXObjectName: name,
          imageHeight: height,
          imageBorder: border,
          gap: gap,
          srcIndex: srcIndex);

  static _Word shapeWord(DocxShape shape, double width,
          {double gap = 0, int srcIndex = 0}) =>
      _Word('', '', '', width,
          isShape: true, shape: shape, gap: gap, srcIndex: srcIndex);

  _Word withWidth(double newWidth) => _Word(text, fontRef, color, newWidth,
      gap: gap,
      lineStartGap: lineStartGap,
      noBreakBefore: noBreakBefore,
      isTab: isTab,
      srcIndex: srcIndex,
      srcOffset: srcOffset);

  _Word copyWithText(String newText, double newWidth,
          {required double gap,
          required bool noBreakBefore,
          required int srcOffset}) =>
      _Word(newText, fontRef, color, newWidth,
          gap: gap,
          lineStartGap: gap == 0 ? 0 : lineStartGap,
          noBreakBefore: noBreakBefore,
          isUnderline: isUnderline,
          isStrike: isStrike,
          backgroundColor: backgroundColor,
          fontSize: fontSize,
          isSuperscript: isSuperscript,
          isSubscript: isSubscript,
          href: href,
          srcIndex: srcIndex,
          srcOffset: srcOffset);
}

/// A flowed line and its resolved metrics.
class _Line {
  final List<_Word> words = [];

  /// True for the first line of a paragraph or a line after a hard break.
  final bool afterBreak;

  /// Where this line starts in the paragraph's children (see
  /// [_Word.srcIndex]); [srcAfterChild] means "after child [srcIndex]".
  final int srcIndex;
  final int srcOffset;
  final bool srcAfterChild;

  double height = 0;

  /// Distance from the line's top to its baseline.
  double baseline = 0;

  _Line({
    required this.afterBreak,
    required this.srcIndex,
    required this.srcOffset,
    this.srcAfterChild = false,
  });
}

/// Where a paragraph appears, which picks its default spacing.
enum _ParaKind { body, cell, listItem }

/// A paragraph laid out into lines, with all box metrics in points.
class _ParaLayout {
  final DocxParagraph paragraph;
  final double fontSize;
  final List<_Line> lines;
  final double spaceBefore;
  final double spaceAfter;
  final double padTop;
  final double padBottom;
  final double padLeft;
  final double padRight;
  final double indentLeft;
  final double firstLineIndent;
  final double textWidth;

  _ParaLayout({
    required this.paragraph,
    required this.fontSize,
    required this.lines,
    required this.spaceBefore,
    required this.spaceAfter,
    required this.padTop,
    required this.padBottom,
    required this.padLeft,
    required this.padRight,
    required this.indentLeft,
    required this.firstLineIndent,
    required this.textWidth,
  });

  double get linesHeight => lines.fold<double>(0, (sum, l) => sum + l.height);

  double get height =>
      spaceBefore + padTop + linesHeight + padBottom + spaceAfter;
}

class _ListItemLayout {
  final _ParaLayout layout;
  final String marker;
  final double markerX;
  final String markerColor;
  final bool markerBold;
  final double fontSize;
  final int nextTopLevel;

  _ListItemLayout({
    required this.layout,
    required this.marker,
    required this.markerX,
    required this.markerColor,
    required this.markerBold,
    required this.fontSize,
    required this.nextTopLevel,
  });
}

class _Insets {
  final double left;
  final double top;
  final double right;
  final double bottom;

  const _Insets(this.left, this.top, this.right, this.bottom);

  double get horizontal => left + right;
  double get vertical => top + bottom;
}

/// A fully-rendered page's content stream plus everything [PdfExporter]
/// needs to turn it into an actual PDF page object, minus the font map -
/// which isn't known until every pending page has been collected. See
/// [PdfExporter.exportToBytes].
class _PendingPage {
  final String content;
  final double width;
  final double height;
  final Map<String, int> xObjectIds;
  final Map<String, int>? extGStateIds;
  final List<_PendingLink> links;

  const _PendingPage({
    required this.content,
    required this.width,
    required this.height,
    required this.xObjectIds,
    required this.extGStateIds,
    required this.links,
  });
}

/// A pending clickable-link rectangle to attach to the current PDF page once
/// its object ID is known (annotations are added after the page's content
/// stream is finalized).
class _PendingLink {
  final double x;
  final double y;
  final double width;
  final double height;
  final String uri;

  const _PendingLink({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.uri,
  });
}

/// An underline/strikethrough rule collected while drawing a line.
class _TextDecoration {
  final double x;
  final double y;
  final double width;
  final String color;
  final double thickness;

  const _TextDecoration({
    required this.x,
    required this.y,
    required this.width,
    required this.color,
    required this.thickness,
  });
}
