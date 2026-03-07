import 'package:dart_style/dart_style.dart';
import 'package:pub_semver/pub_semver.dart';

/// Formats Dart code snippets using a multi-attempt harness strategy.
///
/// Since snippets are often fragments (not full compilation units), this
/// tries multiple approaches before giving up.
class SnippetFormatter {
  SnippetFormatter({int pageWidth = 80, Version? languageVersion})
    : _formatter = DartFormatter(
        languageVersion: languageVersion ?? DartFormatter.latestLanguageVersion,
        pageWidth: pageWidth,
      );

  final DartFormatter _formatter;

  /// Attempts to format [code] using the harness strategy.
  ///
  /// Returns the formatted code on success, or throws a [FormatException]
  /// with a descriptive message if all attempts fail.
  String format(String code) {
    // Attempt 1: format as a standalone compilation unit.
    try {
      return _formatter.format(code);
    } on FormatterException {
      // Fall through to attempt 2.
    }

    // Attempt 2: wrap in a function body and format.
    try {
      return _formatWrapped(code);
    } on FormatterException catch (e) {
      // Both attempts failed.
      throw FormatException('Could not parse snippet:\n${e.message()}');
    }
  }

  String _formatWrapped(String code) {
    final indented = code
        .split('\n')
        .map((line) => line.isEmpty ? '' : '  $line')
        .join('\n');
    final wrapped = 'void _snipHarness() {\n$indented\n}\n';
    final formatted = _formatter.format(wrapped);

    // Strip the wrapper: remove first line and last line (closing brace),
    // then dedent by 2 spaces.
    final lines = formatted.split('\n');
    // First line is "void _snipHarness() {", last non-empty is "}".
    final innerLines = lines.sublist(1, lines.length - 2);
    final dedented = innerLines
        .map((line) {
          if (line.startsWith('  ')) return line.substring(2);
          return line;
        })
        .join('\n');
    return '$dedented\n';
  }
}
