import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:path/path.dart' as p;
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
            'Check formatting without writing changes. Exits with code 1 if files need formatting.',
      )
      ..addFlag('apply', help: 'Write formatted content back to files.');
  }

  @override
  String get name => 'format';

  @override
  String get description =>
      'Format Dart code snippets in Markdown files and doc comments.';

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

    final formatter = SnippetFormatter();
    final mdProcessor = MarkdownProcessor(formatter);
    final docProcessor = DocCommentProcessor(formatter);

    final files = _collectFiles(rest.first);
    var needsFormatting = false;
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
        needsFormatting = true;
        if (apply) {
          file.writeAsStringSync(result.output);
          stdout.writeln('Formatted ${file.path}');
        } else if (check) {
          stdout.writeln('Needs formatting: ${file.path}');
        } else {
          stdout.writeln('Would format: ${file.path}');
        }
      }
    }

    if (errorCount > 0) {
      stderr.writeln('$errorCount snippet(s) had errors.');
    }

    if (check && needsFormatting) return 1;
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
              .where((f) => !p.split(f.path).any((s) => s.startsWith('.'))),
        );
      }
      return files;
    }

    stderr.writeln('Not a file or directory: $target');
    return [];
  }
}
