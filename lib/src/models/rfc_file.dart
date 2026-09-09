// Copyright 2026 The Flutter Authors.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

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

  /// All validation error messages encountered while parsing frontmatter.
  final List<FrontmatterError> frontmatterErrors;

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
    multiLine: true,
  );

  /// Regular expression to match the yaml frontmatter.
  static final RegExp frontMatterPattern = RegExp(
    r'^---\r?\n(.*?)\r?\n---(?:\r?\n|$)',
    dotAll: true,
  );

  /// Regular expression to match an existing `rfc:` key in frontmatter.
  static final RegExp _rfcFrontmatterPattern = RegExp(
    r'^rfc:\s*.*$',
    multiLine: true,
  );

  /// Regular expression to match an existing `updated:` key in frontmatter.
  static final RegExp _updatedFrontmatterPattern = RegExp(
    r'^updated:\s*.*$',
    multiLine: true,
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
      hasFrontmatter && frontmatterErrors.isEmpty && frontmatter != null;

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
    FrontmatterError? structuralError,
  })
  _splitFrontmatter(String content) {
    final match = frontMatterPattern.firstMatch(content);
    if (match == null) {
      final hasOpening = content.startsWith('---');
      return (
        hasFrontmatter: false,
        frontmatterRaw: '',
        body: content,
        frontmatterLineCount: 0,
        structuralError: (
          line: 1,
          error: hasOpening
              ? 'Unclosed YAML frontmatter delimiter (missing closing `---`).'
              : 'File does not start with YAML frontmatter delimiter `---`.',
        ),
      );
    }

    final lineCount = '\n'.allMatches(content.substring(0, match.end)).length;

    return (
      hasFrontmatter: true,
      frontmatterRaw: match.group(1)!,
      body: content.substring(match.end),
      frontmatterLineCount: lineCount,
      structuralError: null,
    );
  }

  /// Parses and validates YAML frontmatter content.
  static ({RfcFrontmatter? frontmatter, List<FrontmatterError> errors})
  _parseFrontmatter(String frontmatterRaw) {
    try {
      final loaded = loadYaml(frontmatterRaw);
      switch (loaded) {
        case final YamlMap map:
          final loadResult = RfcFrontmatter.tryLoad(map);
          return (
            frontmatter: loadResult.frontmatter,
            errors: loadResult.errors,
          );
        case null:
          final empty = YamlMap();
          return (frontmatter: null, errors: RfcFrontmatter.validate(empty));
        default:
          const err = (
            line: 2,
            error: 'YAML frontmatter must be a key-value mapping.',
          );
          return (frontmatter: null, errors: [err]);
      }
    } on YamlException catch (e) {
      final line = (e.span?.start.line ?? 0) + 2;
      final error = (
        line: line,
        error: 'Failed to parse YAML frontmatter: ${e.message}',
      );

      return (frontmatter: null, errors: [error]);
    } catch (e) {
      return (
        frontmatter: null,
        errors: [(line: 2, error: 'Failed to parse YAML frontmatter: $e')],
      );
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

    final match = headingPattern.firstMatch(body);
    if (match == null || body.substring(0, match.start).trim().isNotEmpty) {
      final line = frontmatterLineCount + 1;
      return (
        heading: null,
        id: null,
        title: null,
        line: line,
        error:
            'Line $line: Markdown body must begin with a level-1 heading (`$expectedFormat`).',
      );
    }
    final lineNumber =
        frontmatterLineCount +
        '\n'.allMatches(body.substring(0, match.start)).length +
        1;
    return (
      heading: body.substring(match.start, match.end),
      id: match.group(1),
      title: match.group(2)?.trim() ?? '',
      line: lineNumber,
      error: null,
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
    required String newCategory,
    required int newIndex,
    DateTime? updatedTime,
  }) {
    if (!RegExp(r'^\d{3}$').hasMatch(newCategory)) {
      throw ArgumentError(
        'newCategory must be a 3-digit string, got "$newCategory"',
      );
    }

    if (newIndex < 0 || newIndex > 9999) {
      throw ArgumentError('newIndex must be between 0 and 9999, got $newIndex');
    }
    final newId = '$newCategory.${newIndex.toNNNN()}';
    final timestamp = (updatedTime ?? clock.now()).toUtc().toIso8601String();

    // Update frontmatter lines
    String newFrontmatterRaw = frontmatterRaw;

    if (_rfcFrontmatterPattern.hasMatch(newFrontmatterRaw)) {
      newFrontmatterRaw = newFrontmatterRaw.replaceFirst(
        _rfcFrontmatterPattern,
        "rfc: '$newId'",
      );
    } else {
      newFrontmatterRaw = "rfc: '$newId'\n$newFrontmatterRaw";
    }

    if (_updatedFrontmatterPattern.hasMatch(newFrontmatterRaw)) {
      newFrontmatterRaw = newFrontmatterRaw.replaceFirst(
        _updatedFrontmatterPattern,
        'updated: $timestamp',
      );
    } else {
      newFrontmatterRaw = '$newFrontmatterRaw\nupdated: $timestamp';
    }
    newFrontmatterRaw = newFrontmatterRaw.trim();

    // Update first level-1 heading in body
    String newBody = body;
    final headingResult = _findFirstHeading(newBody, 0);
    if (headingResult.heading != null) {
      final title = headingResult.title ?? '';
      final newHeading = title.isNotEmpty
          ? '# RFC $newId: $title'
          : '# RFC $newId';
      newBody = newBody.replaceFirst(headingResult.heading!, newHeading);
    }

    return '---\n$newFrontmatterRaw\n---\n$newBody';
  }
}
