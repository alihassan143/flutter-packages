import 'package:docx_creator/docx_creator.dart';
import 'package:flutter/material.dart';

import '../docx_view_config.dart';
import '../search/docx_search_controller.dart';
import '../theme/docx_view_theme.dart';
import '../utils/block_index_counter.dart';
import 'image_builder.dart';
import 'list_builder.dart';
import 'paragraph_builder.dart';
import 'shape_builder.dart';
import 'table_builder.dart';

/// Generates Flutter widgets from [DocxNode] elements.
///
/// This is the core "brain" that maps OpenXML elements to Flutter widgets.
class DocxWidgetGenerator {
  final DocxViewConfig config;
  final DocxViewTheme theme;
  final DocxTheme? docxTheme;
  final DocxSearchController? searchController;

  final void Function(int id)? onFootnoteTap;
  final void Function(int id)? onEndnoteTap;

  /// Paragraph builder for text rendering.
  late ParagraphBuilder _paragraphBuilder;

  /// Table builder for table rendering.
  late TableBuilder _tableBuilder;

  /// List builder for list rendering.
  late ListBuilder _listBuilder;

  /// Image builder for image rendering.
  late ImageBuilder _imageBuilder;

  /// Shape builder for shape rendering.
  late ShapeBuilder _shapeBuilder;

  /// Store the last used counter to access widget keys after generation.
  BlockIndexCounter? _lastCounter;

  /// Block keys for navigation.
  Map<int, GlobalKey> get keys => _lastCounter?.keyRegistry ?? {};

  DocxWidgetGenerator({
    required this.config,
    DocxViewTheme? theme,
    this.docxTheme,
    this.searchController,
    this.onFootnoteTap,
    this.onEndnoteTap,
  }) : theme = theme ?? DocxViewTheme.light() {
    _paragraphBuilder = ParagraphBuilder(
      theme: this.theme,
      config: config,
      searchController: searchController,
      onFootnoteTap: onFootnoteTap,
      docxTheme: docxTheme,
      onEndnoteTap: onEndnoteTap,
    );
    _imageBuilder = ImageBuilder(config: config);
    // TableBuilder, ListBuilder, ShapeBuilder need docxTheme, set in generateWidgets
  }

  /// Generate a list of widgets from a parsed document.
  List<Widget> generateWidgets(DocxBuiltDocument doc) {
    // Re-initialize builders that depend on document-specific theme
    _paragraphBuilder = ParagraphBuilder(
      theme: theme,
      config: config,
      searchController: searchController,
      onFootnoteTap: onFootnoteTap,
      onEndnoteTap: onEndnoteTap,
      docxTheme: doc.theme,
    );

    _listBuilder = ListBuilder(
      theme: theme,
      config: config,
      paragraphBuilder: _paragraphBuilder,
      docxTheme: doc.theme,
    );

    _imageBuilder = ImageBuilder(config: config);

    _shapeBuilder = ShapeBuilder(
      config: config,
      docxTheme: doc.theme,
    );

    _tableBuilder = TableBuilder(
      theme: theme,
      config: config,
      paragraphBuilder: _paragraphBuilder,
      listBuilder: _listBuilder,
      imageBuilder: _imageBuilder,
      shapeBuilder: _shapeBuilder,
      docxTheme: doc.theme,
    );

    if (config.pageMode == DocxPageMode.paged) {
      return _generatePagedWidgets(doc);
    }

    return _generateContinuousWidgets(doc);
  }

  /// Original continuous generation logic
  List<Widget> _generateContinuousWidgets(DocxBuiltDocument doc) {
    final widgets = <Widget>[];
    final counter = BlockIndexCounter();

    // 1. Header
    // We must pass the counter to align indices with extraction
    if (doc.section?.header != null) {
      widgets.addAll(_generateBlockWidgets(doc.section!.header!.children,
          counter: counter));
      widgets.add(const Divider(height: 32, thickness: 1, color: Colors.grey));
    }

    // 2. Body
    _lastCounter = counter;
    widgets.addAll(_generateBlockWidgets(doc.elements, counter: counter));

    // 3. Footnotes
    if (config.showFootnotes &&
        doc.footnotes != null &&
        doc.footnotes!.isNotEmpty) {
      widgets.add(const Divider(height: 32, thickness: 1));
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: Text('Footnotes',
            style: theme.defaultTextStyle
                .copyWith(fontWeight: FontWeight.bold, fontSize: 18)),
      ));

      for (var footnote in doc.footnotes!) {
        widgets.add(_buildNoteWidget(footnote.footnoteId, footnote.content));
      }
    }

    // 4. Endnotes
    if (config.showEndnotes &&
        doc.endnotes != null &&
        doc.endnotes!.isNotEmpty) {
      widgets.add(const Divider(height: 32, thickness: 1));
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: Text('Endnotes',
            style: theme.defaultTextStyle
                .copyWith(fontWeight: FontWeight.bold, fontSize: 18)),
      ));

      for (var endnote in doc.endnotes!) {
        widgets.add(_buildNoteWidget(endnote.endnoteId, endnote.content));
      }
    }

    // 5. Footer
    if (doc.section?.footer != null) {
      widgets.add(const Divider(height: 32, thickness: 1, color: Colors.grey));
      widgets.addAll(_generateBlockWidgets(doc.section!.footer!.children,
          counter: counter));
    }

    return widgets;
  }

  /// Generate widgets grouped into Pages with content-aware pagination.
  List<Widget> _generatePagedWidgets(DocxBuiltDocument doc) {
    final pages = <List<Widget>>[];
    var currentPageContent = <Widget>[];
    final counter = BlockIndexCounter();
    _lastCounter = counter;

    // Page dimensions
    final pageWidth = config.pageWidth ?? 794;
    final pageHeight = config.pageHeight ?? (pageWidth * 1.414);
    const pagePadding = 48.0 * 2;
    const headerFooterEstimate = 100.0;
    final availableHeight = pageHeight - pagePadding - headerFooterEstimate;

    double currentPageHeight = 0;

    void startNewPage() {
      if (currentPageContent.isNotEmpty) {
        pages.add(List.from(currentPageContent));
        currentPageContent.clear();
        currentPageHeight = 0;
      }
    }

    // Pre-calculate Header widgets for the first page
    List<Widget>? firstPageHeaderWidgets;
    if (doc.section?.header != null) {
      firstPageHeaderWidgets = _generateBlockWidgets(
        doc.section!.header!.children,
        counter: counter,
      );
    }

    // Batch elements between page breaks, then generate widgets for each batch
    List<DocxNode> currentBatch = [];

    double estimateBatchHeight(List<DocxNode> batch) {
      double height = 0;
      for (var element in batch) {
        height += _estimateElementHeight(element, pageWidth);
      }
      return height;
    }

    void flushBatch() {
      if (currentBatch.isNotEmpty) {
        final batchHeight = estimateBatchHeight(currentBatch);

        // Check if batch would overflow current page
        if (currentPageHeight + batchHeight > availableHeight &&
            currentPageContent.isNotEmpty) {
          startNewPage();
        }

        // Generate widgets for the batch (preserves floating element grouping)
        final widgets = _generateBlockWidgets(currentBatch, counter: counter);
        currentPageContent.addAll(widgets);
        currentPageHeight += batchHeight;
        currentBatch.clear();
      }
    }

    for (var element in doc.elements) {
      // Check for explicit page breaks
      bool isPageBreak = false;
      if (element is DocxSectionBreakBlock) {
        isPageBreak = true;
      } else if (element is DocxParagraph && element.pageBreakBefore) {
        isPageBreak = true;
      }

      if (isPageBreak) {
        flushBatch();
        startNewPage();
        if (element is! DocxSectionBreakBlock) {
          currentBatch.add(element);
        }
      } else {
        currentBatch.add(element);

        // Check if we should flush (content getting too tall)
        // But don't flush right after adding a floating table - let it group with next paragraphs
        bool lastWasFloatingTable =
            element is DocxTable && element.position != null;

        if (!lastWasFloatingTable) {
          final batchHeight = estimateBatchHeight(currentBatch);
          if (batchHeight > availableHeight) {
            flushBatch();
          }
        }
      }
    }

    flushBatch();
    startNewPage();

    if (pages.isEmpty) {
      pages.add([]);
    }

    return pages.asMap().entries.map((entry) {
      final index = entry.key;
      final content = entry.value;
      final headerWidgets = (index == 0) ? firstPageHeaderWidgets : null;
      return _buildPageContainer(content, doc, headerWidgets: headerWidgets);
    }).toList();
  }

  /// Estimate the height of a document element for pagination.
  double _estimateElementHeight(DocxNode element, double pageWidth) {
    const lineHeight = 24.0; // Approximate line height
    const paragraphSpacing = 16.0;

    if (element is DocxParagraph) {
      // Estimate based on text content
      int totalChars = 0;
      for (var child in element.children) {
        if (child is DocxText) {
          totalChars += child.content.length;
        }
      }
      // Estimate characters per line based on page width
      final charsPerLine = ((pageWidth - 96) / 8).floor(); // ~8px per char
      final lines = (totalChars / charsPerLine).ceil().clamp(1, 100);
      return (lines * lineHeight) + paragraphSpacing;
    } else if (element is DocxTable) {
      // Simple row-based estimate - more accurate for most tables
      final rowCount = element.rows.length;
      return (rowCount * 30.0) + 16.0; // ~30px per row + margins
    } else if (element is DocxList) {
      // Estimate based on item count
      return element.items.length * 30.0 + 10.0;
    } else if (element is DocxImage) {
      // Use actual dimensions if available
      final height = element.height > 0 ? element.height.toDouble() : 200.0;
      return height + 16.0;
    } else if (element is DocxShapeBlock) {
      return 100.0; // Default shape height
    } else if (element is DocxDropCap) {
      return 80.0; // Drop cap height
    }

    return lineHeight + paragraphSpacing; // Default
  }

  Widget _buildNoteWidget(int id, List<DocxNode> content) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$id. ',
              style: theme.defaultTextStyle
                  .copyWith(fontSize: 12, fontWeight: FontWeight.bold)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _generateBlockWidgets(content),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageContainer(List<Widget> content, DocxBuiltDocument doc,
      {List<Widget>? headerWidgets}) {
    List<Widget> pageChildren = [];

    // Header
    if (doc.section?.header != null) {
      if (headerWidgets != null) {
        pageChildren.addAll(headerWidgets);
      } else {
        // Regenerate for subsequent pages (no counter, so no indices/keys)
        pageChildren
            .addAll(_generateBlockWidgets(doc.section!.header!.children));
      }
      pageChildren.add(const SizedBox(height: 20)); // Header margin
    }

    pageChildren.addAll(content);

    if (doc.section?.footer != null) {
      // Use SizedBox for margin
      pageChildren.add(const SizedBox(height: 40));
      pageChildren.add(const Divider());
      pageChildren.addAll(_generateBlockWidgets(doc.section!.footer!.children));
    }

    // Calculate page dimensions
    final pageWidth = config.pageWidth ?? 794;
    final pageHeight = config.pageHeight ?? (pageWidth * 1.414); // A4 ratio
    const pagePadding = 48.0;

    return Container(
      width: pageWidth,
      height: pageHeight,
      margin: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: theme.backgroundColor ?? Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(pagePadding),
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: pageChildren,
          ),
        ),
      ),
    );
  }

  /// Generate widgets for a list of blocks.
  List<Widget> _generateBlockWidgets(List<DocxNode> elements,
      {BlockIndexCounter? counter}) {
    final widgets = <Widget>[];
    int i = 0;

    // Track floats that have been "consumed" by a previous paragraph's grouping
    final consumedFloats = <DocxInline>{};

    while (i < elements.length) {
      final element = elements[i];

      // Check for floating table
      if (element is DocxTable && element.position != null) {
        // This is a floating table - group with following paragraphs
        final floatingTable = element;
        final followingParagraphs = <DocxNode>[];

        // Collect paragraphs that should wrap around this table
        int j = i + 1;
        while (j < elements.length && followingParagraphs.length < 5) {
          final next = elements[j];
          if (next is DocxParagraph || next is DocxDropCap) {
            followingParagraphs.add(next);
            j++;
          } else {
            break; // Stop at non-paragraph block
          }
        }

        if (followingParagraphs.isNotEmpty) {
          // Build the floating Row layout
          final tableWidget =
              _tableBuilder.build(floatingTable, counter: counter);
          final paragraphWidgets = followingParagraphs.map((p) {
            if (p is DocxParagraph) {
              return _paragraphBuilder.build(p, counter: counter);
            } else if (p is DocxDropCap) {
              return _paragraphBuilder.buildDropCap(p);
            }
            return const SizedBox.shrink();
          }).toList();

          // Determine float side from table position
          final isRightFloat =
              floatingTable.position?.hAnchor == DocxTableHAnchor.margin &&
                  floatingTable.alignment == DocxAlign.right;

          Widget rowWidget;
          if (isRightFloat) {
            // Table on the right
            rowWidget = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                    flex: 2,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: paragraphWidgets)),
                const SizedBox(width: 12),
                Flexible(flex: 1, child: tableWidget),
              ],
            );
          } else {
            // Table on the left (default)
            rowWidget = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(flex: 1, child: tableWidget),
                const SizedBox(width: 12),
                Expanded(
                    flex: 2,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: paragraphWidgets)),
              ],
            );
          }

          widgets.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: rowWidget,
          ));
          i = j; // Skip to after grouped paragraphs
          continue;
        }
      }

      // Handle Paragraphs with special float grouping logic
      if (element is DocxParagraph) {
        final (localLefts, localRights) = getFloatsFromParagraph(element);

        // Filter out floats we already handled in a previous group
        final activeLefts =
            localLefts.where((f) => !consumedFloats.contains(f)).toList();
        final activeRights =
            localRights.where((f) => !consumedFloats.contains(f)).toList();

        final extraRights = <DocxInline>[];

        // If we have unconsumed left floats, we are a potential anchor for a group
        // Look ahead for right floats in subsequent paragraphs
        if (activeLefts.isNotEmpty) {
          int j = i + 1;
          // Look ahead a few paragraphs
          while (j < elements.length && j < i + 5) {
            final next = elements[j];
            if (next is DocxParagraph) {
              final (nextLefts, nextRights) = getFloatsFromParagraph(next);

              // If next has valid lefts, it starts its own group - stop scanning
              if (nextLefts.any((f) => !consumedFloats.contains(f))) {
                break;
              }

              // Inspect next rights
              final nextActiveRights =
                  nextRights.where((f) => !consumedFloats.contains(f)).toList();

              if (nextActiveRights.isNotEmpty) {
                // Determine if we should group these rights with current lefts
                extraRights.addAll(nextActiveRights);
                consumedFloats.addAll(nextActiveRights);
              }
            } else {
              // Non-paragraph breaks the group visual flow
              break;
            }
            j++;
          }
        }

        final finalRights = [...activeRights, ...extraRights];

        // If we have active floats (either our own or adopted ones), render a Float Row
        if (activeLefts.isNotEmpty || finalRights.isNotEmpty) {
          // Mark our own floats as consumed
          consumedFloats.addAll(activeLefts);
          consumedFloats.addAll(activeRights);

          // Build the content WITHOUT the floats we are displaying here
          // We must exclude both activeLefts and activeRights from the content rendering
          final floatsToExclude = {...activeLefts, ...activeRights};

          final contentWidget = _paragraphBuilder
              .buildExcludingFloats(element, floatsToExclude, counter: counter);

          // Helper to build a column of floats
          List<Widget> buildFloatColumn(List<DocxInline> floats) {
            return floats.map((img) {
              Widget child;
              if (img is DocxInlineImage) {
                child = Image.memory(img.bytes,
                    width: img.width, height: img.height, fit: BoxFit.contain);
              } else if (img is DocxShape) {
                child = _shapeBuilder.buildInlineShape(img);
              } else {
                child = const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: child,
              );
            }).toList();
          }

          final rowWidget = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (activeLefts.isNotEmpty) ...[
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: buildFloatColumn(activeLefts),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(child: contentWidget),
              if (finalRights.isNotEmpty) ...[
                const SizedBox(width: 12),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: buildFloatColumn(finalRights),
                ),
              ]
            ],
          );

          widgets.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: rowWidget,
          ));

          i++;
          continue;
        } else {
          // No active floats to render in the custom layout -- check for hidden consumed floats
          if (localLefts.any((f) => consumedFloats.contains(f)) ||
              localRights.any((f) => consumedFloats.contains(f))) {
            final floatsToExclude = {...localLefts, ...localRights}
                .where((f) => consumedFloats.contains(f))
                .toSet();

            widgets.add(_paragraphBuilder.buildExcludingFloats(
                element, floatsToExclude,
                counter: counter));

            i++;
            continue;
          }
        }
      }

      // Standard element processing
      final widget = generateWidget(element, counter: counter);
      if (widget != null) {
        widgets.add(widget);
      }
      i++;
    }

    return widgets;
  }

  /// Extract floating images from ANY paragraph, including those with text.
  /// Returns (leftFloats, rightFloats).
  (List<DocxInline>, List<DocxInline>) getFloatsFromParagraph(
      DocxParagraph paragraph) {
    final leftFloats = <DocxInline>[];
    final rightFloats = <DocxInline>[];

    for (final child in paragraph.children) {
      if (child is DocxInlineImage &&
          child.positionMode == DocxDrawingPosition.floating) {
        if (child.hAlign == DrawingHAlign.right) {
          rightFloats.add(child);
        } else if (child.hAlign != DrawingHAlign.center) {
          leftFloats.add(child);
        }
      } else if (child is DocxShape &&
          child.position == DocxDrawingPosition.floating) {
        if (child.horizontalAlign == DrawingHAlign.right) {
          rightFloats.add(child);
        } else if (child.horizontalAlign != DrawingHAlign.center) {
          leftFloats.add(child);
        }
      }
    }

    return (leftFloats, rightFloats);
  }

  /// Generate a single widget from a [DocxNode].
  Widget? generateWidget(DocxNode node, {BlockIndexCounter? counter}) {
    try {
      if (node is DocxParagraph) {
        return _paragraphBuilder.build(node, counter: counter);
      } else if (node is DocxTable) {
        return _tableBuilder.build(node, counter: counter);
      } else if (node is DocxList) {
        return _listBuilder.build(node, counter: counter);
      } else if (node is DocxImage) {
        return _imageBuilder.buildBlockImage(node);
      } else if (node is DocxShapeBlock) {
        return _shapeBuilder.buildBlockShape(node);
      } else if (node is DocxDropCap) {
        return _paragraphBuilder.buildDropCap(node);
      } else if (node is DocxSectionBreakBlock) {
        // Render section breaks as horizontal dividers
        return const Divider(height: 24, thickness: 1);
      } else if (node is DocxRawXml) {
        return config.showDebugInfo
            ? buildDebugPlaceholder('[Unsupported element]')
            : const SizedBox.shrink();
      }
    } catch (e, stack) {
      // Silent failure: return debug widget or empty space
      if (config.showDebugInfo) {
        return buildDebugPlaceholder('Error: $e\n$stack',
            color: Colors.red.shade100);
      }
      return const SizedBox.shrink();
    }
    return null;
  }

  Widget buildDebugPlaceholder(String message, {Color? color}) {
    return Container(
      padding: const EdgeInsets.all(8),
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: color ?? Colors.grey.shade100,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: Colors.grey.shade600,
          fontSize: 10,
          fontFamily: 'Courier',
        ),
      ),
    );
  }

  /// Extract all text content for search indexing.
  List<String> extractTextForSearch(DocxBuiltDocument doc) {
    final texts = <String>[];
    final counter = BlockIndexCounter();

    // Header
    if (doc.section?.header != null) {
      _extractFromBlocks(doc.section!.header!.children, texts, counter);
    }

    // Body
    _extractFromBlocks(doc.elements, texts, counter);

    // Footer
    if (doc.section?.footer != null) {
      _extractFromBlocks(doc.section!.footer!.children, texts, counter);
    }

    return texts;
  }

  void _extractFromBlocks(
      List<DocxNode> nodes, List<String> texts, BlockIndexCounter counter) {
    for (final node in nodes) {
      if (node is DocxParagraph) {
        texts.add(_extractFromParagraph(node));
        counter.increment();
      } else if (node is DocxTable) {
        for (final row in node.rows) {
          for (final cell in row.cells) {
            _extractFromBlocks(cell.children, texts, counter);
          }
        }
      } else if (node is DocxList) {
        for (final item in node.items) {
          // List item behaves like a paragraph
          texts.add(_extractFromInlines(item.children));
          counter.increment();
        }
      } else if (node is DocxSectionBreakBlock) {
        // Ignored
      }
      // Other blocks
    }
  }

  String _extractFromParagraph(DocxParagraph paragraph) {
    return _extractFromInlines(paragraph.children);
  }

  String _extractFromInlines(List<DocxInline> inlines) {
    final buffer = StringBuffer();
    for (final inline in inlines) {
      if (inline is DocxText) {
        buffer.write(inline.content);
      } else if (inline is DocxTab) {
        buffer.write('    ');
      } else if (inline is DocxLineBreak) {
        buffer.write('\n');
      } else if (inline is DocxCheckbox) {
        buffer.write(inline.isChecked ? '☒ ' : '☐ ');
      }
      // Ignore others
    }
    return buffer.toString();
  }
}
