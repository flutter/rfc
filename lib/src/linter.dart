// Copyright 2026 The Flutter Authors.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/file.dart';
import 'package:path/path.dart' as p;

import 'github_annotation.dart';
import 'models/rfc_file.dart';
import 'taxonomy.dart';

/// A lint issue discovered in an RFC document.
class LintIssue implements GithubAnnotatable {
  final String filePath;
  final int line;
  final int column;
  final String message;

  const LintIssue({
    required this.filePath,
    required this.message,
    this.line = 1,
    this.column = 1,
  });

  /// Formats the issue as a GitHub Actions workflow annotation.
  ///
  /// Percent-encodes special characters (%, \r, \n) per GitHub Actions workflow
  /// command specifications so multiline schema templates are preserved cleanly.
  @override
  String toGithubAnnotation() => message.toGithubAnnotation(
    filePath: filePath,
    line: line,
    column: column,
  );

  @override
  String toString() => '$filePath:$line:$column: $message';
}

/// Linter enforcing RFC structure, metadata, taxonomy, and number allocation rules.
class RfcLinter {
  final FileSystem fs;
  final Taxonomy taxonomy;
  final Set<String> labels;
  final Set<String> existingBasenames;
  final bool enforceDrafts;

  RfcLinter({
    required this.fs,
    required this.taxonomy,
    this.labels = const <String>{},
    this.enforceDrafts = false,
    Set<String> existingFilesOnMain = const <String>{},
  }) : existingBasenames = {
         for (final file in existingFilesOnMain) p.basename(file),
       };

  /// Lints a single RFC file.
  Future<List<LintIssue>> lintFile(File file) async {
    final issues = <LintIssue>[];
    final relativePath = file.path;

    if (!await file.exists()) {
      issues.add(LintIssue(filePath: relativePath, message: 'File not found.'));
      return issues;
    }

    final content = await file.readAsString();
    final rfc = RfcFile.parse(content, path: file.path);
    final fileName = p.basename(file.path);

    // 1. Filename & Path Validation
    if (!rfc.hasValidFilename) {
      issues.add(
        LintIssue(
          filePath: relativePath,
          line: 1,
          message:
              'Filename "$fileName" does not match required format "AAA.NNNN-<slug>.md" '
              '(where AAA is 3 digits, NNNN is 4 digits, and slug is lowercase kebab-case).',
        ),
      );
      return issues; // Cannot perform further structural checks reliably
    }

    // 2. Taxonomy Validation
    if (!taxonomy.isValidCategory(rfc.category!)) {
      issues.add(
        LintIssue(
          filePath: relativePath,
          line: 1,
          message:
              'Subsystem category "${rfc.category}" is not defined in the architecture taxonomy. '
              'See rfc/000.0001-flutter-architecture-and-reference-taxonomy.md.',
        ),
      );
    }

    // 3. Draft vs Assigned Number Enforcement (PR Context)
    if (enforceDrafts) {
      final isExistingOnMain = existingBasenames.contains(fileName);
      const bootstrapRfcs = {'000.0001', '000.0002'};
      final isBootstrap = bootstrapRfcs.contains(rfc.rfcId);

      if (!rfc.isDraft && !isExistingOnMain && !isBootstrap) {
        final hasReadyOrAssigned =
            labels.contains('rfc-ready') || labels.contains('rfc-assigned');
        if (!hasReadyOrAssigned) {
          issues.add(
            LintIssue(
              filePath: relativePath,
              line: 1,
              message:
                  'RFC has assigned number "${rfc.rfcId}", but PR does not have '
                  '"rfc-ready" or "rfc-assigned" label. RFCs under review must use index "0000".',
            ),
          );
        }
      }
    }

    // 4. YAML Frontmatter Validation
    if (rfc.frontmatterErrors.isNotEmpty) {
      for (final (:line, :error) in rfc.frontmatterErrors) {
        issues.add(
          LintIssue(filePath: relativePath, line: line, message: error),
        );
      }
      issues.add(
        LintIssue(
          filePath: relativePath,
          line: rfc.hasFrontmatter ? 2 : 1,
          message:
              'Expected frontmatter format:\n${RfcFrontmatter.expectedSchemaTemplate.trimRight()}',
        ),
      );
      if (!rfc.hasFrontmatter) {
        return issues;
      }
    }

    final fm = rfc.frontmatter;
    final rfcId = fm?.rfc;
    final expectedId = rfc.rfcId;

    if (rfcId != null && rfcId != expectedId) {
      issues.add(
        LintIssue(
          filePath: relativePath,
          line: 2,
          message:
              'Frontmatter "rfc" value ("$rfcId") does not match filename identifier ("$expectedId").',
        ),
      );
    }

    // 5. First Heading Validation
    if (rfc.firstHeading == null) {
      issues.add(
        LintIssue(
          filePath: relativePath,
          line: 1,
          message:
              'Document must contain a top-level heading matching "# RFC ${rfc.rfcId}: <Title>".',
        ),
      );
    } else {
      if (rfc.firstHeadingId != expectedId) {
        issues.add(
          LintIssue(
            filePath: relativePath,
            line: rfc.firstHeadingLine ?? 1,
            message:
                'First heading RFC identifier ("${rfc.firstHeadingId}") does not match "$expectedId".',
          ),
        );
      }

      final fmTitle = fm?.title.trim();
      if (fmTitle != null &&
          fmTitle.isNotEmpty &&
          rfc.firstHeadingTitle != fmTitle) {
        issues.add(
          LintIssue(
            filePath: relativePath,
            line: rfc.firstHeadingLine ?? 1,
            message:
                'First heading title ("${rfc.firstHeadingTitle}") does not match frontmatter title ("$fmTitle").',
          ),
        );
      }
    }

    return issues;
  }

  /// Lints all RFC markdown files in the specified directory.
  Future<List<LintIssue>> lintDirectory(Directory dir) async {
    final issues = <LintIssue>[];
    if (!await dir.exists()) {
      issues.add(
        LintIssue(filePath: dir.path, message: 'Directory does not exist.'),
      );
      return issues;
    }

    final entries = await dir.list().toList();
    entries.sort((a, b) => a.path.compareTo(b.path));

    for (final entry in entries) {
      if (entry is File && entry.path.endsWith('.md')) {
        issues.addAll(await lintFile(entry));
      }
    }

    return issues;
  }
}
