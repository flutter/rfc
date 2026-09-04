// Copyright 2026 The Flutter Authors.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:clock/clock.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'rfc_author.dart';
import 'rfc_frontmatter.dart';

export 'rfc_author.dart';
export 'rfc_frontmatter.dart';

/// Formatting extensions for RFC category and index numbers.
extension RfcNumberFormatting on int {
  /// Formats this integer as a 4-digit zero-padded RFC index string (e.g. `1.toNNNN()` -> `"0001"`, `0.toNNNN()` -> `"0000"`).
  String toNNNN() => toString().padLeft(4, '0');

  /// Formats this integer as a 3-digit zero-padded RFC category string (e.g. `0.toAAA()` -> `"000"`, `110.toAAA()` -> `"110"`).
  String toAAA() => toString().padLeft(3, '0');
}

/// Represents a parsed RFC markdown file.
class RfcFile {
  /// File path.
  final String path;

  /// 3-digit category (e.g. "000", "110"), or null if filename is invalid.
  final String? category;

  /// Numerical category of the RFC (e.g. 0 for "000", 110 for "110"), or null if filename is invalid.
  int? get categoryNumber => category != null ? int.tryParse(category!) : null;

  /// Numerical index of the RFC (e.g. 1 for "0001", 0 for "0000"), or null if filename is invalid.
  final int? index;

  /// 4-digit zero-padded index string (e.g. "0001", "0000"), or null if filename is invalid.
  String? get indexString => index?.toNNNN();

  /// Slugified title in lowercase kebab-case, or null if filename is invalid.
  final String? slug;

  /// Whether the file starts with and successfully parses YAML frontmatter.
  final bool hasFrontmatter;

  /// Raw frontmatter content between the leading and closing `---` delimiters.
  final String frontmatterRaw;

  /// Parsed strongly-typed RFC frontmatter, or null if missing or invalid schema.
  final RfcFrontmatter? frontmatter;

  /// Underlying raw YamlMap, or null if missing or invalid YAML syntax.
  final YamlMap? rawYamlFrontmatter;

  /// Structural or syntax error message encountered while parsing frontmatter
  /// (e.g. unclosed delimiter or invalid YAML syntax), if any.
  ///
  /// For schema validation errors on frontmatter fields, see [frontmatterErrors]
  /// and [frontmatterFeedback].
  final String? frontmatterError;

  /// All validation error messages encountered while parsing frontmatter.
  final List<String> frontmatterErrors;

  /// Markdown content after the closing `---` delimiter.
  final String body;

  /// Full text of the first level-1 heading (`# RFC AAA.NNNN: <Title>`).
  final String? firstHeading;

  /// RFC identifier extracted from the first level-1 heading.
  final String? firstHeadingId;

  /// Title extracted from the first level-1 heading.
  final String? firstHeadingTitle;

  /// Line number (1-based) where the first level-1 heading was found in the file.
  final int? firstHeadingLine;

  /// Line ending detected from the original file content (`\r\n` or `\n`).
  final String lineEnding;

  const RfcFile._({
    required this.path,
    required this.category,
    required this.index,
    required this.slug,
    required this.hasFrontmatter,
    required this.frontmatterRaw,
    required this.frontmatter,
    required this.rawYamlFrontmatter,
    required this.frontmatterError,
    required this.frontmatterErrors,
    required this.body,
    required this.firstHeading,
    required this.firstHeadingId,
    required this.firstHeadingTitle,
    required this.firstHeadingLine,
    required this.lineEnding,
  });

  /// Regular expression for RFC filenames: `AAA.NNNN-<slug>.md`.
  static final RegExp filenamePattern = RegExp(
    r'^(\d{3})\.(\d{4})-([a-z0-9]+(?:-[a-z0-9]+)*)\.md$',
  );

  /// Regular expression for first level-1 RFC heading: `# RFC AAA.NNNN: <Title>`.
  static final RegExp headingPattern = RegExp(
    r'^#\s+RFC\s+(\d{3}\.\d{4})(?::\s*(.*))?$',
  );

  /// Whether the file name conforms to `AAA.NNNN-<slug>.md`.
  bool get hasValidFilename =>
      category != null && index != null && slug != null;

  /// Whether this file is a draft RFC (`.0000`).
  bool get isDraft => index == 0;

  /// The combined RFC identifier (e.g. "000.0001"), or null if filename is invalid.
  String? get rfcId => hasValidFilename ? '$category.${index!.toNNNN()}' : null;

  /// Formatted feedback containing all frontmatter errors and the expected schema template,
  /// or null if frontmatter has no errors.
  String? get frontmatterFeedback => frontmatterErrors.isNotEmpty
      ? RfcFrontmatter.formatErrors(frontmatterErrors)
      : null;

  /// Whether frontmatter conforms completely to the RFC schema.
  bool get hasValidFrontmatter =>
      hasFrontmatter &&
      frontmatterError == null &&
      frontmatterErrors.isEmpty &&
      frontmatter != null;

  /// Frontmatter `type` field value.
  String? get frontmatterType =>
      frontmatter?.type ?? rawYamlFrontmatter?['type']?.toString();

  /// Frontmatter `rfc` field value.
  String? get frontmatterRfc =>
      frontmatter?.rfc ?? rawYamlFrontmatter?['rfc']?.toString();

  /// Frontmatter `title` field value.
  String? get frontmatterTitle =>
      frontmatter?.title ?? rawYamlFrontmatter?['title']?.toString();

  /// Frontmatter `description` field value.
  String? get frontmatterDescription =>
      frontmatter?.description ??
      rawYamlFrontmatter?['description']?.toString();

  /// Frontmatter `status` field value.
  String? get frontmatterStatus =>
      frontmatter?.status.value ?? rawYamlFrontmatter?['status']?.toString();

  /// Frontmatter `tags` list.
  List<String>? get frontmatterTags {
    if (frontmatter != null) return frontmatter!.tags;
    final val = rawYamlFrontmatter?['tags'];
    if (val is List) {
      return [...val.map((e) => '$e')];
    }
    return null;
  }

  /// Frontmatter `authors` list as strings.
  List<String>? get frontmatterAuthors {
    if (frontmatter != null) {
      return frontmatter!.authors.map((a) => a.raw).toList();
    }
    final val = rawYamlFrontmatter?['authors'];
    if (val is List) {
      return [...val.map((e) => '$e')];
    }
    return null;
  }

  /// Frontmatter `supersedes` field value.
  String? get frontmatterSupersedes =>
      frontmatter?.supersedes ?? rawYamlFrontmatter?['supersedes']?.toString();

  /// Frontmatter `superseded_by` field value.
  String? get frontmatterSupersededBy =>
      frontmatter?.supersededBy ??
      rawYamlFrontmatter?['superseded_by']?.toString();

  /// Strongly-typed frontmatter `authors` list.
  List<RfcAuthor>? get authors => frontmatter?.authors;

  /// Parses an RFC markdown file content.
  static RfcFile parse(String content, {required String path}) {
    final fileName = p.basename(path);
    final fnMatch = filenamePattern.firstMatch(fileName);
    final category = fnMatch?.group(1);
    final indexStr = fnMatch?.group(2);
    final index = indexStr != null ? int.tryParse(indexStr) : null;
    final slug = fnMatch?.group(3);

    // Parse frontmatter
    final isCrlf = content.contains('\r\n');
    final lineEnding = isCrlf ? '\r\n' : '\n';

    bool hasFrontmatter = false;
    String frontmatterRaw = '';
    RfcFrontmatter? frontmatter;
    YamlMap? rawYamlFrontmatter;
    String? frontmatterError;
    final frontmatterErrors = <String>[];
    String body = content;
    int frontmatterLineCount = 0;

    final lines = content.split(RegExp(r'\r?\n'));
    if (lines.isNotEmpty && lines.first.trim() == '---') {
      int closingLine = -1;
      for (int i = 1; i < lines.length; i++) {
        if (lines[i].trim() == '---') {
          closingLine = i;
          break;
        }
      }
      if (closingLine != -1) {
        hasFrontmatter = true;
        frontmatterRaw = lines.sublist(1, closingLine).join(lineEnding);
        body = lines.sublist(closingLine + 1).join(lineEnding);
        frontmatterLineCount = closingLine + 1;

        try {
          final loaded = loadYaml(frontmatterRaw);
          if (loaded is YamlMap) {
            rawYamlFrontmatter = loaded;
            final loadResult = RfcFrontmatter.tryLoad(loaded);
            if (loadResult.frontmatter != null) {
              frontmatter = loadResult.frontmatter;
            } else {
              frontmatterErrors.addAll(loadResult.errors);
            }
          } else if (loaded == null) {
            rawYamlFrontmatter = YamlMap();
            frontmatterErrors.addAll(
              RfcFrontmatter.validate(rawYamlFrontmatter),
            );
          } else {
            frontmatterError = 'YAML frontmatter must be a key-value mapping.';
            frontmatterErrors.add(frontmatterError);
          }
        } catch (e) {
          frontmatterError = 'Failed to parse YAML frontmatter: $e';
          frontmatterErrors.add(frontmatterError);
        }
      } else {
        frontmatterError =
            'Unclosed YAML frontmatter delimiter (missing closing `---`).';
        frontmatterErrors.add(frontmatterError);
      }
    } else {
      frontmatterError =
          'File does not start with YAML frontmatter delimiter `---`.';
      frontmatterErrors.add(frontmatterError);
    }

    // Find first level-1 heading outside of code fences
    String? firstHeading;
    String? firstHeadingId;
    String? firstHeadingTitle;
    int? firstHeadingLine;

    final bodyLines = body.split(isCrlf ? '\r\n' : '\n');
    bool inCodeBlock = false;
    for (int i = 0; i < bodyLines.length; i++) {
      final line = bodyLines[i].trim();
      if (line.startsWith('```')) {
        inCodeBlock = !inCodeBlock;
        continue;
      }
      if (!inCodeBlock && line.startsWith('# ')) {
        final headingMatch = headingPattern.firstMatch(line);
        firstHeading = line;
        firstHeadingLine = frontmatterLineCount + i + 1;
        if (headingMatch != null) {
          firstHeadingId = headingMatch.group(1);
          firstHeadingTitle = headingMatch.group(2)?.trim() ?? '';
        }
        break; // Only the first level-1 heading
      }
    }

    return RfcFile._(
      path: path,
      category: category,
      index: index,
      slug: slug,
      hasFrontmatter: hasFrontmatter,
      frontmatterRaw: frontmatterRaw,
      frontmatter: frontmatter,
      rawYamlFrontmatter: rawYamlFrontmatter,
      frontmatterError: frontmatterError,
      frontmatterErrors: List.unmodifiable(frontmatterErrors),
      body: body,
      firstHeading: firstHeading,
      firstHeadingId: firstHeadingId,
      firstHeadingTitle: firstHeadingTitle,
      firstHeadingLine: firstHeadingLine,
      lineEnding: lineEnding,
    );
  }

  /// Generates transformed file content with updated category, index, and timestamp.
  ///
  /// Preserves all other frontmatter fields (such as `status: draft`, comments, formatting)
  /// and updates the first level-1 heading without corrupting code blocks or body text.
  String transformedContent({
    required Object newCategory,
    required Object newIndex,
    DateTime? updatedTime,
  }) {
    final String newCategoryStr;
    if (newCategory is int) {
      if (newCategory < 0 || newCategory > 999) {
        throw ArgumentError(
          'newCategory must be between 0 and 999, got $newCategory',
        );
      }
      newCategoryStr = newCategory.toAAA();
    } else if (newCategory is String) {
      if (!RegExp(r'^\d{3}$').hasMatch(newCategory)) {
        throw ArgumentError(
          'newCategory must be a 3-digit string, got "$newCategory"',
        );
      }
      newCategoryStr = newCategory;
    } else {
      throw ArgumentError(
        'newCategory must be an int or a 3-digit String, got ${newCategory.runtimeType}',
      );
    }

    final String newIndexStr;
    if (newIndex is int) {
      if (newIndex < 0 || newIndex > 9999) {
        throw ArgumentError(
          'newIndex must be between 0 and 9999, got $newIndex',
        );
      }
      newIndexStr = newIndex.toNNNN();
    } else if (newIndex is String) {
      if (!RegExp(r'^\d{4}$').hasMatch(newIndex)) {
        throw ArgumentError(
          'newIndex must be a 4-digit zero-padded string, got "$newIndex"',
        );
      }
      newIndexStr = newIndex;
    } else {
      throw ArgumentError(
        'newIndex must be an int or a 4-digit String, got ${newIndex.runtimeType}',
      );
    }

    final nl = lineEnding;
    final newId = '$newCategoryStr.$newIndexStr';

    final timestamp = (updatedTime ?? clock.now()).toUtc().toIso8601String();

    // Update frontmatter lines
    final fmLines = frontmatterRaw.split(RegExp(r'\r?\n'));
    bool rfcReplaced = false;
    bool updatedReplaced = false;

    for (int i = 0; i < fmLines.length; i++) {
      final line = fmLines[i];
      if (RegExp(r'^rfc:\s*.*$').hasMatch(line)) {
        fmLines[i] = "rfc: '$newId'";
        rfcReplaced = true;
      } else if (RegExp(r'^updated:\s*.*$').hasMatch(line)) {
        fmLines[i] = 'updated: $timestamp';
        updatedReplaced = true;
      }
    }

    if (!rfcReplaced) {
      fmLines.insert(0, "rfc: '$newId'");
    }
    if (!updatedReplaced) {
      fmLines.add('updated: $timestamp');
    }

    final newFrontmatterRaw = fmLines.join(nl);

    // Update first level-1 heading in body, strictly outside of code blocks
    final bodyLines = body.split(RegExp(r'\r?\n'));
    bool inCodeBlock = false;
    bool headingReplaced = false;

    for (int i = 0; i < bodyLines.length; i++) {
      final line = bodyLines[i];
      final trimmed = line.trim();
      if (trimmed.startsWith('```')) {
        inCodeBlock = !inCodeBlock;
        continue;
      }
      if (!inCodeBlock && !headingReplaced) {
        final match = headingPattern.firstMatch(trimmed);
        if (match != null) {
          final title = match.group(2)?.trim() ?? '';
          bodyLines[i] = title.isNotEmpty
              ? '# RFC $newId: $title'
              : '# RFC $newId';
          headingReplaced = true;
          break;
        }
      }
    }

    final newBody = bodyLines.join(nl);
    return '---$nl$newFrontmatterRaw$nl---$nl$newBody';
  }
}
