// Copyright 2026 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:clock/clock.dart';
import 'package:yaml/yaml.dart';

import 'rfc_author.dart';

/// RFC document lifecycle status.
enum RfcStatus {
  draft('draft'),
  review('review'),
  stable('stable'),
  superseded('superseded'),
  withdrawn('withdrawn'),
  rejected('rejected'),
  deprecated('deprecated');

  final String value;
  const RfcStatus(this.value);

  /// Parses an RFC status string case-insensitively, or returns `null` if invalid.
  static RfcStatus? tryParse(String? value) =>
      switch (value?.toLowerCase().trim()) {
        'draft' => RfcStatus.draft,
        'review' => RfcStatus.review,
        'stable' => RfcStatus.stable,
        'superseded' => RfcStatus.superseded,
        'withdrawn' => RfcStatus.withdrawn,
        'rejected' => RfcStatus.rejected,
        'deprecated' => RfcStatus.deprecated,
        _ => null,
      };

  @override
  String toString() => value;
}

/// Strongly-typed model representing validated YAML frontmatter of an RFC.
class RfcFrontmatter {
  /// Document type. Must be `'rfc'`.
  final String type;

  /// RFC identifier (e.g. `'000.0001'`).
  final String rfc;

  /// Proposal title.
  final String title;

  /// High-level summary description.
  final String description;

  /// Lifecycle status.
  final RfcStatus status;

  /// ISO 8601 UTC creation timestamp.
  final DateTime created;

  /// ISO 8601 UTC last updated timestamp.
  final DateTime updated;

  /// Taxonomy and category tags.
  final List<String> tags;

  /// List of typed author attributions.
  final List<RfcAuthor> authors;

  /// Optional identifier of the RFC this document supersedes (e.g. `'000.0001'`).
  final String? supersedes;

  /// Optional identifier of the RFC that supersedes this document (e.g. `'000.0002'`).
  final String? supersededBy;

  const RfcFrontmatter({
    required this.type,
    required this.rfc,
    required this.title,
    required this.description,
    required this.status,
    required this.created,
    required this.updated,
    required this.tags,
    required this.authors,
    this.supersedes,
    this.supersededBy,
  });

  /// ISO 8601 UTC string representation of [created].
  String get createdIso => created.toUtc().toIso8601String();

  /// ISO 8601 UTC string representation of [updated].
  String get updatedIso => updated.toUtc().toIso8601String();

  /// Canonical expected frontmatter schema template showing all required fields
  /// and common optional fields with format examples.
  static const String expectedSchemaTemplate = '''
type: rfc
rfc: '000.0001'
title: Proposal Title
description: High-level summary description of the RFC proposal.
status: draft
created: 2026-08-27T00:00:00Z
updated: 2026-08-27T00:00:00Z
tags:
  - 000-meta
authors:
  - https://github.com/octocat
  - '"Author Name" <email@example.com>'
# supersedes: '000.0000' # Optional
# superseded_by: '000.0002' # Optional
''';

  /// Canonical example frontmatter template.
  static const String exampleTemplate = expectedSchemaTemplate;

  /// Formats a list of validation [errors] alongside the canonical expected schema template.
  static String formatErrors(List<String> errors, {String? schemaTemplate}) {
    final template = schemaTemplate ?? expectedSchemaTemplate;
    final buffer = StringBuffer('Invalid RFC frontmatter:\n');
    for (final err in errors) {
      buffer.writeln('  - $err');
    }
    buffer.writeln();
    buffer.writeln('Expected frontmatter format:');
    buffer.write(template.trimRight());
    return buffer.toString();
  }

  /// List of valid status string values derived from [RfcStatus.values].
  static List<String> get validStatusStrings => [
    for (var status in RfcStatus.values) status.value,
  ];

  /// Validates a mapping against the RFC frontmatter schema.
  ///
  /// Returns a list of error messages with actionable feedback and expected formats.
  /// An empty list indicates valid frontmatter.
  static List<String> validate(Map<dynamic, dynamic> yaml) {
    final errors = <String>[];

    // 1. type
    switch (yaml['type']) {
      case 'rfc':
        break;
      case final typeVal:
        errors.add(
          'Frontmatter "type" must be "rfc" (found "$typeVal"). Expected format: "type: rfc".',
        );
    }

    // 2. rfc
    switch (yaml['rfc']) {
      case null:
        errors.add(
          'Frontmatter "rfc" field is required. Missing value (found "null"). '
          'Expected format: "AAA.NNNN" (e.g. \'000.0001\' or \'110.0000\').',
        );
      case final rfcVal:
        final rfcStr = '$rfcVal'.trim();
        if (!RegExp(r'^\d{3}\.\d{4}$').hasMatch(rfcStr)) {
          errors.add(
            'Frontmatter "rfc" must match format "AAA.NNNN" (found "$rfcStr"). '
            'Expected format: "AAA.NNNN" (3 digits, dot, 4 digits, e.g. \'000.0001\' or \'110.0000\').',
          );
        }
    }

    // 3. title
    switch (yaml['title']) {
      case null:
        errors.add(
          'Frontmatter "title" is required and must be a non-empty string. '
          'Missing value (found "null"). Expected format: title: Proposal Title.',
        );
      case final String s when s.trim().isEmpty:
        errors.add(
          'Frontmatter "title" is required and must be a non-empty string. '
          'Found empty string. Expected format: title: Proposal Title.',
        );
      case String():
        break;
      case final other:
        errors.add(
          'Frontmatter "title" is required and must be a non-empty string. '
          'Found ${other.runtimeType} "$other". Expected format: title: Proposal Title.',
        );
    }

    // 4. description
    switch (yaml['description']) {
      case null:
        errors.add(
          'Frontmatter "description" is required and must be a non-empty string. '
          'Missing value (found "null"). Expected format: description: High-level summary description.',
        );
      case final String s when s.trim().isEmpty:
        errors.add(
          'Frontmatter "description" is required and must be a non-empty string. '
          'Found empty string. Expected format: description: High-level summary description.',
        );
      case String():
        break;
      case final other:
        errors.add(
          'Frontmatter "description" is required and must be a non-empty string. '
          'Found ${other.runtimeType} "$other". Expected format: description: High-level summary description.',
        );
    }

    // 5. status
    switch (yaml['status']) {
      case null:
        errors.add(
          'Frontmatter "status" must be one of: ${validStatusStrings.join(', ')} (found "null"). '
          'Expected format: status: draft.',
        );
      case final statusVal:
        final statusStr = statusVal.toString().trim();
        final parsedStatus = RfcStatus.tryParse(statusStr);
        if (parsedStatus == null) {
          errors.add(
            'Frontmatter "status" must be one of: ${validStatusStrings.join(', ')} (found "$statusStr"). '
            'Expected format: status: draft.',
          );
        }
    }

    // 6. created
    final createdVal = yaml['created'];
    final createdResult = _parseUtcTimestamp(createdVal, 'created');
    if (createdResult.error != null) {
      errors.add(createdResult.error!);
    }

    // 7. updated
    final updatedVal = yaml['updated'];
    final updatedResult = _parseUtcTimestamp(updatedVal, 'updated');
    if (updatedResult.error != null) {
      errors.add(updatedResult.error!);
    }

    // 8. tags
    switch (yaml['tags']) {
      case null:
        errors.add(
          'Frontmatter "tags" must be a non-empty list of strings. '
          'Missing value (found "null"). Expected format:\ntags:\n  - 000-meta',
        );
      case final List<Object?> list when list.isEmpty:
        errors.add(
          'Frontmatter "tags" must be a non-empty list of strings. '
          'Found empty list. Expected format:\ntags:\n  - 000-meta',
        );
      case final List<Object?> list:
        for (final tag in list) {
          if (tag == null || tag.toString().trim().isEmpty) {
            errors.add(
              'Frontmatter "tags" items must be non-empty strings. Found "$tag". '
              'Expected format: a list of non-empty category/topic strings (e.g. 000-meta).',
            );
            break;
          }
        }
      case final other:
        errors.add(
          'Frontmatter "tags" must be a non-empty list of strings. '
          'Found ${other.runtimeType} "$other". Expected format:\ntags:\n  - 000-meta',
        );
    }

    // 9. authors
    switch (yaml['authors']) {
      case null:
        errors.add(
          'Frontmatter "authors" must be a non-empty list of authors. '
          'Missing value (found "null"). Expected format:\nauthors:\n  - https://github.com/<username>\n  - \'"Display Name" <user@example.com>\'',
        );
      case final List<Object?> list when list.isEmpty:
        errors.add(
          'Frontmatter "authors" must be a non-empty list of authors. '
          'Found empty list. Expected format:\nauthors:\n  - https://github.com/<username>\n  - \'"Display Name" <user@example.com>\'',
        );
      case final List<Object?> list:
        for (final authorItem in list) {
          if (authorItem == null) {
            errors.add(
              'Author entries cannot be null. '
              'Expected format: "https://github.com/<username>" or \'"Display Name" <user@example.com>\'.',
            );
            continue;
          }
          final authorStr = authorItem.toString().trim();
          if (authorStr.isEmpty) {
            errors.add(
              'Author entries cannot be empty. '
              'Expected format: "https://github.com/<username>" or \'"Display Name" <user@example.com>\'.',
            );
            continue;
          }
          final parsedAuthor = RfcAuthor.tryParse(authorStr);
          if (parsedAuthor == null) {
            errors.add(
              'Author "$authorStr" must be a GitHub profile URL ("https://github.com/<username>") '
              'or RFC 5322 mailbox (\'"Display Name" <user@example.com>\'). '
              'Expected format: "https://github.com/<username>" or \'"Display Name" <user@example.com>\'.',
            );
          }
        }
      case final other:
        errors.add(
          'Frontmatter "authors" must be a non-empty list of authors. '
          'Found ${other.runtimeType} "$other". Expected format:\nauthors:\n  - https://github.com/<username>\n  - \'"Display Name" <user@example.com>\'',
        );
    }

    // 10. supersedes (optional)
    switch (yaml['supersedes']) {
      case null:
        break;
      case final supersedesVal:
        final sStr = supersedesVal.toString().trim();
        if (!RegExp(r'^\d{3}\.\d{4}$').hasMatch(sStr)) {
          errors.add(
            'Frontmatter "supersedes" must match format "AAA.NNNN" (found "$sStr"). '
            'Expected format: 3 digits, dot, 4 digits (e.g. "000.0001").',
          );
        }
    }

    // 11. superseded_by (optional)
    switch (yaml['superseded_by']) {
      case null:
        break;
      case final supersededByVal:
        final sStr = supersededByVal.toString().trim();
        if (!RegExp(r'^\d{3}\.\d{4}$').hasMatch(sStr)) {
          errors.add(
            'Frontmatter "superseded_by" must match format "AAA.NNNN" (found "$sStr"). '
            'Expected format: 3 digits, dot, 4 digits (e.g. "000.0002").',
          );
        }
    }

    return errors;
  }

  /// Parses a [Map] into [RfcFrontmatter].
  ///
  /// Throws [FormatException] if validation errors are detected.
  factory RfcFrontmatter.fromYaml(Map<dynamic, dynamic> yaml) {
    final errors = validate(yaml);
    if (errors.isNotEmpty) {
      throw FormatException(formatErrors(errors));
    }

    final type = yaml['type'].toString().trim();
    final rfc = yaml['rfc'].toString().trim();
    final title = yaml['title'].toString().trim();
    final description = yaml['description'].toString().trim();
    final status = RfcStatus.tryParse(yaml['status'].toString().trim())!;
    final created = _parseUtcTimestamp(yaml['created'], 'created').dateTime!;
    final updated = _parseUtcTimestamp(yaml['updated'], 'updated').dateTime!;
    final tags = List<String>.unmodifiable(
      (yaml['tags'] as List).map((e) => e.toString().trim()),
    );
    final authors = List<RfcAuthor>.unmodifiable(
      (yaml['authors'] as List).map(
        (e) => RfcAuthor.parse(e.toString().trim()),
      ),
    );
    final supersedes = yaml['supersedes']?.toString().trim();
    final supersededBy = yaml['superseded_by']?.toString().trim();

    return RfcFrontmatter(
      type: type,
      rfc: rfc,
      title: title,
      description: description,
      status: status,
      created: created,
      updated: updated,
      tags: tags,
      authors: authors,
      supersedes: supersedes,
      supersededBy: supersededBy,
    );
  }

  /// Parses a raw YAML frontmatter string into [RfcFrontmatter].
  ///
  /// Throws [FormatException] if the string cannot be parsed as a YAML mapping
  /// or fails schema validation.
  factory RfcFrontmatter.parse(String yamlString) {
    dynamic loaded;
    try {
      loaded = loadYaml(yamlString);
    } catch (e) {
      throw FormatException(
        formatErrors(['Failed to parse YAML frontmatter: $e']),
      );
    }
    if (loaded is! Map) {
      throw FormatException(
        formatErrors(const ['YAML frontmatter must be a key-value mapping.']),
      );
    }
    return RfcFrontmatter.fromYaml(loaded);
  }

  /// Safely attempts to parse a [Map] or [YamlMap] into [RfcFrontmatter].
  ///
  /// Returns a record with the parsed [frontmatter] (or `null`), any [errors],
  /// and formatted [feedback] (or `null` if valid).
  static ({RfcFrontmatter? frontmatter, List<String> errors, String? feedback})
  tryLoad(dynamic yaml) {
    if (yaml is! Map) {
      const err = 'YAML frontmatter must be a key-value mapping.';
      return (
        frontmatter: null,
        errors: const [err],
        feedback: formatErrors([err]),
      );
    }
    final errors = validate(yaml);
    if (errors.isNotEmpty) {
      return (
        frontmatter: null,
        errors: errors,
        feedback: formatErrors(errors),
      );
    }
    try {
      return (
        frontmatter: RfcFrontmatter.fromYaml(yaml),
        errors: const <String>[],
        feedback: null,
      );
    } on FormatException catch (e) {
      return (frontmatter: null, errors: [e.message], feedback: e.message);
    }
  }

  static ({DateTime? dateTime, String? error}) _parseUtcTimestamp(
    dynamic val,
    String fieldName,
  ) {
    final nowExample = clock.now().toUtc().toIso8601String();
    switch (val) {
      case null:
        return (
          dateTime: null,
          error:
              'Frontmatter "$fieldName" must be an ISO 8601 UTC timestamp. Missing value (found "null"). '
              'Expected format: YYYY-MM-DDTHH:MM:SSZ (e.g. $nowExample).',
        );
      case DateTime dt when !dt.isUtc:
        return (
          dateTime: null,
          error:
              'Frontmatter "$fieldName" must be an ISO 8601 UTC timestamp. Found non-UTC "$dt". '
              'Expected format: YYYY-MM-DDTHH:MM:SSZ (e.g. ${dt.toUtc().toIso8601String()}).',
        );
      case DateTime dt:
        return (dateTime: dt, error: null);
      case String s:
        final trimmed = s.trim();
        final upper = trimmed.toUpperCase();
        if (upper.endsWith('Z') ||
            upper.endsWith('+00:00') ||
            upper.endsWith('+0000') ||
            upper.endsWith('-00:00') ||
            upper.endsWith('-0000') ||
            upper.endsWith('+00') ||
            upper.endsWith('-00')) {
          final dt = DateTime.tryParse(trimmed);
          if (dt != null && dt.isUtc) {
            return (dateTime: dt.toUtc(), error: null);
          }
        }
        return (
          dateTime: null,
          error:
              'Frontmatter "$fieldName" must be an ISO 8601 UTC timestamp. Found "$s". '
              'Expected format: YYYY-MM-DDTHH:MM:SSZ (e.g. $nowExample).',
        );
      case final invalid:
        return (
          dateTime: null,
          error:
              'Frontmatter "$fieldName" must be an ISO 8601 UTC timestamp. Found "$invalid". '
              'Expected format: YYYY-MM-DDTHH:MM:SSZ (e.g. $nowExample).',
        );
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RfcFrontmatter &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          rfc == other.rfc &&
          title == other.title &&
          description == other.description &&
          status == other.status &&
          created == other.created &&
          updated == other.updated &&
          _listEquals(tags, other.tags) &&
          _listEquals(authors, other.authors) &&
          supersedes == other.supersedes &&
          supersededBy == other.supersededBy;

  @override
  int get hashCode => Object.hash(
    type,
    rfc,
    title,
    description,
    status,
    created,
    updated,
    Object.hashAll(tags),
    Object.hashAll(authors),
    supersedes,
    supersededBy,
  );

  @override
  String toString() =>
      'RfcFrontmatter(rfc: $rfc, title: "$title", status: ${status.value}, authors: $authors)';

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
