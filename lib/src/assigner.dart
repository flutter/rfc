// Copyright 2026 The Flutter Authors.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io' show Process;
import 'dart:math';
import 'package:clock/clock.dart';
import 'package:file/file.dart';
import 'package:path/path.dart' as p;

import 'git_lister.dart';
import 'git_lister.dart' as git_lister;
import 'github_client.dart' show ProcessRunner;
import 'models/rfc_file.dart';

export 'git_lister.dart' show GitListFunction, defaultGitList;

/// Result of an RFC number assignment operation.
class AssignmentResult {
  final String oldPath;
  final String newPath;
  final String category;
  final int oldIndex;
  final int newIndex;
  final String newContent;
  final bool dryRun;

  const AssignmentResult({
    required this.oldPath,
    required this.newPath,
    required this.category,
    required this.oldIndex,
    required this.newIndex,
    required this.newContent,
    required this.dryRun,
  });

  String get newRfcId => '$category.${newIndex.toNNNN()}';
}

/// Allocates sequential RFC numbers, updates frontmatter & headings, and handles git/label sync.
class RfcAssigner {
  /// Default directory name containing RFC markdown documents.
  static const String rfcDir = 'rfc';

  final FileSystem fs;
  final GitListFunction gitList;

  const RfcAssigner({
    required this.fs,
    this.gitList = RfcAssigner.defaultGitList,
  });

  /// Discovers RFC filenames in main branch via git.
  static Future<Set<String>> defaultGitList({
    String baseBranch = 'origin/main',
    ProcessRunner processRunner = Process.run,
  }) => git_lister.defaultGitList(
    baseBranch: baseBranch,
    processRunner: processRunner,
  );

  Future<Set<String>> _getMainBranchRfcFiles() async => await gitList();

  /// Allocates the next sequential RFC number in the target category.
  ///
  /// Workflow:
  /// 1. Identifies the target RFC file using [targetPath] if provided, or discovers
  ///    a single `.0000` draft in [rfcDir]. If no `.0000` draft exists, checks
  ///    for re-allocation on an existing RFC colliding with [gitList].
  /// 2. Discovers all used numeric indices within the matching category (`AAA.`)
  ///    across the working tree and the main branch.
  /// 3. Computes the next available sequential index number (1-9999).
  /// 4. Transforms the RFC document content: updates frontmatter `rfc` and
  ///    `updated` timestamp (using [updatedTime] or `clock.now()`), and
  ///    updates the top-level `# RFC AAA.NNNN: Title` heading while preserving
  ///    `status: draft`.
  /// 5. Renames and writes the file on disk, unless [dryRun] is `true`.
  ///
  /// Parameters:
  /// - [targetPath]: Explicit path to the RFC file to assign. If `null`,
  ///   automatically selects the single candidate draft file in [rfcDir].
  /// - [dryRun]: When `true`, computes the assignment and transformed content
  ///   without modifying the filesystem. Defaults to `false`.
  /// - [updatedTime]: Timestamp to write into the frontmatter `updated` field.
  ///   Defaults to `clock.now()`.
  ///
  /// Returns an [AssignmentResult] containing paths, category, index numbers,
  /// transformed content, and [dryRun] status.
  ///
  /// Throws:
  /// - [ArgumentError] if [targetPath] does not exist.
  /// - [StateError] if the filename does not conform to `AAA.NNNN-<slug>.md`,
  ///   if multiple draft RFCs exist without an explicit [targetPath],
  ///   if no RFC requiring assignment is found, or if category index 9999 is reached.
  Future<AssignmentResult> assign({
    String? targetPath,
    bool dryRun = false,
    DateTime? updatedTime,
  }) async {
    Set<String>? cachedMainFiles;
    Future<Set<String>> getMainFiles() async =>
        cachedMainFiles ??= await _getMainBranchRfcFiles();

    final dir = fs.directory(rfcDir);

    // Identify the target RFC file to assign.
    final RfcFile targetRfc;
    List<FileSystemEntity>? cachedEntries;

    if (targetPath != null) {
      targetRfc = await _resolveExplicitTarget(targetPath, dir);
    } else {
      (targetRfc, cachedEntries) = await _discoverTarget(dir, getMainFiles);
    }

    final category = targetRfc.category!;
    final oldIndex = targetRfc.index!;

    // Discover all existing indices in this category across working tree and main.
    // Reject out of hand anything that doesn't start with category.
    final usedIndices = <int>{};
    final prefix = '$category.';
    final targetBasename = p.basename(targetRfc.path);

    final entries = cachedEntries ?? await dir.list().toList();
    for (final entry in entries) {
      if (entry is! File) continue;
      final fileName = p.basename(entry.path);
      if (fileName == targetBasename) continue;
      if (!fileName.startsWith(prefix)) continue;
      final match = RfcFile.filenamePattern.firstMatch(fileName);
      if (match != null) {
        final idx = int.parse(match.group(2)!);
        if (idx != 0) {
          usedIndices.add(idx);
        }
      }
    }

    // From main branch
    final mainFiles = await getMainFiles();
    for (final mf in mainFiles) {
      final fileName = p.basename(mf);
      if (!fileName.startsWith(prefix)) continue;
      final match = RfcFile.filenamePattern.firstMatch(fileName);
      if (match != null) {
        final idx = int.parse(match.group(2)!);
        if (idx != 0) {
          usedIndices.add(idx);
        }
      }
    }

    // Compute next sequential number.
    final candidate = usedIndices.isEmpty ? 1 : usedIndices.reduce(max) + 1;

    // Congrats, you win the overflow prize.
    if (candidate > 9999) {
      throw StateError(
        'Maximum RFC index (9999) reached in category "$category".',
      );
    }

    final newIndexStr = candidate.toNNNN();
    final newFileName = '$category.$newIndexStr-${targetRfc.slug}.md';
    final newPath = p.join(p.dirname(targetRfc.path), newFileName);

    // Transform content (preserves status: draft, updates rfc & updated, updates header)
    final effectiveUpdatedTime = updatedTime ?? clock.now();
    final newContent = targetRfc.transformedContent(
      newCategory: category,
      newIndex: candidate,
      updatedTime: effectiveUpdatedTime,
    );

    // Execute filesystem changes if not dryRun
    if (!dryRun) {
      final oldFile = fs.file(targetRfc.path);
      final newFile = fs.file(newPath);

      if (newPath != targetRfc.path) {
        await newFile.writeAsString(newContent);
        await oldFile.delete();
      } else {
        await oldFile.writeAsString(newContent);
      }
    }

    return AssignmentResult(
      oldPath: targetRfc.path,
      newPath: newPath,
      category: category,
      oldIndex: oldIndex,
      newIndex: candidate,
      newContent: newContent,
      dryRun: dryRun,
    );
  }

  Future<RfcFile> _resolveExplicitTarget(
    String targetPath,
    Directory dir,
  ) async {
    final targetFile = fs.file(targetPath);
    if (!await targetFile.exists()) {
      throw ArgumentError('Target RFC file "$targetPath" does not exist.');
    }
    final fileName = p.basename(targetPath);
    if (!RfcFile.filenamePattern.hasMatch(fileName)) {
      throw StateError(
        'Target RFC "$targetPath" does not conform to format '
        '"AAA.NNNN-<slug>.md".',
      );
    }
    if (!await dir.exists()) {
      throw StateError('RFC directory "$rfcDir" does not exist.');
    }
    final content = await targetFile.readAsString();
    return RfcFile.parse(content, path: targetPath);
  }

  Future<(RfcFile, List<FileSystemEntity>)> _discoverTarget(
    Directory dir,
    Future<Set<String>> Function() getMainFiles,
  ) async {
    if (!await dir.exists()) {
      throw StateError('RFC directory "$rfcDir" does not exist.');
    }
    final cachedEntries = await dir.list().toList();
    final draftFiles = <File>[];
    for (final entry in cachedEntries) {
      if (entry is File) {
        final fileName = p.basename(entry.path);
        final match = RfcFile.filenamePattern.firstMatch(fileName);
        if (match != null && int.parse(match.group(2)!) == 0) {
          draftFiles.add(entry);
        }
      }
    }

    if (draftFiles.length == 1) {
      final draftFile = draftFiles.first;
      final content = await draftFile.readAsString();
      return (RfcFile.parse(content, path: draftFile.path), cachedEntries);
    } else if (draftFiles.length > 1) {
      throw StateError(
        'Multiple draft RFCs (.0000) found in "$rfcDir". '
        'Specify --target-file explicitly.',
      );
    } else {
      // Collision recovery: When no .0000 draft is found, reallocate an already-assigned
      // RFC that collides with main (e.g. another PR merged with the same number while
      // this PR was in review). The validator prevents the collision from landing in main;
      // this auto-discovers the colliding file so [assign] can reallocate it.
      final targetRfc = await _reallocate(cachedEntries, getMainFiles);
      return (targetRfc, cachedEntries);
    }
  }

  /// Discovers an assigned RFC in the working tree that collides with main
  /// for reallocation.
  ///
  /// This serves as an automated collision recovery mechanism:
  /// 1. A PR is assigned a number (e.g. `110.0042`) and is no longer `.0000`.
  /// 2. Another PR merges into `main` with that same number (`110.0042`) first.
  /// 3. `validate_rfc_number` detects the collision and blocks the PR from merging.
  /// 4. To resolve the collision, the maintainer re-triggers the assigner (e.g.
  ///    via the `assign-rfc-number` label).
  ///
  /// Because the file is already numbered `110.0042`, this helper locates the
  /// colliding RFC so [assign] can re-allocate it to the next available number
  /// (e.g. `110.0043`) without requiring the author to manually revert to `.0000`.
  Future<RfcFile> _reallocate(
    List<FileSystemEntity> cachedEntries,
    Future<Set<String>> Function() getMainFiles,
  ) async {
    final mainFiles = await getMainFiles();
    final mainByCategoryIndex = <String, Set<String>>{};
    for (final mainName in mainFiles.map(p.basename)) {
      final match = RfcFile.filenamePattern.firstMatch(mainName);
      if (match != null) {
        final cat = match.group(1)!;
        final idx = int.parse(match.group(2)!);
        final key = '$cat.${idx.toNNNN()}';
        (mainByCategoryIndex[key] ??= {}).add(mainName);
      }
    }

    final collidingFiles = <File>[];
    for (final entry in cachedEntries) {
      if (entry is File) {
        final fileName = p.basename(entry.path);
        final match = RfcFile.filenamePattern.firstMatch(fileName);
        if (match == null) continue;
        final category = match.group(1)!;
        final index = int.parse(match.group(2)!);
        if (index == 0) continue;

        final key = '$category.${index.toNNNN()}';
        final mainNames = mainByCategoryIndex[key];
        if (mainNames != null &&
            mainNames.any((mainName) => mainName != fileName)) {
          collidingFiles.add(entry);
        }
      }
    }

    if (collidingFiles.length == 1) {
      final collidingFile = collidingFiles.first;
      final content = await collidingFile.readAsString();
      return RfcFile.parse(content, path: collidingFile.path);
    } else if (collidingFiles.length > 1) {
      throw StateError(
        'Multiple colliding RFCs found. Specify --target-file explicitly.',
      );
    } else {
      throw StateError(
        'No RFC requiring number assignment found in "$rfcDir". '
        'Draft RFCs must use index ".0000" to be assigned a number.',
      );
    }
  }
}
