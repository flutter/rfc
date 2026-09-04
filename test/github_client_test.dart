// Copyright 2026 The Flutter Authors.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';
import 'package:rfc_tools/src/github_client.dart';
import 'package:test/test.dart';
import 'mock_process_runner.dart';

void main() {
  group('CliGitHubClient', () {
    test('default constructor uses Process.run', () {
      const client = CliGitHubClient();
      expect(client.processRunner, equals(Process.run));
    });

    group('userExists', () {
      test('returns true when exitCode is 0', () async {
        final runner = MockProcessRunner(exitCode: 0);
        final client = CliGitHubClient(processRunner: runner.run);

        final exists = await client.userExists('octocat');

        expect(exists, isTrue);
        expect(runner.calls, hasLength(1));
        expect(runner.calls.first.executable, equals('gh'));
        expect(
          runner.calls.first.arguments,
          equals(['api', 'users/octocat', '--silent']),
        );
      });

      test('returns false when exitCode is non-zero', () async {
        final runner = MockProcessRunner(exitCode: 1);
        final client = CliGitHubClient(processRunner: runner.run);

        final exists = await client.userExists('unknown-user');

        expect(exists, isFalse);
        expect(runner.calls, hasLength(1));
        expect(runner.calls.first.executable, equals('gh'));
        expect(
          runner.calls.first.arguments,
          equals(['api', 'users/unknown-user', '--silent']),
        );
      });

      test('returns false when process runner throws', () async {
        final runner = MockProcessRunner(
          exceptionToThrow: const SocketException('network down'),
        );
        final client = CliGitHubClient(processRunner: runner.run);

        final exists = await client.userExists('octocat');

        expect(exists, isFalse);
      });
    });
  });

  group('FakeGitHubClient', () {
    test('verifies user existence against existingUsers set', () async {
      final client = FakeGitHubClient(existingUsers: {'user1'});

      expect(await client.userExists('user1'), isTrue);
      expect(await client.userExists('unknown'), isFalse);
    });
  });
}
