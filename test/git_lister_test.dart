// Copyright 2026 The Flutter Authors.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:rfc_tools/src/git_lister.dart';
import 'package:test/test.dart';

import 'mock_process_runner.dart';

void main() {
  group('defaultGitList', () {
    test('returns parsed file set on zero exit code', () async {
      final runner = MockProcessRunner(
        exitCode: 0,
        stdout: 'rfc/000.0001-taxonomy.md\nrfc/000.0002-process.md\n',
      );

      final files = await defaultGitList(
        baseBranch: 'origin/main',
        processRunner: runner.run,
      );

      expect(
        files,
        equals({'rfc/000.0001-taxonomy.md', 'rfc/000.0002-process.md'}),
      );
      expect(runner.calls, hasLength(1));
      expect(
        runner.calls.first.arguments,
        equals(['ls-tree', '-r', '--name-only', 'origin/main', 'rfc/']),
      );
    });

    test('returns empty set on non-zero exit code', () async {
      final runner = MockProcessRunner(
        exitCode: 128,
        stderr: 'fatal: not a valid object name',
      );

      final files = await defaultGitList(
        baseBranch: 'origin/main',
        processRunner: runner.run,
      );

      expect(files, isEmpty);
    });

    test('returns empty set when process throws', () async {
      final runner = MockProcessRunner(
        exceptionToThrow: Exception('process failed'),
      );

      final files = await defaultGitList(
        baseBranch: 'origin/main',
        processRunner: runner.run,
      );

      expect(files, isEmpty);
    });
  });
}
