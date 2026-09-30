import 'dart:math' as math;

import '../../../docx_creator.dart';
import 'pdf_font_manager.dart';

/// Exact block measurement supplied by the renderer, so pagination uses the
/// very same line breaking, fonts and spacing that are later drawn instead
/// of an approximation that can drift from it (which previously let content
/// run past the bottom margin, or leave large gaps).
abstract class PdfBlockMeasurer {
  /// Height of a body paragraph laid out in [width] points.
  double measureParagraph(DocxParagraph paragraph, double width);

  /// Splits [paragraph] at the last line that fits in [availableHeight];
  /// returns `[fitted, remainder]` (fitted has no children if nothing fits).
  List<DocxParagraph> splitParagraph(
      DocxParagraph paragraph, double width, double availableHeight);

  /// Height of a list laid out in [width] points.
  double measureList(DocxList list, double width);

  /// Splits [list] between items; returns `[fitted, remainder]`.
  List<DocxList> splitList(DocxList list, double width, double availableHeight);

  /// Height of a table cell's content (including cell padding) in [width].
  double measureCell(DocxTableCell cell, double width);

  /// Height of every row of [table] with the given column widths, using
  /// the same span-aware cell placement and cell padding as drawing.
  List<double> measureTableRowHeights(DocxTable table, List<double> colWidths);
}

/// Handles document layout, measurement, and pagination.
///
/// Uses a two-pass approach: measure blocks first, then render.
class PdfLayoutEngine {
  final double pageWidth;
  final double pageHeight;
  final double marginTop;
  final double marginBottom;
  final double marginLeft;
  final double marginRight;
  final double baseFontSize;
  final PdfFontManager fontManager;

  /// Footnotes referenced from the document, by ID. When provided,
  /// [paginateWithFootnotes] reserves bottom-of-page space for whichever
  /// footnotes end up referenced on each page.
  final Map<int, DocxFootnote> footnotesById;

  /// When set, all paragraph/list/cell measurement and paragraph/list
  /// splitting is delegated to it (see [PdfBlockMeasurer]).
  final PdfBlockMeasurer? measurer;

  PdfLayoutEngine({
    required this.pageWidth,
    required this.pageHeight,
    this.marginTop = 72,
    this.marginBottom = 72,
    this.marginLeft = 72,
    this.marginRight = 72,
    this.baseFontSize = 12,
    PdfFontManager? fontManager,
    Map<int, DocxFootnote>? footnotesById,
    this.measurer,
  })  : fontManager = fontManager ?? PdfFontManager(),
        footnotesById = footnotesById ?? const {};

  /// Content area dimensions
  double get contentWidth => pageWidth - marginLeft - marginRight;
  double get contentHeight => pageHeight - marginTop - marginBottom;
  double get contentTop => pageHeight - marginTop;
  double get contentBottom => marginBottom;

  /// Paginates document nodes into pages.
  ///
  /// Returns a list of pages, where each page is a list of nodes.
  List<List<DocxNode>> paginate(List<DocxNode> nodes) {
    final pages = <List<DocxNode>>[];
    var currentPage = <DocxNode>[];
    var remainingHeight = contentHeight;

    for (final node in nodes) {
      // Handle explicit page breaks
      if (node is DocxSectionBreakBlock) {
        if (currentPage.isNotEmpty) {
          pages.add(currentPage);
          currentPage = [];
        }
        remainingHeight = contentHeight;
        continue;
      }

      // Honor an explicit "start this paragraph on a new page" request.
      if (node is DocxParagraph &&
          node.pageBreakBefore &&
          currentPage.isNotEmpty) {
        pages.add(currentPage);
        currentPage = [];
        remainingHeight = contentHeight;
      }

      final height = measureNode(node);

      // Check if node fits on current page
      if (remainingHeight - height < 0) {
        // If it fits on a clean page, and we aren't empty, just break page
        if (height <= contentHeight && currentPage.isNotEmpty) {
          pages.add(currentPage);
          currentPage = [];
          remainingHeight = contentHeight;
          currentPage.add(node);
          remainingHeight -= height;
        } else if (node is DocxParagraph) {
          // It does not fit or is huge. Split it.
          if (currentPage.isNotEmpty && remainingHeight < baseFontSize * 2) {
            // Too little space left, just move to next page to start clean
            pages.add(currentPage);
            currentPage = [];
            remainingHeight = contentHeight;
          }

          final splitResult = _splitParagraph(node, remainingHeight);
          final fittedPart = splitResult.first;
          final remainderPart = splitResult.last;

          if (fittedPart.children.isEmpty) {
            // Did not fit at all on current page (or remainingHeight was tiny)
            if (currentPage.isNotEmpty) {
              pages.add(currentPage);
              currentPage = [];
              remainingHeight = contentHeight;

              // Retry on new page
              final splitResult2 = _splitParagraph(node, remainingHeight);
              if (splitResult2.first.children.isNotEmpty) {
                currentPage.add(splitResult2.first);
                remainingHeight -= measureParagraph(splitResult2.first);

                var currentRemainder = splitResult2.last;
                while (currentRemainder.children.isNotEmpty) {
                  if (remainingHeight < baseFontSize) {
                    pages.add(currentPage);
                    currentPage = [];
                    remainingHeight = contentHeight;
                  }

                  final remHeight = measureParagraph(currentRemainder);
                  if (remHeight <= remainingHeight) {
                    currentPage.add(currentRemainder);
                    remainingHeight -= remHeight;
                    break;
                  }

                  final nextSplit =
                      _splitParagraph(currentRemainder, remainingHeight);
                  if (nextSplit.first.children.isNotEmpty) {
                    currentPage.add(nextSplit.first);
                    remainingHeight -= measureParagraph(nextSplit.first);
                    currentRemainder = nextSplit.last;
                  } else {
                    // Should not happen if logic is sound, but safe guard
                    pages.add(currentPage);
                    currentPage = [];
                    remainingHeight = contentHeight;
                  }
                }
              } else {
                // Huge single line?
                currentPage.add(node);
                remainingHeight -= height;
              }
            } else {
              currentPage.add(node);
              remainingHeight -= height;
            }
          } else {
            currentPage.add(fittedPart);
            remainingHeight -= measureParagraph(fittedPart);

            var currentRemainder = remainderPart;
            while (currentRemainder.children.isNotEmpty) {
              if (remainingHeight < baseFontSize) {
                pages.add(currentPage);
                currentPage = [];
                remainingHeight = contentHeight;
              }

              final remHeight = measureParagraph(currentRemainder);
              if (remHeight <= remainingHeight) {
                currentPage.add(currentRemainder);
                remainingHeight -= remHeight;
                break;
              }

              final nextSplit =
                  _splitParagraph(currentRemainder, remainingHeight);
              if (nextSplit.first.children.isNotEmpty) {
                currentPage.add(nextSplit.first);
                remainingHeight -= measureParagraph(nextSplit.first);
                currentRemainder = nextSplit.last;
              } else {
                pages.add(currentPage);
                currentPage = [];
                remainingHeight = contentHeight;
              }
            }
          }
        } else if (node is DocxTable) {
          // Split the table by row so long tables continue onto following
          // pages instead of being drawn past the bottom margin.
          if (currentPage.isNotEmpty && remainingHeight < baseFontSize * 2) {
            pages.add(currentPage);
            currentPage = [];
            remainingHeight = contentHeight;
          }

          // Header rows (`<thead>` / Word's "repeat as header row") are
          // drawn again at the top of every page the table continues on,
          // and are never left alone at the bottom of a page.
          final headerRows = node.rows.sublist(0, _repeatedHeaderCount(node));
          final keepWith = headerRows.length;
          var remainder = node;
          while (remainder.rows.isNotEmpty) {
            final split =
                _splitTable(remainder, remainingHeight, keepWith: keepWith);
            final fitted = split.first;
            final rest = split.last;

            if (fitted.rows.isEmpty) {
              if (currentPage.isEmpty) {
                // Its first row (or rowSpan group) doesn't fit even on an
                // empty page: place just that group and carry on, rather
                // than looping forever or dumping the whole table here.
                final forced = _splitTable(remainder, remainingHeight,
                    force: true, keepWith: keepWith);
                currentPage.add(forced.first);
                remainingHeight -= measureTable(forced.first);
                remainder = _withHeader(forced.last, headerRows);
                if (remainder.rows.isNotEmpty) {
                  pages.add(currentPage);
                  currentPage = [];
                  remainingHeight = contentHeight;
                }
                continue;
              }
              pages.add(currentPage);
              currentPage = [];
              remainingHeight = contentHeight;
              continue;
            }

            currentPage.add(fitted);
            remainingHeight -= measureTable(fitted);
            remainder = _withHeader(rest, headerRows);

            if (remainder.rows.isNotEmpty) {
              pages.add(currentPage);
              currentPage = [];
              remainingHeight = contentHeight;
            }
          }
        } else if (node is DocxList && measurer != null) {
          // Split long lists between items so they continue on the next
          // page instead of being drawn past the bottom margin.
          if (currentPage.isNotEmpty && remainingHeight < baseFontSize * 2) {
            pages.add(currentPage);
            currentPage = [];
            remainingHeight = contentHeight;
          }
          var remainder = node;
          while (remainder.items.isNotEmpty) {
            final split =
                measurer!.splitList(remainder, contentWidth, remainingHeight);
            final fitted = split.first;
            if (fitted.items.isEmpty) {
              if (currentPage.isEmpty) {
                currentPage.add(remainder);
                remainingHeight -= measureList(remainder);
                break;
              }
              pages.add(currentPage);
              currentPage = [];
              remainingHeight = contentHeight;
              continue;
            }
            currentPage.add(fitted);
            remainingHeight -= measureList(fitted);
            remainder = split.last;
            if (remainder.items.isNotEmpty) {
              pages.add(currentPage);
              currentPage = [];
              remainingHeight = contentHeight;
            }
          }
        } else {
          // Not a paragraph or table (e.g. image)
          if (currentPage.isNotEmpty) {
            pages.add(currentPage);
            currentPage = [];
            remainingHeight = contentHeight;
          }
          currentPage.add(node);
          remainingHeight -= height;
        }
      } else {
        currentPage.add(node);
        remainingHeight -= height;
      }
    }

    if (currentPage.isNotEmpty) {
      pages.add(currentPage);
    }

    if (pages.isEmpty) {
      pages.add([]);
    }

    return pages;
  }

  /// Runs [paginate], then rebalances pages so bottom-of-page space is
  /// reserved for any footnotes referenced by paragraphs that landed on
  /// them. Built as a post-process over [paginate]'s output (rather than
  /// threaded through its per-node placement logic) so the already-tested
  /// core pagination algorithm is untouched; whole nodes that would push a
  /// page over budget once its footnotes are accounted for are carried to
  /// the next page instead.
  PdfPaginationResult paginateWithFootnotes(List<DocxNode> nodes) {
    final pages = paginate(nodes);
    if (footnotesById.isEmpty) {
      return PdfPaginationResult(
          pages, List.generate(pages.length, (_) => const <int>[]));
    }

    final adjustedPages = <List<DocxNode>>[];
    final footnoteIdsPerPage = <List<int>>[];
    var carryOver = <DocxNode>[];

    void packPage(List<DocxNode> initial) {
      var candidate = [...carryOver, ...initial];
      carryOver = [];

      while (true) {
        final ids = _footnoteIdsReferencedBy(candidate);
        final footnoteHeight = measureFootnotesHeight(ids);
        final bodyHeight =
            candidate.fold<double>(0, (sum, n) => sum + measureNode(n));

        if (bodyHeight + footnoteHeight <= contentHeight ||
            candidate.length <= 1) {
          adjustedPages.add(candidate);
          footnoteIdsPerPage.add(ids);
          return;
        }
        // Doesn't fit once its footnotes are reserved — bump the last node
        // to the next page and retry.
        carryOver.insert(0, candidate.removeLast());
      }
    }

    for (final page in pages) {
      packPage(page);
    }
    while (carryOver.isNotEmpty) {
      packPage(const []);
    }

    return PdfPaginationResult(adjustedPages, footnoteIdsPerPage);
  }

  /// Footnote IDs referenced by top-level paragraphs (or a drop cap's
  /// `restOfParagraph`, which flows through the same word model as an
  /// ordinary paragraph — see `PdfExporter._renderDropCap`) in [nodes], in
  /// first-reference order, without duplicates.
  List<int> _footnoteIdsReferencedBy(List<DocxNode> nodes) {
    final ids = <int>[];
    void scan(List<DocxInline> children) {
      for (final child in children) {
        if (child is DocxFootnoteRef && !ids.contains(child.footnoteId)) {
          ids.add(child.footnoteId);
        }
      }
    }

    for (final node in nodes) {
      if (node is DocxParagraph) {
        scan(node.children);
      } else if (node is DocxDropCap) {
        scan(node.restOfParagraph);
      }
    }
    return ids;
  }

  /// Height needed to render the given footnote IDs' content at the bottom
  /// of a page, at the page's content width. Shared by pagination (to
  /// reserve the space) and rendering (to draw it), so the two can't drift
  /// apart.
  double measureFootnotesHeight(List<int> footnoteIds) {
    if (footnoteIds.isEmpty) return 0;
    // Separator line + top spacing above the first footnote.
    var height = 10.0;
    for (final id in footnoteIds) {
      final footnote = footnotesById[id];
      if (footnote == null) continue;
      for (final block in footnote.content) {
        if (block is DocxParagraph) {
          height += measurer != null
              ? measurer!.measureParagraph(block, contentWidth)
              : measureParagraphInWidth(block, contentWidth - 20);
        }
      }
    }
    return height;
  }

  /// Measures the height of a node.
  double measureNode(DocxNode node) {
    if (node is DocxParagraph) {
      return measureParagraph(node);
    } else if (node is DocxTable) {
      return measureTable(node);
    } else if (node is DocxList) {
      return measureList(node);
    } else if (node is DocxImage) {
      final scale = node.width > contentWidth && node.width > 0
          ? contentWidth / node.width
          : 1.0;
      return node.height * scale + 10;
    } else if (node is DocxDropCap) {
      return _measureDropCap(node);
    } else if (node is DocxTableOfContents) {
      return node.cachedContent
          .fold<double>(0, (sum, block) => sum + measureNode(block));
    } else if (node is DocxShapeBlock) {
      return node.shape.height + 10;
    }
    return baseFontSize * 1.5;
  }

  /// Measures paragraph height including line wrapping.
  double measureParagraph(DocxParagraph paragraph) {
    final m = measurer;
    if (m != null) return m.measureParagraph(paragraph, contentWidth);
    final fontSize =
        _effectiveFontSize(paragraph, getFontSize(paragraph.styleId));
    final lineHeight = fontSize * 1.4;
    final indent = (paragraph.indentLeft ?? 0) / 20.0;
    final indentRight = (paragraph.indentRight ?? 0) / 20.0;
    final availableWidth = contentWidth - indent - indentRight;
    final extra = _paragraphExtraHeight(paragraph);

    if (paragraph.children.isEmpty) {
      return lineHeight + fontSize * 0.5 + extra;
    }

    // Collect text
    final textBuffer = StringBuffer();
    for (final child in paragraph.children) {
      if (child is DocxText) {
        textBuffer.write(child.content);
      } else if (child is DocxLineBreak) {
        textBuffer.write('\n');
      } else if (child is DocxTab) {
        textBuffer.write('    ');
      }
    }

    final text = textBuffer.toString();
    final lines = _wrapText(text, availableWidth, fontSize,
        fontRef: _fallbackFontRefFor(paragraph.children));

    return lines * lineHeight +
        fontSize * 0.5 +
        extra +
        _inlineMediaExtraHeight(paragraph.children, lineHeight);
  }

  /// Extra height to reserve for inline images/shapes taller than a normal
  /// text line, on top of the plain word-wrap line count above - which,
  /// like `PdfExporter._collectWords`, only ever looks at [DocxText]/
  /// [DocxLineBreak]/[DocxTab] and so is otherwise blind to inline media
  /// entirely. Without this, a paragraph with e.g. an inline badge icon
  /// measures as if it were pure text, pagination reserves far too little
  /// space for it, and the next node on the page gets drawn starting well
  /// inside the image instead of below it.
  ///
  /// Conservative rather than exact: each oversized image/shape adds its
  /// own full overhang regardless of which wrapped line it actually lands
  /// on (in principle two could share a line and this would double-count
  /// the overhang), so this can only ever reserve more height than the
  /// renderer's own per-line max ends up needing - never less, which is the
  /// direction that would risk the overlap this exists to prevent.
  double _inlineMediaExtraHeight(List<DocxInline> children, double lineHeight) {
    var extra = 0.0;
    for (final child in children) {
      double? mediaHeight;
      if (child is DocxInlineImage) {
        mediaHeight = child.height;
      } else if (child is DocxShape) {
        mediaHeight = child.height;
      }
      if (mediaHeight != null && mediaHeight > lineHeight) {
        extra += mediaHeight - lineHeight;
      }
    }
    return extra;
  }

  /// Measures a drop cap's height: the letter's own `dropCap.lines`-line
  /// block, plus however many extra full-width lines `restOfParagraph`
  /// spills past it. Mirrors `PdfExporter._renderDropCap`'s wrap-around flow
  /// (narrow lines beside the letter, full width after) so pagination can't
  /// drift from what actually gets drawn.
  double _measureDropCap(DocxDropCap node) {
    final dropCapFontSize = node.fontSize ?? (baseFontSize * node.lines);
    final dropCapWidth =
        fontManager.measureText(node.letter, dropCapFontSize, isBold: true);
    final hGap = node.hSpace > 0 ? node.hSpace / 20.0 : baseFontSize * 0.3;
    final narrowWidth = (contentWidth - dropCapWidth - hGap)
        .clamp(0.0, contentWidth)
        .toDouble();
    final dropCapLineHeight = baseFontSize * 1.4;
    final dropCapBlockHeight = node.lines * dropCapLineHeight;

    final textBuffer = StringBuffer();
    for (final child in node.restOfParagraph) {
      if (child is DocxText) {
        textBuffer.write(child.content);
      } else if (child is DocxLineBreak) {
        textBuffer.write('\n');
      } else if (child is DocxTab) {
        textBuffer.write('    ');
      }
    }
    final text = textBuffer.toString();
    if (text.isEmpty) {
      return dropCapBlockHeight + baseFontSize * 0.5;
    }

    final wrappedLines = _wrapTextVariableWidth(
        text, baseFontSize, (i) => i < node.lines ? narrowWidth : contentWidth,
        fontRef: _fallbackFontRefFor(node.restOfParagraph));
    final textHeight = wrappedLines <= node.lines
        ? dropCapBlockHeight
        : dropCapBlockHeight + (wrappedLines - node.lines) * dropCapLineHeight;

    return textHeight + baseFontSize * 0.5;
  }

  /// Largest per-run [DocxText.fontSize] in the paragraph, falling back to
  /// [baseSize]. Keeps pagination height in sync with what
  /// `PdfExporter._renderParagraph` actually draws per word.
  double _effectiveFontSize(DocxParagraph paragraph, double baseSize) {
    var maxSize = baseSize;
    for (final child in paragraph.children) {
      if (child is DocxText &&
          child.fontSize != null &&
          child.fontSize! > maxSize) {
        maxSize = child.fontSize!;
      }
    }
    return maxSize;
  }

  /// Extra vertical space (padding + spacing, in points) a paragraph reserves
  /// beyond its wrapped text lines.
  double _paragraphExtraHeight(DocxParagraph paragraph) {
    final paddingV =
        ((paragraph.paddingTop ?? 0) + (paragraph.paddingBottom ?? 0)) / 20.0;
    final spacingV =
        ((paragraph.spacingBefore ?? 0) + (paragraph.spacingAfter ?? 0)) / 20.0;
    return paddingV + spacingV;
  }

  /// Resolves each column's rendered width in points from
  /// [DocxTable.resolvedGridColumns] (twips), proportionally scaled to fit
  /// [contentWidth]. Shared by measurement, splitting, and rendering so all
  /// three always agree on where column boundaries fall.
  List<double> tableColumnWidths(DocxTable table) {
    final gridColumns = table.resolvedGridColumns;
    if (gridColumns.isEmpty) return const [];
    final totalGridTwips = gridColumns.fold<int>(0, (a, b) => a + b);
    if (totalGridTwips <= 0) {
      final n = gridColumns.length;
      return List<double>.filled(n, contentWidth / n);
    }
    // Keep the table's real width (Word doesn't stretch narrower tables),
    // honour percentage widths, and only shrink tables wider than the page.
    var target = totalGridTwips / 20.0;
    if (table.widthType == DocxWidthType.pct && (table.width ?? 0) > 0) {
      target = contentWidth * table.width! / 5000.0;
    } else if (table.widthType == DocxWidthType.dxa && (table.width ?? 0) > 0) {
      target = table.width! / 20.0;
    }
    if (target > contentWidth) target = contentWidth;
    return gridColumns.map((w) => w / totalGridTwips * target).toList();
  }

  /// Horizontal offset of a table within the content area, from its
  /// alignment (tables narrower than the page can be centered/right).
  double tableOffset(DocxTable table, List<double> colWidths) {
    final width = colWidths.fold<double>(0, (a, b) => a + b);
    final slack = contentWidth - width;
    if (slack <= 0) return 0;
    if (table.alignment == DocxAlign.center) return slack / 2;
    if (table.alignment == DocxAlign.right) return slack;
    return 0;
  }

  /// Measures a row's height given each column's width in points, accounting
  /// for colSpan (a cell's available width is the sum of the columns it
  /// spans).
  double measureRowHeight(DocxTableRow row, List<double> colWidths) {
    var maxRowHeight = measurer != null ? (row.height ?? 0) / 20.0 : 20.0;
    var colIndex = 0;
    for (final cell in row.cells) {
      var spanWidth = 0.0;
      for (var j = 0;
          j < cell.colSpan && colIndex + j < colWidths.length;
          j++) {
        spanWidth += colWidths[colIndex + j];
      }
      if (spanWidth <= 0) spanWidth = contentWidth;
      final cellHeight =
          measureCell(cell, measurer != null ? spanWidth : spanWidth - 4);
      if (cellHeight > maxRowHeight) maxRowHeight = cellHeight;
      colIndex += cell.colSpan;
    }
    return maxRowHeight;
  }

  /// Measures table height.
  double measureTable(DocxTable table) {
    if (table.rows.isEmpty) return 0;

    final colWidths = tableColumnWidths(table);
    return _rowHeights(table, colWidths).fold<double>(0, (a, b) => a + b) + 10;
  }

  /// Splits a table into a part that fits [availableHeight] and the
  /// remaining rows, mirroring [_splitParagraph] for tables. The first
  /// [keepWith] rows (repeated header rows) never make up a part on their
  /// own: at least one row after them must fit too.
  List<DocxTable> _splitTable(DocxTable table, double availableHeight,
      {bool force = false, int keepWith = 0}) {
    if (table.rows.isEmpty) return [table, table.copyWith(rows: const [])];

    final colWidths = tableColumnWidths(table);
    final heights = _rowHeights(table, colWidths);
    final continues = _rowContinuesSpan(table);
    var usedHeight = 10.0; // trailing spacing measureTable() also reserves
    var i = 0;
    // Last row index after which a page break is allowed (not inside a
    // rowSpan group, which would orphan the spanned cells).
    var lastBreak = 0;

    for (; i < table.rows.length; i++) {
      if (usedHeight + heights[i] > availableHeight) break;
      usedHeight += heights[i];
      if (i + 1 > keepWith &&
          (i + 1 >= table.rows.length || !continues[i + 1])) {
        lastBreak = i + 1;
      }
    }

    // Break at the last allowed boundary. If even the first row (or rowSpan
    // group) doesn't fit, report nothing fitted so the caller can move to a
    // new page; only when [force]d (already on an empty page) is that
    // group placed anyway.
    if (lastBreak > 0) {
      i = lastBreak;
    } else if (force) {
      i = math.min(_groupEnd(continues, keepWith), table.rows.length);
    } else {
      return [table.copyWith(rows: const []), table];
    }
    final fittedRows = table.rows.sublist(0, i);

    final remainderRows = table.rows.sublist(i);
    return [
      table.copyWith(rows: fittedRows),
      table.copyWith(rows: remainderRows, hasHeader: false),
    ];
  }

  /// Number of leading rows marked [DocxTableRow.isHeader] that repeat on
  /// continuation pages, or 0 when a rowSpan runs out of them into the body
  /// or they are the whole table.
  int _repeatedHeaderCount(DocxTable table) {
    var count = 0;
    while (count < table.rows.length && table.rows[count].isHeader) {
      count++;
    }
    if (count == 0 || count == table.rows.length) return 0;
    if (_rowContinuesSpan(table)[count]) return 0;
    return count;
  }

  DocxTable _withHeader(DocxTable rest, List<DocxTableRow> headerRows) =>
      headerRows.isEmpty || rest.rows.isEmpty
          ? rest
          : rest.copyWith(rows: [...headerRows, ...rest.rows]);

  /// Row heights, exact when a [measurer] is set.
  List<double> _rowHeights(DocxTable table, List<double> colWidths) {
    final m = measurer;
    if (m != null) return m.measureTableRowHeights(table, colWidths);
    return [for (final row in table.rows) measureRowHeight(row, colWidths)];
  }

  /// For each row, whether a rowSpan cell from an earlier row still covers
  /// it (so the table must not be split right before it).
  List<bool> _rowContinuesSpan(DocxTable table) {
    final result = List<bool>.filled(table.rows.length, false);
    var coveredUntil = -1; // last row index covered by an open span
    for (var r = 0; r < table.rows.length; r++) {
      result[r] = r <= coveredUntil;
      for (final cell in table.rows[r].cells) {
        if (cell.rowSpan > 1) {
          coveredUntil = math.max(coveredUntil, r + cell.rowSpan - 1);
        }
      }
    }
    return result;
  }

  /// End (exclusive) of the rowSpan group starting at [start].
  int _groupEnd(List<bool> continues, int start) {
    var end = start + 1;
    while (end < continues.length && continues[end]) {
      end++;
    }
    return end;
  }

  /// Measures cell height.
  double measureCell(DocxTableCell cell, double width) {
    final m = measurer;
    if (m != null) return m.measureCell(cell, width);
    double height = 0;
    for (final block in cell.children) {
      if (block is DocxParagraph) {
        height += measureParagraphInWidth(block, width);
      } else if (block is DocxTable) {
        height += measureTableInWidth(block, width);
      } else if (block is DocxList) {
        height += block.items.length * baseFontSize * 1.5;
      }
    }
    return height + 10;
  }

  /// Measures paragraph in specific width.
  double measureParagraphInWidth(DocxParagraph paragraph, double width) {
    final fontSize = getFontSize(paragraph.styleId);
    final lineHeight = fontSize * 1.4;

    if (paragraph.children.isEmpty) return lineHeight;

    final textBuffer = StringBuffer();
    for (final child in paragraph.children) {
      if (child is DocxText) textBuffer.write(child.content);
    }

    final lines = _wrapText(textBuffer.toString(), width, fontSize,
        fontRef: _fallbackFontRefFor(paragraph.children));
    return lines * lineHeight;
  }

  /// Measures table in specific width.
  double measureTableInWidth(DocxTable table, double width) {
    if (table.rows.isEmpty) return 0;

    final cols = table.rows.first.cells.length;
    final colWidth = width / cols;

    double totalHeight = 0;
    for (final row in table.rows) {
      double maxRowHeight = 20;
      for (final cell in row.cells) {
        final cellHeight = measureCell(cell, colWidth - 4);
        if (cellHeight > maxRowHeight) maxRowHeight = cellHeight;
      }
      totalHeight += maxRowHeight;
    }
    return totalHeight + 10;
  }

  /// Measures list height.
  double measureList(DocxList list) {
    final m = measurer;
    if (m != null) return m.measureList(list, contentWidth);
    double height = 0;
    for (final item in list.items) {
      height += measureListItem(item, list.style);
    }
    return height + 10;
  }

  /// Measures list item height.
  double measureListItem(DocxListItem item, DocxListStyle listStyle) {
    final fontSize =
        item.overrideStyle?.fontSize ?? listStyle.fontSize ?? baseFontSize;
    // contentWidth includes margins.
    // List indentation: ~36pt (0.5 inch) per level + hanging indent
    final indent = (item.level + 1) * 36.0;
    final availableWidth = contentWidth - indent;

    final lineHeight = fontSize * 1.4;

    if (item.children.isEmpty) {
      return lineHeight + fontSize * 0.5;
    }

    final textBuffer = StringBuffer();
    for (final child in item.children) {
      if (child is DocxText) {
        textBuffer.write(child.content);
      } else if (child is DocxLineBreak) {
        textBuffer.write('\n');
      } else if (child is DocxTab) {
        textBuffer.write('    ');
      }
    }

    final text = textBuffer.toString();
    final lines = _wrapText(text, availableWidth, fontSize,
        fontRef: _fallbackFontRefFor(item.children));

    return lines * lineHeight + fontSize * 0.5;
  }

  /// If any run in [children] needs the Unicode fallback font (any
  /// character outside WinAnsi, e.g. an emoji or unembedded non-Latin
  /// script - see [PdfFontManager.needsUnicodeFallback]), returns that
  /// font's ref so callers can measure with it; otherwise null (plain
  /// metrics).
  ///
  /// `PdfExporter._withUnicodeFallback` makes this choice per *run* - a
  /// [DocxText] whose content contains a fallback-needing character has
  /// its *entire* run, plain-ASCII words included, drawn through the
  /// (generally wider) fallback font, not just that one character. This
  /// file's measurement methods build one plain-text buffer by
  /// concatenating every run before wrapping, which loses run boundaries -
  /// so the best it can do without a structural rewrite is apply the
  /// fallback font to the *whole* wrap pass whenever any run in the
  /// paragraph/item needs it. That over-measures pure-ASCII runs sharing a
  /// paragraph with a fallback-needing one by a small amount, but that's
  /// the safe direction: measuring every word with plain metrics while the
  /// renderer actually draws some of them (possibly wider) through the
  /// fallback font is what previously undercounted wrapped lines and let
  /// the overflow spill into whatever was drawn next.
  String? _fallbackFontRefFor(List<DocxInline> children) {
    for (final child in children) {
      if (child is DocxText &&
          fontManager.needsUnicodeFallback(child.content)) {
        return fontManager.fallbackUnicodeFontRef;
      }
    }
    return null;
  }

  /// Gets font size for a style.
  double getFontSize(String? styleId) {
    if (styleId == null) return baseFontSize.toDouble();
    // Relative sizes mirroring the DOCX heading styles this package writes
    // (Heading1 24pt, Heading2 20pt, Heading3 16pt at a 12pt base).
    const headingScale = {
      'Heading1': 2.0,
      'Heading2': 1.67,
      'Heading3': 1.33,
      'Heading4': 1.17,
      'Heading5': 1.0,
      'Heading6': 0.92,
      'Title': 2.33,
      'Subtitle': 1.25,
    };
    for (final entry in headingScale.entries) {
      if (styleId == entry.key) return baseFontSize * entry.value;
    }
    if (styleId.startsWith('Heading')) return baseFontSize * 1.17;
    return baseFontSize.toDouble();
  }

  // ... (previous code)

  /// Splits a paragraph into two parts: one that fits in availableHeight, and the remainder.
  /// Returns a list of two DocxParagraphs. The second one is null if everything fits.
  ///
  /// Known gap: unlike [_wrapText]/[_wrapTextVariableWidth] and
  /// `PdfExporter._splitOverlongWords`, this method's own word-wrap
  /// simulation still treats every space-delimited word as fitting on one
  /// line. A paragraph containing an overlong word/URL that needs to be
  /// split exactly at a page boundary can therefore have its "fitted" part
  /// slightly exceed the available height once actually rendered. Tracked
  /// as a follow-up; the far more common single-page overflow case is
  /// fixed.
  List<DocxParagraph> _splitParagraph(
      DocxParagraph paragraph, double availableHeight) {
    final m = measurer;
    if (m != null) {
      return m.splitParagraph(paragraph, contentWidth, availableHeight);
    }
    final fontSize =
        _effectiveFontSize(paragraph, getFontSize(paragraph.styleId));
    final lineHeight = fontSize * 1.4;
    final indent = (paragraph.indentLeft ?? 0) / 20.0;
    final availableWidth = contentWidth - indent;

    // 1. Calculate max lines
    // We remove some padding/margins from available height to be safe
    final maxLines = ((availableHeight - fontSize * 0.5) / lineHeight).floor();

    if (maxLines <= 0) {
      // Can't fit anything substantial
      return [_createParagraph(paragraph, []), paragraph];
    }

    final fittedChildren = <DocxInline>[];
    final remainingChildren = <DocxInline>[];

    var currentLine = 1;
    var currentLineWidth = 0.0;
    var splitOccurred = false;

    // Iterate children
    for (var i = 0; i < paragraph.children.length; i++) {
      final child = paragraph.children[i];

      if (splitOccurred) {
        remainingChildren.add(child);
        continue;
      }

      if (child is DocxText) {
        // Unlike [_wrapText] (which measures a concatenation of every run
        // and so can only apply the fallback font paragraph-wide, see
        // [_fallbackFontRefFor]), this loop already visits each run
        // separately - so it can match `PdfExporter._withUnicodeFallback`'s
        // actual per-run decision exactly.
        final runFontRef = fontManager.needsUnicodeFallback(child.content)
            ? fontManager.fallbackUnicodeFontRef
            : null;
        final spaceWidth =
            fontManager.measureText(' ', fontSize, fontRef: runFontRef);
        final text = child.content;
        final lines = text.split('\n');

        // We might need to split this text node
        final fittedTextBuffer = StringBuffer();
        final remainingTextBuffer = StringBuffer();
        var nodeSplit = false;

        for (var l = 0; l < lines.length; l++) {
          final line = lines[l];

          if (nodeSplit) {
            if (l > 0) remainingTextBuffer.write('\n');
            remainingTextBuffer.write(line);
            continue;
          }

          if (l > 0) {
            // Newline in source means new line in output
            currentLine++;
            currentLineWidth = 0;
            if (currentLine > maxLines) {
              // Split at this newline
              nodeSplit = true;
              if (l > 0) remainingTextBuffer.write('\n');
              remainingTextBuffer.write(line);
              continue;
            }
            fittedTextBuffer.write('\n');
          }

          if (line.isEmpty) continue; // Empty line (just newline handled above)

          final words = line.split(' ');
          for (var w = 0; w < words.length; w++) {
            final word = words[w];
            final wordWidth =
                fontManager.measureText(word, fontSize, fontRef: runFontRef);

            if (currentLineWidth + wordWidth > availableWidth &&
                currentLineWidth > 0) {
              currentLine++;
              currentLineWidth = wordWidth + spaceWidth;
            } else {
              currentLineWidth += wordWidth + spaceWidth;
            }

            if (currentLine > maxLines) {
              // Split here
              nodeSplit = true;
              // Add this word and rest of line to remainder
              for (var k = w; k < words.length; k++) {
                if (k > w) remainingTextBuffer.write(' ');
                remainingTextBuffer.write(words[k]);
              }
              break;
            } else {
              if (w > 0) fittedTextBuffer.write(' ');
              fittedTextBuffer.write(word);
            }
          }
        }

        if (fittedTextBuffer.isNotEmpty) {
          fittedChildren.add(_cloneText(child, fittedTextBuffer.toString()));
        }
        if (remainingTextBuffer.isNotEmpty) {
          remainingChildren
              .add(_cloneText(child, remainingTextBuffer.toString()));
          splitOccurred = true;
        } else if (nodeSplit) {
          splitOccurred = true;
        }
      } else if (child is DocxLineBreak) {
        currentLine++;
        currentLineWidth = 0;
        if (currentLine > maxLines) {
          splitOccurred = true;
          remainingChildren.add(child);
        } else {
          fittedChildren.add(child);
        }
      } else {
        // Tab or others
        if (child is DocxTab) {
          currentLineWidth += fontSize * 3; // Approx tab width
          if (currentLineWidth > availableWidth) {
            currentLine++;
            currentLineWidth = fontSize * 3;
          }
        }

        if (currentLine > maxLines) {
          splitOccurred = true;
          remainingChildren.add(child);
        } else {
          fittedChildren.add(child);
        }
      }
    }

    return [
      _createParagraph(paragraph, fittedChildren),
      remainingChildren.isEmpty
          ? _createParagraph(paragraph, [])
          : _createParagraph(paragraph, remainingChildren)
    ];
  }

  DocxParagraph _createParagraph(
      DocxParagraph original, List<DocxInline> newChildren) {
    return original.copyWith(children: newChildren);
  }

  DocxText _cloneText(DocxText original, String newContent) {
    return original.copyWith(content: newContent);
  }

  /// Counts lines needed for text in given width. [fontRef] - see
  /// [_fallbackFontRefFor] - measures every word through that font instead
  /// of the plain metrics when set.
  int _wrapText(String text, double availableWidth, double fontSize,
      {String? fontRef}) {
    // 1. Split by explicit newlines
    final paragraphs = text.split('\n');
    int totalLines = 0;

    for (final para in paragraphs) {
      if (para.isEmpty) {
        totalLines++;
        continue;
      }

      // 2. Measure words and wrap
      final words = para.split(' ');
      var currentLineWidth = 0.0;
      var lines = 1;
      final spaceWidth =
          fontManager.measureText(' ', fontSize, fontRef: fontRef);

      for (final word in words) {
        final wordWidth =
            fontManager.measureText(word, fontSize, fontRef: fontRef);

        // A word wider than the whole line will be split across multiple
        // lines by the renderer (see PdfExporter._splitOverlongWords) -
        // without this, pagination would reserve too little height and
        // body content could overlap the page boundary.
        if (wordWidth > availableWidth && availableWidth > 0) {
          if (currentLineWidth > 0) lines++;
          final wholeLines = (wordWidth / availableWidth).ceil();
          lines += wholeLines - 1;
          // The word's last chunk only fills the *remainder* of its final
          // line, not the whole width - carry that forward so the next
          // word is correctly judged against how much room is actually
          // left, not treated as if the line were nearly full.
          currentLineWidth =
              (wordWidth - (wholeLines - 1) * availableWidth) + spaceWidth;
          continue;
        }

        if (currentLineWidth + wordWidth > availableWidth &&
            currentLineWidth > 0) {
          lines++;
          currentLineWidth = wordWidth + spaceWidth;
        } else {
          currentLineWidth += wordWidth + spaceWidth;
        }
      }
      totalLines += lines;
    }

    return totalLines > 0 ? totalLines : 1;
  }

  /// Same greedy word-wrap estimate as [_wrapText], but the available width
  /// can differ per output line (`widthForLine(lineIndex)`) — used by
  /// [_measureDropCap] since the lines beside the drop cap letter are
  /// narrower than the ones below it.
  int _wrapTextVariableWidth(
      String text, double fontSize, double Function(int lineIndex) widthForLine,
      {String? fontRef}) {
    final paragraphs = text.split('\n');
    int totalLines = 0;

    for (final para in paragraphs) {
      if (para.isEmpty) {
        totalLines++;
        continue;
      }

      final words = para.split(' ');
      var currentLineWidth = 0.0;
      var lines = 1;
      final spaceWidth =
          fontManager.measureText(' ', fontSize, fontRef: fontRef);

      for (final word in words) {
        final wordWidth =
            fontManager.measureText(word, fontSize, fontRef: fontRef);
        final availableWidth = widthForLine(totalLines + lines - 1);

        if (wordWidth > availableWidth && availableWidth > 0) {
          if (currentLineWidth > 0) lines++;
          final wholeLines = (wordWidth / availableWidth).ceil();
          lines += wholeLines - 1;
          currentLineWidth =
              (wordWidth - (wholeLines - 1) * availableWidth) + spaceWidth;
          continue;
        }

        if (currentLineWidth + wordWidth > availableWidth &&
            currentLineWidth > 0) {
          lines++;
          currentLineWidth = wordWidth + spaceWidth;
        } else {
          currentLineWidth += wordWidth + spaceWidth;
        }
      }
      totalLines += lines;
    }

    return totalLines > 0 ? totalLines : 1;
  }
}

/// Result of [PdfLayoutEngine.paginateWithFootnotes]: the paginated body
/// content, plus which footnote IDs (in first-reference order) should be
/// rendered at the bottom of each corresponding page.
class PdfPaginationResult {
  final List<List<DocxNode>> pages;
  final List<List<int>> footnoteIdsPerPage;

  const PdfPaginationResult(this.pages, this.footnoteIdsPerPage);
}
