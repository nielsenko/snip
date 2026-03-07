/// Result of formatting a single code snippet.
sealed class SnippetResult {
  const SnippetResult({required this.original, required this.startLine});

  /// The original (possibly unformatted) code.
  final String original;

  /// Line number in the source file where this snippet starts.
  final int startLine;
}

/// Snippet was formatted successfully.
final class SnippetFormatted extends SnippetResult {
  const SnippetFormatted({
    required super.original,
    required super.startLine,
    required this.formatted,
  });

  final String formatted;

  bool get changed => original != formatted;
}

/// Snippet could not be parsed or formatted.
final class SnippetError extends SnippetResult {
  const SnippetError({
    required super.original,
    required super.startLine,
    required this.message,
  });

  final String message;
}

/// Result of processing an entire file.
class FileResult {
  const FileResult({
    required this.path,
    required this.snippets,
    required this.output,
  });

  final String path;
  final List<SnippetResult> snippets;

  /// The full file content after formatting all snippets.
  final String output;

  bool get changed => snippets.any((s) => s is SnippetFormatted && s.changed);

  bool get hasErrors => snippets.any((s) => s is SnippetError);
}
