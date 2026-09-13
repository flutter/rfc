// Copyright 2026 The Flutter Authors.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io' show Process, ProcessException, ProcessResult;

import 'process_logger.dart';
import 'process_runner.dart';

/// Function signature for discovering RFC filenames in the main branch via git.
typedef GitListFunction = Future<Set<String>> Function({String baseBranch});

/// Parses lines of git ls-tree output into a Set of file paths.
Set<String> parseLsTreeOutput(dynamic stdout) {
  final String output = stdout is List<int> ? utf8.decode(stdout) : '$stdout';
  return {
    for (var line in LineSplitter.split(output))
      if (line.trim() case final trimmed when trimmed.isNotEmpty) trimmed,
  };
}

/// Discovers RFC filenames in main branch via git.
Future<Set<String>> defaultGitList({
  String baseBranch = 'origin/main',
  ProcessRunner processRunner = Process.run,
  bool throwOnError = false,
}) async {
  final trimmedBranch = baseBranch.trim();
  final cleanBranch = trimmedBranch.replaceFirst(
    RegExp(r'^(?:remotes\/)?(?:origin|upstream)\/'),
    '',
  );
  final branchesToTry = [
    trimmedBranch,
    if (cleanBranch != trimmedBranch) cleanBranch,
  ];

  ProcessResult? lastResult;
  String? lastBranch;
  for (final branch in branchesToTry) {
    lastBranch = branch;
    try {
      final result = await processRunner('git', [
        'ls-tree',
        '-r',
        '--name-only',
        branch,
        'rfc/',
      ]);
      if (result.exitCode == 0) {
        return parseLsTreeOutput(result.stdout);
      }
      lastResult = result;
      logProcessResult(result, command: 'git ls-tree');
    } catch (e) {
      logProcessError(e, command: 'git ls-tree');
      if (throwOnError) rethrow;
    }
  }

  if (throwOnError && lastResult != null) {
    final err = '${lastResult.stderr}'.trim();
    throw ProcessException(
      'git',
      ['ls-tree', '-r', '--name-only', lastBranch ?? trimmedBranch, 'rfc/'],
      err.isNotEmpty
          ? err
          : 'git ls-tree failed with exit code ${lastResult.exitCode}',
      lastResult.exitCode,
    );
  }
  return <String>{};
}
