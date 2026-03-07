/// A minimal recursive-descent scanner for Dart source code.
///
/// Scans the entire source in a single pass, correctly handling nested block
/// comments (`/* /* */ */`), triple-quoted strings, and raw strings. Produces
/// a per-line classification so callers can identify real doc comment lines.
class DartScanner {
  DartScanner(this._source);

  final String _source;
  int _pos = 0;
  bool _inMultiline = false;

  List<LineKind> scan() {
    final lines = _source.split('\n');
    final result = List<LineKind>.filled(lines.length, LineKind.code);

    _pos = 0;
    _inMultiline = false;

    var lineStart = 0;
    for (var i = 0; i < lines.length; i++) {
      final lineEnd = lineStart + lines[i].length;
      result[i] = _classifyLine(lineStart, lineEnd);
      lineStart = lineEnd + 1; // +1 for '\n'
    }

    return result;
  }

  LineKind _classifyLine(int lineStart, int lineEnd) {
    if (_inMultiline && _pos > lineEnd) {
      return LineKind.other;
    }

    if (_inMultiline) {
      _inMultiline = false;
      _scanCodeUntil(lineEnd);
      return LineKind.code;
    }

    _pos = lineStart;
    _skipWhitespace(lineEnd);

    if (_pos >= lineEnd) return LineKind.code;

    // Doc comment: `///` but not `////`.
    if (_pos + 2 <= lineEnd &&
        _at(_pos) == $slash &&
        _at(_pos + 1) == $slash &&
        _at(_pos + 2) == $slash &&
        (_pos + 3 >= lineEnd || _at(_pos + 3) != $slash)) {
      _pos = lineEnd;
      return LineKind.docComment;
    }

    _scanCodeUntil(lineEnd);
    return LineKind.code;
  }

  void _skipWhitespace(int limit) {
    while (_pos < limit && (_at(_pos) == 0x20 || _at(_pos) == 0x09)) {
      _pos++;
    }
  }

  void _scanCodeUntil(int limit) {
    while (_pos < limit) {
      final c = _at(_pos);

      if (c == $slash && _pos + 1 < _source.length) {
        final next = _at(_pos + 1);
        if (next == $slash) {
          _pos = limit;
          return;
        }
        if (next == $star) {
          _scanBlockComment();
          if (_pos > limit) {
            _inMultiline = true;
            return;
          }
          continue;
        }
      }

      if (c == $r &&
          _pos + 1 < _source.length &&
          (_at(_pos + 1) == $singleQuote || _at(_pos + 1) == $doubleQuote)) {
        _pos++;
        _scanString(_at(_pos), limit);
        if (_inMultiline) return;
        continue;
      }

      if (c == $singleQuote || c == $doubleQuote) {
        _scanString(c, limit);
        if (_inMultiline) return;
        continue;
      }

      _pos++;
    }
  }

  void _scanBlockComment() {
    _pos += 2;
    var depth = 1;
    while (_pos < _source.length && depth > 0) {
      final c = _at(_pos);
      if (c == $slash && _pos + 1 < _source.length && _at(_pos + 1) == $star) {
        depth++;
        _pos += 2;
      } else if (c == $star &&
          _pos + 1 < _source.length &&
          _at(_pos + 1) == $slash) {
        depth--;
        _pos += 2;
      } else {
        _pos++;
      }
    }
  }

  void _scanString(int quote, int lineLimit) {
    if (_pos + 2 < _source.length &&
        _at(_pos + 1) == quote &&
        _at(_pos + 2) == quote) {
      _pos += 3;
      _scanTripleString(quote);
      if (_pos > lineLimit) _inMultiline = true;
      return;
    }

    _pos++;
    while (_pos < _source.length) {
      final c = _at(_pos);
      if (c == $backslash) {
        _pos += 2;
        continue;
      }
      if (c == quote) {
        _pos++;
        return;
      }
      if (c == $newline) return;
      _pos++;
    }
  }

  void _scanTripleString(int quote) {
    while (_pos < _source.length) {
      final c = _at(_pos);
      if (c == $backslash) {
        _pos += 2;
        continue;
      }
      if (c == quote &&
          _pos + 2 < _source.length &&
          _at(_pos + 1) == quote &&
          _at(_pos + 2) == quote) {
        _pos += 3;
        return;
      }
      _pos++;
    }
  }

  int _at(int i) => _source.codeUnitAt(i);
}

const $slash = 0x2F;
const $star = 0x2A;
const $singleQuote = 0x27;
const $doubleQuote = 0x22;
const $backslash = 0x5C;
const $newline = 0x0A;
const $r = 0x72;

enum LineKind { code, docComment, other }
