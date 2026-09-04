// Copyright 2026 The Flutter Authors.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/memory.dart';
import 'package:rfc_tools/src/github_client.dart';
import 'package:rfc_tools/src/linter.dart';
import 'package:rfc_tools/src/taxonomy.dart';
import 'package:test/test.dart';

void main() {
  group('RfcLinter', () {
    late MemoryFileSystem fs;
    late FakeGitHubClient gh;
    late Taxonomy taxonomy;

    const validTaxonomy = '''
# RFC 000.0001: Taxonomy
### 000 – Meta
* **000:** Meta
### 100 – Core
* **110:** Foundation
''';

    const validDoc = '''---
type: rfc
rfc: '110.0000'
title: Sample Feature
description: A great new feature for foundation.
status: draft
created: 2026-09-01T00:00:00Z
updated: 2026-09-01T00:00:00Z
tags:
  - 110-foundation
authors:
  - https://github.com/octocat
---

# RFC 110.0000: Sample Feature

## Overview
Body content here.
''';

    setUp(() async {
      fs = MemoryFileSystem();
      gh = FakeGitHubClient(existingUsers: {'octocat'});
      taxonomy = Taxonomy.fromMarkdown(validTaxonomy);
      await fs.directory('rfc').create(recursive: true);
    });

    test('passes completely valid draft RFC in PR', () async {
      final file = fs.file('rfc/110.0000-sample-feature.md');
      await file.writeAsString(validDoc);

      final linter = RfcLinter(
        fs: fs,
        gh: gh,
        taxonomy: taxonomy,
        labels: <String>{}, // PR without any special labels
        validateGitHubUsers: true,
      );

      final issues = await linter.lintFile(file);
      expect(issues, isEmpty);
    });

    test('detects non-kebab-case slug', () async {
      final file = fs.file('rfc/110.0000-Invalid_Slug.md');
      await file.writeAsString(validDoc);

      final linter = RfcLinter(fs: fs, gh: gh, taxonomy: taxonomy);

      final issues = await linter.lintFile(file);
      expect(issues, isNotEmpty);
      expect(issues.first.message, contains('does not match required format'));
    });

    test('detects unknown category against taxonomy', () async {
      final doc = validDoc
          .replaceAll('110.0000', '999.0000')
          .replaceAll('110-foundation', '999-unknown');
      final file = fs.file('rfc/999.0000-sample-feature.md');
      await file.writeAsString(doc);

      final linter = RfcLinter(fs: fs, gh: gh, taxonomy: taxonomy);

      final issues = await linter.lintFile(file);
      expect(
        issues.any(
          (i) => i.message.contains('not defined in the architecture taxonomy'),
        ),
        isTrue,
      );
    });

    test(
      'enforces .0000 when rfc-ready/rfc-assigned is absent in PR',
      () async {
        final doc = validDoc.replaceAll('110.0000', '110.0042');
        final file = fs.file('rfc/110.0042-sample-feature.md');
        await file.writeAsString(doc);

        final linter = RfcLinter(
          fs: fs,
          gh: gh,
          taxonomy: taxonomy,
          labels: <String>{}, // Missing rfc-ready and rfc-assigned
          enforceDrafts: true,
        );

        final issues = await linter.lintFile(file);
        expect(
          issues.any(
            (i) =>
                i.message.contains('RFCs under review must use index "0000"'),
          ),
          isTrue,
        );
      },
    );

    test('allows .NNNN when rfc-assigned or rfc-ready is present', () async {
      final doc = validDoc.replaceAll('110.0000', '110.0042');
      final file = fs.file('rfc/110.0042-sample-feature.md');
      await file.writeAsString(doc);

      final linterReady = RfcLinter(
        fs: fs,
        gh: gh,
        taxonomy: taxonomy,
        labels: {'rfc-ready'},
        enforceDrafts: true,
      );
      expect(await linterReady.lintFile(file), isEmpty);

      final linterAssigned = RfcLinter(
        fs: fs,
        gh: gh,
        taxonomy: taxonomy,
        labels: {'rfc-assigned'},
        enforceDrafts: true,
      );
      expect(await linterAssigned.lintFile(file), isEmpty);
    });

    test(
      'allows .NNNN when enforceDrafts is false (standard mode or main)',
      () async {
        final doc = validDoc.replaceAll('110.0000', '110.0042');
        final file = fs.file('rfc/110.0042-sample-feature.md');
        await file.writeAsString(doc);

        final linter = RfcLinter(fs: fs, gh: gh, taxonomy: taxonomy);

        expect(await linter.lintFile(file), isEmpty);
      },
    );

    test('validates GitHub username existence via fake client', () async {
      final doc = validDoc.replaceAll('octocat', 'nonexistent-user');
      final file = fs.file('rfc/110.0000-sample-feature.md');
      await file.writeAsString(doc);

      final linter = RfcLinter(
        fs: fs,
        gh: gh,
        taxonomy: taxonomy,
        validateGitHubUsers: true,
      );

      final issues = await linter.lintFile(file);
      expect(
        issues.any(
          (i) => i.message.contains(
            'GitHub user "nonexistent-user" does not exist',
          ),
        ),
        isTrue,
      );
    });

    test('detects missing required frontmatter fields', () async {
      const missingType = '''---
rfc: '110.0000'
title: Test
description: Test
status: draft
created: 2026-09-01T00:00:00Z
updated: 2026-09-01T00:00:00Z
tags: [110-foundation]
authors: [https://github.com/octocat]
---
# RFC 110.0000: Test
''';
      final file = fs.file('rfc/110.0000-test.md');
      await file.writeAsString(missingType);

      final linter = RfcLinter(fs: fs, gh: gh, taxonomy: taxonomy);
      final issues = await linter.lintFile(file);
      expect(
        issues.any(
          (i) => i.message.contains('Frontmatter "type" must be "rfc"'),
        ),
        isTrue,
      );
      expect(
        issues.any((i) => i.message.contains('Expected frontmatter format:')),
        isTrue,
      );
    });

    test(
      'reports multiple frontmatter errors together along with expected schema template',
      () async {
        const missingAuthorAndUpdated = '''---
type: rfc
rfc: '110.0000'
title: Multiple Errors
description: Missing author and updated timestamp.
status: draft
created: 2026-09-01T00:00:00Z
tags: [110-foundation]
---
# RFC 110.0000: Multiple Errors
''';
        final file = fs.file('rfc/110.0000-multiple-errors.md');
        await file.writeAsString(missingAuthorAndUpdated);

        final linter = RfcLinter(fs: fs, gh: gh, taxonomy: taxonomy);
        final issues = await linter.lintFile(file);

        expect(
          issues.any(
            (i) => i.message.contains(
              'Frontmatter "updated" must be an ISO 8601 UTC timestamp.',
            ),
          ),
          isTrue,
        );
        expect(
          issues.any(
            (i) => i.message.contains(
              'Frontmatter "authors" must be a non-empty list of authors.',
            ),
          ),
          isTrue,
        );
        expect(
          issues.any((i) => i.message.contains('Expected frontmatter format:')),
          isTrue,
        );
      },
    );

    test('detects heading title mismatch', () async {
      const headingMismatch = '''---
type: rfc
rfc: '110.0000'
title: Real Title
description: Test
status: draft
created: 2026-09-01T00:00:00Z
updated: 2026-09-01T00:00:00Z
tags: [110-foundation]
authors: [https://github.com/octocat]
---
# RFC 110.0000: Mismatched Title
''';
      final file = fs.file('rfc/110.0000-test.md');
      await file.writeAsString(headingMismatch);

      final linter = RfcLinter(fs: fs, gh: gh, taxonomy: taxonomy);
      final issues = await linter.lintFile(file);
      expect(
        issues.any((i) => i.message.contains('First heading title')),
        isTrue,
      );
    });

    test('detects empty items in frontmatter tags', () async {
      final doc = validDoc.replaceAll(
        'tags:\n  - 110-foundation',
        'tags: [""]',
      );
      final file = fs.file('rfc/110.0000-sample-feature.md');
      await file.writeAsString(doc);

      final linter = RfcLinter(fs: fs, gh: gh, taxonomy: taxonomy);
      final issues = await linter.lintFile(file);
      expect(
        issues.any(
          (i) => i.message.contains(
            'Frontmatter "tags" items must be non-empty strings',
          ),
        ),
        isTrue,
      );
    });

    test('detects frontmatter rfc mismatch with filename identifier', () async {
      final doc = validDoc.replaceAll("rfc: '110.0000'", "rfc: '110.0001'");
      final file = fs.file('rfc/110.0000-sample-feature.md');
      await file.writeAsString(doc);

      final linter = RfcLinter(fs: fs, gh: gh, taxonomy: taxonomy);
      final issues = await linter.lintFile(file);
      expect(
        issues.any(
          (i) => i.message.contains(
            'Frontmatter "rfc" value ("110.0001") does not match filename identifier ("110.0000").',
          ),
        ),
        isTrue,
      );
    });

    test('detects unclosed frontmatter', () async {
      const unclosed = '''---
type: rfc
rfc: '110.0000'
title: Unclosed
# Missing closing delimiter
''';
      final file = fs.file('rfc/110.0000-sample-feature.md');
      await file.writeAsString(unclosed);

      final linter = RfcLinter(fs: fs, gh: gh, taxonomy: taxonomy);
      final issues = await linter.lintFile(file);
      expect(
        issues.any(
          (i) => i.message.contains('Unclosed YAML frontmatter delimiter'),
        ),
        isTrue,
      );
    });

    test('detects invalid non-UTC timestamp', () async {
      final doc = validDoc.replaceAll(
        'created: 2026-09-01T00:00:00Z',
        'created: 2026-09-01 12:00:00',
      );
      final file = fs.file('rfc/110.0000-sample-feature.md');
      await file.writeAsString(doc);

      final linter = RfcLinter(fs: fs, gh: gh, taxonomy: taxonomy);
      final issues = await linter.lintFile(file);
      expect(
        issues.any(
          (i) => i.message.contains('must be an ISO 8601 UTC timestamp'),
        ),
        isTrue,
      );
    });

    test(
      'allows editing an existing RFC from main without PR labels',
      () async {
        final doc = validDoc.replaceAll('110.0000', '110.0001');
        final file = fs.file('rfc/110.0001-sample-feature.md');
        await file.writeAsString(doc);

        final linter = RfcLinter(
          fs: fs,
          gh: gh,
          taxonomy: taxonomy,
          labels: <String>{}, // PR with no labels
          existingFilesOnMain: {
            'rfc/110.0001-sample-feature.md',
          }, // Already merged on main!
        );

        final issues = await linter.lintFile(file);
        expect(issues, isEmpty);
      },
    );

    group('LintIssue', () {
      test(
        'toGithubAnnotation percent-encodes newlines and special characters',
        () {
          const template = '''
Expected frontmatter format:
type: rfc
rfc: '000.0001'
description: 100% complete
''';
          const issue = LintIssue(
            filePath: 'rfc/110.0000-feature.md',
            line: 2,
            column: 1,
            message: template,
          );

          final annotation = issue.toGithubAnnotation();
          expect(annotation.contains('\n'), isFalse);
          expect(annotation.contains('\r'), isFalse);
          expect(
            annotation,
            startsWith('::error file=rfc/110.0000-feature.md,line=2,col=1::'),
          );
          expect(
            annotation,
            contains('Expected frontmatter format:%0Atype: rfc'),
          );
          expect(annotation, contains('100%25 complete'));
        },
      );
    });
  });
}
