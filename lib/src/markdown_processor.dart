// SPDX-License-Identifier: BSD-3-Clause

import 'format_result.dart';
import 'snippet_formatter.dart';

/// Regex matching ```dart code blocks in Markdown.
///
/// Captures:
///   Group 1: leading whitespace before the opening fence
///   Group 2: the code content between the fences
final _dartBlockRegex = RegExp(
  r'^([ \t]*)```dart\s*\n([\s\S]*?)^\1```\s*$',
  multiLine: true,
);

/// Processes Markdown content, formatting embedded Dart code blocks.
class MarkdownProcessor {
  const MarkdownProcessor(this._formatter);

  final SnippetFormatter _formatter;

  /// Processes [content] from a file at [path], returning a [FileResult].
  FileResult process(String content, {required String path}) {
    final snippets = <SnippetResult>[];
    final buffer = StringBuffer();
    var lastEnd = 0;

    for (final match in _dartBlockRegex.allMatches(content)) {
      // Append text before this match verbatim.
      buffer.write(content.substring(lastEnd, match.start));

      final indent = match.group(1)!;
      final code = match.group(2)!;
      final startLine = _lineNumber(content, match.start);

      // Strip the block indent from code lines before formatting.
      final dedented = _dedent(code, indent);

      try {
        final formatted = _formatter.format(dedented);
        final reindented = _indent(formatted, indent);

        snippets.add(
          SnippetFormatted(
            original: code,
            startLine: startLine,
            formatted: reindented,
          ),
        );

        buffer.write('$indent```dart\n$reindented$indent```');
      } on FormatException catch (e) {
        snippets.add(
          SnippetError(
            original: code,
            startLine: startLine,
            message: e.message,
          ),
        );
        // Preserve the original block unchanged.
        buffer.write('$indent```dart\n$code$indent```');
      }

      lastEnd = match.end;
    }

    // Append any remaining text after the last match.
    buffer.write(content.substring(lastEnd));

    return FileResult(
      path: path,
      snippets: snippets,
      output: buffer.toString(),
    );
  }

  /// Returns the 1-based line number for [offset] in [content].
  int _lineNumber(String content, int offset) {
    return content.substring(0, offset).split('\n').length;
  }

  /// Removes [indent] prefix from each line of [code].
  String _dedent(String code, String indent) {
    if (indent.isEmpty) return code;
    return code
        .split('\n')
        .map((line) {
          if (line.startsWith(indent)) return line.substring(indent.length);
          return line;
        })
        .join('\n');
  }

  /// Adds [indent] prefix to each non-empty line of [code].
  String _indent(String code, String indent) {
    if (indent.isEmpty) return code;
    return code
        .split('\n')
        .map((line) => line.isEmpty ? line : '$indent$line')
        .join('\n');
  }
}
