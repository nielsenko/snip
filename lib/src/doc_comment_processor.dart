import 'format_result.dart';
import 'snippet_formatter.dart';

/// Regex matching ```dart code blocks inside `///` doc comments.
///
/// Captures the full block including the `///` prefixed fence lines.
final _docDartBlockRegex = RegExp(
  r'^([ \t]*///[ \t]*)```dart\s*\n((?:[ \t]*///.*\n)*?)[ \t]*///[ \t]*```\s*$',
  multiLine: true,
);

/// Processes Dart files, formatting code blocks in `///` doc comments.
class DocCommentProcessor {
  DocCommentProcessor(this._formatter);

  final SnippetFormatter _formatter;

  /// Processes [content] from a file at [path], returning a [FileResult].
  FileResult process(String content, {required String path}) {
    final snippets = <SnippetResult>[];
    final buffer = StringBuffer();
    var lastEnd = 0;

    for (final match in _docDartBlockRegex.allMatches(content)) {
      buffer.write(content.substring(lastEnd, match.start));

      final prefix = match.group(1)!;
      final rawBlock = match.group(2)!;
      final startLine = _lineNumber(content, match.start);

      // Strip the `/// ` prefix from each code line.
      final code = _stripDocPrefix(rawBlock);

      try {
        final formatted = _formatter.format(code);
        final recommented = _addDocPrefix(formatted, prefix);

        snippets.add(
          SnippetFormatted(
            original: code,
            startLine: startLine,
            formatted: formatted,
          ),
        );

        buffer.write('$prefix```dart\n$recommented$prefix```');
      } on FormatException catch (e) {
        snippets.add(
          SnippetError(
            original: code,
            startLine: startLine,
            message: e.message,
          ),
        );
        // Preserve original block unchanged.
        buffer.write('$prefix```dart\n$rawBlock$prefix```');
      }

      lastEnd = match.end;
    }

    buffer.write(content.substring(lastEnd));

    return FileResult(
      path: path,
      snippets: snippets,
      output: buffer.toString(),
    );
  }

  int _lineNumber(String content, int offset) {
    return content.substring(0, offset).split('\n').length;
  }

  /// Strips the `///` prefix (and optional trailing space) from each line.
  String _stripDocPrefix(String block) {
    return block
        .split('\n')
        .map((line) {
          final stripped = line.trimLeft();
          if (stripped.startsWith('/// ')) return stripped.substring(4);
          if (stripped.startsWith('///')) return stripped.substring(3);
          return line;
        })
        .join('\n');
  }

  /// Adds a doc comment prefix to each line of formatted code.
  String _addDocPrefix(String code, String prefix) {
    return code
        .split('\n')
        .map((line) {
          if (line.isEmpty) return line;
          return '$prefix$line';
        })
        .join('\n');
  }
}
