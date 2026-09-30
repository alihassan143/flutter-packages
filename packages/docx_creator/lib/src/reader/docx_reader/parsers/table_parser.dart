import 'package:docx_creator/docx_creator.dart';
import 'package:xml/xml.dart';

/// Parses table elements (w:tbl).
class TableParser {
  /// The context for the current reader session.
  final ReaderContext context;

  /// The parser used for inline elements within table cells.
  final InlineParser inlineParser;

  /// Creates a [TableParser] with the specified [context] and [inlineParser].
  TableParser(this.context, this.inlineParser);

  /// Parse a table element into DocxTable.
  DocxTable parse(XmlElement node) {
    // 1. Parse Table Properties
    DocxTableStyle style = const DocxTableStyle(border: DocxBorder.single);
    int? tableWidth;
    DocxWidthType widthType = DocxWidthType.auto;

    final tblPr = node.getElement('w:tblPr');
    DocxAlign? alignment;
    DocxTablePosition? position;
    String? styleId;
    String? tblOverlap;

    if (tblPr != null) {
      final tblBorders = tblPr.getElement('w:tblBorders');
      if (tblBorders != null) {
        style = DocxTableStyle(
          borderTop: _parseBorderSide(tblBorders.getElement('w:top')),
          borderBottom: _parseBorderSide(tblBorders.getElement('w:bottom')),
          borderLeft: _parseBorderSide(tblBorders.getElement('w:left')),
          borderRight: _parseBorderSide(tblBorders.getElement('w:right')),
          borderInsideH: _parseBorderSide(tblBorders.getElement('w:insideH')),
          borderInsideV: _parseBorderSide(tblBorders.getElement('w:insideV')),
        );
      }

      // Parse table shading (background)
      final shd = tblPr.getElement('w:shd');
      if (shd != null) {
        final fill = shd.getAttribute('w:fill');
        if (fill != null && fill != 'auto') {
          style = style.copyWith(fill: fill);
        }
      }

      // Parse table-wide cell margins (uses the left margin as the padding
      // value; mirrors the writer in DocxTableStyle.buildXml, which applies
      // cellPadding uniformly to all four sides).
      final tblCellMar = tblPr.getElement('w:tblCellMar');
      if (tblCellMar != null) {
        final left = tblCellMar.getElement('w:left');
        final padding = int.tryParse(left?.getAttribute('w:w') ?? '');
        if (padding != null) {
          style = style.copyWith(cellPadding: padding);
        }
      }

      final tblW = tblPr.getElement('w:tblW');
      if (tblW != null) {
        final w = int.tryParse(tblW.getAttribute('w:w') ?? '');
        final type = tblW.getAttribute('w:type');
        if (w != null) tableWidth = w;
        if (type == 'dxa') widthType = DocxWidthType.dxa;
        if (type == 'pct') widthType = DocxWidthType.pct;
        if (type == 'auto') widthType = DocxWidthType.auto;
      }

      // Parse table style
      final tblStyle = tblPr.getElement('w:tblStyle');
      if (tblStyle != null) {
        styleId = tblStyle.getAttribute('w:val');
      }

      // Parse table alignment (justification)
      final jc = tblPr.getElement('w:jc');
      if (jc != null) {
        final val = jc.getAttribute('w:val');
        if (val == 'left') alignment = DocxAlign.left;
        if (val == 'center') alignment = DocxAlign.center;
        if (val == 'right') alignment = DocxAlign.right;
      }

      // Parse floating table position
      final tblpPr = tblPr.getElement('w:tblpPr');
      if (tblpPr != null) {
        DocxTableHAnchor hAnchor = DocxTableHAnchor.margin;
        DocxTableVAnchor vAnchor = DocxTableVAnchor.text;

        final hAnchorVal = tblpPr.getAttribute('w:horzAnchor');
        if (hAnchorVal == 'text') hAnchor = DocxTableHAnchor.text;
        if (hAnchorVal == 'margin') hAnchor = DocxTableHAnchor.margin;
        if (hAnchorVal == 'page') hAnchor = DocxTableHAnchor.page;

        final vAnchorVal = tblpPr.getAttribute('w:vertAnchor');
        if (vAnchorVal == 'text') vAnchor = DocxTableVAnchor.text;
        if (vAnchorVal == 'margin') vAnchor = DocxTableVAnchor.margin;
        if (vAnchorVal == 'page') vAnchor = DocxTableVAnchor.page;

        position = DocxTablePosition(
          hAnchor: hAnchor,
          vAnchor: vAnchor,
          tblpX: int.tryParse(tblpPr.getAttribute('w:tblpX') ?? ''),
          tblpY: int.tryParse(tblpPr.getAttribute('w:tblpY') ?? ''),
          leftFromText:
              int.tryParse(tblpPr.getAttribute('w:leftFromText') ?? '') ?? 180,
          rightFromText:
              int.tryParse(tblpPr.getAttribute('w:rightFromText') ?? '') ?? 180,
          topFromText:
              int.tryParse(tblpPr.getAttribute('w:topFromText') ?? '') ?? 0,
          bottomFromText:
              int.tryParse(tblpPr.getAttribute('w:bottomFromText') ?? '') ?? 0,
        );
      }

      // Parse table overlap
      final tblOverlapElem = tblPr.getElement('w:tblOverlap');
      if (tblOverlapElem != null) {
        tblOverlap = tblOverlapElem.getAttribute('w:val');
      }
    }

    // Parse table look (conditional formatting)
    DocxTableLook look = const DocxTableLook();
    if (tblPr != null) {
      final tblLook = tblPr.getElement('w:tblLook');
      if (tblLook != null) {
        // Try individual attributes first (newer Word format)
        final firstRowAttr = tblLook.getAttribute('w:firstRow');
        final lastRowAttr = tblLook.getAttribute('w:lastRow');
        final firstColAttr = tblLook.getAttribute('w:firstColumn');
        final lastColAttr = tblLook.getAttribute('w:lastColumn');
        final noHBandAttr = tblLook.getAttribute('w:noHBand');
        final noVBandAttr = tblLook.getAttribute('w:noVBand');

        // If attributes exist, use them
        if (firstRowAttr != null || noHBandAttr != null) {
          look = DocxTableLook(
            firstRow: firstRowAttr != '0',
            lastRow: lastRowAttr == '1',
            firstColumn: firstColAttr == '1',
            lastColumn: lastColAttr == '1',
            noHBand: noHBandAttr == '1',
            noVBand: noVBandAttr == '1',
          );
        } else {
          // Fallback: Decode from w:val hex value (older Word format)
          final valAttr = tblLook.getAttribute('w:val');
          if (valAttr != null) {
            final val = int.tryParse(valAttr, radix: 16) ?? 0;
            look = DocxTableLook(
              firstRow: (val & 0x0020) != 0,
              lastRow: (val & 0x0040) != 0,
              firstColumn: (val & 0x0080) != 0,
              lastColumn: (val & 0x0100) != 0,
              noHBand: (val & 0x0200) != 0,
              noVBand: (val & 0x0400) != 0,
            );
          }
        }
      }
    }

    // ============================================================
    // True-Fidelity: Parse Table Grid (column widths)
    // ============================================================
    List<int>? gridColumns;
    final tblGrid = node.getElement('w:tblGrid');
    if (tblGrid != null) {
      gridColumns = <int>[];
      for (var gridCol in tblGrid.findAllElements('w:gridCol')) {
        final w = int.tryParse(gridCol.getAttribute('w:w') ?? '');
        if (w != null) gridColumns.add(w);
      }
      // If empty list, set to null
      if (gridColumns.isEmpty) gridColumns = null;
    }

    // 2. Parse Rows and Cells
    final rawRows = <_TempRow>[];

    for (var child in node.children) {
      if (child is XmlElement && child.name.local == 'tr') {
        final cells = <_TempCell>[];
        bool isHeader = false;
        String? cnfStyle;
        int? height;

        // Check for header row property, cnfStyle, and row height
        final trPr = child.getElement('w:trPr');
        if (trPr != null) {
          if (trPr.getElement('w:tblHeader') != null) {
            isHeader = true;
          }
          final cs = trPr.getElement('w:cnfStyle');
          if (cs != null) {
            cnfStyle = cs.getAttribute('w:val');
          }
          // Parse row height
          final trHeight = trPr.getElement('w:trHeight');
          if (trHeight != null) {
            height = int.tryParse(trHeight.getAttribute('w:val') ?? '');
          }
        }

        for (var cellNode in child.children) {
          if (cellNode is XmlElement && cellNode.name.local == 'tc') {
            cells.add(_parseCell(cellNode));
          }
        }
        if (cells.isNotEmpty) {
          rawRows.add(_TempRow(
            cells: cells,
            isHeader: isHeader,
            cnfStyle: cnfStyle,
            height: height,
          ));
        }
      }
    }

    // 3. Resolve row spans
    final grid = _resolveRowSpans(rawRows);
    final finalRows = <DocxTableRow>[];

    // Resolve Table Style from context
    final resolvedTableStyle = context.resolveStyle(styleId);

    final rowCount = grid.length;
    final int colCount =
        grid.isNotEmpty ? grid.first.fold(0, (sum, c) => sum + c.gridSpan) : 0;

    for (int i = 0; i < grid.length; i++) {
      final r = grid[i];
      final isHeaderRow = i < rawRows.length ? rawRows[i].isHeader : false;
      final rowCnfStyle = i < rawRows.length ? rawRows[i].cnfStyle : null;
      final cells = <DocxTableCell>[];
      int colIndex = 0;

      for (var c in r) {
        final effectiveStyle = _resolveCellStyle(
            resolvedTableStyle, i, colIndex, rowCount, colCount, look);

        // Convert percentage width from gridCol if applicable
        int? cellWidth = c.width;
        if (widthType == DocxWidthType.pct && gridColumns != null) {
          // Calculate explicit width if using percentages
          // Assuming full width is page width minus margins for now
          // (Implementation could be refined with actual section context)
          // For now, if resolvedGridColumns has values, use them.
        }

        cells.add(DocxTableCell(
          children: c.children,
          colSpan: c.gridSpan,
          rowSpan: c.finalRowSpan,
          shadingFill: c.shadingFill ?? effectiveStyle.shadingFill,
          themeFill: c.themeFill ?? effectiveStyle.themeFill,
          themeFillTint: c.themeFillTint ?? effectiveStyle.themeFillTint,
          themeFillShade: c.themeFillShade ?? effectiveStyle.themeFillShade,
          width: cellWidth,
          borderTop: c.borderTop ?? effectiveStyle.borderTop,
          borderBottom: c.borderBottom ?? effectiveStyle.borderBottomSide,
          borderLeft: c.borderLeft ?? effectiveStyle.borderLeft,
          borderRight: c.borderRight ?? effectiveStyle.borderRight,
          verticalAlign: c.verticalAlign ??
              effectiveStyle.verticalAlign ??
              DocxVerticalAlign.top,
          cnfStyle: c.cnfStyle,
          marginLeft: c.marginLeft,
          marginRight: c.marginRight,
          marginTop: c.marginTop,
          marginBottom: c.marginBottom,
        ));
        colIndex += c.gridSpan;
      }
      final rowHeight = i < rawRows.length ? rawRows[i].height : null;
      finalRows.add(DocxTableRow(
        cells: cells,
        isHeader: isHeaderRow,
        cnfStyle: rowCnfStyle,
        height: rowHeight,
      ));
    }

    // Determine if table has any header rows
    final hasHeader = finalRows.any((row) => row.isHeader);

    return DocxTable(
      rows: finalRows,
      style: style,
      width: tableWidth,
      widthType: widthType,
      hasHeader: hasHeader,
      alignment: alignment,
      position: position,
      styleId: styleId,
      tblOverlap: tblOverlap,
      look: look,
      gridColumns: gridColumns,
    );
  }

  _TempCell _parseCell(XmlElement cellNode) {
    final tcPr = cellNode.getElement('w:tcPr');
    int gridSpan = 1;
    String? vMergeVal;
    String? shadingFill;
    String? themeFill;
    String? themeFillTint;
    String? themeFillShade;
    int? cellWidth;
    DocxBorderSide? borderTop;
    DocxBorderSide? borderBottom;
    DocxBorderSide? borderLeft;
    DocxBorderSide? borderRight;
    DocxVerticalAlign? verticalAlign;
    String? cnfStyle;
    int? marginLeft;
    int? marginRight;
    int? marginTop;
    int? marginBottom;

    if (tcPr != null) {
      final gs = tcPr.getElement('w:gridSpan');
      if (gs != null) {
        gridSpan = int.tryParse(gs.getAttribute('w:val') ?? '1') ?? 1;
      }

      final vm = tcPr.getElement('w:vMerge');
      if (vm != null) {
        vMergeVal = vm.getAttribute('w:val') ?? 'continue';
      }

      final shd = tcPr.getElement('w:shd');
      if (shd != null) {
        shadingFill = shd.getAttribute('w:fill');
        if (shadingFill == 'auto' || shadingFill == null) {
          shadingFill = null;
        } else {
          // Normalize to include # prefix if it's a hex color
          if (shadingFill.length == 6 &&
              RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(shadingFill)) {
            shadingFill = '#$shadingFill';
          }
        }

        themeFill = shd.getAttribute('w:themeFill');
        themeFillTint = shd.getAttribute('w:themeFillTint');
        themeFillShade = shd.getAttribute('w:themeFillShade');
      }

      // Parse vertical alignment
      final vAlignElem = tcPr.getElement('w:vAlign');
      if (vAlignElem != null) {
        final val = vAlignElem.getAttribute('w:val');
        if (val == 'top') verticalAlign = DocxVerticalAlign.top;
        if (val == 'center') verticalAlign = DocxVerticalAlign.center;
        if (val == 'bottom') verticalAlign = DocxVerticalAlign.bottom;
      }

      final tcW = tcPr.getElement('w:tcW');
      if (tcW != null) {
        cellWidth = int.tryParse(tcW.getAttribute('w:w') ?? '');
      }

      final tcBorders = tcPr.getElement('w:tcBorders');
      if (tcBorders != null) {
        borderTop = _parseBorderSide(tcBorders.getElement('w:top'));
        borderBottom = _parseBorderSide(tcBorders.getElement('w:bottom'));
        borderLeft = _parseBorderSide(tcBorders.getElement('w:left'));
        borderRight = _parseBorderSide(tcBorders.getElement('w:right'));
      }

      final cs = tcPr.getElement('w:cnfStyle');
      if (cs != null) {
        cnfStyle = cs.getAttribute('w:val');
      }

      final tcMar = tcPr.getElement('w:tcMar');
      if (tcMar != null) {
        int? side(String a, [String? b]) {
          final el =
              tcMar.getElement(a) ?? (b != null ? tcMar.getElement(b) : null);
          return int.tryParse(el?.getAttribute('w:w') ?? '');
        }

        marginLeft = side('w:left', 'w:start');
        marginRight = side('w:right', 'w:end');
        marginTop = side('w:top');
        marginBottom = side('w:bottom');
      }
    }

    // Parse cell children (paragraphs, nested tables)
    final children = <DocxBlock>[];
    for (var c in cellNode.children) {
      if (c is XmlElement && c.name.local == 'p') {
        children.add(_parseFullParagraph(c));
      } else if (c is XmlElement && c.name.local == 'tbl') {
        children.add(parse(c)); // Recursive for nested tables
      } else if (c is XmlElement &&
          ['ins', 'del', 'smartTag', 'sdt'].contains(c.name.local)) {
        // Handle block-level containers in cells
        var contentNodes = c.children;
        if (c.name.local == 'sdt') {
          final content = c.findAllElements('w:sdtContent').firstOrNull;
          if (content != null) contentNodes = content.children;
        }
        for (var child in contentNodes) {
          if (child is XmlElement && child.name.local == 'p') {
            children.add(_parseFullParagraph(child));
          } else if (child is XmlElement && child.name.local == 'tbl') {
            children.add(parse(child));
          }
        }
      }
    }

    return _TempCell(
      children: children,
      gridSpan: gridSpan,
      vMerge: vMergeVal,
      shadingFill: shadingFill,
      themeFill: themeFill,
      themeFillTint: themeFillTint,
      themeFillShade: themeFillShade,
      width: cellWidth,
      borderTop: borderTop,
      borderBottom: borderBottom,
      borderLeft: borderLeft,
      borderRight: borderRight,
      verticalAlign: verticalAlign,
      cnfStyle: cnfStyle,
      marginLeft: marginLeft,
      marginRight: marginRight,
      marginTop: marginTop,
      marginBottom: marginBottom,
    );
  }

  /// Full paragraph parser for table cells - preserves all text formatting.
  DocxParagraph _parseFullParagraph(XmlElement xml) {
    String? pStyle;
    DocxAlign? align;
    String? shadingFill;
    String? cnfStyle;

    // Parse paragraph properties
    final pPr = xml.getElement('w:pPr');
    if (pPr != null) {
      // Style reference
      final pStyleElem = pPr.getElement('w:pStyle');
      if (pStyleElem != null) {
        pStyle = pStyleElem.getAttribute('w:val');
      }

      // Alignment
      final jcElem = pPr.getElement('w:jc');
      if (jcElem != null) {
        final val = jcElem.getAttribute('w:val');
        if (val == 'center') align = DocxAlign.center;
        if (val == 'right' || val == 'end') align = DocxAlign.right;
        if (val == 'both' || val == 'distribute') align = DocxAlign.justify;
        if (val == 'left' || val == 'start') align = DocxAlign.left;
      }

      // Shading
      final shdElem = pPr.getElement('w:shd');
      if (shdElem != null) {
        shadingFill = shdElem.getAttribute('w:fill');
        if (shadingFill == 'auto') shadingFill = null;
      }

      final cs = pPr.getElement('w:cnfStyle');
      if (cs != null) {
        cnfStyle = cs.getAttribute('w:val');
      }
    }

    // Resolve style for inheritance
    final effectiveStyle = context.resolveStyle(pStyle ?? 'Normal');

    // Parse direct properties (override styles)
    // Extract rPr from pPr if present
    final rPr = pPr?.getElement('w:rPr');
    final parsedProps = DocxStyle.fromXml('temp', pPr: pPr, rPr: rPr);

    // Merge: Style < Direct
    final finalProps = effectiveStyle.merge(parsedProps);

    // Parse inline children with full formatting
    final children =
        inlineParser.parseChildren(xml.children, parentStyle: finalProps);

    return DocxParagraph(
      children: children,
      styleId: pStyle,
      align: align ?? effectiveStyle.align ?? DocxAlign.left,
      shadingFill: shadingFill ?? effectiveStyle.shadingFill,
      themeFill: effectiveStyle.themeFill,
      themeFillTint: effectiveStyle.themeFillTint,
      themeFillShade: effectiveStyle.themeFillShade,
      cnfStyle: cnfStyle,
    );
  }

  DocxBorderSide? _parseBorderSide(XmlElement? borderElem) {
    if (borderElem == null) return null;
    final val = borderElem.getAttribute('w:val');
    if (val == 'none' || val == 'nil') return const DocxBorderSide.none();
    if (val == null) return null;

    int size = 4;
    final szAttr = borderElem.getAttribute('w:sz');
    if (szAttr != null) {
      final s = int.tryParse(szAttr);
      if (s != null) size = s;
    }

    int space = 0;
    final spaceAttr = borderElem.getAttribute('w:space');
    if (spaceAttr != null) {
      final s = int.tryParse(spaceAttr);
      if (s != null) space = s;
    }

    var color = DocxColor.black;
    final colorAttr = borderElem.getAttribute('w:color');
    if (colorAttr != null && colorAttr != 'auto') {
      color = DocxColor(colorAttr);
    }

    final themeColor = borderElem.getAttribute('w:themeColor');
    final themeTint = borderElem.getAttribute('w:themeTint');
    final themeShade = borderElem.getAttribute('w:themeShade');

    var style = DocxBorder.single;
    String? rawVal;
    bool found = false;

    for (var b in DocxBorder.values) {
      if (b.xmlValue == val) {
        style = b;
        found = true;
        break;
      }
    }
    if (!found) {
      rawVal = val;
    }

    return DocxBorderSide(
      style: style,
      size: size,
      space: space,
      color: color,
      themeColor: themeColor,
      themeTint: themeTint,
      themeShade: themeShade,
      rawVal: rawVal,
    );
  }

  /// Resolves row spans (vMerge) by tracking grid columns.
  List<List<_TempCell>> _resolveRowSpans(List<_TempRow> rows) {
    if (rows.isEmpty) return [];

    final result = <List<_TempCell>>[];
    // Track the source cell for active vertical merges per grid column
    final activeMerges = <int, _TempCell>{};
    // Track the row index where the merge started
    final mergeStartRows = <int, int>{};

    for (int rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final inputRow = rows[rowIndex];
      final outputRow = <_TempCell>[];
      int currentGridCol = 0;

      for (var cell in inputRow.cells) {
        final gridSpan = cell.gridSpan;
        bool isContinue = cell.vMerge == 'continue' || cell.vMerge == '';
        bool isRestart = cell.vMerge == 'restart';

        if (cell.vMerge != null) {
          if (isRestart) {
            final newCell = cell.copyWith(finalRowSpan: 1);
            for (int i = 0; i < gridSpan; i++) {
              activeMerges[currentGridCol + i] = newCell;
              mergeStartRows[currentGridCol + i] = rowIndex;
            }
            outputRow.add(newCell);
          } else if (isContinue) {
            if (activeMerges.containsKey(currentGridCol)) {
              final startRowIndex = mergeStartRows[currentGridCol]!;

              var targetRow = result[startRowIndex];
              int checkCol = 0;
              for (int cIdx = 0; cIdx < targetRow.length; cIdx++) {
                final c = targetRow[cIdx];
                if (currentGridCol >= checkCol &&
                    currentGridCol < checkCol + c.gridSpan) {
                  targetRow[cIdx] =
                      c.copyWith(finalRowSpan: c.finalRowSpan + 1);
                  break;
                }
                checkCol += c.gridSpan;
              }
            } else {
              outputRow.add(cell.copyWith(finalRowSpan: 1));
            }
          }
        } else {
          final newCell = cell.copyWith(finalRowSpan: 1);
          for (int i = 0; i < gridSpan; i++) {
            activeMerges.remove(currentGridCol + i);
            mergeStartRows.remove(currentGridCol + i);
          }
          outputRow.add(newCell);
        }

        currentGridCol += gridSpan;
      }

      result.add(outputRow);
    }

    return result;
  }

  DocxStyle _resolveCellStyle(DocxStyle base, int row, int col, int rowCount,
      int colCount, DocxTableLook look) {
    var style = base;

    // Banding (Horizontal) - default Odd/Even assumption
    if (!look.noHBand) {
      if (row % 2 == 0) {
        style = style
            .merge(base.tableConditionals['band1Horz'] ?? DocxStyle.empty());
      } else {
        style = style
            .merge(base.tableConditionals['band2Horz'] ?? DocxStyle.empty());
      }
    }
    if (!look.noVBand) {
      if (col % 2 == 0) {
        style = style
            .merge(base.tableConditionals['band1Vert'] ?? DocxStyle.empty());
      } else {
        style = style
            .merge(base.tableConditionals['band2Vert'] ?? DocxStyle.empty());
      }
    }

    if (look.firstRow && row == 0) {
      style =
          style.merge(base.tableConditionals['firstRow'] ?? DocxStyle.empty());
    }
    if (look.lastRow && row == rowCount - 1) {
      style =
          style.merge(base.tableConditionals['lastRow'] ?? DocxStyle.empty());
    }
    if (look.firstColumn && col == 0) {
      style =
          style.merge(base.tableConditionals['firstCol'] ?? DocxStyle.empty());
    }
    if (look.lastColumn && col == colCount - 1) {
      style =
          style.merge(base.tableConditionals['lastCol'] ?? DocxStyle.empty());
    }

    if (look.firstRow && look.firstColumn && row == 0 && col == 0) {
      style =
          style.merge(base.tableConditionals['nwCell'] ?? DocxStyle.empty());
    }
    if (look.firstRow && look.lastColumn && row == 0 && col == colCount - 1) {
      style =
          style.merge(base.tableConditionals['neCell'] ?? DocxStyle.empty());
    }
    if (look.lastRow && look.firstColumn && row == rowCount - 1 && col == 0) {
      style =
          style.merge(base.tableConditionals['swCell'] ?? DocxStyle.empty());
    }
    if (look.lastRow &&
        look.lastColumn &&
        row == rowCount - 1 &&
        col == colCount - 1) {
      style =
          style.merge(base.tableConditionals['seCell'] ?? DocxStyle.empty());
    }

    return style;
  }
}

/// Temporary cell structure for row span resolution.
class _TempCell {
  final List<DocxBlock> children;
  final int gridSpan;
  final String? vMerge;
  final String? shadingFill;
  final String? themeFill;
  final String? themeFillTint;
  final String? themeFillShade;
  final int? width;
  final DocxBorderSide? borderTop;
  final DocxBorderSide? borderBottom;
  final DocxBorderSide? borderLeft;
  final DocxBorderSide? borderRight;
  final DocxVerticalAlign? verticalAlign;
  final int finalRowSpan;
  final String? cnfStyle;
  final int? marginLeft;
  final int? marginRight;
  final int? marginTop;
  final int? marginBottom;

  _TempCell({
    required this.children,
    this.gridSpan = 1,
    this.vMerge,
    this.shadingFill,
    this.themeFill,
    this.themeFillTint,
    this.themeFillShade,
    this.width,
    this.borderTop,
    this.borderBottom,
    this.borderLeft,
    this.borderRight,
    this.verticalAlign,
    this.finalRowSpan = 1,
    this.cnfStyle,
    this.marginLeft,
    this.marginRight,
    this.marginTop,
    this.marginBottom,
  });

  _TempCell copyWith({int? finalRowSpan}) {
    return _TempCell(
      children: children,
      gridSpan: gridSpan,
      vMerge: vMerge,
      shadingFill: shadingFill,
      themeFill: themeFill,
      themeFillTint: themeFillTint,
      themeFillShade: themeFillShade,
      width: width,
      borderTop: borderTop,
      borderBottom: borderBottom,
      borderLeft: borderLeft,
      borderRight: borderRight,
      verticalAlign: verticalAlign,
      marginLeft: marginLeft,
      marginRight: marginRight,
      marginTop: marginTop,
      marginBottom: marginBottom,
      finalRowSpan: finalRowSpan ?? this.finalRowSpan,
      cnfStyle: cnfStyle,
    );
  }
}

/// Temporary row structure for header detection.
class _TempRow {
  final List<_TempCell> cells;
  final bool isHeader;
  final String? cnfStyle;
  final int? height;

  _TempRow({
    required this.cells,
    this.isHeader = false,
    this.cnfStyle,
    this.height,
  });
}
