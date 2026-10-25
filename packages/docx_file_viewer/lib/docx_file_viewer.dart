/// docx_viewer - Native Flutter DOCX Viewer
///
/// Render Word documents with native Flutter widgets:
/// ```dart
/// import 'package:docx_file_viewer/docx_viewer.dart';
///
/// DocxView(
///   file: myDocxFile,
///   config: DocxViewConfig(enableSearch: true),
/// )
/// ```
library;

export 'src/docx_view.dart';
export 'src/docx_view_config.dart';
export 'src/search/docx_search_controller.dart';
export 'src/theme/docx_view_theme.dart';
export 'src/utils/block_index_counter.dart';
export 'src/utils/docx_units.dart';
export 'src/widgets/docx_node_bound.dart';
