import 'package:xml/xml.dart';

import '../../../../docx_creator.dart';

/// Parses document section properties (page size, margins, headers, footers).
class SectionParser {
  final ReaderContext context;
  final BlockParser blockParser;

  SectionParser(this.context) : blockParser = BlockParser(context);

  /// Parse section properties from document body.
  DocxSectionDef parse(XmlElement body, {DocxColor? backgroundColor}) {
    final sectPr = body.getElement('w:sectPr');

    DocxPageSize pageSize = DocxPageSize.letter;
    DocxPageOrientation orientation = DocxPageOrientation.portrait;
    int? customWidth;
    int? customHeight;
    int marginTop = kDefaultMarginTop;
    int marginBottom = kDefaultMarginBottom;
    int marginLeft = kDefaultMarginLeft;
    int marginRight = kDefaultMarginRight;
    int columnCount = 1;
    int columnSpacing = kDefaultColumnSpacing;
    bool columnSeparator = false;
    DocxHeader? header;
    DocxFooter? footer;
    DocxBackgroundImage? backgroundImage;

    if (sectPr != null) {
      // Page Size
      final pgSz = sectPr.getElement('w:pgSz');
      if (pgSz != null) {
        final w = int.tryParse(pgSz.getAttribute('w:w') ?? '12240') ?? 12240;
        final h = int.tryParse(pgSz.getAttribute('w:h') ?? '15840') ?? 15840;
        final orient = pgSz.getAttribute('w:orient');

        if (orient == 'landscape') {
          orientation = DocxPageOrientation.landscape;
        }

        if ((w == 12240 && h == 15840) || (w == 15840 && h == 12240)) {
          pageSize = DocxPageSize.letter;
        } else if ((w == 11906 && h == 16838) || (w == 16838 && h == 11906)) {
          pageSize = DocxPageSize.a4;
        } else {
          pageSize = DocxPageSize.custom;
          customWidth = w;
          customHeight = h;
        }
      }

      // Margins
      final pgMar = sectPr.getElement('w:pgMar');
      if (pgMar != null) {
        marginTop =
            int.tryParse(pgMar.getAttribute('w:top') ?? '') ?? marginTop;
        marginBottom =
            int.tryParse(pgMar.getAttribute('w:bottom') ?? '') ?? marginBottom;
        marginLeft =
            int.tryParse(pgMar.getAttribute('w:left') ?? '') ?? marginLeft;
        marginRight =
            int.tryParse(pgMar.getAttribute('w:right') ?? '') ?? marginRight;
      }

      // Columns (equal-width only; per-column w:col overrides aren't read)
      final cols = sectPr.getElement('w:cols');
      if (cols != null) {
        columnCount =
            int.tryParse(cols.getAttribute('w:num') ?? '') ?? columnCount;
        columnSpacing =
            int.tryParse(cols.getAttribute('w:space') ?? '') ?? columnSpacing;
        final sep = cols.getAttribute('w:sep');
        columnSeparator = sep == '1' || sep == 'true' || sep == 'on';
      }

      // Headers
      for (var headerRef in sectPr.findAllElements('w:headerReference')) {
        final rId = headerRef.getAttribute('r:id');
        final type = headerRef.getAttribute('w:type') ?? 'default';
        if (rId != null) {
          final rel = context.getRelationship(rId);
          if (rel != null) {
            if (_isBackgroundHeader(rId)) {
              backgroundImage = _readBackgroundImage(rId);
            } else if (type == 'default' || header == null) {
              header = _readHeader(rel);
            }
          }
        }
      }

      // Footers
      for (var footerRef in sectPr.findAllElements('w:footerReference')) {
        final rId = footerRef.getAttribute('r:id');
        if (rId != null) {
          final rel = context.getRelationship(rId);
          if (rel != null) {
            footer = _readFooter(rel);
          }
        }
      }
    }

    return DocxSectionDef(
      pageSize: pageSize,
      orientation: orientation,
      customWidth: customWidth,
      customHeight: customHeight,
      marginTop: marginTop,
      marginBottom: marginBottom,
      marginLeft: marginLeft,
      marginRight: marginRight,
      columnCount: columnCount,
      columnSpacing: columnSpacing,
      columnSeparator: columnSeparator,
      header: header,
      footer: footer,
      backgroundColor: backgroundColor,
      backgroundImage: backgroundImage,
    );
  }

  bool _isBackgroundHeader(String rId) {
    return rId == 'rIdBgHdr';
  }

  DocxBackgroundImage? _readBackgroundImage(String rId) {
    final rel = context.getRelationship(rId);
    if (rel == null) return null;

    String target = rel.target;
    if (!target.startsWith('/')) target = 'word/$target';

    final xmlContent = context.readContent(target);
    if (xmlContent == null) return null;

    try {
      final xml = XmlDocument.parse(xmlContent);
      final blip = xml.findAllElements('a:blip').firstOrNull;
      if (blip != null) {
        final embedId = blip.getAttribute('r:embed');
        if (embedId != null) {
          // Load header relationships
          final headerRelsPath = 'word/_rels/${target.split('/').last}.rels';
          final relsContent = context.readContent(headerRelsPath);
          if (relsContent != null) {
            final relsXml = XmlDocument.parse(relsContent);
            for (var r in relsXml.findAllElements('Relationship')) {
              if (r.getAttribute('Id') == embedId) {
                final imgTarget = r.getAttribute('Target');
                if (imgTarget != null) {
                  String imgPath = imgTarget;
                  if (!imgPath.startsWith('/')) imgPath = 'word/$imgPath';
                  final imageBytes = context.readBytes(imgPath);
                  if (imageBytes != null) {
                    // Determine extension from file path
                    String ext = 'png';
                    if (imgPath.contains('.')) {
                      ext = imgPath.split('.').last.toLowerCase();
                    }
                    return DocxBackgroundImage(
                        bytes: imageBytes, extension: ext);
                  }
                }
              }
            }
          }
        }
      }
    } catch (_) {}

    return null;
  }

  DocxHeader? _readHeader(DocxRelationship rel) {
    String target = rel.target;
    if (!target.startsWith('/')) target = 'word/$target';

    final xmlContent = context.readContent(target);
    if (xmlContent == null) return null;

    try {
      final xml = XmlDocument.parse(xmlContent);
      final body = xml.findAllElements('w:hdr').firstOrNull;
      if (body != null) {
        final elements = blockParser.parseBlocks(body.children);
        return DocxHeader(children: elements.cast<DocxBlock>());
      }
    } catch (_) {}

    return null;
  }

  DocxFooter? _readFooter(DocxRelationship rel) {
    String target = rel.target;
    if (!target.startsWith('/')) target = 'word/$target';

    final xmlContent = context.readContent(target);
    if (xmlContent == null) return null;

    try {
      final xml = XmlDocument.parse(xmlContent);
      final body = xml.findAllElements('w:ftr').firstOrNull;
      if (body != null) {
        final elements = blockParser.parseBlocks(body.children);
        return DocxFooter(children: elements.cast<DocxBlock>());
      }
    } catch (_) {}

    return null;
  }
}
