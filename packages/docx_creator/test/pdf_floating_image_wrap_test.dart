import 'dart:convert';
import 'dart:typed_data';

import 'package:docx_creator/docx_creator.dart';
import 'package:test/test.dart';

/// Regression test for PDF export honoring `DocxInlineImage.positionMode:
/// floating` + `textWrap: square/tight`.
///
/// Before this fix, every DocxInlineImage - floating or not - flowed as a
/// plain inline "word" in the surrounding text, so text never wrapped
/// around a floated image on PDF export even though the Flutter viewer
/// (docx_file_viewer's ParagraphBuilder) already does this via its
/// currentLeftFloats/currentRightFloats handling.
void main() {
  test('text wraps beside a left-floated image, then returns to full width',
      () {
    final longText = List.generate(80, (i) => 'word$i').join(' ');
    final doc = DocxBuiltDocument(elements: [
      DocxParagraph(children: [
        DocxInlineImage(
          bytes: Uint8List(0),
          extension: 'png',
          width: 150,
          height: 100,
          positionMode: DocxDrawingPosition.floating,
          textWrap: DocxTextWrap.square,
          hAlign: DrawingHAlign.left,
        ),
        DocxText(longText),
      ]),
    ]);

    final bytes = PdfExporter(compressContent: false).exportToBytes(doc);
    final content = latin1.decode(bytes, allowInvalid: true);

    final imageMatch =
        RegExp(r'([\d.]+) 0 0 ([\d.]+) ([\d.]+) ([\d.]+) cm\s*/Im1 Do')
            .firstMatch(content);
    expect(imageMatch, isNotNull,
        reason: 'expected to find the floated image draw operator');
    final imageW = double.parse(imageMatch!.group(1)!);
    final imageX = double.parse(imageMatch.group(3)!);
    final imageRight = imageX + imageW;

    // The content stream emits one Tm (text matrix) per word, not per
    // line - each word is absolutely positioned (needed for justify
    // stretch), so a line's words share one y but climb in x as they're
    // drawn. Group by y (rounded, to dodge float noise) and take each
    // line's smallest x as that line's start, in first-seen (= drawing =
    // document) order.
    final tms = RegExp(r'1 0 0 1 ([\d.]+) ([\d.]+) Tm')
        .allMatches(content)
        .map((m) => (x: double.parse(m.group(1)!), y: double.parse(m.group(2)!)))
        .toList();
    final lineStartXByY = <double, double>{};
    final yOrder = <double>[];
    for (final tm in tms) {
      final y = (tm.y * 100).round() / 100;
      final current = lineStartXByY[y];
      if (current == null) {
        yOrder.add(y);
        lineStartXByY[y] = tm.x;
      } else if (tm.x < current) {
        lineStartXByY[y] = tm.x;
      }
    }
    final lineXs = yOrder.map((y) => lineStartXByY[y]!).toList();
    expect(lineXs, isNotEmpty, reason: 'expected at least one text line');

    // The lines beside the image must start to its right...
    expect(lineXs.first, greaterThanOrEqualTo(imageRight),
        reason: 'first wrapped line must start clear of the floated image');
    // ...and once the text runs past the image's height, later lines must
    // return to the paragraph's normal (unindented) left edge - i.e.
    // strictly left of where the wrapped lines started.
    expect(lineXs.last, lessThanOrEqualTo(imageX),
        reason: 'text must return to full width below the floated image');
  });

  test('a center-aligned float is left unwrapped (documented limit)', () {
    final doc = DocxBuiltDocument(elements: [
      DocxParagraph(children: [
        DocxInlineImage(
          bytes: Uint8List(0),
          extension: 'png',
          width: 150,
          height: 100,
          positionMode: DocxDrawingPosition.floating,
          textWrap: DocxTextWrap.square,
          hAlign: DrawingHAlign.center,
        ),
        DocxText('short text'),
      ]),
    ]);

    // Must not throw - center floats fall back to the pre-existing inline
    // placement rather than being wrapped.
    expect(() => PdfExporter().exportToBytes(doc), returnsNormally);
  });
}
