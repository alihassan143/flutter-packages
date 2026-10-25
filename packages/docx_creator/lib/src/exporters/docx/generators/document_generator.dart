import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:docx_creator/docx_creator.dart';
import 'package:xml/xml.dart';

import '../../../ast/docx_hyperlink_registry.dart';
import '../docx_export_state.dart';

class DocxDocumentGenerator {
  static ArchiveFile generate(DocxExportState state) {
    final builder = XmlBuilder();
    builder.processing(
      'xml',
      'version="1.0" encoding="UTF-8" standalone="yes"',
    );
    builder.element(
      'w:document',
      nest: () {
        // Core WordprocessingML namespace
        builder.attribute(
          'xmlns:w',
          'http://schemas.openxmlformats.org/wordprocessingml/2006/main',
        );
        // DrawingML WordprocessingDrawing namespace
        builder.attribute(
          'xmlns:wp',
          'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing',
        );
        // Relationships namespace
        builder.attribute(
          'xmlns:r',
          'http://schemas.openxmlformats.org/officeDocument/2006/relationships',
        );
        // DrawingML main namespace
        builder.attribute(
          'xmlns:a',
          'http://schemas.openxmlformats.org/drawingml/2006/main',
        );
        // Picture namespace
        builder.attribute(
          'xmlns:pic',
          'http://schemas.openxmlformats.org/drawingml/2006/picture',
        );
        // VML namespaces for legacy shapes
        builder.attribute(
          'xmlns:v',
          'urn:schemas-microsoft-com:vml',
        );
        builder.attribute(
          'xmlns:o',
          'urn:schemas-microsoft-com:office:office',
        );
        // Math namespace
        builder.attribute(
          'xmlns:m',
          'http://schemas.openxmlformats.org/officeDocument/2006/math',
        );
        // Markup Compatibility namespace
        builder.attribute(
          'xmlns:mc',
          'http://schemas.openxmlformats.org/markup-compatibility/2006',
        );
        // Word 2010 extensions
        builder.attribute(
          'xmlns:w14',
          'http://schemas.microsoft.com/office/word/2010/wordml',
        );
        // WordprocessingShape namespace (Word 2010+)
        builder.attribute(
          'xmlns:wps',
          'http://schemas.microsoft.com/office/word/2010/wordprocessingShape',
        );
        // WordprocessingGroup namespace (Word 2010+)
        builder.attribute(
          'xmlns:wpg',
          'http://schemas.microsoft.com/office/word/2010/wordprocessingGroup',
        );
        // DrawingML WordprocessingDrawing (Word 2010+)
        builder.attribute(
          'xmlns:wp14',
          'http://schemas.microsoft.com/office/word/2010/wordprocessingDrawing',
        );

        // Add background (color and/or image)
        _buildBackground(builder, state);

        DocxHyperlinkRegistry.begin(state.hyperlinkRelIds);
        try {
          builder.element(
            'w:body',
            nest: () {
              for (final element in state.doc.elements) {
                element.buildXml(builder);
              }
              // Build section properties including background header reference
              _buildSectionProperties(builder, state);
            },
          );
        } finally {
          DocxHyperlinkRegistry.end();
        }
      },
    );
    final xml = builder.buildDocument().toXmlString();
    final bytes = utf8.encode(xml);
    return ArchiveFile(
      'word/document.xml',
      bytes.length,
      bytes,
    );
  }

  static void _buildBackground(XmlBuilder builder, DocxExportState state) {
    final hasColor = state.doc.section?.backgroundColor != null;

    if (hasColor) {
      builder.element(
        'w:background',
        nest: () {
          builder.attribute('w:color', state.doc.section!.backgroundColor!.hex);
        },
      );
    }
  }

  static void _buildSectionProperties(
      XmlBuilder builder, DocxExportState state) {
    builder.element(
      'w:sectPr',
      nest: () {
        if (state.doc.section?.header != null) {
          builder.element(
            'w:headerReference',
            nest: () {
              builder.attribute('w:type', 'default');
              builder.attribute('r:id', 'rId5');
            },
          );
        } else if (state.backgroundImage != null) {
          builder.element(
            'w:headerReference',
            nest: () {
              builder.attribute('w:type', 'default');
              builder.attribute('r:id', 'rIdBgHdr');
            },
          );
        }

        if (state.doc.section?.footer != null) {
          builder.element(
            'w:footerReference',
            nest: () {
              builder.attribute('w:type', 'default');
              builder.attribute('r:id', 'rId6');
            },
          );
        }

        final section = state.doc.section;
        if (section != null) {
          final isLandscape =
              section.orientation == DocxPageOrientation.landscape;
          builder.element(
            'w:pgSz',
            nest: () {
              builder.attribute(
                'w:w',
                (isLandscape ? section.effectiveHeight : section.effectiveWidth)
                    .toString(),
              );
              builder.attribute(
                'w:h',
                (isLandscape ? section.effectiveWidth : section.effectiveHeight)
                    .toString(),
              );
              if (isLandscape) {
                builder.attribute('w:orient', 'landscape');
              }
            },
          );
          builder.element(
            'w:pgMar',
            nest: () {
              builder.attribute('w:top', section.marginTop.toString());
              builder.attribute('w:right', section.marginRight.toString());
              builder.attribute('w:bottom', section.marginBottom.toString());
              builder.attribute('w:left', section.marginLeft.toString());
              builder.attribute('w:header', '720');
              builder.attribute('w:footer', '720');
            },
          );
          if (section.columnCount > 1) {
            builder.element('w:cols', nest: () {
              builder.attribute('w:num', section.columnCount.toString());
              builder.attribute('w:space', section.columnSpacing.toString());
              if (section.columnSeparator) builder.attribute('w:sep', '1');
            });
          }
        } else {
          // Default page size (Letter)
          builder.element(
            'w:pgSz',
            nest: () {
              builder.attribute('w:w', '12240');
              builder.attribute('w:h', '15840');
            },
          );
          builder.element(
            'w:pgMar',
            nest: () {
              builder.attribute('w:top', '1440');
              builder.attribute('w:right', '1440');
              builder.attribute('w:bottom', '1440');
              builder.attribute('w:left', '1440');
              builder.attribute('w:header', '720');
              builder.attribute('w:footer', '720');
            },
          );
        }
      },
    );
  }
}
