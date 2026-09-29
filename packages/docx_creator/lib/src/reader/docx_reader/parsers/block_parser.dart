import 'package:xml/xml.dart';

import '../../../../docx_creator.dart';

/// Parses block-level content (paragraphs, lists, tables).
class BlockParser {
  /// The context for the current reader session.
  final ReaderContext context;

  /// The parser used for inline elements (text, images, etc.).
  final InlineParser inlineParser;

  /// The parser used for table elements.
  final TableParser tableParser;

  /// Creates a [BlockParser] with the specified [context].
  BlockParser(this.context)
      : inlineParser = InlineParser(context),
        tableParser = TableParser(context, InlineParser(context));

  /// Tracks the number of items encountered for each numId to enable list continuity.
  final Map<int, int> _numIdItemCounts = {};

  /// Parse body element into list of DocxNodes.
  List<DocxNode> parseBody(XmlElement body) {
    return parseBlocks(body.children);
  }

  /// Parse a list of XML children into DocxNodes.
  List<DocxNode> parseBlocks(Iterable<XmlNode> children) {
    final result = <DocxNode>[];
    final pendingListItems = <DocxParagraph>[];
    int? currentNumId;

    void flushPendingList() {
      if (pendingListItems.isNotEmpty && currentNumId != null) {
        result.add(_createListFromParagraphs(pendingListItems, currentNumId!));
        pendingListItems.clear();
        currentNumId = null;
      }
    }

    // Convert to list for indexed access (needed for drop cap look-ahead)
    final childList = children.toList();
    int i = 0;

    while (i < childList.length) {
      final child = childList[i];
      if (child is XmlElement) {
        if (child.name.local == 'p') {
          // Check for drop cap first
          final pPr = child.getElement('w:pPr');
          final framePr = pPr?.getElement('w:framePr');
          final dropCapAttr = framePr?.getAttribute('w:dropCap');

          if (dropCapAttr != null &&
              (dropCapAttr == 'drop' || dropCapAttr == 'margin')) {
            // This is a drop cap paragraph
            // Look ahead to the next paragraph for the "rest of paragraph" content
            XmlElement? nextParagraph;
            int nextParaIndex = i + 1;
            while (nextParaIndex < childList.length) {
              final nextChild = childList[nextParaIndex];
              if (nextChild is XmlElement && nextChild.name.local == 'p') {
                // Check if this next paragraph is also a drop cap (shouldn't be, but check)
                final nextPPr = nextChild.getElement('w:pPr');
                final nextFramePr = nextPPr?.getElement('w:framePr');
                final nextDropCap = nextFramePr?.getAttribute('w:dropCap');
                if (nextDropCap == null) {
                  nextParagraph = nextChild;
                }
                break;
              }
              nextParaIndex++;
            }

            final dropCap =
                _parseDropCap(child, framePr!, dropCapAttr, nextParagraph);
            flushPendingList();
            result.add(dropCap);

            // Skip the next paragraph since we consumed it as part of the drop cap
            if (nextParagraph != null) {
              i = nextParaIndex;
            }
          } else {
            final para = parseParagraph(child);
            if (para.numId != null) {
              // List item
              if (currentNumId != null && currentNumId != para.numId) {
                flushPendingList();
              }
              currentNumId = para.numId;
              pendingListItems.add(para);
            } else {
              flushPendingList();
              result.add(para);
            }
          }

          // Check for section break embedded in this paragraph (reuse pPr from above)
          if (pPr != null) {
            final sectPr = pPr.getElement('w:sectPr');
            if (sectPr != null) {
              final sectionDef = _parseSectionProperties(sectPr);
              result.add(DocxSectionBreakBlock(sectionDef));
            }
          }
        } else if (child.name.local == 'tbl') {
          flushPendingList();
          result.add(tableParser.parse(child));
        } else if (['ins', 'del', 'smartTag', 'sdt']
            .contains(child.name.local)) {
          // Handle block-level containers (Track Changes, etc.)
          var contentNodes = child.children;
          if (child.name.local == 'sdt') {
            final sdtPr = child.getElement('w:sdtPr');
            final gallery = sdtPr
                ?.getElement('w:docPartObj')
                ?.getElement('w:docPartGallery');
            final isTOC = gallery?.getAttribute('w:val') == 'Table of Contents';

            if (isTOC) {
              final content = child.getElement('w:sdtContent');
              if (content != null) {
                // Parse TOC content (cached items)
                final tocContent = parseBlocks(content.children);
                // Extract instruction from content (first paragraph usually has field code)
                String instruction = 'TOC \\o "1-3" \\h \\z \\u'; // Default
                // Try to find instruction in children...
                // (Simplified: Just use default or try to extract if critical)
                result.add(DocxTableOfContents(
                  cachedContent: tocContent.whereType<DocxBlock>().toList(),
                  instruction: instruction,
                ));
                i++;
                continue; // Skip the generic processing
              }
            } else {
              final content = child.findAllElements('w:sdtContent').firstOrNull;
              if (content != null) contentNodes = content.children;
            }
          }
          result.addAll(parseBlocks(contentNodes));
        }
      }
      i++;
    }

    flushPendingList();
    return result;
  }

  /// Parse a paragraph element.
  DocxParagraph parseParagraph(XmlElement xml) {
    String? pStyle;
    String? cnfStyle;

    // Parse paragraph properties
    final pPr = xml.getElement('w:pPr');
    if (pPr != null) {
      final pStyleElem = pPr.getElement('w:pStyle');
      if (pStyleElem != null) {
        pStyle = pStyleElem.getAttribute('w:val');
      }
      final cs = pPr.getElement('w:cnfStyle');
      if (cs != null) {
        cnfStyle = cs.getAttribute('w:val');
      }
    }

    // Resolve Style Properties
    final effectiveStyle = context.resolveStyle(pStyle ?? 'Normal');

    // Parse direct properties (override styles)
    // Extract rPr from pPr if present (paragraph mark properties which act as run defaults)
    final rPr = pPr?.getElement('w:rPr');
    final parsedProps = DocxStyle.fromXml('temp', pPr: pPr, rPr: rPr);

    // Merge: Style < Direct
    final finalProps = effectiveStyle.merge(parsedProps);

    // Parse runs and other inline content
    final children =
        inlineParser.parseChildren(xml.children, parentStyle: finalProps);

    return DocxParagraph(
      children: children,
      styleId: pStyle,
      align: finalProps.align ?? DocxAlign.left,
      shadingFill: finalProps.shadingFill,
      themeFill: finalProps.themeFill,
      themeFillTint: finalProps.themeFillTint,
      themeFillShade: finalProps.themeFillShade,
      numId: finalProps.numId,
      ilvl: finalProps.ilvl,
      spacingAfter: finalProps.spacingAfter,
      spacingBefore: finalProps.spacingBefore,
      lineSpacing: finalProps.lineSpacing,
      lineRule: finalProps.lineRule,
      indentLeft: finalProps.indentLeft,
      indentRight: finalProps.indentRight,
      indentFirstLine: finalProps.indentFirstLine,
      borderTop: finalProps.borderTop,
      borderBottomSide: finalProps.borderBottomSide,
      borderLeft: finalProps.borderLeft,
      borderRight: finalProps.borderRight,
      borderBetween: finalProps.borderBetween,
      cnfStyle: cnfStyle,
    );
  }

  /// Create a DocxList from collected list paragraphs.
  DocxList _createListFromParagraphs(
      List<DocxParagraph> paragraphs, int numId) {
    // Look up numbering definition once
    final numberingDef = context.parsedNumberings[numId];

    // Helper to resolve style for a given level
    DocxListStyle resolveStyleForLevel(int level) {
      if (numberingDef != null) {
        final levelDef =
            numberingDef.levels.where((l) => l.level == level).firstOrNull;

        if (levelDef != null) {
          DocxNumberFormat format = DocxNumberFormat.decimal;
          switch (levelDef.numFmt) {
            case 'bullet':
              format = DocxNumberFormat.bullet;
              break;
            case 'lowerLetter':
            case 'lowerAlpha':
              format = DocxNumberFormat.lowerAlpha;
              break;
            case 'upperLetter':
            case 'upperAlpha':
              format = DocxNumberFormat.upperAlpha;
              break;
            case 'lowerRoman':
              format = DocxNumberFormat.lowerRoman;
              break;
            case 'upperRoman':
              format = DocxNumberFormat.upperRoman;
              break;
            default:
              format = DocxNumberFormat.decimal;
          }

          return DocxListStyle(
            imageBulletBytes: levelDef.picBulletImage,
            bullet: levelDef.bulletChar ?? '•',
            numberFormat: format,
            // `w:ind w:left` is the level's absolute indent, while
            // DocxListStyle.indentPerLevel is multiplied by (level + 1)
            // wherever it's applied (DOCX writer, PDF exporter).
            indentPerLevel: levelDef.indentLeft != null
                ? (levelDef.indentLeft! / (level + 1)).round()
                : 720,
            hangingIndent: levelDef.hanging ?? 360,
            themeColor: levelDef.themeColor,
            themeTint: levelDef.themeTint,
            themeShade: levelDef.themeShade,
            themeFont: levelDef.themeFont,
            fontFamily: levelDef.bulletFont,
          );
        }
      }
      return const DocxListStyle();
    }

    // Determine base style from the first item (legacy behavior compat)
    final firstLevel = paragraphs.first.ilvl ?? 0;
    final baseStyle = resolveStyleForLevel(firstLevel);

    final items = paragraphs.map((p) {
      final level = p.ilvl ?? 0;

      // If this item's level differs from the base, or if we want to be safe,
      // we resolve its specific style.
      // If it differs from the base list style, we set it as an override.
      // For simplicity/correctness, if it's not the first item's level, or if it has image bullets,
      // we attach the override.
      DocxListStyle? override;
      if (level != firstLevel) {
        override = resolveStyleForLevel(level);
      }

      return DocxListItem(
        p.children,
        level: level,
        overrideStyle: override,
      );
    }).toList();

    // Calculate start index for continuity
    int start = 1;
    if (_numIdItemCounts.containsKey(numId)) {
      start = _numIdItemCounts[numId]! + 1;
    }

    _numIdItemCounts[numId] = (start - 1) + items.length;

    return DocxList(
      items: items,
      isOrdered: _isOrderedList(numId),
      style: baseStyle,
      startIndex: start,
      numId: numId,
    );
  }

  /// Determine if a list is ordered based on numbering definitions.
  bool _isOrderedList(int numId) {
    if (context.parsedNumberings.containsKey(numId)) {
      final def = context.parsedNumberings[numId]!;
      // Check level 0 or any level?
      // Usually checking level 0 is sufficient for list type
      final lvl = def.levels.where((l) => l.level == 0).firstOrNull ??
          def.levels.firstOrNull;
      if (lvl != null) {
        return lvl.numFmt != 'bullet';
      }
    }

    // Fallback to XML parsing if not found in parsed map (legacy/safety)
    final numberingXml = context.numberingXml;
    if (numberingXml == null) return false;

    try {
      final xml = XmlDocument.parse(numberingXml);

      // Find abstract numId for this numId
      int? abstractNumId;
      for (var num in xml.findAllElements('w:num')) {
        final id = int.tryParse(num.getAttribute('w:numId') ?? '');
        if (id == numId) {
          final abstractRef = num.getElement('w:abstractNumId');
          if (abstractRef != null) {
            abstractNumId =
                int.tryParse(abstractRef.getAttribute('w:val') ?? '');
          }
          break;
        }
      }

      if (abstractNumId == null) return false;

      // Check numbering format
      for (var abstractNum in xml.findAllElements('w:abstractNum')) {
        final id =
            int.tryParse(abstractNum.getAttribute('w:abstractNumId') ?? '');
        if (id == abstractNumId) {
          final lvl = abstractNum.findAllElements('w:lvl').firstOrNull;
          if (lvl != null) {
            final numFmt = lvl.getElement('w:numFmt');
            if (numFmt != null) {
              final val = numFmt.getAttribute('w:val');
              return val != 'bullet';
            }
          }
          break;
        }
      }
    } catch (_) {}

    return false;
  }

  /// Parse section properties from a w:sectPr element.
  DocxSectionDef _parseSectionProperties(XmlElement sectPr) {
    DocxPageSize pageSize = DocxPageSize.letter;
    DocxPageOrientation orientation = DocxPageOrientation.portrait;
    int? customWidth;
    int? customHeight;
    int marginTop = kDefaultMarginTop;
    int marginBottom = kDefaultMarginBottom;
    int marginLeft = kDefaultMarginLeft;
    int marginRight = kDefaultMarginRight;

    // Page Size
    final pgSz = sectPr.getElement('w:pgSz');
    if (pgSz != null) {
      final w = int.tryParse(pgSz.getAttribute('w:w') ?? '12240') ?? 12240;
      final h = int.tryParse(pgSz.getAttribute('w:h') ?? '15840') ?? 15840;
      final orient = pgSz.getAttribute('w:orient');

      if (orient == 'landscape') {
        orientation = DocxPageOrientation.landscape;
      }

      if ((w == 12240 && h == 15840) || (w == 15840 && h == 12240)) {
        pageSize = DocxPageSize.letter;
      } else if ((w == 11906 && h == 16838) || (w == 16838 && h == 11906)) {
        pageSize = DocxPageSize.a4;
      } else {
        pageSize = DocxPageSize.custom;
        customWidth = w;
        customHeight = h;
      }
    }

    // Margins
    final pgMar = sectPr.getElement('w:pgMar');
    if (pgMar != null) {
      marginTop = int.tryParse(pgMar.getAttribute('w:top') ?? '') ?? marginTop;
      marginBottom =
          int.tryParse(pgMar.getAttribute('w:bottom') ?? '') ?? marginBottom;
      marginLeft =
          int.tryParse(pgMar.getAttribute('w:left') ?? '') ?? marginLeft;
      marginRight =
          int.tryParse(pgMar.getAttribute('w:right') ?? '') ?? marginRight;
    }

    return DocxSectionDef(
      pageSize: pageSize,
      orientation: orientation,
      customWidth: customWidth,
      customHeight: customHeight,
      marginTop: marginTop,
      marginBottom: marginBottom,
      marginLeft: marginLeft,
      marginRight: marginRight,
    );
  }

  /// Parse a drop cap paragraph from w:framePr with w:dropCap.
  /// The [nextParagraph] parameter is the following paragraph in the document,
  /// which often contains the "rest of paragraph" text that wraps around the drop cap.
  DocxDropCap _parseDropCap(
      XmlElement xml, XmlElement framePr, String dropCapAttr,
      [XmlElement? nextParagraph]) {
    // Get drop cap style
    final style = dropCapAttr == 'margin'
        ? DocxDropCapStyle.margin
        : DocxDropCapStyle.drop;

    // Get number of lines
    final linesAttr = framePr.getAttribute('w:lines');
    final lines = int.tryParse(linesAttr ?? '3') ?? 3;

    // Get horizontal space
    final hSpaceAttr = framePr.getAttribute('w:hSpace');
    final hSpace = int.tryParse(hSpaceAttr ?? '0') ?? 0;

    // Extract the drop cap letter from the first run
    String letter = '';
    String? fontFamily;
    double? fontSize;

    final runs = xml.findAllElements('w:r');
    if (runs.isNotEmpty) {
      final firstRun = runs.first;
      final textElem = firstRun.getElement('w:t');
      if (textElem != null) {
        letter = textElem.innerText;
      }

      // Get font properties
      final rPr = firstRun.getElement('w:rPr');
      if (rPr != null) {
        final szElem = rPr.getElement('w:sz');
        if (szElem != null) {
          final szVal = int.tryParse(szElem.getAttribute('w:val') ?? '');
          if (szVal != null) fontSize = szVal / 2.0;
        }
        final rFonts = rPr.getElement('w:rFonts');
        if (rFonts != null) {
          fontFamily = rFonts.getAttribute('w:ascii');
        }
      }
    }

    // Parse the rest of the paragraph content
    final restOfChildren = <DocxInline>[];
    final effectiveStyle = context.resolveStyle('Normal');

    // First, check if there's content in the current paragraph after the drop cap
    final allChildren = xml.children;
    bool skippedFirstRun = false;
    final nodesToParse = <XmlNode>[];

    for (var child in allChildren) {
      if (child is XmlElement && child.name.local == 'r') {
        if (!skippedFirstRun) {
          skippedFirstRun = true;
          continue;
        }
      }
      if (child is XmlElement && ['pPr', 'sectPr'].contains(child.name.local)) {
        continue; // Skip properties
      }
      nodesToParse.add(child);
    }

    restOfChildren.addAll(
        inlineParser.parseChildren(nodesToParse, parentStyle: effectiveStyle));

    // If we have a next paragraph, parse its content as the "rest of paragraph"
    // This handles the common Word case where the drop cap letter and rest of text
    // are in separate paragraphs
    if (nextParagraph != null) {
      final nextChildren = nextParagraph.children;
      final nextNodesToParse = <XmlNode>[];

      for (var child in nextChildren) {
        if (child is XmlElement &&
            ['pPr', 'sectPr'].contains(child.name.local)) {
          continue; // Skip properties
        }
        nextNodesToParse.add(child);
      }

      // Resolve style for the next paragraph
      final nextPPr = nextParagraph.getElement('w:pPr');
      String? nextPStyle;
      if (nextPPr != null) {
        final pStyleElem = nextPPr.getElement('w:pStyle');
        if (pStyleElem != null) {
          nextPStyle = pStyleElem.getAttribute('w:val');
        }
      }
      final nextEffectiveStyle = context.resolveStyle(nextPStyle ?? 'Normal');

      restOfChildren.addAll(inlineParser.parseChildren(nextNodesToParse,
          parentStyle: nextEffectiveStyle));
    }

    return DocxDropCap(
      letter: letter,
      lines: lines,
      style: style,
      hSpace: hSpace,
      fontFamily: fontFamily,
      fontSize: fontSize,
      restOfParagraph: restOfChildren,
    );
  }
}
