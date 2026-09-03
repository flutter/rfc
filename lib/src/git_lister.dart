// Copyright 2026 The Flutter Authors.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'github_client.dart' show ProcessRunner;

/// Signature for querying RFC files on a remote/base git branch.
typedef GitListFunction = Future<Set<String>> Function({String baseBranch});

/// Default implementation querying git via `git ls-tree`.
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
      '--',
      'rfc/',
    ]);
    if (result.exitCode != 0) {
      stdout.writeln('exit code: ${result.exitCode}');
      stdout.writeln('git ls-tree stdout:');
      stdout.writeln(result.stdout);
      stderr.writeln('git ls-tree stderr:');
      stderr.writeln(result.stderr);
      return const <String>{};
    }
    final stdoutStr = result.stdout as String;
    return stdoutStr
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
  } catch (_) {
    return const <String>{};
  }
}
