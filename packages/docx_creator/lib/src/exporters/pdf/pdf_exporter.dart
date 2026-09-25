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
class PdfExporter {
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
    );

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
  /// per-line widths ([_flowWordsVariableWidth]) instead of the earlier
  /// approach of concatenating letter + text into one oversized paragraph.
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
        _collectWords(dropCap.restOfParagraph, builder, baseFontSize, false);
    final spaceWidth = baseFontSize * 0.278;
    // Split against the narrower of the two widths so a long word can never
    // overflow either the column beside the drop cap letter or the
    // full-width lines below it.
    final splitWidth = narrowWidth > 0 ? narrowWidth : maxWidth;
    final splitWords =
        _splitOverlongWords(words, splitWidth, baseFontSize, builder);
    final lines = _flowWordsVariableWidth(
        splitWords, spaceWidth,
        (i) => i < dropCap.lines ? narrowWidth : maxWidth);

    final lineHeights = <double>[];
    for (final line in lines) {
      if (line.isEmpty) {
        lineHeights.add(dropCapLineHeight);
        continue;
      }
      lineHeights.add(_lineHeightFor(line, baseFontSize));
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
    var lineY = y - baseFontSize;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final currentLineHeight = lineHeights[i];
      if (line.isNotEmpty) {
        final narrow = i < dropCap.lines;
        _drawWordLine(
          builder: builder,
          line: line,
          startX: narrow ? x + dropCapWidth + hGap : x,
          lineMaxWidth: narrow ? narrowWidth : maxWidth,
          y: lineY,
          fontSize: baseFontSize,
          spaceWidth: spaceWidth,
          align: DocxAlign.left,
          isLastLine: i == lines.length - 1,
          decorations: decorations,
        );
      }
      lineY -= currentLineHeight;
    }

    for (final dec in decorations) {
      builder.saveState();
      builder.setStrokeColorHex(dec.color);
      builder.drawLine(dec.x, dec.y, dec.x + dec.width, dec.y, lineWidth: 0.5);
      builder.restoreState();
    }

    final textBottom = lineY;
    final dropCapBottom = y - dropCapBlockHeight;
    final finalY = textBottom < dropCapBottom ? textBottom : dropCapBottom;
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

  double _renderParagraph(
    DocxParagraph paragraph,
    PdfContentBuilder builder,
    double startX,
    double startY,
    PdfLayoutEngine layout,
  ) {
    final fontSize = layout.getFontSize(paragraph.styleId);
    final lineHeight = fontSize * 1.4;
    final indent = (paragraph.indentLeft ?? 0) / 20.0;
    final indentRight = (paragraph.indentRight ?? 0) / 20.0;

    final paddingLeft = (paragraph.paddingLeft ?? 0) / 20.0;
    final paddingRight = (paragraph.paddingRight ?? 0) / 20.0;
    final paddingTop = (paragraph.paddingTop ?? 0) / 20.0;
    final paddingBottom = (paragraph.paddingBottom ?? 0) / 20.0;

    final maxWidth =
        layout.contentWidth - indent - indentRight - paddingLeft - paddingRight;

    // Collect words with their formatting
    final isHeading = paragraph.styleId?.startsWith('Heading') ?? false;
    var words = _collectWords(paragraph.children, builder, fontSize, isHeading);
    words = _splitOverlongWords(words, maxWidth, fontSize, builder);

    // Flow words into lines - use proper Helvetica space width (0.278)
    final spaceWidth = fontSize * 0.278;
    final lines = _flowWords(words, maxWidth, spaceWidth);

    // Track decoration positions for drawing after text
    final decorations = <_TextDecoration>[];

    // Calculate per-line heights based on max font size in each line (and
    // any inline image/shape taller than the text, so the cursor advances
    // far enough to clear it instead of overlapping whatever is drawn next
    // - see [_lineHeightFor]).
    final lineHeights = <double>[];
    for (final line in lines) {
      if (line.isEmpty) {
        lineHeights.add(lineHeight);
      } else {
        lineHeights.add(_lineHeightFor(line, fontSize));
      }
    }

    // Calculate total height for paragraph background
    final totalParagraphHeight =
        lineHeights.fold<double>(0, (sum, h) => sum + h) +
            paddingTop +
            paddingBottom;

    // Draw paragraph background (use full width for code blocks etc.)
    if (paragraph.shadingFill != null && paragraph.shadingFill != 'auto') {
      builder.saveState();
      builder.setFillColorHex(paragraph.shadingFill!);
      final bgBottom = startY - totalParagraphHeight;
      // Background covers indent + padding + text width + padding
      // But standard Word behavior suggests background covers the entire block width INCLUDING indent?
      // Actually, shading usually applies to the text box.
      // If we want FULL shading, we might strictly use (maxWidth + paddingLeft + paddingRight).
      // Let's stick to the box model we built: indent implies empty space outside.
      builder.fillRect(startX + indent, bgBottom,
          maxWidth + paddingLeft + paddingRight, totalParagraphHeight);
      builder.restoreState();
    }

    // Draw paragraph borders (e.g. <hr>/blockquote/code-block rules), which
    // were previously only used to derive spacing and never actually drawn.
    if (paragraph.borderTop != null ||
        paragraph.borderBottomSide != null ||
        paragraph.borderLeft != null ||
        paragraph.borderRight != null) {
      final boxLeft = startX + indent;
      final boxRight = startX + indent + maxWidth + paddingLeft + paddingRight;
      final boxTop = startY;
      final boxBottom = startY - totalParagraphHeight;

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

    // Render lines (adjust Y for padding)
    // Baseline should be approx 1em down from top to fit text inside the line height
    var y = startY - paddingTop - fontSize;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final currentLineHeight = lineHeights[i];

      if (line.isEmpty) {
        y -= currentLineHeight;
        continue;
      }

      _drawWordLine(
        builder: builder,
        line: line,
        startX: startX + indent + paddingLeft,
        lineMaxWidth: maxWidth,
        y: y,
        fontSize: fontSize,
        spaceWidth: spaceWidth,
        align: paragraph.align,
        isLastLine: i == lines.length - 1,
        decorations: decorations,
      );

      // Move to next line
      y -= currentLineHeight;
    }

    _strokeDecorations(builder, decorations);

    if (lines.isEmpty) y = startY - lineHeight;

    // Add extra spacing after paragraphs (especially headings)
    final spacing = isHeading ? fontSize * 0.8 : fontSize * 0.5;
    return y - spacing;
  }

  /// Height a flowed line needs to draw without clipping/overlapping
  /// whatever comes next: the tallest text run on the line (`fontSize *
  /// 1.4`, matching every other line-height computation in this file), or
  /// an inline image/shape's own height when that's taller. Inline images
  /// and shapes carry no [_Word.fontSize] (they're not text), so a plain
  /// max-of-fontSize scan silently ignores them - previously the line
  /// advance after a line containing e.g. a badge icon or inline shape used
  /// only the text line height, leaving the cursor far short of clearing
  /// the image and causing every following line/paragraph to be drawn on
  /// top of it.
  double _lineHeightFor(List<_Word> line, double fontSize) {
    var maxFontInLine = fontSize;
    var maxBlockHeight = 0.0;
    for (final word in line) {
      final wordFontSize = (word.fontSize ?? fontSize).toDouble();
      if (wordFontSize > maxFontInLine) maxFontInLine = wordFontSize;
      if (word.isImage) {
        if (word.imageHeight > maxBlockHeight) maxBlockHeight = word.imageHeight;
      } else if (word.isShape) {
        final shapeHeight = word.shape!.height;
        if (shapeHeight > maxBlockHeight) maxBlockHeight = shapeHeight;
      }
    }
    final textLineHeight = maxFontInLine * 1.4;
    return maxBlockHeight > textLineHeight ? maxBlockHeight : textLineHeight;
  }

  /// Strokes underline/strikethrough rules collected by [_drawWordLine]
  /// while drawing a paragraph/list item/cell's lines. Must run after the
  /// text is drawn - a line can't be stroked inside a PDF text object.
  void _strokeDecorations(
      PdfContentBuilder builder, List<_TextDecoration> decorations) {
    for (final dec in decorations) {
      builder.saveState();
      builder.setStrokeColorHex(dec.color);
      builder.drawLine(dec.x, dec.y, dec.x + dec.width, dec.y, lineWidth: 0.5);
      builder.restoreState();
    }
  }

  /// Draws one already-flowed line of words (text, images, shapes,
  /// checkboxes) at baseline [y], resolving [align] against [lineMaxWidth]
  /// to find the line's starting x. Shared between [_renderParagraph] and
  /// the drop cap's rest-of-paragraph flow ([_renderDropCap]) so both draw
  /// words identically — the only difference between them is what width/x
  /// each line gets, which the caller decides per line.
  void _drawWordLine({
    required PdfContentBuilder builder,
    required List<_Word> line,
    required double startX,
    required double lineMaxWidth,
    required double y,
    required double fontSize,
    required double spaceWidth,
    required DocxAlign align,
    required bool isLastLine,
    required List<_TextDecoration> decorations,
  }) {
    // Calculate max font size for this line for proper baseline positioning
    var maxFontInLine = fontSize;
    for (final word in line) {
      final wordFontSize = (word.fontSize ?? fontSize).toDouble();
      if (wordFontSize > maxFontInLine) maxFontInLine = wordFontSize;
    }

    // Calculate alignment
    var lineWidth = 0.0;
    for (var j = 0; j < line.length; j++) {
      lineWidth += line[j].width;
      if (j < line.length - 1 && !line[j + 1].glueToPrevious) {
        lineWidth += spaceWidth;
      }
    }

    var x = startX;
    var wordSpacing = 0.0;

    if (align == DocxAlign.center) {
      x += (lineMaxWidth - lineWidth) / 2;
    } else if (align == DocxAlign.right) {
      x += lineMaxWidth - lineWidth;
    } else if (align == DocxAlign.justify && !isLastLine) {
      var spaceCount = 0;
      for (var j = 1; j < line.length; j++) {
        if (!line[j].glueToPrevious) spaceCount++;
      }
      if (spaceCount > 0) {
        final slack = lineMaxWidth - lineWidth;
        if (slack > 0 && slack < fontSize * 2) {
          wordSpacing = slack / spaceCount;
        }
      }
    }

    // First pass: draw text backgrounds
    var bgX = x;
    for (var k = 0; k < line.length; k++) {
      final word = line[k];
      if (!word.isTab && word.backgroundColor != null) {
        final wordFontSize = (word.fontSize ?? fontSize).toDouble();
        builder.saveState();
        builder.setFillColorHex(word.backgroundColor!);
        // Draw background rectangle behind word using word's font size
        builder.fillRect(
            bgX, y - wordFontSize * 0.2, word.width, wordFontSize * 1.2);
        builder.restoreState();
      }
      bgX += word.width;
      if (k < line.length - 1 && !line[k + 1].glueToPrevious) {
        bgX += spaceWidth + wordSpacing;
      }
    }

    // Second pass: draw text with manual position tracking
    var textX = x;

    for (var k = 0; k < line.length; k++) {
      final word = line[k];

      if (word.isTab) {
        textX += word.width;
      } else if (word.isImage) {
        final imgY = y - word.imageHeight * 0.8;
        builder.drawImage(
            word.imageXObjectName!, textX, imgY, word.width, word.imageHeight);
        _drawImageBorder(builder, word.imageBorder, textX, imgY, word.width,
            word.imageHeight);
        textX += word.width;
        if (k < line.length - 1 && !line[k + 1].glueToPrevious) {
          textX += spaceWidth + wordSpacing;
        }
      } else if (word.isShape) {
        _drawShape(builder, word.shape!, textX, y - word.shape!.height * 0.8);
        textX += word.width;
        if (k < line.length - 1 && !line[k + 1].glueToPrevious) {
          textX += spaceWidth + wordSpacing;
        }
      } else if (word.isCheckbox) {
        // Draw checkbox manually
        builder.saveState();

        final boxSize = fontSize * 0.8;
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
        textX += word.width;

        if (k < line.length - 1 && !line[k + 1].glueToPrevious) {
          textX += spaceWidth + wordSpacing;
        }
      } else {
        // Normal text rendering with absolute positioning
        var effFontSize = (word.fontSize ?? fontSize).toDouble();
        var yPos = y;

        if (word.isSuperscript) {
          effFontSize *= 0.6;
          yPos = y + maxFontInLine * 0.4;
        } else if (word.isSubscript) {
          effFontSize *= 0.6;
          yPos = y - maxFontInLine * 0.2;
        }

        builder.beginText();
        builder.setTextMatrix(textX, yPos);
        builder.setFont(word.fontRef, effFontSize);
        builder.setFillColorHex(word.color);
        builder.showText(word.text);
        // Every word gets its own absolutely-positioned Tj, so a text
        // extractor (pypdf, browser copy/paste, ...) sees no natural glyph
        // advance to infer a word boundary from - draw an actual space
        // glyph between words instead of just leaving a positional gap, or
        // adjacent words silently run together when extracted/searched.
        if (k < line.length - 1 && !line[k + 1].glueToPrevious) {
          builder.setTextMatrix(textX + word.width, yPos);
          builder.showText(' ');
        }
        builder.endText();

        // Collect underline/strikethrough decorations
        if (word.isUnderline) {
          decorations.add(_TextDecoration(
            x: textX,
            y: yPos - effFontSize * 0.15,
            width: word.width,
            color: word.color,
            isStrike: false,
          ));
        }
        if (word.isStrike) {
          decorations.add(_TextDecoration(
            x: textX,
            y: yPos + effFontSize * 0.3,
            width: word.width,
            color: word.color,
            isStrike: true,
          ));
        }

        if (word.href != null) {
          _pageLinks.add(_PendingLink(
            x: textX,
            y: yPos - effFontSize * 0.2,
            width: word.width,
            height: effFontSize * 1.2,
            uri: word.href!,
          ));
        }

        textX += word.width;

        if (k < line.length - 1 && !line[k + 1].glueToPrevious) {
          textX += spaceWidth + wordSpacing;
        }
      }
    }
  }

  /// Turns a run of inline nodes (paragraph children, or a drop cap's
  /// `restOfParagraph`) into flat [_Word]s ready for [_flowWords]/
  /// [_flowWordsVariableWidth]. Shared so drop caps flow their trailing text
  /// through the exact same word model as ordinary paragraphs instead of a
  /// parallel, easily-divergent implementation.
  /// Falls back to the bundled Unicode-broad font when [content] has a
  /// character [selectedFontRef] (a standard font, or an embedded font
  /// that doesn't happen to cover it) can't render. An explicit
  /// [fontFamily] request always wins - this only fills the gap left when
  /// the caller didn't ask for a specific font and would otherwise silently
  /// lose (standard font) or mis-render (an unrelated embedded font)
  /// characters like Cyrillic/Greek/Vietnamese text.
  String _withUnicodeFallback(
      String selectedFontRef, String content, String? fontFamily) {
    if (fontFamily != null) return selectedFontRef;
    if (!_fontManager.needsUnicodeFallback(content)) return selectedFontRef;
    return _fontManager.fallbackUnicodeFontRef;
  }

  List<_Word> _collectWords(List<DocxInline> children,
      PdfContentBuilder builder, double fontSize, bool isHeading) {
    final words = <_Word>[];
    for (final child in children) {
      if (child is DocxText) {
        // Apply bold for headings or if text is explicitly bold
        final fontRef = _withUnicodeFallback(
          _fontManager.selectFont(
            isBold: child.isBold || isHeading,
            isItalic: child.isItalic,
            fontFamily: child.fontFamily,
          ),
          child.content,
          child.fontFamily,
        );
        final color = child.effectiveColorHex ?? '000000';

        // Determine background color from highlight or shadingFill
        String? backgroundColor;
        if (child.highlight != DocxHighlight.none) {
          backgroundColor = _highlightToHex(child.highlight);
        } else if (child.shadingFill != null && child.shadingFill != 'auto') {
          backgroundColor = child.shadingFill;
        }

        // Decode HTML entities and handle newlines
        final decodedText = PdfContentBuilder.decodeHtmlEntities(child.content);

        // Split by newlines first to preserve line breaks in code blocks
        final lines = decodedText.split('\n');
        for (var lineIdx = 0; lineIdx < lines.length; lineIdx++) {
          final line = lines[lineIdx];

          // Split each line segment by spaces for word wrapping
          for (final word in line.split(' ')) {
            if (word.isNotEmpty) {
              // Check for checkboxes
              bool isCheckbox = false;
              int? checkboxType;
              if (word == '☐') {
                isCheckbox = true;
                checkboxType = 0;
              } else if (word == '☑') {
                isCheckbox = true;
                checkboxType = 1;
              } else if (word == '☒') {
                isCheckbox = true;
                checkboxType = 2;
              }

              // Calculate width - handle custom font size and superscript/subscript
              var effFontSize = (child.fontSize ?? fontSize).toDouble();
              if (child.isSuperscript || child.isSubscript) {
                effFontSize *= 0.6;
              }
              // Use isBold for accurate text measurement
              final isBold = child.isBold || isHeading;
              final width = isCheckbox
                  ? effFontSize
                  : builder.measureText(word, effFontSize,
                      isBold: isBold,
                      fontRef: fontRef,
                      fontManager: _fontManager);

              words.add(_Word(
                word,
                fontRef,
                color,
                width,
                isUnderline: child.isUnderline,
                isStrike: child.isStrike,
                backgroundColor: backgroundColor,
                fontSize: child.fontSize,
                isSuperscript: child.isSuperscript,
                isSubscript: child.isSubscript,
                isCheckbox: isCheckbox,
                checkboxType: checkboxType,
                href: child.href,
              ));
            }
          }

          // Add line break between text lines (but not after the last one)
          if (lineIdx < lines.length - 1) {
            words.add(_Word.lineBreak());
          }
        }
      } else if (child is DocxLineBreak) {
        words.add(_Word.lineBreak());
      } else if (child is DocxTab) {
        words.add(_Word.tab(fontSize * 3));
      } else if (child is DocxInlineImage) {
        final imageWord = _registerInlineImage(child);
        if (imageWord != null) words.add(imageWord);
      } else if (child is DocxShape) {
        words.add(_Word.shape(child, child.width));
      } else if (child is DocxFootnoteRef || child is DocxEndnoteRef) {
        // The reference itself is just a small superscript number in the
        // body text; the actual note content is rendered separately (at the
        // bottom of the page for footnotes, or on a trailing page for
        // endnotes — see _renderFootnoteArea / the endnotes pass in
        // exportToBytes).
        final markerId = child is DocxFootnoteRef
            ? child.footnoteId
            : (child as DocxEndnoteRef).endnoteId;
        final marker = '$markerId';
        final markerFontRef = _fontManager.selectFont();
        final markerWidth = builder.measureText(
            marker, fontSize.toDouble() * 0.6,
            fontRef: markerFontRef, fontManager: _fontManager);
        words.add(_Word(marker, markerFontRef, '000000', markerWidth,
            isSuperscript: true));
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

  List<List<_Word>> _flowWords(
      List<_Word> words, double maxWidth, double spaceWidth) {
    final lines = <List<_Word>>[];
    var currentLine = <_Word>[];
    var currentWidth = 0.0;

    for (final word in words) {
      if (word.isBreak) {
        lines.add(currentLine);
        currentLine = [];
        currentWidth = 0;
        continue;
      }

      // A glued continuation chunk (see _splitOverlongWords) never gets a
      // space before it - it's part of the same original word.
      final gap =
          (currentLine.isNotEmpty && !word.glueToPrevious) ? spaceWidth : 0.0;

      if (currentWidth + gap + word.width > maxWidth &&
          currentLine.isNotEmpty) {
        lines.add(currentLine);
        currentLine = [word];
        currentWidth = word.width;
      } else {
        currentWidth += gap;
        currentLine.add(word);
        currentWidth += word.width;
      }
    }

    if (currentLine.isNotEmpty) lines.add(currentLine);
    if (lines.isEmpty) lines.add([]);
    return lines;
  }

  /// Same greedy line-packing as [_flowWords], but the available width can
  /// differ per output line (`widthForLine(lineIndex)`) instead of being one
  /// constant — used by [_renderDropCap] so the lines running alongside the
  /// drop cap letter are narrower than the lines below it.
  List<List<_Word>> _flowWordsVariableWidth(List<_Word> words,
      double spaceWidth, double Function(int lineIndex) widthForLine) {
    final lines = <List<_Word>>[];
    var currentLine = <_Word>[];
    var currentWidth = 0.0;

    for (final word in words) {
      final maxWidth = widthForLine(lines.length);

      if (word.isBreak) {
        lines.add(currentLine);
        currentLine = [];
        currentWidth = 0;
        continue;
      }

      final gap =
          (currentLine.isNotEmpty && !word.glueToPrevious) ? spaceWidth : 0.0;

      if (currentWidth + gap + word.width > maxWidth &&
          currentLine.isNotEmpty) {
        lines.add(currentLine);
        currentLine = [word];
        currentWidth = word.width;
      } else {
        currentWidth += gap;
        currentLine.add(word);
        currentWidth += word.width;
      }
    }

    if (currentLine.isNotEmpty) lines.add(currentLine);
    if (lines.isEmpty) lines.add([]);
    return lines;
  }

  /// Breaks any word wider than [maxWidth] into smaller glued chunks (see
  /// [_Word.glueToPrevious]) that each individually fit, so a long word or
  /// URL with no natural break point no longer draws past the right margin
  /// unbroken. Words that already fit, and non-text words (tabs, images,
  /// shapes, checkboxes), pass through unchanged.
  ///
  /// [defaultFontSize] must be the caller's own resolved paragraph font size
  /// (e.g. a heading's larger size), not [fontSize] (the exporter's flat
  /// base size) - it's only used as a fallback for words with no per-run
  /// [_Word.fontSize] override, exactly like [_collectWords] does.
  List<_Word> _splitOverlongWords(List<_Word> words, double maxWidth,
      double defaultFontSize, PdfContentBuilder builder) {
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

      var effFontSize = (word.fontSize ?? defaultFontSize).toDouble();
      if (word.isSuperscript || word.isSubscript) effFontSize *= 0.6;
      final isBold = word.fontRef == PdfFontManager.fontBold ||
          word.fontRef == PdfFontManager.fontBoldItalic;
      final runes = word.text.runes.toList();

      // Measure each rune's width once and accumulate a running sum while
      // extending a chunk, instead of re-measuring the whole growing
      // substring per character (which is quadratic in the word's length).
      final runeWidths = List<double>.generate(
        runes.length,
        (i) => builder.measureText(String.fromCharCode(runes[i]), effFontSize,
            isBold: isBold, fontRef: word.fontRef, fontManager: _fontManager),
      );

      var start = 0;
      var isFirstChunk = true;
      while (start < runes.length) {
        var end = start + 1;
        var chunkWidth = runeWidths[start];
        while (end < runes.length && chunkWidth + runeWidths[end] <= maxWidth) {
          chunkWidth += runeWidths[end];
          end++;
        }

        result.add(_Word(
          String.fromCharCodes(runes, start, end),
          word.fontRef,
          word.color,
          chunkWidth,
          isUnderline: word.isUnderline,
          isStrike: word.isStrike,
          backgroundColor: word.backgroundColor,
          fontSize: word.fontSize,
          isSuperscript: word.isSuperscript,
          isSubscript: word.isSubscript,
          href: word.href,
          glueToPrevious: !isFirstChunk,
        ));
        isFirstChunk = false;
        start = end;
      }
    }
    return result;
  }

  /// Renders a table with real column widths (from
  /// [DocxTable.resolvedGridColumns]), colSpan/rowSpan-aware cell placement,
  /// per-cell/table border and style resolution, and nested list/table
  /// content in cells. [availableWidth] lets nested tables (rendered inside
  /// a cell) use the cell's width instead of the full page content width;
  /// pagination itself is handled ahead of time by
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

    final colX = List<double>.filled(colWidths.length + 1, startX);
    for (var i = 0; i < colWidths.length; i++) {
      colX[i + 1] = colX[i] + colWidths[i];
    }

    var y = startY;
    // Columns still occupied by a rowSpan cell that started on an earlier
    // row: column index -> rows remaining (including the current one).
    final activeSpans = <int, int>{};

    for (final row in table.rows) {
      final rowHeight = layout.measureRowHeight(row, colWidths);

      // Map this row's cells onto grid columns, skipping columns currently
      // occupied by a taller cell spanning down from a previous row. This
      // assumes rows omit cells for spanned columns (the convention the
      // DOCX writer itself follows: it never emits a `w:vMerge="continue"`
      // placeholder cell for continuation rows).
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
          activeSpans[colIndex] = cell.rowSpan - 1;
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

      // Content: paragraphs, plus nested lists/tables that were previously
      // silently dropped.
      for (final p in placements) {
        final cellX = p.x + 2;
        var cellY = y - fontSize - 4;
        for (final block in p.cell.children) {
          if (block is DocxParagraph) {
            _renderCellParagraph(
                block, builder, cellX, cellY, p.width - 4, layout);
            cellY -= layout.measureParagraphInWidth(block, p.width - 4);
          } else if (block is DocxList) {
            cellY = _renderListInWidth(
                block, builder, cellX, cellY, p.width - 4, layout);
          } else if (block is DocxTable) {
            cellY = _renderTable(block, builder, cellX, cellY, layout,
                availableWidth: p.width - 4);
          }
        }
      }

      // Age spans that were already active going into this row; ones that
      // just started here already have `rowSpan - 1` remaining rows AFTER
      // this one, so they're left untouched.
      for (final key in activeSpans.keys.toList()) {
        if (placements.any((p) => p.colIndex == key)) continue;
        final remaining = activeSpans[key]! - 1;
        if (remaining <= 0) {
          activeSpans.remove(key);
        } else {
          activeSpans[key] = remaining;
        }
      }

      y -= rowHeight;
    }

    return y - 10;
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

  /// Minimal text-only renderer for a [DocxList] nested inside a table cell,
  /// wrapped to [width] instead of the page's content width. Previously
  /// nested lists in cells reserved layout space (via
  /// `PdfLayoutEngine.measureCell`) but drew nothing at all.
  double _renderListInWidth(
    DocxList list,
    PdfContentBuilder builder,
    double startX,
    double startY,
    double width,
    PdfLayoutEngine layout,
  ) {
    var y = startY;
    // Keyed by nesting level so a sub-item restarts at 1 instead of
    // continuing its parent's count (e.g. "1., 2." then a nested item
    // showing "3." instead of restarting its own "1.").
    final orderedCounters = <int, int>{};
    final lineHeight = fontSize * 1.4;
    const bulletIndent = 12.0;
    const textIndent = 14.0;
    final spaceWidth = fontSize * 0.278;

    for (final item in list.items) {
      final levelIndent = item.level * bulletIndent;
      final markerX = startX + levelIndent;
      final contentX = markerX + textIndent;
      final availableWidth = width - levelIndent - textIndent;

      orderedCounters.removeWhere((level, _) => level > item.level);
      String marker;
      if (list.isOrdered) {
        final start = item.level == 0 ? list.startIndex : 1;
        final next = (orderedCounters[item.level] ?? (start - 1)) + 1;
        orderedCounters[item.level] = next;
        marker = '$next.';
      } else {
        marker = '•';
      }
      builder.beginText();
      builder.setTextMatrix(markerX, y);
      builder.setFont(PdfFontManager.fontRegular, fontSize.toDouble());
      builder.setFillColorHex('000000');
      builder.showText(marker);
      builder.endText();

      final text =
          item.children.whereType<DocxText>().map((t) => t.content).join();
      final words = PdfContentBuilder.decodeHtmlEntities(text)
          .split(' ')
          .where((w) => w.isNotEmpty)
          .toList();

      final lines = <List<String>>[];
      var currentLine = <String>[];
      var currentWidth = 0.0;
      for (final word in words) {
        final w = builder.measureText(word, fontSize.toDouble());
        if (currentWidth + w + spaceWidth > availableWidth &&
            currentLine.isNotEmpty) {
          lines.add(currentLine);
          currentLine = [word];
          currentWidth = w;
        } else {
          if (currentLine.isNotEmpty) currentWidth += spaceWidth;
          currentLine.add(word);
          currentWidth += w;
        }
      }
      if (currentLine.isNotEmpty) lines.add(currentLine);
      if (lines.isEmpty) lines.add(const []);

      for (final line in lines) {
        if (line.isNotEmpty) {
          builder.beginText();
          builder.setTextMatrix(contentX, y);
          builder.setFont(PdfFontManager.fontRegular, fontSize.toDouble());
          builder.setFillColorHex('000000');
          builder.showText(line.join(' '));
          builder.endText();
        }
        y -= lineHeight;
      }
    }

    return y;
  }

  double _renderCellParagraph(
    DocxParagraph paragraph,
    PdfContentBuilder builder,
    double x,
    double y,
    double width,
    PdfLayoutEngine layout,
  ) {
    // 1. Collect all words from the paragraph
    final words = <_Word>[];
    for (final child in paragraph.children) {
      if (child is DocxText) {
        final fontRef = _withUnicodeFallback(
          _fontManager.selectFont(
            isBold: child.isBold,
            isItalic: child.isItalic,
            fontFamily: child.fontFamily,
          ),
          child.content,
          child.fontFamily,
        );
        final color = child.effectiveColorHex ?? '000000';

        String? backgroundColor;
        if (child.highlight != DocxHighlight.none) {
          backgroundColor = _highlightToHex(child.highlight);
        } else if (child.shadingFill != null && child.shadingFill != 'auto') {
          backgroundColor = child.shadingFill;
        }

        final decodedText = PdfContentBuilder.decodeHtmlEntities(child.content);
        final lines = decodedText.split('\n');

        for (var lineIdx = 0; lineIdx < lines.length; lineIdx++) {
          final line = lines[lineIdx];

          for (final word in line.split(' ')) {
            if (word.isNotEmpty) {
              // Check for checkboxes
              bool isCheckbox = false;
              int? checkboxType;
              if (word == '\u2610') {
                isCheckbox = true;
                checkboxType = 0;
              } else if (word == '\u2611') {
                isCheckbox = true;
                checkboxType = 1;
              } else if (word == '\u2612') {
                isCheckbox = true;
                checkboxType = 2;
              }

              // Calculate width - handle custom font size and superscript/subscript
              var effFontSize = (child.fontSize ?? fontSize).toDouble();
              if (child.isSuperscript || child.isSubscript) {
                effFontSize *= 0.6;
              }
              final w = isCheckbox
                  ? effFontSize
                  : builder.measureText(word, effFontSize,
                      isBold: child.isBold,
                      fontRef: fontRef,
                      fontManager: _fontManager);

              words.add(_Word(
                word,
                fontRef,
                color,
                w.toDouble(),
                isUnderline: child.isUnderline,
                isStrike: child.isStrike,
                backgroundColor: backgroundColor,
                fontSize: child.fontSize,
                isSuperscript: child.isSuperscript,
                isSubscript: child.isSubscript,
                isCheckbox: isCheckbox,
                checkboxType: checkboxType,
              ));
            }
          }

          if (lineIdx < lines.length - 1) {
            words.add(_Word.lineBreak());
          }
        }
      }
    }

    if (words.isEmpty) {
      return fontSize * 1.4; // Return default line height if empty
    }

    // 2. Flow words into lines based on cell width - use proper Helvetica space width (0.278)
    final spaceWidth = fontSize * 0.278;
    final splitWords =
        _splitOverlongWords(words, width, fontSize.toDouble(), builder);
    final lines = _flowWords(splitWords, width, spaceWidth);
    final lineHeight = fontSize * 1.4;

    // 3. Render each line
    var currentY = y - fontSize * 0.3; // Align baseline
    final decorations = <_TextDecoration>[];
    for (final line in lines) {
      if (line.isEmpty) {
        currentY -= lineHeight;
        continue;
      }

      _drawWordLine(
        builder: builder,
        line: line,
        startX: x,
        lineMaxWidth: width,
        y: currentY,
        fontSize: fontSize.toDouble(),
        spaceWidth: spaceWidth,
        align: DocxAlign.left,
        isLastLine: true,
        decorations: decorations,
      );

      currentY -= lineHeight;
    }
    _strokeDecorations(builder, decorations);

    // Return total height used
    return lines.length * lineHeight;
  }

  double _renderList(
    DocxList list,
    PdfContentBuilder builder,
    double startX,
    double startY,
    PdfLayoutEngine layout,
  ) {
    var y = startY;
    var index = list.startIndex;
    final lineHeight = fontSize * 1.5;
    final bulletIndent = 36.0;
    final textIndent = 24.0;

    for (final item in list.items) {
      final levelIndent = item.level * bulletIndent;
      final markerX = startX + levelIndent;
      final contentX = markerX + textIndent;
      final availableWidth =
          layout.contentWidth - (contentX - layout.marginLeft);

      // Draw bullet/number marker
      final marker = list.isOrdered ? '${index++}.' : '\x95';
      builder.beginText();
      builder.setTextMatrix(markerX, y);
      builder.setFont(PdfFontManager.fontRegular, fontSize.toDouble());
      builder.setFillColorHex('000000');
      builder.showText(marker);
      builder.endText();

      // Collect all words
      final words = <_Word>[];
      for (final child in item.children) {
        if (child is DocxText) {
          final fontRef = _withUnicodeFallback(
            _fontManager.selectFont(
              isBold: child.isBold,
              isItalic: child.isItalic,
              fontFamily: child.fontFamily,
            ),
            child.content,
            child.fontFamily,
          );
          final color = child.effectiveColorHex ?? '000000';

          String? backgroundColor;
          if (child.highlight != DocxHighlight.none) {
            backgroundColor = _highlightToHex(child.highlight);
          } else if (child.shadingFill != null && child.shadingFill != 'auto') {
            backgroundColor = child.shadingFill;
          }

          // Decode HTML entities and handle newlines
          final decodedText =
              PdfContentBuilder.decodeHtmlEntities(child.content);
          final textLines = decodedText.split('\n');

          for (var lineIdx = 0; lineIdx < textLines.length; lineIdx++) {
            final line = textLines[lineIdx];
            final parts = line.split(' ');
            for (var i = 0; i < parts.length; i++) {
              final word = parts[i];
              if (word.isNotEmpty) {
                // Check for checkboxes
                bool isCheckbox = false;
                int? checkboxType;
                if (word == '\u2610') {
                  isCheckbox = true;
                  checkboxType = 0;
                } else if (word == '\u2611') {
                  isCheckbox = true;
                  checkboxType = 1;
                } else if (word == '\u2612') {
                  isCheckbox = true;
                  checkboxType = 2;
                }

                // Calculate width - handle superscript/subscript
                var effFontSize = (child.fontSize ?? fontSize).toDouble();
                if (child.isSuperscript || child.isSubscript) {
                  effFontSize *= 0.6;
                }
                final w = isCheckbox
                    ? effFontSize
                    : builder.measureText(word, effFontSize,
                        isBold: child.isBold,
                        fontRef: fontRef,
                        fontManager: _fontManager);

                words.add(_Word(
                  word,
                  fontRef,
                  color,
                  w,
                  isUnderline: child.isUnderline,
                  isStrike: child.isStrike,
                  backgroundColor: backgroundColor,
                  fontSize: child.fontSize,
                  isSuperscript: child.isSuperscript,
                  isSubscript: child.isSubscript,
                  isCheckbox: isCheckbox,
                  checkboxType: checkboxType,
                ));
              }
            }

            if (lineIdx < textLines.length - 1) {
              words.add(_Word.lineBreak());
            }
          }
        }
      }

      if (words.isNotEmpty) {
        final spaceWidth = fontSize * 0.278;
        final splitWords = _splitOverlongWords(
            words, availableWidth, fontSize.toDouble(), builder);
        final lines = _flowWords(splitWords, availableWidth, spaceWidth);

        // Render list item lines
        var currentY = y - fontSize * 0.3; // Align baseline (approx)
        final decorations = <_TextDecoration>[];
        for (final line in lines) {
          if (line.isEmpty) {
            currentY -= lineHeight;
            continue;
          }

          _drawWordLine(
            builder: builder,
            line: line,
            startX: contentX,
            lineMaxWidth: availableWidth,
            y: currentY,
            fontSize: fontSize.toDouble(),
            spaceWidth: spaceWidth,
            align: DocxAlign.left,
            isLastLine: true,
            decorations: decorations,
          );

          currentY -= lineHeight;
        }
        _strokeDecorations(builder, decorations);
        y = currentY;
      } else {
        y -= lineHeight;
      }

      y -= fontSize * 0.2;
    }

    return y - 10;
  }

  double _renderImage(
    DocxImage image,
    PdfContentBuilder builder,
    double x,
    double y,
    PdfLayoutEngine layout,
  ) {
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

    final renderHeight = image.height;
    final renderWidth = image.width; // Or scale if needed

    // Calculate X position based on alignment (mirrors _renderShapeBlock).
    var drawX = x;
    if (image.align == DocxAlign.center) {
      drawX = x + (layout.contentWidth - renderWidth) / 2;
    } else if (image.align == DocxAlign.right) {
      drawX = x + layout.contentWidth - renderWidth;
    }

    // Draw image
    // Note: PDF coordinates are bottom-up, so y is bottom-left of image
    // But our y is top-down flow. We want top-left of image at y.
    // So draw at y - height
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

  /// Registers a [DocxInlineImage] (an inline paragraph run, not a
  /// block-level [DocxImage]) as a page XObject and returns a placeholder
  /// "word" for it so it flows into the surrounding text like any other
  /// word instead of being silently skipped.
  _Word? _registerInlineImage(DocxInlineImage image) {
    final writer = _writer;
    if (writer == null) return null;

    final imageId = writer.addImage(
      bytes: image.bytes,
      width: image.width.toInt(),
      height: image.height.toInt(),
    );
    final imageName = '/Im${++_imageCount}';
    _pageImages[imageName] = imageId;

    return _Word.image(imageName, image.width, image.height,
        imageBorder: image.border);
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

class _Word {
  final String text;
  final String fontRef;
  final String color;
  final double width;
  final bool isTab;
  final bool isBreak;

  // Text decorations
  final bool isUnderline;
  final bool isStrike;

  // Background color (from highlight or shadingFill)
  final String? backgroundColor;

  // Font adjustments
  final double? fontSize;
  final bool isSuperscript;
  final bool isSubscript;

  // Custom rendering
  final bool isCheckbox;
  final int? checkboxType; // 0=unchecked, 1=checked, 2=crossed

  // Hyperlink target, if this word came from a DocxText with an href.
  final String? href;

  // Inline image, if this "word" is actually a DocxInlineImage.
  final bool isImage;
  final String? imageXObjectName;
  final double imageHeight;
  final DocxBorderSide? imageBorder;

  // Inline shape, if this "word" is actually a DocxShape.
  final bool isShape;
  final DocxShape? shape;

  /// True if this word is a continuation chunk of a single original word
  /// that was too wide to fit on one line and was split by
  /// [PdfExporter._splitOverlongWords] - the line-flow/draw logic must not
  /// insert a space before it (it's a piece of one word, not a new word),
  /// though a line break is still allowed between chunks.
  final bool glueToPrevious;

  _Word(
    this.text,
    this.fontRef,
    this.color,
    this.width, {
    this.isUnderline = false,
    this.isStrike = false,
    this.backgroundColor,
    this.fontSize,
    this.isSuperscript = false,
    this.isSubscript = false,
    this.isCheckbox = false,
    this.checkboxType,
    this.href,
    this.glueToPrevious = false,
  })  : isTab = false,
        isBreak = false,
        isImage = false,
        imageXObjectName = null,
        imageHeight = 0,
        imageBorder = null,
        isShape = false,
        shape = null;

  _Word.tab(this.width)
      : text = '',
        fontRef = '',
        color = '',
        isTab = true,
        isBreak = false,
        isUnderline = false,
        isStrike = false,
        backgroundColor = null,
        fontSize = null,
        isSuperscript = false,
        isSubscript = false,
        isCheckbox = false,
        checkboxType = null,
        href = null,
        isImage = false,
        imageXObjectName = null,
        imageHeight = 0,
        imageBorder = null,
        isShape = false,
        shape = null,
        glueToPrevious = false;

  _Word.lineBreak()
      : text = '',
        fontRef = '',
        color = '',
        width = 0,
        isTab = false,
        isBreak = true,
        isUnderline = false,
        isStrike = false,
        backgroundColor = null,
        fontSize = null,
        isSuperscript = false,
        isSubscript = false,
        isCheckbox = false,
        checkboxType = null,
        href = null,
        isImage = false,
        imageXObjectName = null,
        imageHeight = 0,
        imageBorder = null,
        isShape = false,
        shape = null,
        glueToPrevious = false;

  _Word.image(this.imageXObjectName, this.width, this.imageHeight,
      {this.imageBorder})
      : text = '',
        fontRef = '',
        color = '',
        isTab = false,
        isBreak = false,
        isUnderline = false,
        isStrike = false,
        backgroundColor = null,
        fontSize = null,
        isSuperscript = false,
        isSubscript = false,
        isCheckbox = false,
        checkboxType = null,
        href = null,
        isImage = true,
        isShape = false,
        shape = null,
        glueToPrevious = false;

  _Word.shape(this.shape, this.width)
      : text = '',
        fontRef = '',
        color = '',
        isTab = false,
        isBreak = false,
        isUnderline = false,
        isStrike = false,
        backgroundColor = null,
        fontSize = null,
        isSuperscript = false,
        isSubscript = false,
        isCheckbox = false,
        checkboxType = null,
        href = null,
        isImage = false,
        imageXObjectName = null,
        imageHeight = 0,
        imageBorder = null,
        isShape = true,
        glueToPrevious = false;
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

/// Helper class to track text decoration positions for underline/strikethrough
class _TextDecoration {
  final double x;
  final double y;
  final double width;
  final String color;
  final bool isStrike;

  const _TextDecoration({
    required this.x,
    required this.y,
    required this.width,
    required this.color,
    required this.isStrike,
  });
}
