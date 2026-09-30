import 'package:xml/xml.dart';

import '../core/enums.dart';
import '../core/xml_extension.dart';
import 'docx_block.dart';
import 'docx_inline.dart';
import 'docx_node.dart';

/// Table styling options.
///
/// Use these to create professional looking tables.
class DocxTableStyle {
  /// Border style for all borders.
  final DocxBorder border;

  /// Border color (hex).
  final String borderColor;

  /// Border width in eighths of a point (4 = 0.5pt, 8 = 1pt).
  final int borderWidth;

  /// Header row background color.
  final String? headerFill;

  /// Alternating row colors (zebra striping).
  final String? evenRowFill;
  final String? oddRowFill;

  /// Cell padding in twips, or null to use Word defaults.
  final int? cellPadding;

  /// Detailed border overrides.
  final DocxBorderSide? borderTop;
  final DocxBorderSide? borderBottom;
  final DocxBorderSide? borderLeft;
  final DocxBorderSide? borderRight;
  final DocxBorderSide? borderInsideH;
  final DocxBorderSide? borderInsideV;

  /// Global table background color (shading).
  final String? fill;

  const DocxTableStyle({
    this.border = DocxBorder.single,
    this.borderColor = 'auto',
    this.borderWidth = 4,
    this.headerFill,
    this.evenRowFill,
    this.oddRowFill,
    this.cellPadding,
    this.borderTop,
    this.borderBottom,
    this.borderLeft,
    this.borderRight,
    this.borderInsideH,
    this.borderInsideV,
    this.fill,
  });

  /// Simple grid style with borders.
  static const grid = DocxTableStyle(
    border: DocxBorder.single,
    borderColor: 'auto',
  );

  /// Plain style with no borders.
  static const plain = DocxTableStyle(
    border: DocxBorder.none,
  );

  DocxTableStyle copyWith({
    DocxBorder? border,
    String? borderColor,
    int? borderWidth,
    String? headerFill,
    String? evenRowFill,
    String? oddRowFill,
    int? cellPadding,
    DocxBorderSide? borderTop,
    DocxBorderSide? borderBottom,
    DocxBorderSide? borderLeft,
    DocxBorderSide? borderRight,
    DocxBorderSide? borderInsideH,
    DocxBorderSide? borderInsideV,
    String? fill,
  }) {
    return DocxTableStyle(
      border: border ?? this.border,
      borderColor: borderColor ?? this.borderColor,
      borderWidth: borderWidth ?? this.borderWidth,
      headerFill: headerFill ?? this.headerFill,
      evenRowFill: evenRowFill ?? this.evenRowFill,
      oddRowFill: oddRowFill ?? this.oddRowFill,
      cellPadding: cellPadding ?? this.cellPadding,
      borderTop: borderTop ?? this.borderTop,
      borderBottom: borderBottom ?? this.borderBottom,
      borderLeft: borderLeft ?? this.borderLeft,
      borderRight: borderRight ?? this.borderRight,
      borderInsideH: borderInsideH ?? this.borderInsideH,
      borderInsideV: borderInsideV ?? this.borderInsideV,
      fill: fill ?? this.fill,
    );
  }

  /// Header highlighted with gray background.
  static const headerHighlight = DocxTableStyle(headerFill: 'E0E0E0');

  /// Zebra striping for readability.
  static const zebra = DocxTableStyle(
    headerFill: 'E0E0E0',
    evenRowFill: 'F5F5F5',
  );

  /// Professional blue header.
  static const professional = DocxTableStyle(
    headerFill: '4472C4',
    borderColor: '4472C4',
  );
}

/// Horizontal anchor position for floating tables.
enum DocxTableHAnchor {
  text,
  margin,
  page,
}

/// Vertical anchor position for floating tables.
enum DocxTableVAnchor {
  text,
  margin,
  page,
}

/// Floating table position properties.
///
/// Used to position a table relative to the page, margin, or text.
class DocxTablePosition {
  /// Horizontal anchor (what the X position is relative to).
  final DocxTableHAnchor hAnchor;

  /// Vertical anchor (what the Y position is relative to).
  final DocxTableVAnchor vAnchor;

  /// X position in twips (from the horizontal anchor).
  final int? tblpX;

  /// Y position in twips (from the vertical anchor).
  final int? tblpY;

  /// Left margin from surrounding text in twips.
  final int leftFromText;

  /// Right margin from surrounding text in twips.
  final int rightFromText;

  /// Top margin from surrounding text in twips.
  final int topFromText;

  /// Bottom margin from surrounding text in twips.
  final int bottomFromText;

  const DocxTablePosition({
    this.hAnchor = DocxTableHAnchor.margin,
    this.vAnchor = DocxTableVAnchor.text,
    this.tblpX,
    this.tblpY,
    this.leftFromText = 180,
    this.rightFromText = 180,
    this.topFromText = 0,
    this.bottomFromText = 0,
  });

  /// Center the table horizontally.
  static const centered = DocxTablePosition(
    hAnchor: DocxTableHAnchor.margin,
    tblpX: 0,
  );

  /// Align table to right margin.
  static const right = DocxTablePosition(
    hAnchor: DocxTableHAnchor.margin,
  );
}

/// Table look flags (conditional formatting).
class DocxTableLook {
  final bool firstRow;
  final bool lastRow;
  final bool firstColumn;
  final bool lastColumn;
  final bool noHBand;
  final bool noVBand;

  const DocxTableLook({
    this.firstRow = true,
    this.lastRow = false,
    this.firstColumn = true,
    this.lastColumn = false,
    this.noHBand = false,
    this.noVBand = true,
  });

  /// Calculates the hex value for w:val attribute based on flags.
  String get hex {
    int val = 0;
    if (firstRow) val |= 0x0020;
    if (lastRow) val |= 0x0040;
    if (firstColumn) val |= 0x0080;
    if (lastColumn) val |= 0x0100;
    if (noHBand) val |= 0x0200;
    if (noVBand) val |= 0x0400;
    return val.toRadixString(16).padLeft(4, '0').toUpperCase();
  }
}

/// A table element in the document.
class DocxTable extends DocxBlock {
  /// Table rows.
  final List<DocxTableRow> rows;

  /// Table styling.
  final DocxTableStyle style;

  /// Table look (conditional formatting).
  final DocxTableLook look;

  /// Table width value.
  final int? width;

  /// Table width type.
  final DocxWidthType widthType;

  /// Whether first row is a header.
  final bool hasHeader;

  /// Table horizontal alignment (left, center, right).
  final DocxAlign? alignment;

  /// Floating table position properties.
  final DocxTablePosition? position;

  /// Table style ID (e.g., "TableGrid", "MediumShading1-Accent1").
  final String? styleId;

  /// Table overlap setting (e.g., "never" for floating tables).
  final String? tblOverlap;

  final List<int>? gridColumns;

  /// Returns effective grid columns.
  ///
  /// If [gridColumns] is set, returns it.
  /// Otherwise, calculates columns based on the first row's cells.
  /// If [width] type is auto/pct (or null), assumes ~9022 twips (A4 printable width)
  /// and distributes evenly if cell widths are missing.
  List<int> get resolvedGridColumns {
    if (gridColumns != null && gridColumns!.isNotEmpty) {
      return gridColumns!;
    }

    if (rows.isEmpty) return [];

    // Column count must account for colSpan and for columns still covered
    // by a rowSpan cell from an earlier row (rows omit those cells), not
    // just the first row's cell count - otherwise a first row such as
    // `<th colspan="2">` + `<th>` yields 2 columns for a 3-column table.
    var columnCount = 0;
    final explicitWidths = <int, int>{};
    final activeSpans = <int, int>{};
    for (final row in rows) {
      var col = 0;
      for (final cell in row.cells) {
        while ((activeSpans[col] ?? 0) > 0) {
          col++;
        }
        if (cell.colSpan == 1 && cell.width != null) {
          explicitWidths.putIfAbsent(col, () => cell.width!);
        }
        if (cell.rowSpan > 1) {
          for (var c = col; c < col + cell.colSpan; c++) {
            activeSpans[c] = cell.rowSpan;
          }
        }
        col += cell.colSpan;
      }
      var end = col;
      activeSpans.forEach((c, remaining) {
        if (remaining > 0 && c + 1 > end) end = c + 1;
      });
      if (end > columnCount) columnCount = end;
      for (final key in activeSpans.keys.toList()) {
        activeSpans[key] = activeSpans[key]! - 1;
      }
    }
    if (columnCount == 0) return [];

    // Distribute total available width
    // Standard A4 (11906) - Margins (1440*2) = 9026. Rounding to 9022 as suggested.
    const int totalWidth = 9022;
    if (explicitWidths.length == columnCount) {
      return List<int>.generate(columnCount, (i) => explicitWidths[i]!);
    }
    if (explicitWidths.isNotEmpty) {
      // Share what the explicit columns leave over among the others.
      final used = explicitWidths.values.fold<int>(0, (a, b) => a + b);
      final missing = columnCount - explicitWidths.length;
      final rest = ((totalWidth - used) / missing).floor();
      final fill = rest > 360 ? rest : 360;
      return List<int>.generate(columnCount, (i) => explicitWidths[i] ?? fill);
    }
    final colWidth = (totalWidth / columnCount).floor();
    return List<int>.filled(columnCount, colWidth);
  }

  /// Whether this table is floating (has custom positioning).
  bool get isFloating => position != null;

  const DocxTable({
    required this.rows,
    this.style = const DocxTableStyle(),
    this.width,
    this.widthType = DocxWidthType.auto,
    this.hasHeader = true,
    this.alignment,
    this.position,
    this.styleId,
    this.tblOverlap,
    this.look = const DocxTableLook(),
    this.gridColumns,
    super.id,
  });

  /// Creates a table from a 2D list of strings.
  factory DocxTable.fromData(
    List<List<String>> data, {
    bool hasHeader = true,
    DocxTableStyle style = const DocxTableStyle(),
    String? styleId,
  }) {
    final rows = <DocxTableRow>[];
    for (int i = 0; i < data.length; i++) {
      final isHeader = hasHeader && i == 0;
      final isEven = i % 2 == 0;

      String? rowFill;
      if (isHeader && style.headerFill != null) {
        rowFill = style.headerFill;
      } else if (!isHeader) {
        rowFill = isEven ? style.evenRowFill : style.oddRowFill;
      }

      final cells = data[i]
          .map(
            (text) => DocxTableCell.text(
              text,
              isBold: isHeader,
              shadingFill: rowFill,
            ),
          )
          .toList();
      rows.add(DocxTableRow(cells: cells));
    }
    return DocxTable(
        rows: rows, style: style, hasHeader: hasHeader, styleId: styleId);
  }

  DocxTable copyWith({
    List<DocxTableRow>? rows,
    DocxTableStyle? style,
    int? width,
    DocxWidthType? widthType,
    bool? hasHeader,
    DocxAlign? alignment,
    DocxTablePosition? position,
    String? styleId,
    String? tblOverlap,
    DocxTableLook? look,
    List<int>? gridColumns,
  }) {
    return DocxTable(
      rows: rows ?? this.rows,
      style: style ?? this.style,
      width: width ?? this.width,
      widthType: widthType ?? this.widthType,
      hasHeader: hasHeader ?? this.hasHeader,
      alignment: alignment ?? this.alignment,
      position: position ?? this.position,
      styleId: styleId ?? this.styleId,
      tblOverlap: tblOverlap ?? this.tblOverlap,
      look: look ?? this.look,
      gridColumns: gridColumns ?? this.gridColumns,
      id: id,
    );
  }

  @override
  void accept(DocxVisitor visitor) {
    visitor.visitTable(this);
  }

  @override
  void buildXml(XmlBuilder builder) {
    builder.element(
      'w:tbl',
      nest: () {
        // Table properties
        builder.element(
          'w:tblPr',
          nest: () {
            builder.element(
              'w:tblStyle',
              nest: () {
                builder.attribute('w:val', styleId ?? 'TableGrid');
              },
            );

            // Floating table position (tblpPr must be early)
            if (position != null) {
              builder.element(
                'w:tblpPr',
                nest: () {
                  builder.attribute(
                      'w:leftFromText', position!.leftFromText.toString());
                  builder.attribute(
                      'w:rightFromText', position!.rightFromText.toString());
                  builder.attribute(
                      'w:topFromText', position!.topFromText.toString());
                  builder.attribute(
                      'w:bottomFromText', position!.bottomFromText.toString());
                  builder.attribute('w:vertAnchor', position!.vAnchor.name);
                  builder.attribute('w:horzAnchor', position!.hAnchor.name);
                  if (position!.tblpX != null) {
                    builder.attribute('w:tblpX', position!.tblpX.toString());
                  }
                  if (position!.tblpY != null) {
                    builder.attribute('w:tblpY', position!.tblpY.toString());
                  }
                },
              );
            }

            // Table Overlap (for floating tables)
            if (tblOverlap != null) {
              builder.element('w:tblOverlap', nest: () {
                builder.attribute('w:val', tblOverlap!);
              });
            }

            builder.element(
              'w:tblW',
              nest: () {
                builder.attribute('w:w', (width ?? 0).toString());
                builder.attribute('w:type', widthType.name);
              },
            );

            // Table alignment (justification)
            if (alignment != null) {
              builder.element(
                'w:jc',
                nest: () {
                  builder.attribute('w:val', alignment!.xmlValue);
                },
              );
            }

            // Borders - only emit if explicitly set or no style ID
            final hasExplicitBorders = style.borderTop != null ||
                style.borderBottom != null ||
                style.borderLeft != null ||
                style.borderRight != null ||
                style.borderInsideH != null ||
                style.borderInsideV != null;

            if (hasExplicitBorders || styleId == null) {
              builder.element(
                'w:tblBorders',
                nest: () {
                  // Helper to resolve border
                  void buildSide(String tag, DocxBorderSide? side) {
                    if (side != null) {
                      builder.element(tag, nest: () {
                        builder.attribute('w:val', side.xmlStyle);
                        builder.attribute('w:sz', side.size.toString());
                        builder.attribute('w:space', side.space.toString());
                        if (side.color != DocxColor.auto) {
                          builder.attribute('w:color', side.color.hex);
                        } else {
                          builder.attribute('w:color', 'auto');
                        }
                        if (side.themeColor != null) {
                          builder.attribute('w:themeColor', side.themeColor!);
                        }
                        if (side.themeTint != null) {
                          builder.attribute('w:themeTint', side.themeTint!);
                        }
                        if (side.themeShade != null) {
                          builder.attribute('w:themeShade', side.themeShade!);
                        }
                      });
                    } else if (styleId == null &&
                        style.border != DocxBorder.none) {
                      // Fallback to global style only if no styleId
                      _buildBorder(builder, tag);
                    }
                  }

                  buildSide('w:top', style.borderTop);
                  buildSide('w:bottom', style.borderBottom);
                  buildSide('w:left', style.borderLeft);
                  buildSide('w:right', style.borderRight);
                  buildSide('w:insideH', style.borderInsideH);
                  buildSide('w:insideV', style.borderInsideV);
                },
              );
            }

            // Table shading (global)
            if (style.fill != null) {
              builder.element('w:shd', nest: () {
                builder.attribute('w:fill', style.fill!.replaceAll('#', ''));
                builder.attribute('w:val', 'clear');
              });
            }

            // Cell margins/padding - only emit if explicitly set
            if (style.cellPadding != null) {
              builder.element(
                'w:tblCellMar',
                nest: () {
                  builder.element(
                    'w:top',
                    nest: () {
                      builder.attribute('w:w', style.cellPadding.toString());
                      builder.attribute('w:type', 'dxa');
                    },
                  );
                  builder.element(
                    'w:left',
                    nest: () {
                      builder.attribute('w:w', style.cellPadding.toString());
                      builder.attribute('w:type', 'dxa');
                    },
                  );
                  builder.element(
                    'w:bottom',
                    nest: () {
                      builder.attribute('w:w', style.cellPadding.toString());
                      builder.attribute('w:type', 'dxa');
                    },
                  );
                  builder.element(
                    'w:right',
                    nest: () {
                      builder.attribute('w:w', style.cellPadding.toString());
                      builder.attribute('w:type', 'dxa');
                    },
                  );
                },
              );
            }

            // Table Look (Must be last)
            builder.element('w:tblLook', nest: () {
              builder.attribute('w:val', look.hex);
              builder.attribute('w:firstRow', look.firstRow ? '1' : '0');
              builder.attribute('w:lastRow', look.lastRow ? '1' : '0');
              builder.attribute('w:firstColumn', look.firstColumn ? '1' : '0');
              builder.attribute('w:lastColumn', look.lastColumn ? '1' : '0');
              builder.attribute('w:noHBand', look.noHBand ? '1' : '0');
              builder.attribute('w:noVBand', look.noVBand ? '1' : '0');
            });
          },
        );
        // Table Grid - use preserved values or calculate from cells
        // Table Grid
        builder.element('w:tblGrid', nest: () {
          final cols = resolvedGridColumns;
          for (var colWidth in cols) {
            builder.element('w:gridCol', nest: () {
              builder.attribute('w:w', colWidth.toString());
            });
          }
        });

        // Rows
        final cols = resolvedGridColumns;
        for (int i = 0; i < rows.length; i++) {
          rows[i].buildXmlWithStyle(
            builder,
            style,
            isHeader: hasHeader && i == 0,
            isEven: i % 2 == 0,
            gridCols: cols,
          );
        }
      },
    );
  }

  void _buildBorder(XmlBuilder builder, String tag) {
    builder.element(
      tag,
      nest: () {
        builder.attribute('w:val', style.border.xmlValue);
        builder.attribute('w:sz', style.borderWidth.toString());
        builder.attribute('w:space', '0');
        builder.attribute('w:color', style.borderColor);
      },
    );
  }
}

/// A row within a [DocxTable].
class DocxTableRow extends DocxNode {
  /// Cells in this row.
  final List<DocxTableCell> cells;

  /// Row height in twips (null = auto).
  final int? height;

  /// Whether this row is a header row (repeats on new pages).
  final bool isHeader;

  /// Conditional formatting style flags (e.g., '100000000000' for header row).
  final String? cnfStyle;

  const DocxTableRow({
    required this.cells,
    this.height,
    this.isHeader = false,
    this.cnfStyle,
    super.id,
  });

  DocxTableRow copyWith({
    List<DocxTableCell>? cells,
    int? height,
    bool? isHeader,
    String? cnfStyle,
  }) {
    return DocxTableRow(
      cells: cells ?? this.cells,
      height: height ?? this.height,
      isHeader: isHeader ?? this.isHeader,
      cnfStyle: cnfStyle ?? this.cnfStyle,
      id: id,
    );
  }

  @override
  void accept(DocxVisitor visitor) {
    visitor.visitTableRow(this);
  }

  @override
  void buildXml(XmlBuilder builder) {
    buildXmlWithStyle(
      builder,
      const DocxTableStyle(),
      isHeader: isHeader,
      isEven: false,
    );
  }

  void buildXmlWithStyle(
    XmlBuilder builder,
    DocxTableStyle style, {
    required bool isHeader,
    required bool isEven,
    List<int>? gridCols,
  }) {
    builder.element(
      'w:tr',
      nest: () {
        // Row properties
        if (height != null || isHeader || this.isHeader || cnfStyle != null) {
          builder.element(
            'w:trPr',
            nest: () {
              // Conditional formatting style (must come first)
              if (cnfStyle != null) {
                builder.element('w:cnfStyle', nest: () {
                  builder.attribute('w:val', cnfStyle!);
                });
              }
              if (height != null) {
                builder.element(
                  'w:trHeight',
                  nest: () {
                    builder.attribute('w:val', height.toString());
                    builder.attribute('w:hRule', 'exact');
                  },
                );
              }
              // Mark as header row (repeats on each page)
              if (isHeader || this.isHeader) {
                builder.element('w:tblHeader');
              }
            },
          );
        }
        int colIndex = 0;
        for (var cell in cells) {
          int? cellWidth = cell.width;
          if (cellWidth == null &&
              gridCols != null &&
              colIndex < gridCols.length) {
            // Calculate width from gridCols based on colSpan
            cellWidth = 0;
            for (int j = 0; j < cell.colSpan; j++) {
              if (colIndex + j < gridCols.length) {
                cellWidth = cellWidth! + gridCols[colIndex + j];
              }
            }
          }
          cell.buildXmlWithWidth(builder, cellWidth);
          colIndex += cell.colSpan;
        }
      },
    );
  }
}

/// A cell within a [DocxTableRow].
class DocxTableCell extends DocxNode {
  /// Block content in this cell.
  final List<DocxBlock> children;

  /// Column span (merge cells horizontally).
  final int colSpan;

  /// Row span (merge cells vertically).
  final int rowSpan;

  /// Vertical alignment within the cell.
  final DocxVerticalAlign verticalAlign;

  /// Background shading color hex.
  final String? shadingFill;

  /// Theme-based fill color reference.
  final String? themeFill;

  /// Theme fill tint adjustment.
  final String? themeFillTint;

  /// Theme fill shade adjustment.
  final String? themeFillShade;

  /// Cell width in twips.
  final int? width;

  /// Conditional formatting style flags.
  final String? cnfStyle;

  // Borders
  final DocxBorderSide? borderTop;
  final DocxBorderSide? borderBottom;
  final DocxBorderSide? borderLeft;
  final DocxBorderSide? borderRight;

  // Margins (cell padding) in twips; null falls back to the table's
  // `DocxTableStyle.cellPadding`.
  final int? marginLeft;
  final int? marginRight;
  final int? marginTop;
  final int? marginBottom;

  const DocxTableCell({
    this.children = const [],
    this.colSpan = 1,
    this.rowSpan = 1,
    this.verticalAlign = DocxVerticalAlign.center,
    this.shadingFill,
    this.themeFill,
    this.themeFillTint,
    this.themeFillShade,
    this.width,
    this.borderTop,
    this.borderBottom,
    this.borderLeft,
    this.borderRight,
    this.marginLeft,
    this.marginRight,
    this.marginTop,
    this.marginBottom,
    this.cnfStyle,
    super.id,
  });

  /// Creates a cell with simple text content.
  factory DocxTableCell.text(
    String text, {
    bool isBold = false,
    DocxAlign align = DocxAlign.left,
    DocxVerticalAlign verticalAlign = DocxVerticalAlign.center,
    DocxTextAlignment? textAlignment,
    String? shadingFill,
  }) {
    return DocxTableCell(
      verticalAlign: verticalAlign,
      shadingFill: shadingFill,
      children: [
        DocxParagraph(
          align: align,
          textAlignment: textAlignment,
          children: [isBold ? DocxText.bold(text) : DocxText(text)],
        ),
      ],
    );
  }

  /// Creates a cell with rich content.
  factory DocxTableCell.rich(List<DocxInline> content, {String? shadingFill}) {
    return DocxTableCell(
      shadingFill: shadingFill,
      children: [DocxParagraph(children: content)],
    );
  }

  DocxTableCell copyWith({
    List<DocxBlock>? children,
    int? colSpan,
    int? rowSpan,
    DocxVerticalAlign? verticalAlign,
    String? shadingFill,
    String? themeFill,
    String? themeFillTint,
    String? themeFillShade,
    int? width,
    DocxBorderSide? borderTop,
    DocxBorderSide? borderBottom,
    DocxBorderSide? borderLeft,
    DocxBorderSide? borderRight,
    int? marginLeft,
    int? marginRight,
    int? marginTop,
    int? marginBottom,
    String? cnfStyle,
  }) {
    return DocxTableCell(
      children: children ?? this.children,
      colSpan: colSpan ?? this.colSpan,
      rowSpan: rowSpan ?? this.rowSpan,
      verticalAlign: verticalAlign ?? this.verticalAlign,
      shadingFill: shadingFill ?? this.shadingFill,
      themeFill: themeFill ?? this.themeFill,
      themeFillTint: themeFillTint ?? this.themeFillTint,
      themeFillShade: themeFillShade ?? this.themeFillShade,
      width: width ?? this.width,
      borderTop: borderTop ?? this.borderTop,
      borderBottom: borderBottom ?? this.borderBottom,
      borderLeft: borderLeft ?? this.borderLeft,
      borderRight: borderRight ?? this.borderRight,
      marginLeft: marginLeft ?? this.marginLeft,
      marginRight: marginRight ?? this.marginRight,
      marginTop: marginTop ?? this.marginTop,
      marginBottom: marginBottom ?? this.marginBottom,
      cnfStyle: cnfStyle ?? this.cnfStyle,
      id: id,
    );
  }

  @override
  void accept(DocxVisitor visitor) {
    visitor.visitTableCell(this);
  }

  void _buildBorder(XmlBuilder builder, String tag, DocxBorderSide side) {
    builder.element(tag, nest: () {
      builder.attribute('w:val', side.xmlStyle);
      builder.attribute('w:sz', side.size.toString());
      builder.attribute('w:space', side.space.toString());
      if (side.color != DocxColor.auto) {
        builder.attribute('w:color', side.color.hex);
      } else {
        builder.attribute('w:color', 'auto');
      }
      if (side.themeColor != null) {
        builder.attribute('w:themeColor', side.themeColor!);
      }
      if (side.themeTint != null) {
        builder.attribute('w:themeTint', side.themeTint!);
      }
      if (side.themeShade != null) {
        builder.attribute('w:themeShade', side.themeShade!);
      }
    });
  }

  @override
  void buildXml(XmlBuilder builder) {
    buildXmlWithWidth(builder, width);
  }

  void buildXmlWithWidth(XmlBuilder builder, int? effectiveWidth) {
    builder.element(
      'w:tc',
      nest: () {
        // Cell properties
        builder.element(
          'w:tcPr',
          nest: () {
            if (cnfStyle != null) {
              builder.element('w:cnfStyle', nest: () {
                builder.attribute('w:val', cnfStyle!);
              });
            }
            if (effectiveWidth != null) {
              builder.element(
                'w:tcW',
                nest: () {
                  builder.attribute('w:w', effectiveWidth.toString());
                  builder.attribute('w:type', 'dxa');
                },
              );
            }
            if (colSpan > 1) {
              builder.element(
                'w:gridSpan',
                nest: () {
                  builder.attribute('w:val', colSpan.toString());
                },
              );
            }
            if (rowSpan > 1) {
              builder.element(
                'w:vMerge',
                nest: () {
                  builder.attribute('w:val', 'restart');
                },
              );
            }
            // Borders (Must be before shd)
            if (borderTop != null ||
                borderBottom != null ||
                borderLeft != null ||
                borderRight != null) {
              builder.element('w:tcBorders', nest: () {
                if (borderTop != null) {
                  _buildBorder(builder, 'w:top', borderTop!);
                }
                if (borderBottom != null) {
                  _buildBorder(builder, 'w:bottom', borderBottom!);
                }
                if (borderLeft != null) {
                  _buildBorder(builder, 'w:left', borderLeft!);
                }
                if (borderRight != null) {
                  _buildBorder(builder, 'w:right', borderRight!);
                }
              });
            }
            writeShading(
              builder,
              fill: shadingFill,
              themeFill: themeFill,
              themeFillTint: themeFillTint,
              themeFillShade: themeFillShade,
            );
            if (marginTop != null ||
                marginLeft != null ||
                marginBottom != null ||
                marginRight != null) {
              // CT_TcMar child order: top, left (start), bottom, right (end).
              builder.element('w:tcMar', nest: () {
                for (final (tag, value) in [
                  ('w:top', marginTop),
                  ('w:left', marginLeft),
                  ('w:bottom', marginBottom),
                  ('w:right', marginRight),
                ]) {
                  if (value == null) continue;
                  builder.element(tag, nest: () {
                    builder.attribute('w:w', value.toString());
                    builder.attribute('w:type', 'dxa');
                  });
                }
              });
            }
            builder.element(
              'w:vAlign',
              nest: () {
                builder.attribute('w:val', verticalAlign.name);
              },
            );
          },
        );

        // Content
        if (children.isEmpty) {
          builder.element('w:p');
        } else {
          for (var child in children) {
            child.buildXml(builder);
          }
        }
      },
    );
  }
}
