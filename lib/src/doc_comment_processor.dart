// SPDX-License-Identifier: BSD-3-Clause

import 'dart_scanner.dart';
import 'format_result.dart';
import 'snippet_formatter.dart';

/// Processes Dart files, formatting code blocks in `///` doc comments.
///
/// Uses [DartScanner] to identify real doc comment lines (ignoring `///` that
/// appears inside strings or block comments), then finds and formats
/// `` ```dart `` blocks within those comments.
class DocCommentProcessor {
  const DocCommentProcessor(this._formatter);

  final SnippetFormatter _formatter;

  FileResult process(String content, {required String path}) {
    final lines = content.split('\n');
    final lineInfos = DartScanner(content).scan();
    final snippets = <SnippetResult>[];
    final output = <String>[];

    int? blockStartLine;
    String? blockPrefix;
    final blockLines = <String>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final isDoc = lineInfos[i] == LineKind.docComment;

      // If we're collecting a code block but hit a non-doc line, flush.
      if (blockStartLine != null && !isDoc) {
        _flushPartial(blockLines, blockPrefix!, output);
        blockStartLine = null;
        blockPrefix = null;
        output.add(line);
        continue;
      }

      if (!isDoc) {
        output.add(line);
        continue;
      }

      final trimmed = line.trimLeft();
      final afterSlashes = trimmed.substring(3).trimLeft();

      // Are we collecting a code block?
      if (blockStartLine != null) {
        if (afterSlashes == '```') {
          // Closing fence - format the collected block.
          final code = _stripDocPrefix(blockLines);
          final prefix = blockPrefix!;

          try {
            final formatted = _formatter.format(code);
            final recommented = _addDocPrefix(formatted, prefix);
            snippets.add(
              SnippetFormatted(
                original: code,
                startLine: blockStartLine,
                formatted: formatted,
              ),
            );
            output.add('$prefix```dart');
            output.addAll(recommented.split('\n'));
          } on FormatException catch (e) {
            snippets.add(
              SnippetError(
                original: code,
                startLine: blockStartLine,
                message: e.message,
              ),
            );
            output.addAll(blockLines);
          }
          output.add(line); // closing fence
          blockLines.clear();
          blockStartLine = null;
          blockPrefix = null;
          continue;
        }

        blockLines.add(line);
        continue;
      }

      // Look for opening ```dart fence.
      if (afterSlashes == '```dart' || afterSlashes.startsWith('```dart ')) {
        blockStartLine = i + 1; // 1-based
        blockPrefix = _extractPrefix(line);
        continue;
      }

      output.add(line);
    }

    // File ended mid-block - flush unchanged.
    if (blockStartLine != null) {
      _flushPartial(blockLines, blockPrefix!, output);
    }

    return FileResult(
      path: path,
      snippets: snippets,
      output: output.join('\n'),
    );
  }

  void _flushPartial(List<String> lines, String prefix, List<String> output) {
    output.add('$prefix```dart');
    output.addAll(lines);
    lines.clear();
  }

  String _extractPrefix(String line) {
    final match = RegExp(r'^([ \t]*///[ \t]*)').firstMatch(line);
    return match?.group(1) ?? '/// ';
  }

  String _stripDocPrefix(List<String> lines) {
    return lines
        .map((line) {
          final stripped = line.trimLeft();
          if (stripped.startsWith('/// ')) return stripped.substring(4);
          if (stripped.startsWith('///')) return stripped.substring(3);
          return line;
        })
        .join('\n');
  }

  String _addDocPrefix(String code, String prefix) {
    final lines = code.split('\n');
    final trimmed = lines.isNotEmpty && lines.last.isEmpty
        ? lines.sublist(0, lines.length - 1)
        : lines;
    return trimmed
        .map((line) => line.isEmpty ? line : '$prefix$line')
        .join('\n');
  }
}
