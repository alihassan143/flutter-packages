import 'package:archive/archive.dart';
import 'package:docx_creator/docx_creator.dart';
import 'package:docx_creator/src/exporters/pdf/pdf_layout_engine.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

void main() {
  group('Multi-column sections (w:cols)', () {
    test('DocxSectionDef round-trips w:cols through DOCX XML', () {
      const section = DocxSectionDef(
        columnCount: 3,
        columnSpacing: 360,
        columnSeparator: true,
      );

      final builder = XmlBuilder();
      section.buildXml(builder);
      final xml = builder.buildDocument().toXmlString();

      expect(xml, contains('<w:cols'));
      expect(xml, contains('w:num="3"'));
      expect(xml, contains('w:space="360"'));
      expect(xml, contains('w:sep="1"'));
    });

    test('single-column section omits w:cols entirely', () {
      const section = DocxSectionDef();
      final builder = XmlBuilder();
      section.buildXml(builder);
      final xml = builder.buildDocument().toXmlString();

      expect(xml, isNot(contains('w:cols')));
    });

    test('SectionParser reads w:cols back into columnCount/Spacing/Separator',
        () {
      final xml = XmlDocument.parse('''
        <w:body xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:p><w:r><w:t>Body</w:t></w:r></w:p>
          <w:sectPr>
            <w:cols w:num="2" w:space="500" w:sep="1"/>
          </w:sectPr>
        </w:body>
      ''');

      final context = ReaderContext(Archive());
      final section = SectionParser(context).parse(xml.rootElement);

      expect(section.columnCount, 2);
      expect(section.columnSpacing, 500);
      expect(section.columnSeparator, true);
    });

    test('SectionParser defaults to single column when w:cols is absent', () {
      final xml = XmlDocument.parse('''
        <w:body xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:p><w:r><w:t>Body</w:t></w:r></w:p>
          <w:sectPr/>
        </w:body>
      ''');

      final context = ReaderContext(Archive());
      final section = SectionParser(context).parse(xml.rootElement);

      expect(section.columnCount, 1);
      expect(section.columnSeparator, false);
    });

    test('DocxDocumentBuilder.section() exposes columnCount/Spacing/Separator',
        () {
      final doc = DocxDocumentBuilder()
          .section(columnCount: 3, columnSpacing: 400, columnSeparator: true)
          .p('Hello')
          .build();

      expect(doc.section?.columnCount, 3);
      expect(doc.section?.columnSpacing, 400);
      expect(doc.section?.columnSeparator, true);
    });

    test('columnContentWidth splits content width minus gutters evenly', () {
      const section = DocxSectionDef(columnCount: 2, columnSpacing: 200);
      // 2 columns, 1 gutter of 200 twips, out of 10000 twips full width.
      expect(section.columnContentWidth(10000), 4900);
    });

    test('PdfLayoutEngine.paginateColumns narrows per-column width', () {
      final layout = PdfLayoutEngine(pageWidth: 612, pageHeight: 792);
      final fullWidth = layout.contentWidth;
      final columnWidth = layout.columnContentWidth(2, 20);

      expect(columnWidth, lessThan(fullWidth));
      expect(columnWidth, closeTo((fullWidth - 20) / 2, 0.001));
    });

    test(
        'PdfLayoutEngine.paginateColumns packs 2 virtual pages per physical page',
        () {
      final layout = PdfLayoutEngine(pageWidth: 612, pageHeight: 792);
      final nodes = List.generate(
        6,
        (i) => DocxParagraph(children: [DocxText('Paragraph $i')]),
      );

      final physicalPages =
          layout.paginateColumns(nodes, columnCount: 2, columnSpacing: 20);

      // All 6 short paragraphs fit in column 1 of page 1 alone when measured
      // at single-column width; packed 2-per-physical-page, that's still 1
      // physical page with up to 2 columns of content.
      expect(physicalPages, isNotEmpty);
      expect(physicalPages.first.length, lessThanOrEqualTo(2));
    });
  });
}
