// Copyright 2026 The Flutter Authors.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

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

  /// Error message encountered while parsing the document heading, if any.
  final String? headingError;

  const RfcFile._({
    required this.path,
    required this.category,
    required this.index,
    required this.slug,
    required this.hasFrontmatter,
    required this.frontmatterRaw,
    required this.frontmatter,
    required this.frontmatterError,
    required this.frontmatterErrors,
    required this.body,
    required this.firstHeading,
    required this.firstHeadingId,
    required this.firstHeadingTitle,
    required this.firstHeadingLine,
    required this.headingError,
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

  /// Whether the document has a valid first level-1 heading.
  bool get hasValidHeading =>
      headingError == null && firstHeading != null && firstHeadingId != null;

  /// Extracts category, index, and slug from an RFC file path.
  static ({String? category, int? index, String? slug}) _parseFilename(
    String path,
  ) {
    final fileName = p.basename(path);
    final fnMatch = filenamePattern.firstMatch(fileName);
    final category = fnMatch?.group(1);
    final indexStr = fnMatch?.group(2);
    final index = indexStr != null ? int.tryParse(indexStr) : null;
    final slug = fnMatch?.group(3);
    return (category: category, index: index, slug: slug);
  }

  /// Separates YAML frontmatter block from markdown body.
  static ({
    bool hasFrontmatter,
    String frontmatterRaw,
    String body,
    int frontmatterLineCount,
    String? structuralError,
  })
  _splitFrontmatter(String content) {
    final lines = [...LineSplitter.split(content)];
    if (lines.isEmpty || lines.first.trim() != '---') {
      return (
        hasFrontmatter: false,
        frontmatterRaw: '',
        body: content,
        frontmatterLineCount: 0,
        structuralError:
            'Line 1: File does not start with YAML frontmatter delimiter `---`.',
      );
    }

    int closingLine = -1;
    for (int i = 1; i < lines.length; i++) {
      if (lines[i].trim() == '---') {
        closingLine = i;
        break;
      }
    }

    if (closingLine == -1) {
      return (
        hasFrontmatter: false,
        frontmatterRaw: '',
        body: content,
        frontmatterLineCount: 0,
        structuralError:
            'Line 1: Unclosed YAML frontmatter delimiter (missing closing `---`).',
      );
    }

    return (
      hasFrontmatter: true,
      frontmatterRaw: lines.sublist(1, closingLine).join('\n'),
      body: lines.sublist(closingLine + 1).join('\n'),
      frontmatterLineCount: closingLine + 1,
      structuralError: null,
    );
  }

  /// Parses and validates YAML frontmatter content.
  static ({RfcFrontmatter? frontmatter, String? error, List<String> errors})
  _parseFrontmatter(String frontmatterRaw) {
    try {
      final loaded = loadYaml(frontmatterRaw);
      switch (loaded) {
        case final YamlMap map:
          final loadResult = RfcFrontmatter.tryLoad(map);
          return (
            frontmatter: loadResult.frontmatter,
            error: null,
            errors: loadResult.errors,
          );
        case null:
          final empty = YamlMap();
          return (
            frontmatter: null,
            error: null,
            errors: RfcFrontmatter.validate(empty),
          );
        default:
          const err = 'Line 2: YAML frontmatter must be a key-value mapping.';
          return (frontmatter: null, error: err, errors: [err]);
      }
    } catch (e) {
      final err = switch (e) {
        YamlException(:final span?, :final message) =>
          'Line ${span.start.line + 2}: Failed to parse YAML frontmatter: $message',
        _ => 'Line 2: Failed to parse YAML frontmatter: $e',
      };
      return (frontmatter: null, error: err, errors: [err]);
    }
  }

  /// Locates and parses the first level-1 heading on the first non-empty line of the markdown body.
  static ({
    String? heading,
    String? id,
    String? title,
    int? line,
    String? error,
  })
  _findFirstHeading(
    String body,
    int frontmatterLineCount, {
    String? expectedId,
    String? expectedTitle,
  }) {
    final idPart = expectedId ?? 'AAA.NNNN';
    final titlePart = (expectedTitle != null && expectedTitle.trim().isNotEmpty)
        ? expectedTitle.trim()
        : '<Title>';
    final expectedFormat = '# RFC $idPart: $titlePart';

    int lineOffset = 0;
    for (final rawLine in LineSplitter.split(body)) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        lineOffset++;
        continue;
      }
      final lineNum = frontmatterLineCount + lineOffset + 1;
      if (line.startsWith('# ')) {
        final headingMatch = headingPattern.firstMatch(line);
        return (
          heading: line,
          id: headingMatch?.group(1),
          title: headingMatch?.group(2)?.trim() ?? '',
          line: lineNum,
          error: headingMatch == null
              ? 'Line $lineNum: Heading must match format "$expectedFormat".'
              : null,
        );
      }
      return (
        heading: null,
        id: null,
        title: null,
        line: lineNum,
        error: line.startsWith('#')
            ? 'Line $lineNum: First heading must be a level-1 heading (`# ...`), but found a deeper heading level.'
            : 'Line $lineNum: Markdown body must begin with a level-1 heading (`$expectedFormat`).',
      );
    }
    final lineNum = frontmatterLineCount + 1;
    return (
      heading: null,
      id: null,
      title: null,
      line: lineNum,
      error:
          'Line $lineNum: Markdown body must begin with a level-1 heading (`$expectedFormat`).',
    );
  }

  /// Converts a kebab-case slug into Title Case (e.g. `extract-value-notifier` -> `Extract Value Notifier`).
  static String _slugToTitle(String slug) {
    return slug
        .split('-')
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  /// Parses an RFC markdown file content.
  static RfcFile parse(String content, {required String path}) {
    final (:category, :index, :slug) = _parseFilename(path);
    final expectedId = category != null && index != null
        ? '$category.${index.toNNNN()}'
        : null;

    final split = _splitFrontmatter(content);
    final parsedFm = split.hasFrontmatter
        ? _parseFrontmatter(split.frontmatterRaw)
        : (
            frontmatter: null,
            error: split.structuralError,
            errors: [if (split.structuralError != null) split.structuralError!],
          );

    final rawTitle = parsedFm.frontmatter?.title;
    final expectedTitle = (rawTitle != null && rawTitle.trim().isNotEmpty)
        ? rawTitle.trim()
        : (slug != null ? _slugToTitle(slug) : null);

    final heading = _findFirstHeading(
      split.body,
      split.frontmatterLineCount,
      expectedId: expectedId,
      expectedTitle: expectedTitle,
    );

    return RfcFile._(
      path: path,
      category: category,
      index: index,
      slug: slug,
      hasFrontmatter: split.hasFrontmatter,
      frontmatterRaw: split.frontmatterRaw,
      frontmatter: parsedFm.frontmatter,
      frontmatterError: parsedFm.error,
      frontmatterErrors: List.unmodifiable(parsedFm.errors),
      body: split.body,
      firstHeading: heading.heading,
      firstHeadingId: heading.id,
      firstHeadingTitle: heading.title,
      firstHeadingLine: heading.line,
      headingError: heading.error,
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

    final newId = '$newCategoryStr.$newIndexStr';
    final timestamp = (updatedTime ?? clock.now()).toUtc().toIso8601String();

    // Update frontmatter lines
    final fmLines = <String>[];
    bool rfcReplaced = false;
    bool updatedReplaced = false;

    for (final line in LineSplitter.split(frontmatterRaw)) {
      if (RegExp(r'^rfc:\s*.*$').hasMatch(line)) {
        fmLines.add("rfc: '$newId'");
        rfcReplaced = true;
      } else if (RegExp(r'^updated:\s*.*$').hasMatch(line)) {
        fmLines.add('updated: $timestamp');
        updatedReplaced = true;
      } else {
        fmLines.add(line);
      }
    }

    if (!rfcReplaced) {
      fmLines.insert(0, "rfc: '$newId'");
    }
    if (!updatedReplaced) {
      fmLines.add('updated: $timestamp');
    }

    final newFrontmatterRaw = fmLines.join('\n');

    // Update first level-1 heading in body
    final bodyLines = <String>[];
    bool headingReplaced = false;

    for (final line in LineSplitter.split(body)) {
      if (!headingReplaced) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty) {
          final match = headingPattern.firstMatch(trimmed);
          if (match != null) {
            final title = match.group(2)?.trim() ?? '';
            bodyLines.add(
              title.isNotEmpty ? '# RFC $newId: $title' : '# RFC $newId',
            );
            headingReplaced = true;
            continue;
          }
        }
      }
      bodyLines.add(line);
    }

    final newBody = bodyLines.join('\n');
    return '---\n$newFrontmatterRaw\n---\n$newBody';
  }
}
