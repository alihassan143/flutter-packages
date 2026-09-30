import 'dart:io';

import 'package:htmltopdfwidgets/htmltopdfwidgets.dart';
import 'package:htmltopdfwidgets/src/browser/css_style.dart';
import 'package:htmltopdfwidgets/src/browser/html_parser.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:test/test.dart';

void main() {
  group('CSSStyle Tests', () {
    test('Parse simple CSS string', () {
      final style = CSSStyle.parse('color: red; font-size: 16px;');
      // CSS `red` is #FF0000.
      expect(style.color, const PdfColor(1, 0, 0));
      expect(style.fontSize, 12.0); // 16px * 0.75 = 12pt
    });

    test('Parse complex CSS string with shorthand', () {
      final style = CSSStyle.parse('margin: 10px 20px; padding: 5px;');
      expect(style.margin!.top, 7.5); // 10px * 0.75
      expect(style.margin!.left, 15.0); // 20px * 0.75
      expect(style.padding!.top, 3.75); // 5px * 0.75
      expect(style.padding!.left, 3.75); // 5px * 0.75
    });

    test('Merge styles', () {
      final style1 = const CSSStyle(color: PdfColors.red, fontSize: 12.0);
      final style2 = const CSSStyle(color: PdfColors.blue);
      final merged = style1.merge(style2);
      expect(merged.color, PdfColors.blue);
      expect(merged.fontSize, 12.0);
    });

    test('Inherit styles', () {
      final parent = const CSSStyle(
          color: PdfColors.red, fontSize: 12.0, margin: EdgeInsets.all(10));
      final child = const CSSStyle().inheritFrom(parent);

      // Inherited properties
      expect(child.color, PdfColors.red);
      expect(child.fontSize, 12.0);

      // Non-inherited properties should be null/reset
      expect(child.margin, null);
    });
  });

  group('HtmlParser Tests', () {
    test('Parse simple HTML structure', () {
      final parser = HtmlParser(htmlString: '<div><p>Hello</p></div>');
      final root = parser.parse();

      expect(root.tagName, 'body'); // Parser wraps in body if missing
      expect(root.children.length, 1);
      expect(root.children[0].tagName, 'div');
      expect(root.children[0].children[0].tagName, 'p');
      expect(root.children[0].children[0].children[0].text, 'Hello');
    });

    test('Compute styles correctly', () {
      final parser =
          HtmlParser(htmlString: '<div style="color: red;"><p>Text</p></div>');
      final root = parser.parse();
      final div = root.children[0];
      final p = div.children[0];

      expect(div.style.color, const PdfColor(1, 0, 0));
      expect(p.style.color, const PdfColor(1, 0, 0)); // Inherited
    });

    test('Parse attributes', () {
      final parser =
          HtmlParser(htmlString: '<a href="https://example.com">Link</a>');
      final root = parser.parse();
      final a = root.children[0];

      expect(a.attributes['href'], 'https://example.com');
    });
  });

  group('PdfBuilder Integration Tests', () {
    late pw.Document pdf;

    setUp(() {
      pdf = pw.Document();
    });

    test('Build PDF with basic elements', () async {
      const html = '''
        <h1>Heading</h1>
        <p>Paragraph with <b>bold</b> and <i>italic</i> text.</p>
      ''';
      final widgets = await HTMLToPdf().convert(html, useNewEngine: true);

      expect(widgets.isNotEmpty, true);
      pdf.addPage(pw.MultiPage(build: (c) => widgets));
    });

    test('Build PDF with lists', () async {
      const html = '''
        <ul>
          <li>Item 1</li>
          <li>Item 2</li>
        </ul>
        <ol>
          <li>Ordered 1</li>
          <li>Ordered 2</li>
        </ol>
      ''';
      final widgets = await HTMLToPdf().convert(html, useNewEngine: true);

      expect(widgets.isNotEmpty, true);
      pdf.addPage(pw.MultiPage(build: (c) => widgets));
    });

    test('Build PDF with table', () async {
      const html = '''
        <table style="border: 1px solid black;">
          <tr>
            <th>Header 1</th>
            <th>Header 2</th>
          </tr>
          <tr>
            <td>Cell 1</td>
            <td>Cell 2</td>
          </tr>
        </table>
      ''';
      final widgets = await HTMLToPdf().convert(html, useNewEngine: true);

      expect(widgets.isNotEmpty, true);
      pdf.addPage(pw.MultiPage(build: (c) => widgets));
    });

    test('Build PDF with image and link', () async {
      const html = '''
        <img src="https://example.com/image.png" style="width: 100px; height: 100px;" />
        <a href="https://example.com">Click me</a>
      ''';
      final widgets = await HTMLToPdf().convert(html, useNewEngine: true);

      expect(widgets.isNotEmpty, true);
      pdf.addPage(pw.MultiPage(build: (c) => widgets));
    });

    tearDownAll(() async {
      final file = File('new_architecture_test_output.pdf');
      await file.writeAsBytes(await pdf.save());
      print('Test PDF saved to ${file.path}');
    });
  });

  group('Bug Fix Tests', () {
    late pw.Document pdf;

    setUp(() {
      pdf = pw.Document();
    });

    test('Text color and background color work together', () async {
      const html = '''
        <p style="color: white; background-color: blue;">White text on blue background</p>
        <p style="color: #FF0000; background-color: #FFFF00;">Red text on yellow background</p>
        <span style="color: green; background-color: pink;">Green text on pink background</span>
        <p>Normal text followed by <span style="color: white; background-color: black;">inverted colors</span> inline</p>
        <mark style="color: blue;">Blue text on mark yellow background</mark>
      ''';
      final widgets = await HTMLToPdf().convert(html, useNewEngine: true);

      expect(widgets.isNotEmpty, true);
      pdf.addPage(pw.MultiPage(build: (c) => widgets));
    });

    test('Long paragraph spans pages without error', () async {
      // Generate a very long paragraph that will exceed single page height
      final longText =
          'This is a very long paragraph that contains extensive content. ' *
              100;
      final html = '''
        <h1>Long Paragraph Test</h1>
        <p>$longText</p>
        <p>This paragraph comes after the long one and should appear on the next page.</p>
      ''';
      final widgets = await HTMLToPdf().convert(html, useNewEngine: true);

      expect(widgets.isNotEmpty, true);
      // This should not throw "Widget cannot exceeded page height" error
      pdf.addPage(pw.MultiPage(build: (c) => widgets));
    });

    test('Multiple long paragraphs with different lengths', () async {
      // Various paragraph lengths to stress test
      final paragraph1 = 'Short paragraph. ' * 10;
      final paragraph2 = 'Medium length paragraph with more content. ' * 50;
      final paragraph3 =
          'Very long paragraph that should definitely exceed page height and needs to wrap across multiple pages. ' *
              150;
      final paragraph4 =
          'Another extremely long paragraph for stress testing the page spanning functionality. ' *
              120;

      final html = '''
        <h1>Multiple Long Paragraphs Test</h1>
        <p>$paragraph1</p>
        <h2>Medium Paragraph Section</h2>
        <p>$paragraph2</p>
        <h2>Very Long Paragraph Section</h2>
        <p>$paragraph3</p>
        <h2>Another Long Paragraph</h2>
        <p>$paragraph4</p>
        <p>Final short paragraph to verify everything rendered correctly.</p>
      ''';
      final widgets = await HTMLToPdf().convert(html, useNewEngine: true);

      expect(widgets.isNotEmpty, true);
      // This should not throw any errors about widget height
      pdf.addPage(pw.MultiPage(build: (c) => widgets));
    });

    test('Long paragraph with color and background styling', () async {
      final styledLongText = 'Styled text that should span pages. ' * 80;
      final html = '''
        <h1>Styled Long Paragraph</h1>
        <p style="color: blue; background-color: #FFFFCC;">$styledLongText</p>
      ''';
      final widgets = await HTMLToPdf().convert(html, useNewEngine: true);

      expect(widgets.isNotEmpty, true);
      pdf.addPage(pw.MultiPage(build: (c) => widgets));
    });

    test('Long markdown content spanning pages', () async {
      final longMarkdown = '''
# Long Markdown Document

${'This is a paragraph with lots of content that will span multiple pages. ' * 200}

## Section 2

${'More content here to test markdown conversion with very long text. ' * 150}

### Subsection

${'Even more content to ensure everything works correctly with page spanning. ' * 500}
      ''';
      final widgets =
          await HTMLToPdf().convertMarkdown(longMarkdown, useNewEngine: true);

      expect(widgets.isNotEmpty, true);
      pdf.addPage(pw.MultiPage(build: (c) => widgets));
    });

    tearDownAll(() async {
      final file = File('bug_fix_test_output.pdf');
      await file.writeAsBytes(await pdf.save());
      print('Bug fix test PDF saved to ${file.path}');
    });
  });

  group('Stress Tests', () {
    late pw.Document pdf;

    setUp(() {
      pdf = pw.Document();
    });

    test('Complex styled content with page breaks', () async {
      const html = '''
<div style="font-family: Arial, sans-serif; line-height: 1.6;">
    <div style="background-color: #2c3e50; color: #ffffff; padding: 40px; text-align: center; border-bottom: 5px solid #e74c3c;">
        <h1 style="font-size: 36px; margin: 0;">Stress Test: Long Styled Content</h1>
        <p style="font-size: 18px; color: #ecf0f1;">Testing pagination and style persistence across page breaks</p>
    </div>

    <div style="padding: 20px;">
        <h2 style="color: #2980b9; border-left: 10px solid #2980b9; padding-left: 15px;">1. The Multi-Page Paragraph Test</h2>
        
        <p style="background-color: #fdf2e9; color: #7e5109; padding: 15px; border: 1px solid #e67e22; font-size: 14px;">
            <b style="color: #d35400; font-size: 18px;">START OF LONG BLOCK:</b> 
            This paragraph is intentionally long to force the PDF engine to break it across at least two or three pages. 
            Lorem ipsum dolor sit amet, consectetur adipiscing elit. <span style="color: #c0392b; font-weight: bold;">[Style Change Mid-Sentence]</span> 
            Donec vel egestas leo, eu fringilla diam. Mauris ac elit eu sem elementum pharetra. Nam interdum, arcu et hendrerit 
            aliquet, ante quam egestas magna, vitae sodales eros lectus porta libero. 
            <br/><br/>
            Continuing the same paragraph block: Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. 
            Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. 
            <span style="background-color: #27ae60; color: white; padding: 2px;">This highlight should ideally persist or break cleanly.</span> 
            Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. 
            Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.
            <br/><br/>
            (Repeating to ensure length) Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor 
            incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco 
            laboris nisi ut aliquip ex ea commodo consequat. <i style="font-size: 20px;">Notice the font size increase here.</i> 
            Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. 
            Curabitur pretium tincidunt lacus. Nulla gravida orci a odio. Nullam varius, turpis et commodo pharetra, 
            est eros bibendum elit, nec luctus magna felis sollicitudin mauris. Integer in mauris eu nibh euismod gravida. 
            Duis ac tellus et risus vulputate vehicula. Donec lobortis risus a elit. Etiam tempor. Ut ullamcorper, 
            ligula eu tempor congue, eros est euismod turpis, id tincidunt sapien risus a quam. Maecenas fermentum 
            consequat mi. Donec fermentum. Pellentesque malesuada nulla a mi. Duis sapien sem, aliquet nec, commodo eget, 
            consequat quis, neque. Aliquam faucibus, elit ut dictum aliquet, felis nisl adipiscing sapien, sed malesuada 
            diam lacus eget erat. Cras mollis scelerisque nunc. Donec vehicula cursus purus. Mauris nulla magna, faucibus 
            interdum, condimentum vel, auctor vitae, magna.
            <br/><br/>
            (Page Break should happen somewhere here)
            <br/><br/>
            <span style="text-decoration: underline; color: #8e44ad;">Continuing the same HTML tag across a potential page break:</span> 
            Aenean placerat. In vulputate urna eu arcu. Aliquam erat volutpat. Suspendisse potenti. Sed vel lacus. 
            Mauris nibh felis, adipiscing varius, adipiscing in, lacinia vel, tellus. Suspendisse ac urna. 
            Etiam pellentesque mauris ut lectus. Nunc tellus ante, mattis eget, gravida vitae, ultricies ac, leo. 
            Integer leo pede, ornare a, lacinia eu, vulputate vel, nisl. Suspendisse mauris. Fusce accumsan mollis eros. 
            Pellentesque a diam sit amet mi ullamcorper vehicula. Integer adipiscing risus a sem. Nullam quis massa sit 
            amet nibh viverra malesuada. Nunc sem lacus, accumsan quis, faucibus non, congue vel, arcu. 
            Ut scelerisque hendrerit tellus. Integer sagittis. Vivamus a mauris eget arcu gravida tristique. 
            Nunc iaculis mi in ante.
        </p>
    </div>

    <div style="background-color: #ecf0f1; padding: 20px;">
        <h2 style="color: #2c3e50;">2. Mixed Styled Items</h2>
        <ul style="list-style-type: square; color: #2980b9;">
            <li style="margin-bottom: 10px;"><b>Item One:</b> With a custom margin bottom.</li>
            <li style="margin-bottom: 10px; color: #e74c3c;"><b>Item Two:</b> Red colored text to check inheritance.</li>
            <li style="margin-bottom: 10px; background-color: #f1c40f; padding: 5px;"><b>Item Three:</b> Highlighted background item.</li>
            <li style="margin-bottom: 10px;"><b>Item Four:</b> 
                <blockquote style="border-left: 5px solid #bdc3c7; padding-left: 10px; font-style: italic;">
                    "A nested blockquote inside a list item to test complex layout nesting."
                </blockquote>
            </li>
        </ul>
    </div>

    <div style="margin-top: 30px; border: 2px dashed #3498db; padding: 15px;">
        <h3 style="text-align: right; color: #34495e;">3. Final Complex Paragraph</h3>
        <p style="text-align: justify; font-size: 12px; color: #34495e;">
            This final section uses <b>text-align: justify</b> and a smaller font size. If the fix for 
            the "exceeded pdf page height" error is working, this container should start on the current 
            page and overflow gracefully to the next without cutting off the dashed border or losing the padding context.
            <br/><br/>
            Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vestibulum eget felis et metus iaculis 
            porttitor. Sed vel convallis mauris. Quisque sed dictum nisi. Nam hendrerit, sem ut 
            pellentesque pretium, magna felis imperdiet purus, id scelerisque magna neque vitae nibh. 
            Pellentesque sed nisl vitae lectus dictum elementum.
        </p>
    </div>
</div>
      ''';
      final widgets = await HTMLToPdf().convert(html, useNewEngine: true);

      expect(widgets.isNotEmpty, true);
      pdf.addPage(pw.MultiPage(build: (c) => widgets));
    });

    tearDownAll(() async {
      final file = File('stress_test_output.pdf');
      await file.writeAsBytes(await pdf.save());
      print('Stress test PDF saved to ${file.path}');
    });
  });

  group('Extreme Stress Tests', () {
    late pw.Document pdf;

    setUp(() {
      pdf = pw.Document();
    });

    test('Extreme pagination with 2x content volume', () async {
      const html = '''
<div style="font-family: 'Helvetica', sans-serif; line-height: 1.8; color: #333;">
    
    <div style="background: linear-gradient(to right, #4b6cb7, #182848); color: white; padding: 50px; text-align: center;">
        <h1 style="font-size: 42px; text-transform: uppercase; letter-spacing: 2px;">Extreme Pagination Stress Test</h1>
        <p style="font-size: 20px; opacity: 0.9;">Testing page height overflow with 2x content volume</p>
    </div>

    <div style="padding: 30px; border: 2px solid #333; margin: 20px;">
        <h2 style="color: #e67e22; text-decoration: underline;">1. The Massive Styled Block (Page Break Target)</h2>
        
        <p style="font-size: 16px; text-align: justify; background-color: #f9f9f9; padding: 25px; border-left: 15px solid #e67e22;">
            <span style="font-size: 24px; font-weight: bold; color: #2c3e50;">PART A:</span>
            This paragraph is designed to be massive. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vivamus lacinia odio vitae vestibulum vestibulum. Cras venenatis euismod malesuada. 
            <span style="color: #2980b9; font-style: italic;">[Checking if blue italics persist across pages]</span> 
            Nullam ac nisi lorem. Maecenas scelerisque, justo et interdum porta, est turpis varius lorem, sed sodales nisl tellus eu diam. 
            Donec vel egestas leo, eu fringilla diam. Mauris ac elit eu sem elementum pharetra. Nam interdum, arcu et hendrerit aliquet, 
            ante quam egestas magna, vitae sodales eros lectus porta libero.
            <br/><br/>
            Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation 
            ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit 
            esse cillum dolore eu fugiat nulla pariatur. <b style="font-size: 22px; background-color: #f1c40f;">This bold highlighted 
            section is a primary suspect for layout errors if it spans a page break.</b> 
            Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum. 
            Curabitur pretium tincidunt lacus. Nulla gravida orci a odio. Nullam varius, turpis et commodo pharetra.
            <br/><br/>
            <span style="font-size: 24px; font-weight: bold; color: #2c3e50;">PART B (Doubled Content):</span>
            Repeating the block to ensure extreme height: Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vivamus lacinia 
            odio vitae vestibulum vestibulum. Cras venenatis euismod malesuada. Nullam ac nisi lorem. Maecenas scelerisque, justo 
            et interdum porta, est turpis varius lorem, sed sodales nisl tellus eu diam. Donec vel egestas leo, eu fringilla diam. 
            Mauris ac elit eu sem elementum pharetra. Nam interdum, arcu et hendrerit aliquet, ante quam egestas magna, vitae 
            sodales eros lectus porta libero.
            <br/><br/>
            Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation 
            ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit 
            esse cillum dolore eu fugiat nulla pariatur. <span style="border: 1px dashed red; padding: 5px;">Dashed border span 
            test across break.</span> Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit 
            anim id est laborum. Curabitur pretium tincidunt lacus. Nulla gravida orci a odio. Nullam varius, turpis et commodo 
            pharetra, est eros bibendum elit, nec luctus magna felis sollicitudin mauris.
            <br/><br/>
            <span style="font-size: 24px; font-weight: bold; color: #2c3e50;">PART C (Final Stretch):</span>
            Integer in mauris eu nibh euismod gravida. Duis ac tellus et risus vulputate vehicula. Donec lobortis risus a elit. 
            Etiam tempor. Ut ullamcorper, ligula eu tempor congue, eros est euismod turpis, id tincidunt sapien risus a quam. 
            Maecenas fermentum consequat mi. Donec fermentum. Pellentesque malesuada nulla a mi. Duis sapien sem, aliquet nec, 
            commodo eget, consequat quis, neque. Aliquam faucibus, elit ut dictum aliquet, felis nisl adipiscing sapien, sed 
            malesuada diam lacus eget erat. Cras mollis scelerisque nunc. Donec vehicula cursus purus. Mauris nulla magna, 
            faucibus interdum, condimentum vel, auctor vitae, magna.
        </p>
    </div>

    <div style="background-color: #2c3e50; color: #ecf0f1; padding: 40px;">
        <h2 style="color: #1abc9c;">2. High-Volume List Items</h2>
        <ul style="line-height: 2.5;">
            <li style="font-size: 18px; border-bottom: 1px solid #34495e; padding: 10px;">
                <b>The "Wall of Text" Item:</b> This single list item contains enough text to be a paragraph itself. 
                Aenean placerat. In vulputate urna eu arcu. Aliquam erat volutpat. Suspendisse potenti. Sed vel lacus. 
                Mauris nibh felis, adipiscing varius, adipiscing in, lacinia vel, tellus. Suspendisse ac urna. 
                Etiam pellentesque mauris ut lectus. Nunc tellus ante, mattis eget, gravida vitae, ultricies ac, leo.
            </li>
            <li style="font-size: 18px; border-bottom: 1px solid #34495e; padding: 10px; color: #f1c40f;">
                <b>Nested Logic Test:</b>
                <div style="margin-top: 10px; background: white; color: black; padding: 15px; border-radius: 10px;">
                    This is a <code style="background: #eee; padding: 2px;">div</code> inside an <code style="background: #eee; padding: 2px;">li</code>. 
                    It contains even more text to push the layout further. Lorem ipsum dolor sit amet, consectetur 
                    adipiscing elit. Mauris ac elit eu sem elementum pharetra. Nam interdum, arcu et hendrerit aliquet, 
                    ante quam egestas magna, vitae sodales eros lectus porta libero.
                </div>
            </li>
            <li style="font-size: 18px; padding: 10px;">
                <b>The Final Push:</b> Ending the list with a very long sentence that tests character wrapping 
                and overflow handling in the PDF generation engine.
            </li>
        </ul>
    </div>

    <div style="padding: 40px; border: 5px double #3498db; margin-top: 20px;">
        <h2 style="color: #3498db;">3. The Climax of Content</h2>
        <p style="font-size: 14px; line-height: 2;">
            <span style="font-size: 26px;">
                <span style="color: #8e44ad;">
                    <span style="border-bottom: 3px dotted #8e44ad;">
                        This sentence is wrapped in three levels of spans.
                    </span>
                </span>
            </span>
            If the engine correctly calculates the height of this deeply nested structure while it is sitting at the 
            very bottom of a page, it should move the entire block to the next page or split it without throwing 
            an "Exceeded PDF page height" error. 
            <br/><br/>
            (Extra filler to ensure length) Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod 
            tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation 
            ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in 
            voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non 
            proident, sunt in culpa qui officia deserunt mollit anim id est laborum.
            <br/><br/>
            (Final doubling) Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor 
            incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation 
            ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in 
            voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non 
            proident, sunt in culpa qui officia deserunt mollit anim id est laborum.
        </p>
    </div>
</div>
      ''';
      final widgets = await HTMLToPdf().convert(html, useNewEngine: true);

      expect(widgets.isNotEmpty, true);
      pdf.addPage(pw.MultiPage(maxPages: 100, build: (c) => widgets));
    });

    tearDownAll(() async {
      final file = File('extreme_stress_test_output.pdf');
      await file.writeAsBytes(await pdf.save());
      print('Extreme stress test PDF saved to ${file.path}');
    });
  });
}
