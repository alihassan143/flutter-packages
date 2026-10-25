import 'package:docx_creator/docx_creator.dart';

/// Undo/redo over a sequence of document edits.
///
/// Every `DocxBuiltDocument` produced by `docx_edit_ops.dart` is immutable
/// and independent of the one before it, so "undo" is just "go back to the
/// previous whole-document reference" - no diffing/patch representation is
/// needed at this stage. That's cheap enough for a document-sized AST; if
/// profiling ever says otherwise, switch to recording each op (ponytail:
/// whole-document snapshots, switch to inverse-operation replay if memory
/// becomes a real problem).
class DocxEditCommandStack {
  final List<DocxBuiltDocument> _history;
  int _index;

  /// Starts the stack at [initialDocument] (nothing to undo yet).
  DocxEditCommandStack(DocxBuiltDocument initialDocument)
      : _history = [initialDocument],
        _index = 0;

  /// The document after all edits applied so far.
  DocxBuiltDocument get current => _history[_index];

  bool get canUndo => _index > 0;
  bool get canRedo => _index < _history.length - 1;

  /// Records [result] as the outcome of an edit applied to [current].
  /// Drops any redo history past the current point, same as a normal
  /// editor once you make a new edit after undoing.
  void push(DocxBuiltDocument result) {
    _history.removeRange(_index + 1, _history.length);
    _history.add(result);
    _index++;
  }

  DocxBuiltDocument undo() {
    if (!canUndo) throw StateError('nothing to undo');
    _index--;
    return current;
  }

  DocxBuiltDocument redo() {
    if (!canRedo) throw StateError('nothing to redo');
    _index++;
    return current;
  }
}
