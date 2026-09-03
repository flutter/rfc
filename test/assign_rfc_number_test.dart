// Copyright 2026 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:clock/clock.dart';
import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:rfc_tools/src/assigner.dart';
import 'package:rfc_tools/src/models/rfc_file.dart';
import 'package:rfc_tools/src/validator.dart';
import 'package:test/test.dart';

import 'mock_process_runner.dart';

void main() {
  group('RfcAssigner', () {
    late MemoryFileSystem fs;

    RfcAssigner createAssigner({
      FileSystem? fileSystem,
      GitListFunction? gitList,
    }) {
      return RfcAssigner(
        fs: fileSystem ?? fs,
        gitList:
            gitList ??
            ({String baseBranch = 'origin/main'}) async => <String>{},
      );
    }

    setUp(() async {
      fs = MemoryFileSystem();
      await fs.directory('rfc').create(recursive: true);
    });

    String rfcBody(String rfcNumber, String title) =>
        '''---
type: rfc
rfc: '$rfcNumber'
title: $title
description: Test
status: draft
created: 2026-08-27T00:00:00Z
updated: 2026-08-27T00:00:00Z
tags: [000-meta]
authors: [https://github.com/octocat]
---
# RFC $rfcNumber: $title
''';

    test('allocates 0003 when 0001 and 0002 exist', () async {
      // Existing RFCs
      await fs
          .file('rfc/000.0001-taxonomy.md')
          .writeAsString(rfcBody('000.0001', 'Taxonomy'));

      await fs
          .file('rfc/000.0002-process.md')
          .writeAsString(rfcBody('000.0002', 'Process'));

      // New draft to assign
      await fs
          .file('rfc/000.0000-third-document.md')
          .writeAsString(rfcBody('000.0000', 'Third Document'));

      final assigner = createAssigner();
      final result = await assigner.assign();

      expect(result.category, equals('000'));
      expect(result.oldIndex, equals(0));
      expect(result.oldIndex.toNNNN(), equals('0000'));
      expect(result.newIndex, equals(3));
      expect(result.newIndex.toNNNN(), equals('0003'));
      expect(result.newPath, equals('rfc/000.0003-third-document.md'));

      // Old draft file removed, new file created
      expect(await fs.file('rfc/000.0000-third-document.md').exists(), isFalse);
      expect(await fs.file('rfc/000.0003-third-document.md').exists(), isTrue);

      final newFileContent = await fs
          .file('rfc/000.0003-third-document.md')
          .readAsString();
      final parsed = RfcFile.parse(newFileContent, path: result.newPath);
      expect(parsed.frontmatter?.rfc, equals('000.0003'));
      expect(
        parsed.frontmatter?.status,
        equals(RfcStatus.draft),
      ); // Preserves draft status!
      expect(parsed.firstHeadingId, equals('000.0003'));
    });

    test('allocates 0001 when category has no previous RFCs', () async {
      await fs
          .file('rfc/110.0000-foundation-feature.md')
          .writeAsString(rfcBody('110.0000', 'Foundation Feature'));

      final assigner = createAssigner();
      final result = await assigner.assign();

      expect(result.category, equals('110'));
      expect(result.newIndex, equals(1));
      expect(result.newPath, equals('rfc/110.0001-foundation-feature.md'));
      expect(
        await fs.file('rfc/110.0001-foundation-feature.md').exists(),
        isTrue,
      );
    });

    test(
      'allocates next sequential number considering files present on main branch via gitList',
      () async {
        await fs
            .file('rfc/110.0000-new-feature.md')
            .writeAsString(rfcBody('110.0000', 'New Feature'));

        final simulatedMain = {
          'rfc/110.0001-main-feature.md',
          'rfc/110.0002-main-feature-2.md',
        };

        final assigner = createAssigner(
          gitList: ({String baseBranch = 'origin/main'}) async => simulatedMain,
        );
        final result = await assigner.assign();

        expect(result.category, equals('110'));
        expect(result.newIndex, equals(3));
        expect(result.newPath, equals('rfc/110.0003-new-feature.md'));
        expect(await fs.file('rfc/110.0003-new-feature.md').exists(), isTrue);
      },
    );

    test(
      'handles Edge Case 1: re-allocates when collision occurs against main',
      () async {
        // Local branch has 110.0002-feature-b.md, but main already merged 110.0002-feature-a.md!
        await fs
            .file('rfc/110.0002-feature-b.md')
            .writeAsString(rfcBody('110.0002', 'Feature B'));

        final simulatedMain = {
          'rfc/110.0001-foundation.md',
          'rfc/110.0002-feature-a.md', // Collision!
        };

        final assigner = createAssigner(
          gitList: ({String baseBranch = 'origin/main'}) async => simulatedMain,
        );
        final result = await assigner.assign();

        expect(result.category, equals('110'));
        expect(result.oldIndex, equals(2));
        expect(result.newIndex, equals(3)); // Re-allocated to next available!
        expect(result.newPath, equals('rfc/110.0003-feature-b.md'));
        expect(await fs.file('rfc/110.0003-feature-b.md').exists(), isTrue);
        expect(await fs.file('rfc/110.0002-feature-b.md').exists(), isFalse);
      },
    );

    test(
      'handles full lifecycle: 0000 -> assigned 0042 -> collision on main -> re-labeled -> 0043',
      () async {
        // 1. User starts with AAA.0000
        await fs
            .file('rfc/110.0000-state-management.md')
            .writeAsString(rfcBody('110.0000', 'State Management Revamp'));

        // Main branch has up to 0041 merged.
        final initialMain = {
          for (var i = 1; i <= 41; i++) 'rfc/110.${i.toNNNN()}-feature-$i.md',
        };

        // 2 & 3. Shepherd uses assign-rfc-number -> allocates 0042
        final gitMain = Set<String>.from(initialMain);
        final initialAssigner = createAssigner(
          gitList: ({String baseBranch = 'origin/main'}) async => gitMain,
        );
        final assignResult1 = await initialAssigner.assign();

        expect(assignResult1.newIndex, equals(42));
        expect(
          assignResult1.newPath,
          equals('rfc/110.0042-state-management.md'),
        );
        expect(
          await fs.file('rfc/110.0000-state-management.md').exists(),
          isFalse,
        );
        expect(
          await fs.file('rfc/110.0042-state-management.md').exists(),
          isTrue,
        );

        // 4. While under review, someone else lands 0042 on main!
        gitMain.add('rfc/110.0042-competing-feature.md');

        // 5.a) Validator detects semantic conflict against main (checkMain)
        final validator = RfcValidator(
          fs: fs,
          gitList: ({String baseBranch = 'origin/main'}) async => gitMain,
        );
        final valResult = await validator.validate(checkMain: true);
        expect(valResult.isValid, isFalse);
        expect(
          valResult.errors.any(
            (e) =>
                e.message.contains(
                  'collides with existing RFC in origin/main',
                ) &&
                e.message.contains('110.0042-competing-feature.md'),
          ),
          isTrue,
        );

        // 5.b) Shepherd re-labels with assign-rfc-number -> re-allocates to 0043!
        final reAssigner = createAssigner(
          gitList: ({String baseBranch = 'origin/main'}) async => gitMain,
        );
        final assignResult2 = await reAssigner.assign();

        expect(assignResult2.oldIndex, equals(42));
        expect(assignResult2.newIndex, equals(43));
        expect(
          assignResult2.newPath,
          equals('rfc/110.0043-state-management.md'),
        );

        // Filesystem check: 0042 deleted, 0043 created
        expect(
          await fs.file('rfc/110.0042-state-management.md').exists(),
          isFalse,
        );
        expect(
          await fs.file('rfc/110.0043-state-management.md').exists(),
          isTrue,
        );

        // Document content check: frontmatter, title, timestamp, draft status
        final newContent = await fs
            .file('rfc/110.0043-state-management.md')
            .readAsString();
        final parsed = RfcFile.parse(newContent, path: assignResult2.newPath);
        expect(parsed.frontmatter?.rfc, equals('110.0043'));
        expect(parsed.frontmatter?.status, equals(RfcStatus.draft));
        expect(parsed.firstHeadingId, equals('110.0043'));
        expect(parsed.firstHeadingTitle, equals('State Management Revamp'));

        // Post-reassignment validation check: now passes cleanly against main!
        final postValResult = await validator.validate(checkMain: true);
        expect(postValResult.isValid, isTrue);
      },
    );

    test('dry-run mode does not modify filesystem or labels', () async {
      await fs
          .file('rfc/210.0000-engine-work.md')
          .writeAsString(rfcBody('210.0000', 'Engine Work'));

      final assigner = createAssigner();
      final result = await assigner.assign(dryRun: true);

      expect(result.dryRun, isTrue);
      expect(result.newIndex, equals(1));
      // File should NOT be changed on disk
      expect(await fs.file('rfc/210.0000-engine-work.md').exists(), isTrue);
      expect(await fs.file('rfc/210.0001-engine-work.md').exists(), isFalse);
    });

    test('assigns specific targetPath when multiple drafts exist', () async {
      await fs
          .file('rfc/110.0000-draft-a.md')
          .writeAsString(rfcBody('110.0000', 'Draft A'));

      await fs
          .file('rfc/110.0000-draft-b.md')
          .writeAsString(rfcBody('110.0000', 'Draft B'));

      final assigner = createAssigner();
      // Throws without targetPath
      expect(() => assigner.assign(), throwsStateError);

      // Succeeds with explicit targetPath
      final result = await assigner.assign(
        targetPath: 'rfc/110.0000-draft-b.md',
      );
      expect(result.newIndex, equals(1));
      expect(result.newPath, equals('rfc/110.0001-draft-b.md'));
      expect(await fs.file('rfc/110.0001-draft-b.md').exists(), isTrue);
      expect(await fs.file('rfc/110.0000-draft-a.md').exists(), isTrue);
    });

    test('throws StateError when no RFC requiring assignment exists', () async {
      await fs
          .file('rfc/110.0001-existing.md')
          .writeAsString(rfcBody('110.0001', 'Existing'));

      final assigner = createAssigner();
      expect(() => assigner.assign(), throwsStateError);
    });

    test(
      'assign uses clock.now() for updated timestamp when updatedTime is omitted',
      () async {
        await fs
            .file('rfc/110.0000-clock-test.md')
            .writeAsString(rfcBody('110.0000', 'Clock Test'));

        final fixedTime = DateTime.utc(2026, 12, 25, 10, 30, 0);
        await withClock(Clock.fixed(fixedTime), () async {
          final assigner = createAssigner();
          final result = await assigner.assign();
          expect(
            result.newContent,
            contains('updated: 2026-12-25T10:30:00.000Z'),
          );
        });
      },
    );

    test(
      'assign uses clock.now() and converts non-UTC clock to Zulu UTC string',
      () async {
        await fs
            .file('rfc/110.0000-clock-offset.md')
            .writeAsString(rfcBody('110.0000', 'Offset Test'));

        // Non-UTC timezone (e.g. +14:00)
        final fixedOffsetTime = DateTime.parse('2026-09-02T02:00:00+14:00');
        await withClock(Clock.fixed(fixedOffsetTime), () async {
          final assigner = createAssigner();
          final result = await assigner.assign();
          expect(
            result.newContent,
            contains('updated: 2026-09-01T12:00:00.000Z'),
          );
        });
      },
    );

    test('throws ArgumentError when targetPath does not exist', () async {
      final assigner = createAssigner();
      expect(
        () => assigner.assign(targetPath: 'rfc/110.0000-nonexistent.md'),
        throwsArgumentError,
      );
    });

    test(
      'throws StateError when targetPath does not conform to AAA.NNNN-<slug>.md',
      () async {
        await fs.file('rfc/invalid-name.md').writeAsString('# Invalid');
        final assigner = createAssigner();
        expect(
          () => assigner.assign(targetPath: 'rfc/invalid-name.md'),
          throwsStateError,
        );
      },
    );

    test('ignores non-matching files and files from other categories', () async {
      // Files that do not conform to RFC pattern or belong to other categories
      await fs.file('rfc/README.md').writeAsString('# Notes');
      await fs.file('rfc/.DS_Store').writeAsString('');
      await fs
          .file('rfc/200.0001-other-category.md')
          .writeAsString(rfcBody('200.0001', 'Other'));

      // Target draft in category 110
      await fs
          .file('rfc/110.0000-target.md')
          .writeAsString(rfcBody('110.0000', 'Target'));

      final assigner = createAssigner();
      final result = await assigner.assign();

      expect(result.category, equals('110'));
      expect(result.newIndex, equals(1));
      expect(result.newPath, equals('rfc/110.0001-target.md'));
    });

    test(
      'throws StateError when multiple collisions occur against main',
      () async {
        await fs
            .file('rfc/110.0002-feature-b.md')
            .writeAsString(rfcBody('110.0002', 'Feature B'));

        await fs
            .file('rfc/110.0003-feature-c.md')
            .writeAsString(rfcBody('110.0003', 'Feature C'));

        final simulatedMain = {
          'rfc/110.0002-feature-a.md', // Collides with 110.0002-feature-b.md
          'rfc/110.0003-feature-z.md', // Collides with 110.0003-feature-c.md
        };

        final assigner = createAssigner(
          gitList: ({String baseBranch = 'origin/main'}) async => simulatedMain,
        );

        expect(() => assigner.assign(), throwsStateError);
      },
    );

    test('handles gaps in existing numbers correctly', () async {
      // NOTE: The validator will fail when there are gaps; this is only
      // checking the assign assigns max+1.
      await fs
          .file('rfc/110.0001-first.md')
          .writeAsString(rfcBody('110.0001', 'First'));

      await fs
          .file('rfc/110.0004-fourth.md')
          .writeAsString(rfcBody('110.0004', 'Fourth'));

      await fs
          .file('rfc/110.0000-new.md')
          .writeAsString(rfcBody('110.0000', 'New'));

      final assigner = createAssigner();
      final result = await assigner.assign();

      expect(result.newIndex, equals(5));
      expect(result.newPath, equals('rfc/110.0005-new.md'));
    });

    test('assigns correctly when targetPath is an absolute path', () async {
      await fs
          .file('rfc/110.0000-abs-path.md')
          .writeAsString(rfcBody('110.0000', 'Absolute Path'));

      final absPath = fs.file('rfc/110.0000-abs-path.md').absolute.path;
      final assigner = createAssigner();
      final result = await assigner.assign(targetPath: absPath);

      expect(result.category, equals('110'));
      expect(result.newIndex, equals(1));
      expect(await fs.file(result.newPath).exists(), isTrue);
      expect(await fs.file(absPath).exists(), isFalse);
    });

    test('throws StateError when category exceeds index 9999', () async {
      await fs
          .file('rfc/110.9999-last.md')
          .writeAsString(rfcBody('110.9999', 'Last'));

      await fs
          .file('rfc/110.0000-overflow.md')
          .writeAsString(rfcBody('110.0000', 'Overflow'));

      final assigner = createAssigner();
      expect(() => assigner.assign(), throwsStateError);
    });

    test('throws ArgumentError when targetPath does not exist', () async {
      final assigner = createAssigner();
      expect(
        () => assigner.assign(targetPath: 'rfc/110.0000-nonexistent.md'),
        throwsArgumentError,
      );
    });

    test('default constructor uses RfcAssigner.defaultGitList', () {
      final assigner = RfcAssigner(fs: fs);
      expect(assigner.gitList, equals(RfcAssigner.defaultGitList));
    });

    test(
      'RfcAssigner.defaultGitList accepts processRunner and queries rfc/ directory',
      () async {
        final runner = MockProcessRunner(
          exitCode: 0,
          stdout: 'rfc/000.0001-taxonomy.md\n',
        );
        final list = await RfcAssigner.defaultGitList(
          processRunner: runner.run,
        );
        expect(list, equals({'rfc/000.0001-taxonomy.md'}));
        expect(
          runner.calls.last.arguments,
          equals(['ls-tree', '-r', '--name-only', 'origin/main', 'rfc/']),
        );
      },
    );
  });

  group('RfcAssigner.defaultGitList', () {
    test('remote branch success returns parsed filenames', () async {
      final runner = MockProcessRunner(
        exitCode: 0,
        stdout: 'rfc/000.0001-taxonomy.md\nrfc/000.0002-process.md\n',
      );

      final files = await RfcAssigner.defaultGitList(
        baseBranch: 'origin/main',
        processRunner: runner.run,
      );

      expect(
        files,
        equals({'rfc/000.0001-taxonomy.md', 'rfc/000.0002-process.md'}),
      );
      expect(runner.calls, hasLength(1));
      expect(runner.calls.first.executable, equals('git'));
      expect(
        runner.calls.first.arguments,
        equals(['ls-tree', '-r', '--name-only', 'origin/main', 'rfc/']),
      );
    });

    test('local branch fallback when remote branch fails', () async {
      final runner = MockProcessRunner(
        handler: (executable, arguments) async {
          if (arguments.contains('origin/main')) {
            return ProcessResult(
              1,
              1,
              '',
              'fatal: Not a valid object name origin/main',
            );
          }
          if (arguments.contains('main')) {
            return ProcessResult(2, 0, 'rfc/000.0001-taxonomy.md\n', '');
          }
          return ProcessResult(3, 1, '', 'unexpected');
        },
      );

      final files = await RfcAssigner.defaultGitList(
        baseBranch: 'origin/main',
        processRunner: runner.run,
      );

      expect(files, equals({'rfc/000.0001-taxonomy.md'}));
      expect(runner.calls, hasLength(2));
      expect(
        runner.calls[0].arguments,
        equals(['ls-tree', '-r', '--name-only', 'origin/main', 'rfc/']),
      );
      expect(
        runner.calls[1].arguments,
        equals(['ls-tree', '-r', '--name-only', 'main', 'rfc/']),
      );
    });

    test('upstream branch fallback when remote branch fails', () async {
      final runner = MockProcessRunner(
        handler: (executable, arguments) async {
          if (arguments.contains('upstream/main')) {
            return ProcessResult(
              1,
              1,
              '',
              'fatal: Not a valid object name upstream/main',
            );
          }
          if (arguments.contains('main')) {
            return ProcessResult(2, 0, 'rfc/000.0001-taxonomy.md\n', '');
          }
          return ProcessResult(3, 1, '', 'unexpected');
        },
      );

      final files = await RfcAssigner.defaultGitList(
        baseBranch: 'upstream/main',
        processRunner: runner.run,
      );

      expect(files, equals({'rfc/000.0001-taxonomy.md'}));
      expect(runner.calls, hasLength(2));
      expect(
        runner.calls[0].arguments,
        equals(['ls-tree', '-r', '--name-only', 'upstream/main', 'rfc/']),
      );
      expect(
        runner.calls[1].arguments,
        equals(['ls-tree', '-r', '--name-only', 'main', 'rfc/']),
      );
    });

    test(
      'local branch without remote prefix fails in single execution',
      () async {
        final runner = MockProcessRunner(exitCode: 1, stderr: 'fatal error');

        final files = await RfcAssigner.defaultGitList(
          baseBranch: 'main',
          processRunner: runner.run,
        );

        expect(files, isEmpty);
        expect(runner.calls, hasLength(1));
      },
    );

    test('error handling when both remote and local fail', () async {
      final runner = MockProcessRunner(exitCode: 1, stderr: 'fatal error');

      final files = await RfcAssigner.defaultGitList(
        baseBranch: 'origin/main',
        processRunner: runner.run,
      );

      expect(files, isEmpty);
      expect(runner.calls, hasLength(2));
    });

    test('error handling when processRunner throws', () async {
      final runner = MockProcessRunner(
        exceptionToThrow: const ProcessException('git', [
          'ls-tree',
        ], 'not found'),
      );

      final files = await RfcAssigner.defaultGitList(
        baseBranch: 'origin/main',
        processRunner: runner.run,
      );

      expect(files, isEmpty);
    });

    test('handles stdout returned as byte list', () async {
      final runner = MockProcessRunner(
        exitCode: 0,
        stdout: [
          114, 102, 99, 47, 48, 48, 48, 46, //
          48, 48, 48, 49, 45, 116, 97, 120,
          111, 110, 111, 109, 121, 46, 109,
          100, 10,
        ], // "rfc/000.0001-taxonomy.md\n"
      );

      final files = await RfcAssigner.defaultGitList(processRunner: runner.run);

      expect(files, equals({'rfc/000.0001-taxonomy.md'}));
    });
  });
}
