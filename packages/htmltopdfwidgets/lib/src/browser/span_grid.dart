import 'dart:math' as math;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// A cell of a [SpanGrid], at [row]/[col] relative to the grid.
class SpanGridCell {
  final pw.Widget child;
  final int row;
  final int col;
  final int colSpan;
  final int rowSpan;

  SpanGridCell(this.child, this.row, this.col, this.colSpan, this.rowSpan);

  /// Position and size within the grid, set by [SpanGrid.layout]; [top]
  /// is measured down from the grid's top edge.
  double x = 0, top = 0, width = 0, height = 0;
}

/// A group of table rows laid out as one grid, so cells can span rows and
/// columns (`pw.Table` supports neither). Row heights follow the browser:
/// each row fits its single-row cells, and a spanning cell taller than its
/// rows spreads the extra height over them in proportion to their heights.
/// Every cell is then stretched to its full (spanned) height so that its
/// background, border and vertical alignment cover the whole area.
class SpanGrid extends pw.MultiChildWidget {
  SpanGrid({
    required this.columnFlex,
    required this.rowCount,
    required this.cells,
    required this.rowColors,
    this.border,
  }) : super(children: [for (final cell in cells) cell.child]);

  /// Relative width of every grid column.
  final List<double> columnFlex;
  final int rowCount;
  final List<SpanGridCell> cells;
  final List<PdfColor?> rowColors;
  final pw.BorderSide? border;

  final _rowTops = <double>[];

  @override
  void layout(pw.Context context, pw.BoxConstraints constraints,
      {bool parentUsesSize = false}) {
    final width = constraints.hasBoundedWidth ? constraints.maxWidth : 480.0;
    final totalFlex = columnFlex.fold<double>(0, (a, b) => a + b);
    final colX = <double>[0];
    for (final f in columnFlex) {
      colX.add(colX.last + (totalFlex > 0 ? f / totalFlex * width : 0));
    }

    final natural = <SpanGridCell, double>{};
    for (final cell in cells) {
      cell.x = colX[cell.col];
      cell.width = colX[cell.col + cell.colSpan] - cell.x;
      cell.child.layout(context,
          pw.BoxConstraints(minWidth: cell.width, maxWidth: cell.width),
          parentUsesSize: true);
      natural[cell] = cell.child.box!.height;
    }

    final heights = List<double>.filled(rowCount, 0);
    for (final cell in cells) {
      if (cell.rowSpan == 1) {
        heights[cell.row] = math.max(heights[cell.row], natural[cell]!);
      }
    }
    for (final cell in cells) {
      if (cell.rowSpan == 1) continue;
      final end = cell.row + cell.rowSpan;
      var have = 0.0;
      for (var r = cell.row; r < end; r++) {
        have += heights[r];
      }
      final extra = natural[cell]! - have;
      if (extra <= 0) continue;
      for (var r = cell.row; r < end; r++) {
        heights[r] +=
            have > 0 ? extra * heights[r] / have : extra / cell.rowSpan;
      }
    }

    _rowTops
      ..clear()
      ..add(0);
    for (final h in heights) {
      _rowTops.add(_rowTops.last + h);
    }
    for (final cell in cells) {
      cell.top = _rowTops[cell.row];
      cell.height = _rowTops[cell.row + cell.rowSpan] - cell.top;
      cell.child.layout(context,
          pw.BoxConstraints.tightFor(width: cell.width, height: cell.height),
          parentUsesSize: true);
    }
    box = PdfRect(0, 0, width, _rowTops.last);
  }

  @override
  void paint(pw.Context context) {
    super.paint(context);
    final b = box!;
    final canvas = context.canvas;
    // Top edge of the grid in page coordinates (y grows upwards).
    final top = b.bottom + b.height;

    for (var r = 0; r < rowCount; r++) {
      final color = rowColors[r];
      if (color == null) continue;
      canvas
        ..setFillColor(color)
        ..drawRect(b.left, top - _rowTops[r + 1], b.width,
            _rowTops[r + 1] - _rowTops[r])
        ..fillPath();
    }
    for (final cell in cells) {
      cell.child.box = PdfRect(b.left + cell.x, top - cell.top - cell.height,
          cell.width, cell.height);
      cell.child.paint(context);
    }
    final side = border;
    if (side != null && side.width > 0) {
      canvas
        ..saveContext()
        ..setStrokeColor(side.color)
        ..setLineWidth(side.width);
      side.style.setStyle(context); // dashed / dotted
      for (final cell in cells) {
        canvas.drawRect(b.left + cell.x, top - cell.top - cell.height,
            cell.width, cell.height);
      }
      canvas.strokePath();
      side.style.unsetStyle(context);
      canvas.restoreContext();
    }
  }
}
