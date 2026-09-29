import 'package:html/dom.dart' as dom;

/// A parsed `<style>` rule: one selector with its declarations.
class CssRule {
  final CssSelector selector;
  final Map<String, String> declarations;
  final Map<String, String> importantDeclarations;
  final int order;

  CssRule(
      this.selector, this.declarations, this.importantDeclarations, this.order);
}

/// Minimal CSS stylesheet parser for `<style>` blocks.
///
/// Supports rule sets, comments, `@media` blocks (their contents are applied
/// unless the query is screen-only), and skips other at-rules.
class CssStylesheet {
  final List<CssRule> rules = [];

  void addSource(String source) {
    final css = source.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
    _parseBlock(css);
  }

  void _parseBlock(String css) {
    var i = 0;
    while (i < css.length) {
      final open = css.indexOf('{', i);
      if (open < 0) break;
      final prelude = css.substring(i, open).trim();
      final close = _matchingBrace(css, open);
      final body = css.substring(open + 1, close < 0 ? css.length : close);
      i = close < 0 ? css.length : close + 1;

      if (prelude.startsWith('@')) {
        // `@import ...;` statements can precede a block in the prelude.
        final at = prelude.substring(prelude.lastIndexOf('@'));
        if (at.startsWith('@media')) {
          final query = at.substring(6).toLowerCase();
          final screenOnly =
              query.contains('screen') && !query.contains('print');
          if (!screenOnly) _parseBlock(body);
        } else if (at.startsWith('@supports')) {
          _parseBlock(body);
        }
        continue;
      }

      // Drop anything before a stray `;` (e.g. `@charset "x";` prefix).
      final selectorText = prelude.contains(';')
          ? prelude.substring(prelude.lastIndexOf(';') + 1).trim()
          : prelude;
      if (selectorText.isEmpty) continue;

      final normal = <String, String>{};
      final important = <String, String>{};
      for (final decl in _splitDeclarations(body)) {
        final idx = decl.indexOf(':');
        if (idx <= 0) continue;
        final prop = decl.substring(0, idx).trim().toLowerCase();
        var value = decl.substring(idx + 1).trim();
        final isImportant = RegExp(r'!\s*important$').hasMatch(value);
        value = value.replaceAll(RegExp(r'!\s*important$'), '').trim();
        if (prop.isEmpty || value.isEmpty) continue;
        (isImportant ? important : normal)[prop] = value;
      }

      for (final part in _splitSelectorList(selectorText)) {
        final selector = CssSelector.tryParse(part);
        if (selector != null) {
          rules.add(CssRule(selector, normal, important, rules.length));
        }
      }
    }
  }

  static int _matchingBrace(String s, int open) {
    var depth = 0;
    for (var i = open; i < s.length; i++) {
      if (s[i] == '{') depth++;
      if (s[i] == '}') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  static List<String> _splitSelectorList(String s) {
    final out = <String>[];
    final buf = StringBuffer();
    var depth = 0;
    for (final ch in s.split('')) {
      if (ch == '(' || ch == '[') depth++;
      if ((ch == ')' || ch == ']') && depth > 0) depth--;
      if (ch == ',' && depth == 0) {
        out.add(buf.toString().trim());
        buf.clear();
      } else {
        buf.write(ch);
      }
    }
    if (buf.toString().trim().isNotEmpty) out.add(buf.toString().trim());
    return out;
  }

  static List<String> _splitDeclarations(String css) {
    final out = <String>[];
    final buf = StringBuffer();
    var depth = 0;
    String? quote;
    for (final ch in css.split('')) {
      if (quote != null) {
        if (ch == quote) quote = null;
      } else if (ch == '"' || ch == "'") {
        quote = ch;
      } else if (ch == '(') {
        depth++;
      } else if (ch == ')' && depth > 0) {
        depth--;
      } else if (ch == ';' && depth == 0) {
        out.add(buf.toString());
        buf.clear();
        continue;
      }
      buf.write(ch);
    }
    if (buf.isNotEmpty) out.add(buf.toString());
    return out;
  }

  /// Rules matching [element], sorted by specificity then source order.
  List<CssRule> matching(dom.Element element) {
    final matched = rules.where((r) => r.selector.matches(element)).toList();
    matched.sort((a, b) {
      final c = a.selector.specificity.compareTo(b.selector.specificity);
      return c != 0 ? c : a.order.compareTo(b.order);
    });
    return matched;
  }
}

enum _Combinator { descendant, child, adjacent, sibling }

class _Compound {
  String? tag;
  String? id;
  final classes = <String>[];
  final attributes = <_AttrTest>[];
  final pseudos = <_Pseudo>[];
  bool never = false;

  bool matches(dom.Element e) {
    if (never) return false;
    if (tag != null && tag != '*' && e.localName?.toLowerCase() != tag) {
      return false;
    }
    if (id != null && e.id != id) return false;
    for (final c in classes) {
      if (!e.classes.contains(c)) return false;
    }
    for (final a in attributes) {
      if (!a.matches(e)) return false;
    }
    for (final p in pseudos) {
      if (!p.matches(e)) return false;
    }
    return true;
  }
}

class _AttrTest {
  final String name;
  final String? op;
  final String? value;
  _AttrTest(this.name, this.op, this.value);

  bool matches(dom.Element e) {
    final actual = e.attributes[name];
    if (actual == null) return false;
    final v = value;
    if (op == null || v == null) return true;
    switch (op) {
      case '=':
        return actual == v;
      case '~=':
        return actual.split(RegExp(r'\s+')).contains(v);
      case '|=':
        return actual == v || actual.startsWith('$v-');
      case '^=':
        return actual.startsWith(v);
      case r'$=':
        return actual.endsWith(v);
      case '*=':
        return actual.contains(v);
    }
    return false;
  }
}

class _Pseudo {
  final String name;
  final String? arg;
  _Pseudo(this.name, this.arg);

  static List<dom.Element> _siblings(dom.Element e) {
    final parent = e.parent;
    if (parent == null) return [e];
    return parent.children;
  }

  bool matches(dom.Element e) {
    final siblings = _siblings(e);
    final index = siblings.indexOf(e);
    switch (name) {
      case 'first-child':
        return index == 0;
      case 'last-child':
        return index == siblings.length - 1;
      case 'only-child':
        return siblings.length == 1;
      case 'first-of-type':
        return siblings.firstWhere((s) => s.localName == e.localName,
                orElse: () => e) ==
            e;
      case 'last-of-type':
        return siblings.lastWhere((s) => s.localName == e.localName,
                orElse: () => e) ==
            e;
      case 'nth-child':
        return _nth(arg ?? '', index + 1);
      case 'nth-last-child':
        return _nth(arg ?? '', siblings.length - index);
      case 'nth-of-type':
        final same = siblings.where((s) => s.localName == e.localName).toList();
        return _nth(arg ?? '', same.indexOf(e) + 1);
      case 'not':
        final inner = CssSelector.tryParse(arg ?? '');
        return inner != null && !inner.matches(e);
      case 'root':
        return e.parent == null || e.localName == 'html';
      case 'empty':
        return e.nodes.isEmpty;
      case 'link':
      case 'any-link':
        return e.localName == 'a' && e.attributes.containsKey('href');
    }
    // Dynamic states (:hover etc.) never apply to a static document.
    return false;
  }

  static bool _nth(String expr, int position) {
    final s = expr.replaceAll(' ', '').toLowerCase();
    if (s == 'odd') return position.isOdd;
    if (s == 'even') return position.isEven;
    final n = int.tryParse(s);
    if (n != null) return position == n;
    final m = RegExp(r'^([+-]?\d*)n([+-]\d+)?$').firstMatch(s);
    if (m == null) return false;
    final aStr = m.group(1)!;
    final a = aStr.isEmpty || aStr == '+'
        ? 1
        : aStr == '-'
            ? -1
            : int.parse(aStr);
    final b = int.tryParse(m.group(2) ?? '0') ?? 0;
    if (a == 0) return position == b;
    final k = (position - b) / a;
    return k >= 0 && k == k.roundToDouble();
  }
}

/// A single complex selector (`div > p.note a[href]`).
class CssSelector {
  final List<_Compound> _compounds;
  final List<_Combinator> _combinators; // between compounds[i] and [i+1]
  final int specificity;

  CssSelector._(this._compounds, this._combinators, this.specificity);

  static CssSelector? tryParse(String text) {
    try {
      return _parse(text.trim());
    } catch (_) {
      return null;
    }
  }

  static CssSelector? _parse(String s) {
    if (s.isEmpty) return null;
    final compounds = <_Compound>[];
    final combinators = <_Combinator>[];
    var ids = 0, classes = 0, types = 0;
    var i = 0;
    var current = _Compound();
    var pendingCombinator = _Combinator.descendant;
    var hasContent = false;

    void finishCompound() {
      if (!hasContent) return;
      if (compounds.isNotEmpty) combinators.add(pendingCombinator);
      compounds.add(current);
      current = _Compound();
      hasContent = false;
      pendingCombinator = _Combinator.descendant;
    }

    String readIdent() {
      final start = i;
      while (i < s.length && RegExp(r'[\w\-\\]').hasMatch(s[i])) {
        i++;
      }
      return s.substring(start, i);
    }

    while (i < s.length) {
      final ch = s[i];
      if (ch == ' ' || ch == '\t' || ch == '\n') {
        finishCompound();
        i++;
        continue;
      }
      if (ch == '>' || ch == '+' || ch == '~') {
        finishCompound();
        pendingCombinator = ch == '>'
            ? _Combinator.child
            : ch == '+'
                ? _Combinator.adjacent
                : _Combinator.sibling;
        i++;
        continue;
      }
      hasContent = true;
      if (ch == '*') {
        current.tag = '*';
        i++;
      } else if (ch == '#') {
        i++;
        current.id = readIdent();
        ids++;
      } else if (ch == '.') {
        i++;
        current.classes.add(readIdent());
        classes++;
      } else if (ch == '[') {
        final end = s.indexOf(']', i);
        if (end < 0) return null;
        final inner = s.substring(i + 1, end).trim();
        i = end + 1;
        final m = RegExp(r'^([\w\-:]+)\s*(?:([~|^$*]?=)\s*(.+?))?(\s+i)?$')
            .firstMatch(inner);
        if (m == null) return null;
        var value = m.group(3);
        if (value != null &&
            value.length >= 2 &&
            (value.startsWith('"') || value.startsWith("'"))) {
          value = value.substring(1, value.length - 1);
        }
        current.attributes.add(_AttrTest(m.group(1)!, m.group(2), value));
        classes++;
      } else if (ch == ':') {
        i++;
        if (i < s.length && s[i] == ':') {
          // Pseudo-elements (::before) generate no matchable element.
          i++;
          readIdent();
          current.never = true;
          continue;
        }
        final name = readIdent().toLowerCase();
        String? arg;
        if (i < s.length && s[i] == '(') {
          var depth = 0;
          final start = i + 1;
          while (i < s.length) {
            if (s[i] == '(') depth++;
            if (s[i] == ')') {
              depth--;
              if (depth == 0) break;
            }
            i++;
          }
          arg = s.substring(start, i);
          i++;
        }
        if (name == 'before' || name == 'after') current.never = true;
        current.pseudos.add(_Pseudo(name, arg));
        classes++;
      } else if (RegExp(r'[\w\-]').hasMatch(ch)) {
        current.tag = readIdent().toLowerCase();
        types++;
      } else {
        return null; // unsupported syntax
      }
    }
    finishCompound();
    if (compounds.isEmpty) return null;
    return CssSelector._(
        compounds, combinators, ids * 10000 + classes * 100 + types);
  }

  bool matches(dom.Element element) =>
      _matchFrom(element, _compounds.length - 1);

  bool _matchFrom(dom.Element element, int index) {
    if (!_compounds[index].matches(element)) return false;
    if (index == 0) return true;
    final combinator = _combinators[index - 1];
    switch (combinator) {
      case _Combinator.child:
        final parent = element.parent;
        return parent != null && _matchFrom(parent, index - 1);
      case _Combinator.descendant:
        var ancestor = element.parent;
        while (ancestor != null) {
          if (_matchFrom(ancestor, index - 1)) return true;
          ancestor = ancestor.parent;
        }
        return false;
      case _Combinator.adjacent:
        final prev = element.previousElementSibling;
        return prev != null && _matchFrom(prev, index - 1);
      case _Combinator.sibling:
        var prev = element.previousElementSibling;
        while (prev != null) {
          if (_matchFrom(prev, index - 1)) return true;
          prev = prev.previousElementSibling;
        }
        return false;
    }
  }
}
