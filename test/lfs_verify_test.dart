// Copyright 2026 The Flutter Authors.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:rfc_tools/src/lfs_verifier.dart';
import 'package:test/test.dart';

import 'mock_process_runner.dart';

MockProcessRunner createGitMockRunner({
  String diffOutput = '',
  String mergeBase = 'merge_base_sha\n',
  int? fsckExitCode,
  String? fsckOutput,
  ProcessRunner? customHandler,
}) {
  return MockProcessRunner(
    handler: (executable, arguments) async {
      if (await customHandler?.call(executable, arguments) case final result?
          when result.exitCode != -999) {
        return result;
      }
      if (arguments.contains('fsck')) {
        if (fsckExitCode != null) {
          return ProcessResult(
            1,
            fsckExitCode,
            fsckOutput ?? (fsckExitCode == 0 ? 'Git LFS fsck OK\n' : ''),
            '',
          );
        }
        return ProcessResult(1, 0, 'Git LFS fsck OK\n', '');
      }
      if (arguments.contains('rev-parse')) {
        return ProcessResult(1, 0, 'sha123\n', '');
      }

      final stdout = switch (arguments) {
        _ when arguments.contains('merge-base') => mergeBase,
        _ when arguments.contains('diff') => diffOutput,
        _ => '',
      };
      return ProcessResult(1, 0, stdout, '');
    },
  );
}

void main() {
  group('LfsVerifier', () {
    group('parseFsckOutput', () {
      test('parses unexpectedGitObject lines', () {
        const output = '''
pointer: unexpectedGitObject: "images/banner.png" (treeish 4b825dc642cb6eb9a060e54bf8d69288fbee4904ce6243dabb9c50119e0780f0) should have been a pointer but was not
pointer: unexpectedGitObject: "assets/sub/doc.pdf" (treeish abc12345) should have been a pointer but was not
''';
        final issues = LfsVerifier.parseFsckOutput(output);
        expect(issues, hasLength(2));
        expect(issues[0].filePath, 'images/banner.png');
        expect(
          issues[0].message,
          contains('should have been a pointer but was not'),
        );
        expect(issues[1].filePath, 'assets/sub/doc.pdf');
        expect(
          issues[1].message,
          contains('should have been a pointer but was not'),
        );
      });

      test('deduplicates identical paths across commits', () {
        const output = '''
pointer: unexpectedGitObject: "dup.png" (treeish 1111) should have been a pointer but was not
pointer: unexpectedGitObject: "dup.png" (treeish 2222) should have been a pointer but was not
''';
        final issues = LfsVerifier.parseFsckOutput(output);
        expect(issues, hasLength(1));
        expect(issues[0].filePath, 'dup.png');
      });

      test('returns empty list for clean fsck output', () {
        const output = 'Git LFS fsck OK\n';
        final issues = LfsVerifier.parseFsckOutput(output);
        expect(issues, isEmpty);
      });
    });

    group('LfsIssue', () {
      test('formats standard error message with file path', () {
        const issue = LfsIssue(
          filePath: 'images/logo.png',
          message: 'bypassed Git LFS',
        );
        expect(
          issue.toString(),
          equals('[ERROR] images/logo.png: bypassed Git LFS'),
        );
      });

      test('formats repository-level error message without file path', () {
        const issue = LfsIssue(filePath: '', message: 'repository-wide error');
        expect(issue.toString(), equals('[ERROR] repository-wide error'));
      });

      test('formats github annotation with file path', () {
        const issue = LfsIssue(
          filePath: 'images/logo.png',
          message: 'bypassed Git LFS',
        );
        expect(
          issue.toGithubAnnotation(),
          equals('::error file=images/logo.png::bypassed Git LFS'),
        );
      });

      test('formats github annotation without file path', () {
        const issue = LfsIssue(filePath: '', message: 'repository-wide error');
        expect(
          issue.toGithubAnnotation(),
          equals('::error::repository-wide error'),
        );
      });
    });

    group('Base target & merge base resolution', () {
      test('resolves branch directly when git rev-parse succeeds', () async {
        final mockRunner = createGitMockRunner();
        final verifier = LfsVerifier(processRunner: mockRunner.run);
        final result = await verifier.resolveBaseTarget('origin/main');
        expect(result, equals('origin/main'));
      });

      test(
        'falls back to origin prefix when given clean branch name',
        () async {
          final mockRunner = createGitMockRunner(
            customHandler: (executable, arguments) async {
              if (arguments.contains('rev-parse')) {
                if (arguments.contains('feature')) {
                  return ProcessResult(1, 1, '', 'not found');
                }
                if (arguments.contains('origin/feature')) {
                  return ProcessResult(1, 0, 'sha456\n', '');
                }
              }
              return ProcessResult(1, -999, '', '');
            },
          );
          final verifier = LfsVerifier(processRunner: mockRunner.run);
          final result = await verifier.resolveBaseTarget('feature');
          expect(result, equals('origin/feature'));
        },
      );

      test('returns merge-base commit sha', () async {
        final mockRunner = createGitMockRunner(
          mergeBase: 'merge_base_commit_sha\n',
        );
        final verifier = LfsVerifier(processRunner: mockRunner.run);
        final result = await verifier.getMergeBase('origin/main');
        expect(result, equals('merge_base_commit_sha'));
      });

      test('returns null when merge-base fails', () async {
        final mockRunner = createGitMockRunner(
          customHandler: (executable, arguments) async {
            if (arguments.contains('merge-base')) {
              return ProcessResult(1, 1, '', 'fatal: no merge base');
            }
            return ProcessResult(1, -999, '', '');
          },
        );
        final verifier = LfsVerifier(processRunner: mockRunner.run);
        final result = await verifier.getMergeBase('origin/main');
        expect(result, isNull);
      });
    });

    group('verifyPullRequest', () {
      group('pointer and filter validation', () {
        test('passes when PR introduces valid LFS pointer', () async {
          final mockRunner = createGitMockRunner(
            diffOutput: 'assets/logo.png\u0000',
            fsckExitCode: 0,
          );

          final verifier = LfsVerifier(processRunner: mockRunner.run);
          final result = await verifier.verifyPullRequest(
            baseBranch: 'origin/main',
          );
          expect(result.isSuccess, isTrue);
          expect(result.issues, isEmpty);
        });

        test('detects raw binary blob bypassing Git LFS in PR diff', () async {
          final mockRunner = createGitMockRunner(
            diffOutput: 'assets/photo.jpg\u0000',
            fsckExitCode: 1,
            fsckOutput:
                'pointer: unexpectedGitObject: "assets/photo.jpg" (treeish sha12345) should have been a pointer but was not\n',
          );

          final verifier = LfsVerifier(processRunner: mockRunner.run);
          final result = await verifier.verifyPullRequest(
            baseBranch: 'origin/main',
          );

          expect(result.isSuccess, isFalse);
          expect(result.issues, hasLength(1));
          expect(
            result.issues.first.message,
            contains('should have been a pointer but was not'),
          );
        });

        test(
          'detects raw binary in intermediate commits when auditIntermediateCommits is true',
          () async {
            final mockRunner = createGitMockRunner(
              diffOutput: 'assets/photo.jpg\u0000',
              fsckExitCode: 1,
              fsckOutput:
                  'pointer: unexpectedGitObject: "assets/photo.jpg" (treeish sha12345) should have been a pointer but was not\n',
            );

            final verifier = LfsVerifier(processRunner: mockRunner.run);
            final result = await verifier.verifyPullRequest(
              baseBranch: 'origin/main',
              auditIntermediateCommits: true,
            );

            expect(result.isSuccess, isFalse);
            expect(result.issues, hasLength(1));
            expect(
              result.issues.first.message,
              contains('should have been a pointer but was not'),
            );
          },
        );

        test(
          'ignores intermediate commits by default when auditIntermediateCommits is false',
          () async {
            final mockRunner = createGitMockRunner(
              diffOutput: '',
              fsckExitCode: 1,
              fsckOutput:
                  'pointer: unexpectedGitObject: "assets/photo.jpg" (treeish sha12345) should have been a pointer but was not\n',
            );

            final verifier = LfsVerifier(processRunner: mockRunner.run);
            final result = await verifier.verifyPullRequest(
              baseBranch: 'origin/main',
              auditIntermediateCommits: false,
            );

            expect(result.isSuccess, isTrue);
            expect(result.issues, isEmpty);
          },
        );
      });

      group('error handling on git failures', () {
        test('fails gracefully when base branch cannot be resolved', () async {
          final mockRunner = MockProcessRunner(exitCode: 1, stderr: 'fatal');
          final verifier = LfsVerifier(processRunner: mockRunner.run);
          final result = await verifier.verifyPullRequest(
            baseBranch: 'nonexistent',
          );

          expect(result.isSuccess, isFalse);
          expect(
            result.issues.first.message,
            contains(
              "Could not resolve base target 'nonexistent' for pull request comparison",
            ),
          );
        });

        test('fails gracefully when merge base cannot be determined', () async {
          final mockRunner = createGitMockRunner(
            customHandler: (executable, arguments) async {
              if (arguments.contains('merge-base')) {
                return ProcessResult(1, 1, '', 'merge-base failed');
              }
              return ProcessResult(1, -999, '', '');
            },
          );

          final verifier = LfsVerifier(processRunner: mockRunner.run);
          final result = await verifier.verifyPullRequest(
            baseBranch: 'origin/main',
          );

          expect(result.isSuccess, isFalse);
          expect(
            result.issues.first.message,
            contains('Could not determine merge base between'),
          );
        });

        test('fails gracefully when git diff fails', () async {
          final mockRunner = createGitMockRunner(
            customHandler: (executable, arguments) async {
              if (arguments.contains('diff')) {
                return ProcessResult(1, 1, '', 'diff failed');
              }
              return ProcessResult(1, -999, '', '');
            },
          );

          final verifier = LfsVerifier(processRunner: mockRunner.run);
          final result = await verifier.verifyPullRequest(
            baseBranch: 'origin/main',
          );

          expect(result.isSuccess, isFalse);
          expect(
            result.issues.first.message,
            contains('Failed to diff commits between'),
          );
        });
      });
    });

    group('verifyTrackedFiles', () {
      test('passes when git lfs fsck succeeds at HEAD', () async {
        final mockRunner = createGitMockRunner(fsckExitCode: 0);

        final verifier = LfsVerifier(processRunner: mockRunner.run);
        final result = await verifier.verifyTrackedFiles();

        expect(result.isSuccess, isTrue);
        expect(result.issues, isEmpty);
      });

      test('detects raw binary in tracked files via fsck', () async {
        final mockRunner = createGitMockRunner(
          fsckExitCode: 1,
          fsckOutput:
              'pointer: unexpectedGitObject: "images/banner.png" (treeish 123) should have been a pointer but was not\n',
        );

        final verifier = LfsVerifier(processRunner: mockRunner.run);
        final result = await verifier.verifyTrackedFiles();

        expect(result.isSuccess, isFalse);
        expect(result.issues, hasLength(1));
        expect(result.issues.first.filePath, equals('images/banner.png'));
        expect(
          result.issues.first.message,
          contains('should have been a pointer but was not'),
        );
      });

      test(
        'handles git lfs fsck failure with repository-level error',
        () async {
          final mockRunner = createGitMockRunner(
            fsckExitCode: 1,
            fsckOutput: 'fatal: error during lfs fsck',
          );

          final verifier = LfsVerifier(processRunner: mockRunner.run);
          final result = await verifier.verifyTrackedFiles();

          expect(result.isSuccess, isFalse);
          expect(
            result.issues.first.message,
            contains('fatal: error during lfs fsck'),
          );
        },
      );
    });

    group('invoked git command line', () {
      // Guards the argv itself. Without these, dropping `--pointers` or
      // mis-scoping the revision would leave every other test green while the
      // tool silently verified nothing.
      /// Returns the argument vectors of every `git` invocation recorded.
      // cspell:ignore Argvs
      List<List<String>> gitArgvs(MockProcessRunner runner) => [
        for (final call in runner.calls)
          if (call.executable == 'git') call.arguments,
      ];

      test('trunk mode invokes git lfs fsck --pointers HEAD', () async {
        final mockRunner = createGitMockRunner(fsckExitCode: 0);

        await LfsVerifier(processRunner: mockRunner.run).verifyTrackedFiles();

        expect(
          gitArgvs(mockRunner),
          contains(equals(['lfs', 'fsck', '--pointers', 'HEAD'])),
        );
      });

      test('intermediate audit scopes fsck to mergeBase..HEAD', () async {
        final mockRunner = createGitMockRunner(
          fsckExitCode: 0,
          mergeBase: 'abc123\n',
        );

        await LfsVerifier(processRunner: mockRunner.run).verifyPullRequest(
          baseBranch: 'origin/main',
          auditIntermediateCommits: true,
        );

        expect(
          gitArgvs(mockRunner),
          contains(equals(['lfs', 'fsck', '--pointers', 'abc123..HEAD'])),
        );
      });

      test('probes each base ref candidate at most once', () async {
        final mockRunner = MockProcessRunner(
          handler: (executable, arguments) async =>
              ProcessResult(1, arguments.contains('rev-parse') ? 1 : 0, '', ''),
        );

        await LfsVerifier(
          processRunner: mockRunner.run,
        ).resolveBaseTarget('origin/main');

        final probed = mockRunner.calls
            .where((c) => c.arguments.contains('rev-parse'))
            .map((c) => c.arguments.last)
            .toList();
        expect(probed, equals(probed.toSet().toList()));
      });
    });

    group('verify routing', () {
      test('routes to verifyPullRequest when baseBranch is set', () async {
        final mockRunner = createGitMockRunner();

        final verifier = LfsVerifier(processRunner: mockRunner.run);
        final result = await verifier.verify(baseBranch: 'origin/main');
        expect(result.isSuccess, isTrue);
      });

      test('routes to verifyTrackedFiles when no args provided', () async {
        final mockRunner = createGitMockRunner();

        final verifier = LfsVerifier(processRunner: mockRunner.run);
        final result = await verifier.verify();
        expect(result.isSuccess, isTrue);
      });
    });

    group('CLI (lfs_verify)', () {
      test('shows help output when --help is supplied', () async {
        final result = await Process.run(Platform.resolvedExecutable, [
          'bin/lfs_verify.dart',
          '--help',
        ]);
        expect(result.exitCode, equals(0));
        expect(result.stdout, contains('Git LFS Verifier'));
        expect(result.stdout, contains('--base-branch'));
        expect(result.stdout, isNot(contains('[...files]')));
      });

      test('fails with exit code 1 on unrecognized argument', () async {
        final result = await Process.run(Platform.resolvedExecutable, [
          'bin/lfs_verify.dart',
          '--unknown-flag',
        ]);
        expect(result.exitCode, equals(1));
        expect(result.stderr, contains('Error parsing arguments'));
      });

      test(
        'fails with error when positional file arguments are provided',
        () async {
          final result = await Process.run(Platform.resolvedExecutable, [
            'bin/lfs_verify.dart',
            'some_file.png',
          ]);
          expect(result.exitCode, equals(1));
          expect(
            result.stderr,
            contains('Error: Positional file arguments are not supported'),
          );
        },
      );

      test(
        'omits bypassed Git LFS instructions when failure is a repository-level ref-not-found error',
        () async {
          final result = await Process.run(Platform.resolvedExecutable, [
            'bin/lfs_verify.dart',
            '--base-branch',
            'nonexistent-ref-12345',
          ]);
          expect(result.exitCode, equals(1));
          expect(result.stderr, contains('Git base ref'));
          expect(
            result.stderr,
            isNot(contains('❌ ERROR: One or more files bypassed Git LFS!')),
          );
        },
      );
    });

    group('isLfsInstalled', () {
      test('returns true when git lfs version succeeds', () async {
        final verifier = LfsVerifier(
          processRunner: (cmd, args) async =>
              ProcessResult(1, 0, 'git-lfs/3.5.0\n', ''),
        );
        expect(await verifier.isLfsInstalled(), isTrue);
      });

      test('returns false when git lfs version fails', () async {
        final verifier = LfsVerifier(
          processRunner: (cmd, args) async =>
              ProcessResult(1, 1, '', 'not a git command'),
        );
        expect(await verifier.isLfsInstalled(), isFalse);
      });

      test('returns false when process runner throws', () async {
        final verifier = LfsVerifier(
          processRunner: (cmd, args) async =>
              throw ProcessException('git', args, 'not found'),
        );
        expect(await verifier.isLfsInstalled(), isFalse);
      });

      test(
        'verify fails with clear issue when git lfs is not installed',
        () async {
          final verifier = LfsVerifier(
            processRunner: (cmd, args) async =>
                ProcessResult(1, 1, '', 'not found'),
          );
          final result = await verifier.verify();
          expect(result.isSuccess, isFalse);
          expect(result.issues, hasLength(1));
          expect(result.issues.first.filePath, isEmpty);
          expect(
            result.issues.first.message,
            contains('Git LFS is not installed or not found in PATH'),
          );
        },
      );
    });
  });
}
