import 'package:snip/snip.dart';
import 'package:test/test.dart';

void main() {
  group('SnippetFormatter', () {
    late SnippetFormatter formatter;

    setUp(() {
      formatter = SnippetFormatter();
    });

    test('formats a full compilation unit', () {
      final result = formatter.format('void main( ) { print("hi"); }\n');
      expect(result, contains('void main()'));
    });

    test('formats a statement fragment via wrapping', () {
      final result = formatter.format('var   x=1;\n');
      expect(result.trim(), equals('var x = 1;'));
    });

    test('throws FormatException on invalid code', () {
      expect(() => formatter.format('}{invalid{{\n'), throwsFormatException);
    });
  });

  group('MarkdownProcessor', () {
    late MarkdownProcessor processor;

    setUp(() {
      processor = MarkdownProcessor(SnippetFormatter());
    });

    test('formats a dart code block', () {
      final input = '''
# Example

```dart
void main( ){print("hello");}
```

Some text.
''';
      final result = processor.process(input, path: 'test.md');
      expect(result.changed, isTrue);
      expect(result.output, contains('void main()'));
      expect(result.output, contains('# Example'));
      expect(result.output, contains('Some text.'));
    });

    test('preserves non-dart code blocks', () {
      final input = '''
```yaml
key: value
```
''';
      final result = processor.process(input, path: 'test.md');
      expect(result.changed, isFalse);
      expect(result.output, equals(input));
    });

    test('handles indented code blocks', () {
      final input = '''
- item:

  ```dart
  var   x=1;
  ```
''';
      final result = processor.process(input, path: 'test.md');
      expect(result.changed, isTrue);
      expect(result.output, contains('  var x = 1;'));
      expect(result.output, contains('  ```dart'));
    });

    test('preserves already-formatted code', () {
      final input = '''
```dart
var x = 1;
```
''';
      final result = processor.process(input, path: 'test.md');
      expect(result.changed, isFalse);
    });

    test('handles multiple code blocks', () {
      final input = '''
```dart
var  x=1;
```

```dart
var  y=2;
```
''';
      final result = processor.process(input, path: 'test.md');
      expect(result.snippets, hasLength(2));
      expect(result.changed, isTrue);
    });
  });

  group('DocCommentProcessor', () {
    late DocCommentProcessor processor;

    setUp(() {
      processor = DocCommentProcessor(SnippetFormatter());
    });

    test('formats dart code in doc comments', () {
      final input = '''
/// Example:
///
/// ```dart
/// void main( ){print("hello");}
/// ```
void foo() {}
''';
      final result = processor.process(input, path: 'test.dart');
      expect(result.changed, isTrue);
      expect(result.output, contains('/// void main()'));
      expect(result.output, contains('void foo() {}'));
    });

    test('preserves non-dart doc blocks', () {
      final input = '''
/// Example:
///
/// ```
/// some output
/// ```
void foo() {}
''';
      final result = processor.process(input, path: 'test.dart');
      expect(result.changed, isFalse);
      expect(result.output, equals(input));
    });
  });
}
