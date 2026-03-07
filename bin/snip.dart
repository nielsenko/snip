import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:snip/snip.dart';

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
      ..addFlag(
        'check',
        help:
            'Check if files need formatting (exit code 1 if so). Does not write.',
      )
      ..addFlag('apply', help: 'Write formatted content back to files.')
      ..addOption(
        'language-version',
        help:
            'Dart language version for formatting (e.g. "3.10").\n'
            'Defaults to the latest version supported by dart_style.',
        valueHelp: 'major.minor',
      );
  }

  @override
  String get name => 'format';

  @override
  String get description =>
      'Format Dart code snippets in Markdown files and doc comments.\n'
      'By default, performs a dry run (reports files that would change).';

  @override
  String get invocation => '${runner!.executableName} $name <path>';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      usageException('Please provide a path to format.');
    }

    final check = argResults!.flag('check');
    final apply = argResults!.flag('apply');

    if (check && apply) {
      usageException('Cannot use --check and --apply together.');
    }

    final versionStr = argResults!.option('language-version');
    Version? languageVersion;
    if (versionStr != null) {
      try {
        languageVersion = Version.parse('$versionStr.0');
      } on FormatException {
        usageException('Invalid language version: "$versionStr".');
      }
    }

    final formatter = SnippetFormatter(languageVersion: languageVersion);
    final mdProcessor = MarkdownProcessor(formatter);
    final docProcessor = DocCommentProcessor(formatter);

    final files = _collectFiles(rest.first);
    var formattedCount = 0;
    var unchangedCount = 0;
    var errorCount = 0;

    for (final file in files) {
      final content = file.readAsStringSync();
      final ext = p.extension(file.path);

      final result = switch (ext) {
        '.md' => mdProcessor.process(content, path: file.path),
        '.dart' => docProcessor.process(content, path: file.path),
        _ => null,
      };

      if (result == null) continue;

      for (final snippet in result.snippets) {
        if (snippet is SnippetError) {
          stderr.writeln(
            '${file.path}:${snippet.startLine}: ${snippet.message}',
          );
          errorCount++;
        }
      }

      if (result.changed) {
        formattedCount++;
        if (apply) {
          file.writeAsStringSync(result.output);
          stdout.writeln('  formatted: ${file.path}');
        } else if (check) {
          stdout.writeln('  needs formatting: ${file.path}');
        } else {
          stdout.writeln('  would format: ${file.path}');
        }
      } else {
        unchangedCount++;
      }
    }

    // Summary line.
    final total = formattedCount + unchangedCount;
    final parts = <String>[
      '$total file(s) scanned',
      '$formattedCount need formatting',
      if (errorCount > 0) '$errorCount error(s)',
    ];
    stdout.writeln(parts.join(', '));

    if (check && formattedCount > 0) return 1;
    return 0;
  }

  List<File> _collectFiles(String target) {
    final type = FileSystemEntity.typeSync(target);

    if (type == FileSystemEntityType.file) {
      return [File(target)];
    }

    if (type == FileSystemEntityType.directory) {
      final files = <File>[];
      for (final pattern in ['**.md', '**.dart']) {
        final glob = Glob(pattern);
        files.addAll(
          glob
              .listSync(root: target)
              .whereType<File>()
              .where(
                (f) => !p
                    .split(f.path)
                    .any((s) => s.startsWith('.') && s != '.' && s != '..'),
              ),
        );
      }
      return files;
    }

    stderr.writeln('Not a file or directory: $target');
    return [];
  }
}
