// Copyright 2026 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/memory.dart';
import 'package:rfc_tools/src/validator.dart';
import 'package:test/test.dart';

void main() {
  group('RfcValidator', () {
    late MemoryFileSystem fs;

    setUp(() async {
      fs = MemoryFileSystem();
      await fs.directory('rfc').create(recursive: true);
    });

    test('passes valid unique RFC tree', () async {
      await fs.file('rfc/110.0001-feature-a.md').writeAsString('''---
type: rfc
rfc: '110.0001'
title: Feature A
---
''');

      await fs.file('rfc/110.0002-feature-b.md').writeAsString('''---
type: rfc
rfc: '110.0002'
title: Feature B
---
''');

      final validator = RfcValidator(fs: fs);
      final result = await validator.validate();
      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test(
      'ValidationResult is a record supporting isSuccess, isValid, and destructuring',
      () async {
        await fs.file('rfc/110.0001-feature-a.md').writeAsString('''---
type: rfc
rfc: '110.0001'
title: Feature A
---
''');

        final validator = RfcValidator(fs: fs);
        final result = await validator.validate();
        expect(result.isValid, isTrue);
        expect(result.errors, isEmpty);

        // Pattern matching and record destructuring
        final (:isSuccess, :errors) = await validator.validate();
        expect(isSuccess, isTrue);
        expect(errors, isEmpty);
      },
    );

    test('detects duplicate RFC numbers within tree', () async {
      await fs.file('rfc/110.0001-feature-a.md').writeAsString('''---
type: rfc
rfc: '110.0001'
title: Feature A
---
''');

      await fs.file('rfc/110.0001-feature-duplicate.md').writeAsString('''---
type: rfc
rfc: '110.0001'
title: Feature Duplicate
---
''');

      final validator = RfcValidator(fs: fs);
      final result = await validator.validate();
      expect(result.isValid, isFalse);
      expect(
        result.errors.any(
          (e) => e.message.contains('Duplicate RFC number "110.0001"'),
        ),
        isTrue,
      );
    });

    test('rejects .0000 drafts when noDrafts is true', () async {
      await fs.file('rfc/110.0000-unassigned-draft.md').writeAsString('''---
type: rfc
rfc: '110.0000'
title: Draft
---
''');

      final validator = RfcValidator(fs: fs);

      // Passes in PR mode (noDrafts = false)
      final prResult = await validator.validate(noDrafts: false);
      expect(prResult.isValid, isTrue);

      // Fails in Merge Queue / Main mode (noDrafts = true)
      final mqResult = await validator.validate(noDrafts: true);
      expect(mqResult.isValid, isFalse);
      expect(
        mqResult.errors.any(
          (e) => e.message.contains('Draft RFC ".0000" detected'),
        ),
        isTrue,
      );
    });

    test('detects collision against simulated main branch', () async {
      await fs.file('rfc/110.0003-my-branch-feature.md').writeAsString('''---
type: rfc
rfc: '110.0003'
title: My Branch Feature
---
''');

      final validator = RfcValidator(
        fs: fs,
        gitList: ({String baseBranch = 'origin/main'}) async => {
          'rfc/110.0003-merged-pr-feature.md',
        },
      );
      final result = await validator.validate(checkMain: true);

      expect(result.isValid, isFalse);
      expect(
        result.errors.any(
          (e) => e.message.contains('collides with existing RFC'),
        ),
        isTrue,
      );
    });

    test(
      'ignores frontmatter contents and focuses on filename numbers',
      () async {
        await fs.file('rfc/110.0001-feature.md').writeAsString('''---
arbitrary: content
---
# Arbitrary content
''');

        final validator = RfcValidator(fs: fs);
        final result = await validator.validate();
        expect(result.isValid, isTrue);
        expect(result.errors, isEmpty);
      },
    );

    test('reports error when rfc directory does not exist', () async {
      final emptyFs = MemoryFileSystem();
      final validator = RfcValidator(fs: emptyFs);
      final result = await validator.validate();
      expect(result.isValid, isFalse);
      expect(
        result.errors.any((e) => e.message.contains('does not exist')),
        isTrue,
      );
    });

    test('passes baseBranch to gitList when checkMain is true', () async {
      String? capturedBranch;

      await fs.file('rfc/110.0001-feature.md').writeAsString('''---
type: rfc
rfc: '110.0001'
title: Feature
---
''');

      final validator = RfcValidator(
        fs: fs,
        gitList: ({String baseBranch = 'origin/main'}) async {
          capturedBranch = baseBranch;
          return <String>{};
        },
      );

      await validator.validate(checkMain: true, baseBranch: 'custom-branch');

      expect(capturedBranch, equals('custom-branch'));
    });

    test('does not invoke gitList when checkMain is false', () async {
      var gitListCalled = false;
      await fs.file('rfc/110.0001-feature.md').writeAsString('''---
type: rfc
rfc: '110.0001'
title: Feature
---
''');

      final validator = RfcValidator(
        fs: fs,
        gitList: ({String baseBranch = 'origin/main'}) async {
          gitListCalled = true;
          return <String>{};
        },
      );

      final result = await validator.validate(checkMain: false);
      expect(result.isValid, isTrue);
      expect(gitListCalled, isFalse);
    });

    test('default constructor uses defaultGitList', () {
      final validator = RfcValidator(fs: fs);
      expect(validator.gitList, equals(defaultGitList));
    });

    group('sequential numbering gap checks', () {
      test('rejects gap when new RFC jumps ahead of baseBranch', () async {
        await fs.file('rfc/110.0050-jump-ahead.md').writeAsString('''---
type: rfc
rfc: '110.0050'
title: Jump Ahead
---
''');

        final validator = RfcValidator(
          fs: fs,
          gitList: ({String baseBranch = 'origin/main'}) async => {
            'rfc/110.0041-feature-41.md',
            'rfc/110.0042-feature-42.md',
          },
        );

        final result = await validator.validate(checkMain: true);
        expect(result.isValid, isFalse);
        expect(
          result.errors.any(
            (e) => e.message.contains(
              'RFC number "110.0050" creates a numbering gap. '
              'Expected next sequential number is "110.0043" (the latest RFC is "110.0042" in origin/main).',
            ),
          ),
          isTrue,
        );
      });

      test(
        'rejects non-0001 start when no RFCs exist in category on baseBranch',
        () async {
          await fs.file('rfc/120.1234-unallocated-start.md').writeAsString(
            '''---
type: rfc
rfc: '120.1234'
title: Unallocated Start
---
''',
          );

          final validator = RfcValidator(
            fs: fs,
            gitList: ({String baseBranch = 'origin/main'}) async => <String>{},
          );

          final result = await validator.validate(checkMain: true);
          expect(result.isValid, isFalse);
          expect(
            result.errors.any(
              (e) => e.message.contains(
                'RFC number "120.1234" creates a numbering gap. '
                'Expected next sequential number is "120.0001" (no RFCs exist in category "120" in origin/main).',
              ),
            ),
            isTrue,
          );
        },
      );

      test('accepts single sequential RFC following baseBranch', () async {
        await fs.file('rfc/110.0043-next-feature.md').writeAsString('''---
type: rfc
rfc: '110.0043'
title: Next Feature
---
''');

        final validator = RfcValidator(
          fs: fs,
          gitList: ({String baseBranch = 'origin/main'}) async => {
            'rfc/110.0042-existing-feature.md',
          },
        );

        final result = await validator.validate(checkMain: true);
        expect(result.isValid, isTrue);
        expect(result.errors, isEmpty);
      });

      test('accepts multiple sequential RFCs following baseBranch', () async {
        await fs.file('rfc/110.0043-feature-c.md').writeAsString('''---
type: rfc
rfc: '110.0043'
title: Feature C
---
''');
        await fs.file('rfc/110.0044-feature-d.md').writeAsString('''---
type: rfc
rfc: '110.0044'
title: Feature D
---
''');

        final validator = RfcValidator(
          fs: fs,
          gitList: ({String baseBranch = 'origin/main'}) async => {
            'rfc/110.0042-feature-b.md',
          },
        );

        final result = await validator.validate(checkMain: true);
        expect(result.isValid, isTrue);
        expect(result.errors, isEmpty);
      });

      test(
        'rejects non-contiguous multiple new RFCs following baseBranch',
        () async {
          await fs.file('rfc/110.0043-feature-c.md').writeAsString('''---
type: rfc
rfc: '110.0043'
title: Feature C
---
''');
          await fs.file('rfc/110.0045-feature-e.md').writeAsString('''---
type: rfc
rfc: '110.0045'
title: Feature E
---
''');

          final validator = RfcValidator(
            fs: fs,
            gitList: ({String baseBranch = 'origin/main'}) async => {
              'rfc/110.0042-feature-b.md',
            },
          );

          final result = await validator.validate(checkMain: true);
          expect(result.isValid, isFalse);
          expect(result.errors, hasLength(1));
          expect(
            result.errors.first.message,
            contains(
              'RFC number "110.0045" creates a numbering gap. '
              'Expected next sequential number is "110.0044" (the latest RFC is "110.0042" in origin/main).',
            ),
          );
        },
      );

      test(
        'allows modifying existing RFC from baseBranch without gap error',
        () async {
          await fs.file('rfc/110.0042-feature-b.md').writeAsString('''---
type: rfc
rfc: '110.0042'
title: Feature B Updated
---
''');

          final validator = RfcValidator(
            fs: fs,
            gitList: ({String baseBranch = 'origin/main'}) async => {
              'rfc/110.0001-feature-a.md',
              'rfc/110.0042-feature-b.md',
            },
          );

          final result = await validator.validate(checkMain: true);
          expect(result.isValid, isTrue);
          expect(result.errors, isEmpty);
        },
      );

      test('rejects internal gap when checkMain is false', () async {
        await fs.file('rfc/110.0001-feature-a.md').writeAsString('''---
type: rfc
rfc: '110.0001'
title: Feature A
---
''');
        await fs.file('rfc/110.0003-feature-c.md').writeAsString('''---
type: rfc
rfc: '110.0003'
title: Feature C
---
''');

        final validator = RfcValidator(fs: fs);
        final result = await validator.validate(checkMain: false);
        expect(result.isValid, isFalse);
        expect(
          result.errors.any(
            (e) => e.message.contains(
              'RFC number "110.0003" creates a numbering gap. '
              'Expected next sequential number is "110.0002".',
            ),
          ),
          isTrue,
        );
      });

      test(
        'rejects tree starting with index > 0001 when checkMain is false',
        () async {
          await fs.file('rfc/110.0005-feature.md').writeAsString('''---
type: rfc
rfc: '110.0005'
title: Feature
---
''');

          final validator = RfcValidator(fs: fs);
          final result = await validator.validate(checkMain: false);
          expect(result.isValid, isFalse);
          expect(
            result.errors.any(
              (e) => e.message.contains(
                'RFC number "110.0005" creates a numbering gap. '
                'Expected next sequential number is "110.0001".',
              ),
            ),
            isTrue,
          );
        },
      );

      test('skips draft .0000 RFCs during gap validation', () async {
        await fs.file('rfc/110.0000-unassigned-draft.md').writeAsString('''---
type: rfc
rfc: '110.0000'
title: Draft
---
''');

        final validator = RfcValidator(
          fs: fs,
          gitList: ({String baseBranch = 'origin/main'}) async => {
            'rfc/110.0042-feature.md',
          },
        );

        final result = await validator.validate(
          checkMain: true,
          noDrafts: false,
        );
        expect(result.isValid, isTrue);
        expect(result.errors, isEmpty);
      });
    });

    group('ValidationError', () {
      test(
        'toGithubAnnotation percent-encodes newlines and special characters',
        () {
          const error = ValidationError(
            filePath: 'rfc/110.0001-feature.md',
            message: 'First line\nSecond line 100%',
          );

          final annotation = error.toGithubAnnotation();
          expect(annotation.contains('\n'), isFalse);
          expect(
            annotation,
            equals(
              '::error file=rfc/110.0001-feature.md::First line%0ASecond line 100%25',
            ),
          );
        },
      );
    });
  });
}
