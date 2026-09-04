// Copyright 2026 The Flutter Authors.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

/// Signature for running an external process asynchronously.
typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// Abstract client for interacting with the GitHub API / CLI.
abstract interface class GitHubClient {
  /// Checks whether a GitHub user exists.
  Future<bool> userExists(String username);
}

/// Production implementation using the `gh` CLI.
class CliGitHubClient implements GitHubClient {
  /// The process runner used to execute external commands.
  final ProcessRunner processRunner;

  const CliGitHubClient({this.processRunner = Process.run});

  @override
  Future<bool> userExists(String username) async {
    try {
      final result = await processRunner('gh', [
        'api',
        'users/$username',
        '--silent',
      ]);
      if (result.exitCode != 0) {
        stdout.writeln('exit code: ${result.exitCode}');
        stdout.writeln('gh api stdout:');
        stdout.writeln(result.stdout);
        stderr.writeln('gh api stderr:');
        stderr.writeln(result.stderr);
      }
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}

/// Test double with in-memory state for hermetic unit testing.
class FakeGitHubClient implements GitHubClient {
  final Set<String> existingUsers;

  FakeGitHubClient({Set<String>? existingUsers})
    : existingUsers = existingUsers ?? <String>{};

  @override
  Future<bool> userExists(String username) async {
    return existingUsers.contains(username);
  }
}
