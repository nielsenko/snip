# snip

A CLI tool that formats Dart code snippets embedded in Markdown files and Dart doc comments.

## Install

```sh
dart install snip
```

## Usage

```sh
# Dry run — show what would change
snip format .

# Check formatting (exit code 1 if files need formatting)
snip format --check .

# Apply formatting
snip format --apply .

# Format a single file
snip format --apply README.md
```

### Options

```
-h, --help                              Print this usage information.
    --[no-]check                        Check if files need formatting (exit code 1 if so). Does not write.
    --[no-]apply                        Write formatted content back to files.
    --language-version=<major.minor>    Dart language version for formatting (e.g. "3.10").
-l, --line-length=<columns>             Target line length (default: 80).
    --[no-]preserve-trailing-commas     Preserve existing trailing commas (force splits).
```

## How it works

Snippets in documentation are often fragments, not full compilation units. snip uses a **harness strategy** to handle this:

1. **Attempt 1:** Format as a standalone compilation unit.
2. **Attempt 2:** Wrap in a function body, format, then strip the wrapper.
3. **Fallback:** Report the error with file path and line number, preserve the original code.

### Supported sources

- **Markdown files** (`.md`): `` ```dart `` fenced code blocks, including indented blocks.
- **Dart files** (`.dart`): `` ```dart `` blocks inside `///` doc comments. Uses a recursive-descent scanner to correctly ignore `///` inside strings and block comments.
