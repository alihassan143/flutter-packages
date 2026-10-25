/// docx_creator - A developer-first DOCX generation library
///
/// Create professional Word documents with a fluent API:
/// ```dart
/// import 'package:docx_creator/docx_creator.dart';
///
/// final doc = docx()
///   .h1('Title')
///   .p('Content')
///   .build();
///
/// await DocxExporter().exportToFile(doc, 'output.docx');
/// ```
library;

export 'src/ast/docx_background_image.dart';
export 'src/ast/docx_block.dart';
export 'src/ast/docx_drawing.dart';
export 'src/ast/docx_drop_cap.dart';
export 'src/ast/docx_footnote.dart';
export 'src/ast/docx_image.dart';
export 'src/ast/docx_inline.dart';
export 'src/ast/docx_list.dart';
export 'src/ast/docx_math.dart';
// AST
export 'src/ast/docx_node.dart';
export 'src/ast/docx_section.dart';
export 'src/ast/docx_section_break.dart';
export 'src/ast/docx_table.dart';
// Builder
export 'src/builder/docx_document_builder.dart';
export 'src/core/defaults.dart';
// Core
export 'src/core/enums.dart';
export 'src/core/exceptions.dart';
export 'src/core/measurements.dart';
export 'src/core/xml_extension.dart';
// Exporters
export 'src/exporters/docx_exporter.dart';
export 'src/exporters/html_exporter.dart';
export 'src/exporters/markdown_exporter.dart';
export 'src/exporters/pdf/pdf_exporter.dart';
// Parsers
export 'src/parsers/html_parser.dart';
export 'src/parsers/markdown_parser.dart';
export 'src/reader/docx_reader/docx_reader.dart';
export 'src/reader/docx_reader/handlers/font_reader.dart';
export 'src/reader/docx_reader/handlers/relationship_manager.dart';
export 'src/reader/docx_reader/models/docx_font.dart';
export 'src/reader/docx_reader/models/docx_relationship.dart';
export 'src/reader/docx_reader/models/docx_style.dart';
// Reader Models
export 'src/reader/docx_reader/models/docx_theme.dart';
export 'src/reader/docx_reader/models/resolved_style.dart';
export 'src/reader/docx_reader/parsers/block_parser.dart';
export 'src/reader/docx_reader/parsers/inline_parser.dart';
export 'src/reader/docx_reader/parsers/numbering_parser.dart';
export 'src/reader/docx_reader/parsers/section_parser.dart';
export 'src/reader/docx_reader/parsers/style_parser.dart';
export 'src/reader/docx_reader/parsers/table_parser.dart';
export 'src/reader/docx_reader/reader_context/reader_context.dart';
export 'src/reader/pdf_reader/pdf_reader.dart';
// Utilities
export 'src/utils/content_types_generator.dart';
export 'src/utils/docx_id_generator.dart';
export 'src/utils/docx_validator.dart';
export 'src/utils/xml_utils.dart' hide DocxIdGenerator;
