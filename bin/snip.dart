// SPDX-License-Identifier: BSD-3-Clause

import 'dart:io';
import 'dart:isolate';

import 'package:args/command_runner.dart';
import 'package:dart_style/dart_style.dart' show TrailingCommas;
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:snip/snip.dart';
import 'package:pool/pool.dart';

void main(List<String> args) async {
  final runner = CommandRunner<int>(
    'snip',
    'Format Dart snippets in Markdown and doc comments.',
  )..addCommand(FormatCommand());

  try {
    final exitCode = await runner.run(args) ?? 0;
    exit(exitCode);
  } on UsageException catch (e) {
    stderr.writeln(e);
    exit(64);
  }
}

class FormatCommand extends Command<int> {
  FormatCommand() {
    argParser
      ..addFlag('apply', help: 'Write formatted content back to files.')
      ..addOption(
        'language-version',
        help:
            'Dart language version for formatting (e.g. "3.10").\n'
            'Defaults to the latest version supported by dart_style.',
        valueHelp: 'major.minor',
      )
      ..addOption(
        'line-length',
        abbr: 'l',
        help: 'Target line length (default: 80).',
        valueHelp: 'columns',
        defaultsTo: '80',
      )
      ..addFlag(
        'preserve-trailing-commas',
        help:
            'Preserve existing trailing commas (force splits).\n'
            'By default, the formatter manages trailing commas automatically.',
      )
      ..addOption(
        'concurrency',
        abbr: 'j',
        help: 'Number of concurrent isolates (default: 80% of CPU cores).',
        valueHelp: 'count',
      );
  }

  @override
  String get name => 'format';

  @override
  String get description =>
      'Format Dart code snippets in Markdown files and doc comments.\n'
      'Reports files that need formatting (exit code 1 if any).\n'
      'Use --apply to write changes back to files.';

  @override
  String get invocation => '${runner!.executableName} $name <path>';

  @override
  Future<int> run() async {
    final argResults = this.argResults!;
    final rest = argResults.rest;
    if (rest.isEmpty) {
      usageException('Please provide a path to format.');
    }

    final apply = argResults.flag('apply');

    final versionStr = argResults.option('language-version');
    Version? languageVersion;
    if (versionStr != null) {
      try {
        languageVersion = Version.parse('$versionStr.0');
      } on FormatException {
        usageException('Invalid language version: "$versionStr".');
      }
    }

    final lineLength = int.tryParse(argResults.option('line-length')!);
    if (lineLength == null || lineLength <= 0) {
      usageException('Invalid line length.');
    }

    final trailingCommas = argResults.flag('preserve-trailing-commas')
        ? TrailingCommas.preserve
        : TrailingCommas.automate;

    final concurrencyStr = argResults.option('concurrency');
    int maxConcurrency;
    if (concurrencyStr != null) {
      maxConcurrency = int.tryParse(concurrencyStr) ?? 0;
      if (maxConcurrency <= 0) {
        usageException('Invalid concurrency value.');
      }
    } else {
      maxConcurrency = (Platform.numberOfProcessors * 0.8).ceil();
    }

    final pool = Pool(maxConcurrency);
    final results = <Future<FileResult>>[];
    await for (final file in _collectFiles(rest.first)) {
      final path = file.path;
      results.add(
        pool.withResource(
          () => Isolate.run(() {
            final fmt = SnippetFormatter(
              languageVersion: languageVersion,
              pageWidth: lineLength,
              trailingCommas: trailingCommas,
            );

            final content = File(path).readAsStringSync();
            final result = switch (p.extension(path)) {
              '.md' => MarkdownProcessor(fmt).process(content, path: path),
              '.dart' => DocCommentProcessor(fmt).process(content, path: path),
              _ => throw StateError(
                'Cannot format snippets in $path. Invalid extension!',
              ),
            };
            if (apply && result.changed) {
              File(result.path).writeAsStringSync(result.output);
            }
            // Drop output to avoid transferring file contents back.
            return result.withoutOutput();
          }),
        ),
      );
    }

    // Report results sequentially to avoid mangled output.
    var fileCount = 0;
    var filesFormatted = 0;
    var filesWithErrors = 0;
    var snippetCount = 0;
    var snippetsFormatted = 0;
    var snippetsWithErrors = 0;

    for (final result in await results.wait) {
      fileCount++;
      for (final snippet in result.snippets) {
        snippetCount++;
        if (snippet is SnippetError) {
          snippetsWithErrors++;
          stderr.writeln(
            '${result.path}:${snippet.startLine}: ${snippet.message}',
          );
        } else if (snippet is SnippetFormatted && snippet.changed) {
          snippetsFormatted++;
        }
      }

      if (result.changed) {
        filesFormatted++;
        if (apply) {
          stdout.writeln('  formatted: ${result.path}');
        } else {
          stdout.writeln('  needs formatting: ${result.path}');
        }
      }
      if (result.hasErrors) filesWithErrors++;
    }

    // Summary line.
    final parts = <String>[
      '$fileCount file(s) scanned',
      '$snippetCount snippet(s) found',
      if (apply && snippetsFormatted > 0)
        '$snippetsFormatted snippet(s) formatted in $filesFormatted file(s)',
      if (!apply && snippetsFormatted > 0)
        '$snippetsFormatted snippet(s) need formatting in $filesFormatted file(s)',
      if (snippetsWithErrors > 0)
        '$snippetsWithErrors snippet(s) with errors in $filesWithErrors file(s)',
    ];
    stdout.writeln(parts.join(', '));

    if (snippetsWithErrors > 0) return 1;
    if (!apply && snippetsFormatted > 0) return 1;
    return 0;
  }

  Stream<File> _collectFiles(String target) async* {
    final type = FileSystemEntity.typeSync(target);

    if (type == FileSystemEntityType.file) {
      yield File(target);
    } else if (type == FileSystemEntityType.directory) {
      yield* Directory(target) // find all markdown or dart files
          .list(recursive: true)
          .whereType<File>()
          .where((f) {
            final ext = p.extension(f.path);
            return ext == '.md' || ext == '.dart';
          });
    } else {
      stderr.writeln('Not a file or directory: $target');
    }
  }
}

extension<T> on Stream<T> {
  Stream<U> whereType<U>() => where((t) => t is U).cast<U>();
}
