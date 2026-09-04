// Copyright 2026 The Flutter Authors.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:math';
import 'package:file/file.dart';
import 'package:path/path.dart' as p;

import 'git_lister.dart';
import 'github_annotation.dart';
import 'models/rfc_file.dart';

export 'git_lister.dart' show GitListFunction, defaultGitList;

/// A validation error encountered during semantic RFC validation.
class ValidationError implements GithubAnnotatable {
  final String filePath;
  final String message;
  final int? line;
  final int? column;

  const ValidationError({
    required this.filePath,
    required this.message,
    this.line,
    this.column,
  });

  /// Formats the error as a GitHub Actions workflow annotation.
  ///
  /// Percent-encodes special characters (%, \r, \n) per GitHub Actions workflow
  /// command specifications.
  @override
  String toGithubAnnotation() => message.toGithubAnnotation(
    filePath: filePath,
    line: line,
    column: column,
  );

  @override
  String toString() {
    if (line != null) {
      if (column != null) {
        return '$filePath:$line:$column: $message';
      }
      return '$filePath:$line: $message';
    }
    return '$filePath: $message';
  }
}

/// Result of RFC semantic number validation.
typedef ValidationResult = ({bool isSuccess, List<ValidationError> errors});

/// Extension on [ValidationResult] providing backwards compatibility.
extension ValidationResultExtension on ValidationResult {
  /// Whether the validation succeeded with no errors.
  ///
  /// Alias for [isSuccess].
  bool get isValid => isSuccess;
}

/// Validates RFC numbers for tree uniqueness, collision with main, and draft absence in merge queues.
class RfcValidator {
  /// Default directory name containing RFC markdown documents.
  static const String rfcDir = 'rfc';

  final FileSystem fs;
  final GitListFunction gitList;

  const RfcValidator({required this.fs, this.gitList = defaultGitList});

  /// Runs semantic validation on all RFC files in the repository.
  ///
  /// Checks:
  /// 1. Filename structure matches `AAA.NNNN-<slug>.md`.
  /// 2. Placeholder `.0000` draft status against [noDrafts].
  /// 3. Tree uniqueness (no duplicate assigned RFC numbers across working tree files).
  /// 4. Collision checks against [baseBranch] when [checkMain] is `true`.
  /// 5. Sequential numbering gap checks: ensures assigned RFC numbers in each
  ///    category are strictly sequential without gaps (e.g., following the
  ///    latest RFC on [baseBranch] when [checkMain] is `true`, or starting at
  ///    `0001` and contiguous when [checkMain] is `false`).
  ///
  /// Parameters:
  /// - [noDrafts]: If `true`, rejects any RFC files with the `.0000` draft index.
  ///   During drafting and socialization (before a number is assigned), `.0000`
  ///   is allowed. Once an RFC number is assigned, in the merge queue, and on
  ///   the `main` branch, `.0000` is forbidden.
  /// - [checkMain]: If `true`, queries [gitList] to discover RFCs on [baseBranch]
  ///   and rejects working tree RFCs whose assigned numbers collide with existing
  ///   files on that branch.
  /// - [baseBranch]: The git branch ref to check against for collisions when
  ///   [checkMain] is `true` (defaults to `'origin/main'`).
  ///
  /// Returns a [ValidationResult] containing any [ValidationError]s found.
  Future<ValidationResult> validate({
    bool noDrafts = false,
    bool checkMain = false,
    String baseBranch = 'origin/main',
  }) async {
    final errors = <ValidationError>[];
    final dir = fs.directory(rfcDir);

    if (!await dir.exists()) {
      errors.add(
        ValidationError(
          filePath: rfcDir,
          message: 'RFC directory "$rfcDir" does not exist.',
        ),
      );
      return (isSuccess: false, errors: errors);
    }

    final entries = await dir.list().toList();
    entries.sort((a, b) => a.path.compareTo(b.path));

    // Validate file-level naming/draft invariants and group valid RFCs by category (AAA).
    final rfcsByCategory = <String, List<RfcFile>>{};
    for (final entry in entries) {
      if (entry is File && entry.path.endsWith('.md')) {
        final rfc = RfcFile.parse('', path: entry.path);

        _validateFileStructure(
          rfc: rfc,
          filePath: entry.path,
          noDrafts: noDrafts,
          errors: errors,
        );

        if (rfc.hasValidFilename) {
          (rfcsByCategory[rfc.category!] ??= []).add(rfc);
        }
      }
    }

    // Discover and index base branch RFCs if --check-main is requested.
    final baseBranchCategories = <String, _BaseBranchCategory>{
      if (checkMain) ...await _indexBaseBranchBySubsystem(baseBranch),
    };

    // For each category AAA:
    //   - verify no duplicates
    //   - verify no collisions (if checkMain)
    //   - verify no gaps
    for (final category in [...rfcsByCategory.keys]..sort()) {
      _validateSubsystemCategory(
        category: category,
        rfcs: rfcsByCategory[category]!,
        checkMain: checkMain,
        baseBranch: baseBranch,
        baseBranchCategory: baseBranchCategories[category],
        errors: errors,
      );
    }

    return (isSuccess: errors.isEmpty, errors: errors);
  }

  /// Validates file-level invariants for a single RFC file:
  /// - Filename matches `AAA.NNNN-<slug>.md`.
  /// - Draft `.0000` status against [noDrafts].
  void _validateFileStructure({
    required RfcFile rfc,
    required String filePath,
    required bool noDrafts,
    required List<ValidationError> errors,
  }) {
    if (!rfc.hasValidFilename) {
      errors.add(
        ValidationError(
          filePath: filePath,
          message:
              'Filename "${p.basename(filePath)}" does not match required format "AAA.NNNN-<slug>.md".',
        ),
      );
      return;
    }

    if (noDrafts && rfc.isDraft) {
      errors.add(
        ValidationError(
          filePath: filePath,
          message:
              'Draft RFC ".0000" detected in "${p.basename(filePath)}". '
              'Drafts must be assigned a sequential RFC number before merging.',
        ),
      );
    }
  }

  /// Validates subsystem category invariants for [category] (`AAA`):
  /// 1. Verify no duplicate assigned numbers within the category.
  /// 2. If [checkMain] is enabled:
  ///    - Verify no collisions with [baseBranch].
  ///    - Verify no gaps following the latest RFC on [baseBranch].
  /// 3. Otherwise:
  ///    - Verify no internal gaps starting from 0001.
  void _validateSubsystemCategory({
    required String category,
    required List<RfcFile> rfcs,
    required bool checkMain,
    required String baseBranch,
    required _BaseBranchCategory? baseBranchCategory,
    required List<ValidationError> errors,
  }) {
    _checkDuplicateNumbers(category: category, rfcs: rfcs, errors: errors);

    if (checkMain) {
      _checkBaseBranchCollisions(
        category: category,
        rfcs: rfcs,
        baseBranch: baseBranch,
        baseBranchCategory: baseBranchCategory,
        errors: errors,
      );
    }

    _checkGaps(
      category: category,
      rfcs: rfcs,
      baseBranch: checkMain ? baseBranch : null,
      baseBranchCategory: checkMain ? baseBranchCategory : null,
      errors: errors,
    );
  }

  /// Discovers and indexes RFC files on [baseBranch] grouped by category `AAA`.
  Future<Map<String, _BaseBranchCategory>> _indexBaseBranchBySubsystem(
    String baseBranch,
  ) async {
    final mainFiles = await gitList(baseBranch: baseBranch);
    final categories = <String, _BaseBranchCategory>{};

    for (final mf in mainFiles) {
      final baseName = p.basename(mf);
      final match = RfcFile.filenamePattern.firstMatch(baseName);
      if (match != null) {
        final cat = match.group(1)!;
        final idx = int.parse(match.group(2)!);
        if (idx != 0) {
          final category = categories.putIfAbsent(
            cat,
            () => _BaseBranchCategory(),
          );
          category.rfcIdToBasename['$cat.${idx.toNNNN()}'] = baseName;
          category.indices.add(idx);
        }
      }
    }
    return categories;
  }

  /// Verifies no duplicate assigned RFC numbers exist within [category].
  void _checkDuplicateNumbers({
    required String category,
    required List<RfcFile> rfcs,
    required List<ValidationError> errors,
  }) {
    final rfcIdToFiles = <String, List<String>>{};
    for (final rfc in rfcs) {
      if (!rfc.isDraft && rfc.rfcId != null) {
        (rfcIdToFiles[rfc.rfcId!] ??= []).add(rfc.path);
      }
    }

    for (final entry in rfcIdToFiles.entries) {
      if (entry.value.length > 1) {
        errors.add(
          ValidationError(
            filePath: entry.value.first,
            message:
                'Duplicate RFC number "${entry.key}" detected across multiple files: '
                '${entry.value.map(p.basename).join(', ')}.',
          ),
        );
      }
    }
  }

  /// Identifies collisions where working tree RFCs reuse an identifier already
  /// landed on [baseBranch] with a different file name.
  void _checkBaseBranchCollisions({
    required String category,
    required List<RfcFile> rfcs,
    required String baseBranch,
    required _BaseBranchCategory? baseBranchCategory,
    required List<ValidationError> errors,
  }) {
    if (baseBranchCategory == null) return;

    for (final rfc in rfcs) {
      if (rfc.isDraft || rfc.rfcId == null) continue;
      final currentBasename = p.basename(rfc.path);
      final existingOnMain = baseBranchCategory.rfcIdToBasename[rfc.rfcId];
      if (existingOnMain != null && existingOnMain != currentBasename) {
        errors.add(
          ValidationError(
            filePath: rfc.path,
            message:
                'RFC number "${rfc.rfcId}" collides with existing RFC in $baseBranch ("$existingOnMain"). '
                'Re-run number assignment to obtain the next sequential number.',
          ),
        );
      }
    }
  }

  /// Ensures assigned RFC numbers in [category] are strictly sequential without gaps.
  ///
  /// When [baseBranch] is provided, validates that new RFCs follow the latest landed RFC
  /// on [baseBranch]. When omitted, validates that working tree RFCs start at 0001 and
  /// are contiguous.
  void _checkGaps({
    required String category,
    required List<RfcFile> rfcs,
    required List<ValidationError> errors,
    String? baseBranch,
    _BaseBranchCategory? baseBranchCategory,
  }) {
    final candidateRfcs = [
      for (var rfc in rfcs)
        if (!rfc.isDraft &&
            rfc.index != null &&
            (baseBranchCategory == null ||
                baseBranchCategory.rfcIdToBasename[rfc.rfcId] == null))
          rfc,
    ]..sort((a, b) => a.index!.compareTo(b.index!));

    final maxBase = baseBranch != null
        ? (baseBranchCategory?.maxIndex ?? 0)
        : 0;
    final contextSuffix = baseBranch != null
        ? (maxBase == 0
              ? ' (no RFCs exist in category "$category" in $baseBranch)'
              : ' (the latest RFC is "$category.${maxBase.toNNNN()}" in $baseBranch)')
        : '';

    var expectedNext = maxBase + 1;
    for (final rfc in candidateRfcs) {
      final actualIndex = rfc.index!;
      if (actualIndex > expectedNext) {
        final expectedPadded = expectedNext.toNNNN();
        errors.add(
          ValidationError(
            filePath: rfc.path,
            message:
                'RFC number "${rfc.rfcId}" creates a numbering gap. '
                'Expected next sequential number is "$category.$expectedPadded"$contextSuffix.',
          ),
        );
        expectedNext = actualIndex + 1;
      } else if (actualIndex == expectedNext) {
        expectedNext++;
      }
    }
  }
}

/// Discovered base branch RFC files and metadata for a category `AAA`.
class _BaseBranchCategory {
  final Map<String, String> rfcIdToBasename = {};
  final List<int> indices = [];

  int get maxIndex => indices.isEmpty ? 0 : indices.reduce(max);
}
