import 'dart:io';
import 'dart:typed_data';

import 'package:docx_creator/docx_creator.dart';
import 'package:flutter/material.dart';

import 'docx_view_config.dart';
import 'font_loader/embedded_font_loader.dart';
import 'search/docx_search_controller.dart';
import 'theme/docx_view_theme.dart';
import 'widget_generator/docx_widget_generator.dart';

/// A Flutter widget for viewing DOCX files.
///
/// Renders Word documents using native Flutter widgets for best performance.
///
/// ## Example
/// ```dart
/// DocxView(
///   file: myDocxFile,
///   config: DocxViewConfig(
///     enableSearch: true,
///     enableZoom: true,
///   ),
/// )
/// ```
class DocxView extends StatefulWidget {
  /// The DOCX file to display. Provide one of: [file], [bytes], or [path].
  final File? file;

  /// Raw DOCX bytes to display.
  final Uint8List? bytes;

  /// Path to a DOCX file.
  final String? path;

  /// Configuration for the viewer.
  final DocxViewConfig config;

  /// Optional search controller for external control.
  final DocxSearchController? searchController;

  /// Callback when document loading completes.
  final VoidCallback? onLoaded;

  /// Callback when document loading fails.
  final void Function(Object error)? onError;

  const DocxView({
    super.key,
    this.file,
    this.bytes,
    this.path,
    this.config = const DocxViewConfig(),
    this.searchController,
    this.onLoaded,
    this.onError,
  }) : assert(
          file != null || bytes != null || path != null,
          'Must provide either file, bytes, or path',
        );

  /// Create from file.
  factory DocxView.file(
    File file, {
    Key? key,
    DocxViewConfig config = const DocxViewConfig(),
    DocxSearchController? searchController,
  }) {
    return DocxView(
      key: key,
      file: file,
      config: config,
      searchController: searchController,
    );
  }

  /// Create from bytes.
  factory DocxView.bytes(
    Uint8List bytes, {
    Key? key,
    DocxViewConfig config = const DocxViewConfig(),
    DocxSearchController? searchController,
  }) {
    return DocxView(
      key: key,
      bytes: bytes,
      config: config,
      searchController: searchController,
    );
  }

  /// Create from path.
  factory DocxView.path(
    String path, {
    Key? key,
    DocxViewConfig config = const DocxViewConfig(),
    DocxSearchController? searchController,
  }) {
    return DocxView(
      key: key,
      path: path,
      config: config,
      searchController: searchController,
    );
  }

  @override
  State<DocxView> createState() => _DocxViewState();
}

class _DocxViewState extends State<DocxView> {
  List<Widget>? _widgets;
  DocxBuiltDocument? _doc; // Store for re-rendering on search
  bool _isLoading = true;
  Object? _error;

  late DocxSearchController _searchController;
  late DocxWidgetGenerator _generator;

  @override
  void initState() {
    super.initState();
    _searchController = widget.searchController ?? DocxSearchController();
    _searchController.addListener(_onSearchChanged);
    _loadDocument();
  }

  @override
  void dispose() {
    if (widget.searchController == null) {
      _searchController.dispose();
    } else {
      _searchController.removeListener(_onSearchChanged);
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(DocxView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file != widget.file ||
        oldWidget.bytes != widget.bytes ||
        oldWidget.path != widget.path) {
      _loadDocument();
    }
  }

  Future<void> _loadDocument() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      Uint8List bytes;
      if (widget.bytes != null) {
        bytes = widget.bytes!;
      } else if (widget.file != null) {
        bytes = await widget.file!.readAsBytes();
      } else if (widget.path != null) {
        bytes = await File(widget.path!).readAsBytes();
      } else {
        throw ArgumentError('No document source provided');
      }

      // Load document using docx_creator
      final doc = await DocxReader.loadFromBytes(bytes);

      for (final font in doc.fonts) {
        await EmbeddedFontLoader.loadFont(
          font.familyName,
          font.bytes,
          obfuscationKey: font.obfuscationKey,
        );
      }

      // Pre-process notes for quick lookup
      final footnoteMap = {for (var f in doc.footnotes ?? []) f.footnoteId: f};
      final endnoteMap = {for (var e in doc.endnotes ?? []) e.endnoteId: e};

      // Initialize widget generator
      _generator = DocxWidgetGenerator(
        config: widget.config,
        theme: widget.config.theme,
        docxTheme: doc.theme,
        searchController: widget.config.enableSearch ? _searchController : null,
        onFootnoteTap: widget.config.showFootnotes
            ? (id) => _showNoteContent('Footnote', footnoteMap[id]?.content)
            : null,
        onEndnoteTap: widget.config.showEndnotes
            ? (id) => _showNoteContent('Endnote', endnoteMap[id]?.content)
            : null,
      );

      // Generate widgets
      final widgets = _generator.generateWidgets(doc);

      // Build search index
      final textIndex = _generator.extractTextForSearch(doc);

      // Update search controller with document text
      _searchController.setDocument(textIndex);

      setState(() {
        _doc = doc;
        _widgets = widgets;
        _isLoading = false;
      });

      widget.onLoaded?.call();
    } catch (e) {
      setState(() {
        _error = e;
        _isLoading = false;
      });
      widget.onError?.call(e);
    }
  }

  void _showNoteContent(String title, List<DocxBlock>? content) {
    if (content == null || content.isEmpty || !mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        // Generate widgets for the note content
        // We use a temporary generator just for this content
        final noteWidgets = _generator.generateWidgets(DocxBuiltDocument(
          elements: content,
          // Empty dummy section/etc
          section: const DocxSectionDef(),
        ));

        // Filter out dividers/headers/etc that handle method might add?
        // generateWidgets handles 'doc' which includes section logic.
        // If we pass content as 'elements', it will be in the body. That's fine.

        return AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: noteWidgets,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _onSearchChanged() {
    if (_doc != null) {
      // Regenerate widgets to reflect search highlights
      final widgets = _generator.generateWidgets(_doc!);

      if (mounted) {
        setState(() {
          _widgets = widgets;
        });

        // Handle navigation
        final matchIndex = _searchController.currentMatchIndex;
        if (matchIndex != -1 && matchIndex < _searchController.matches.length) {
          final match = _searchController.matches[matchIndex];
          final blockIndex = match.blockIndex;

          final key = _generator.keys[blockIndex];
          if (key != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (key.currentContext != null) {
                final context = key.currentContext!;
                if (!context.mounted) return;

                double alignment = 0.5;

                try {
                  // For large blocks, calculate dynamic alignment
                  final renderObject = context.findRenderObject();
                  if (renderObject is RenderBox) {
                    final scrollable = Scrollable.of(context);
                    if (scrollable.position.hasViewportDimension) {
                      final viewportHeight =
                          scrollable.position.viewportDimension;
                      if (renderObject.size.height > viewportHeight) {
                        final text = _searchController.getBlockText(blockIndex);
                        if (text.isNotEmpty) {
                          final relativePos = match.startOffset / text.length;
                          alignment = relativePos.clamp(0.0, 1.0);
                        }
                      }
                    }
                  }
                } catch (e) {
                  debugPrint('DocxView: Error calculating alignment: $e');
                }

                debugPrint(
                    'DocxView: Scrolling to match $matchIndex at block $blockIndex using alignment $alignment');

                Scrollable.ensureVisible(
                  context,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  alignment: alignment,
                );
              } else {
                debugPrint(
                    'DocxView: Key found for block $blockIndex but context is null');
              }
            });
          } else {
            debugPrint('DocxView: No key found for block $blockIndex');
            // Debug dump keys
            debugPrint(
                'DocxView: Available keys: ${_generator.keys.keys.join(', ')}');
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.config.theme ?? DocxViewTheme.light();

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Failed to load document',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              _error.toString(),
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (_widgets == null || _widgets!.isEmpty) {
      return const Center(child: Text('Empty document'));
    }

    // Use theme's background color, fallback to config, then to white
    final backgroundColor =
        widget.config.backgroundColor ?? theme.backgroundColor ?? Colors.white;

    Widget content;
    final list = SingleChildScrollView(
      padding: widget.config.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _widgets!.map((child) {
          if (widget.config.pageMode == DocxPageMode.paged) {
            return Center(child: child);
          }
          return child;
        }).toList(),
      ),
    );

    if (widget.config.pageMode == DocxPageMode.paged) {
      // Paged View: Canvas style
      content = Container(
        color: widget.config.backgroundColor ?? Colors.grey.shade200,
        child: list,
      );
    } else if (widget.config.pageWidth != null) {
      // Page Layout Mode (Legacy constrained continuous)
      content = Container(
        color: widget.config.backgroundColor ?? const Color(0xFFF0F0F0),
        alignment: Alignment.topCenter,
        child: Container(
          width: widget.config.pageWidth,
          margin: const EdgeInsets.symmetric(vertical: 24),
          decoration: BoxDecoration(
            color: theme.backgroundColor ?? Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: list,
        ),
      );
    } else {
      // Standard Responsive Mode
      content = Container(
        color: backgroundColor,
        child: list,
      );
    }

    // Wrap with InteractiveViewer for zoom functionality
    if (widget.config.enableZoom) {
      content = InteractiveViewer(
        minScale: widget.config.minScale,
        maxScale: widget.config.maxScale,
        child: content,
      );
    }

    return content;
  }
}

/// Widget extension for adding a search bar.
class DocxViewWithSearch extends StatefulWidget {
  final File? file;
  final Uint8List? bytes;
  final String? path;
  final DocxViewConfig config;

  const DocxViewWithSearch({
    super.key,
    this.file,
    this.bytes,
    this.path,
    this.config = const DocxViewConfig(),
  });

  @override
  State<DocxViewWithSearch> createState() => _DocxViewWithSearchState();
}

class _DocxViewWithSearchState extends State<DocxViewWithSearch> {
  final DocxSearchController _searchController = DocxSearchController();
  final TextEditingController _textController = TextEditingController();
  bool _showSearch = false;

  @override
  void dispose() {
    _searchController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search bar
        if (_showSearch)
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.grey.shade100,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: InputDecoration(
                      hintText: 'Search...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      isDense: true,
                    ),
                    onSubmitted: (value) {
                      _searchController.search(value);
                    },
                    onChanged: (value) {
                      // Optional: live search
                      // _searchController.search(value);
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: _searchController.previousMatch,
                  tooltip: 'Previous match',
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_downward),
                  onPressed: _searchController.nextMatch,
                  tooltip: 'Next match',
                ),
                ListenableBuilder(
                  listenable: _searchController,
                  builder: (context, _) {
                    if (_searchController.matchCount > 0) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          '${_searchController.currentMatchIndex + 1}/${_searchController.matchCount}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    setState(() {
                      _showSearch = false;
                      _searchController.clear();
                      _textController.clear();
                    });
                  },
                ),
              ],
            ),
          ),
        // Document view
        Expanded(
          child: Stack(
            children: [
              DocxView(
                file: widget.file,
                bytes: widget.bytes,
                path: widget.path,
                config: widget.config,
                searchController: _searchController,
              ),
              // Search FAB
              if (!_showSearch)
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: FloatingActionButton(
                    mini: true,
                    onPressed: () {
                      setState(() {
                        _showSearch = true;
                      });
                    },
                    child: const Icon(Icons.search),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
