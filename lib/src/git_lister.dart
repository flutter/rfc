// Copyright 2026 The Flutter Authors.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io' show Process, ProcessResult, stdout, stderr;

import 'github_client.dart' show ProcessRunner;

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

void _logGitError(ProcessResult result) {
  stdout.writeln('exit code: ${result.exitCode}');
  stdout.writeln('git ls-tree stdout:');
  stdout.writeln(result.stdout);
  stderr.writeln('git ls-tree stderr:');
  stderr.writeln(result.stderr);
}

/// Discovers RFC filenames in main branch via git.
Future<Set<String>> defaultGitList({
  String baseBranch = 'origin/main',
  ProcessRunner processRunner = Process.run,
}) async {
  try {
    final result = await processRunner('git', [
      'ls-tree',
      '-r',
      '--name-only',
      baseBranch,
      'rfc/',
    ]);
    if (result.exitCode == 0) {
      return parseLsTreeOutput(result.stdout);
    }

    final cleanBranch = baseBranch.replaceFirst(
      RegExp(r'^(?:remotes\/)?(?:origin|upstream)\/'),
      '',
    );
    if (cleanBranch != baseBranch) {
      final locResult = await processRunner('git', [
        'ls-tree',
        '-r',
        '--name-only',
        cleanBranch,
        'rfc/',
      ]);
      if (locResult.exitCode == 0) {
        return parseLsTreeOutput(locResult.stdout);
      }
      _logGitError(locResult);
    } else {
      _logGitError(result);
    }
  } catch (e) {
    stderr.writeln('git ls-tree exception: $e');
  }
  return <String>{};
}
