// Basic OMML (`m:oMath`) equation support: parse into DocxMath, round-trip
// back to XML, and render in PDF export without throwing.
import 'package:docx_creator/docx_creator.dart';
import 'package:docx_creator/src/reader/docx_reader/parsers/omml_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

const _mathNs = 'xmlns:m="http://schemas.openxmlformats.org/officeDocument/'
    '2006/math"';

XmlElement _oMath(String inner) =>
    XmlDocument.parse('<m:oMath $_mathNs>$inner</m:oMath>').rootElement;

void main() {
  group('OmmlParser', () {
    test('parses a fraction', () {
      final math = OmmlParser.parse(_oMath(
          '<m:f><m:num><m:r><m:t>1</m:t></m:r></m:num>'
          '<m:den><m:r><m:t>2</m:t></m:r></m:den></m:f>'))!;

      expect(math.children, hasLength(1));
      final frac = math.children.single as DocxMathFraction;
      expect(flattenNodes(frac.numerator), '1');
      expect(flattenNodes(frac.denominator), '2');
    });

    test('parses a superscript', () {
      final math = OmmlParser.parse(_oMath(
          '<m:sSup><m:e><m:r><m:t>x</m:t></m:r></m:e>'
          '<m:sup><m:r><m:t>2</m:t></m:r></m:sup></m:sSup>'))!;

      final sup = math.children.single as DocxMathSuperscript;
      expect(flattenNodes(sup.base), 'x');
      expect(flattenNodes(sup.superscript), '2');
    });

    test('flattens an unrecognized construct (matrix) to text instead of '
        'dropping it', () {
      final math = OmmlParser.parse(_oMath(
          '<m:m><m:mr><m:e><m:r><m:t>a</m:t></m:r></m:e></m:mr></m:m>'))!;

      expect(math.children, hasLength(1));
      expect((math.children.single as DocxMathText).text, 'a');
    });
  });

  test('DocxMath round-trips through buildXml and OmmlParser', () {
    const original = DocxMath([
      DocxMathFraction([DocxMathText('1')], [DocxMathText('2')]),
    ]);

    final builder = XmlBuilder();
    original.buildXml(builder);
    final xml = builder.buildDocument().toXmlString();

    final reparsed = OmmlParser.parse(XmlDocument.parse(xml).rootElement)!;
    final frac = reparsed.children.single as DocxMathFraction;
    expect(flattenNodes(frac.numerator), '1');
    expect(flattenNodes(frac.denominator), '2');
  });

  test('PDF export renders a paragraph containing an equation without '
      'throwing', () {
    final doc = docx()
        .add(DocxParagraph(children: [
          DocxText('Equation: '),
          const DocxMath([
            DocxMathFraction([DocxMathText('1')], [DocxMathText('2')]),
          ]),
          DocxText(' done.'),
        ]))
        .build();

    final bytes = PdfExporter(compressContent: false).exportToBytes(doc);
    final content = String.fromCharCodes(bytes);

    expect(bytes, isNotEmpty);
    expect(content, contains('(Equation:'));
    expect(content, contains('(done.)'));
  });
}
