// Copyright 2026 The Flutter Authors.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:clock/clock.dart';
import 'package:rfc_tools/src/models/rfc_file.dart';
import 'package:test/test.dart';

void main() {
  group('RfcFile', () {
    const sample = '''---
type: rfc
rfc: '110.0000'
title: Extract Value Notifier
description: Extract ValueNotifier into a foundation package.
status: draft
created: 2026-08-27T00:00:00Z
updated: 2026-08-27T00:00:00Z
tags:
  - 110-foundation
authors:
  - https://github.com/octocat
---

# RFC 110.0000: Extract Value Notifier

## Overview
Some markdown text.

```markdown
# RFC 999.9999: Fake Heading in Code Block
```
''';

    test('parses filename, frontmatter, and heading correctly', () {
      final rfc = RfcFile.parse(
        sample,
        path: 'rfc/110.0000-extract-value-notifier.md',
      );

      expect(rfc.hasValidFilename, isTrue);
      expect(rfc.category, equals('110'));
      expect(rfc.index, equals(0));
      expect(rfc.indexString, equals('0000'));
      expect(rfc.slug, equals('extract-value-notifier'));
      expect(rfc.isDraft, isTrue);
      expect(rfc.rfcId, equals('110.0000'));

      expect(rfc.hasFrontmatter, isTrue);
      expect(rfc.hasValidFrontmatter, isTrue);
      expect(rfc.frontmatter, isNotNull);
      expect(rfc.frontmatter!.type, equals('rfc'));
      expect(rfc.frontmatter!.rfc, equals('110.0000'));
      expect(rfc.frontmatter!.status, equals(RfcStatus.draft));
      expect(rfc.frontmatter!.created, equals(DateTime.utc(2026, 8, 27)));
      expect(rfc.frontmatter!.updated, equals(DateTime.utc(2026, 8, 27)));

      // Typed authors
      expect(rfc.authors, isNotNull);
      expect(rfc.authors!.length, equals(1));
      expect(rfc.authors!.first, isA<GitHubAuthor>());
      expect((rfc.authors!.first as GitHubAuthor).username, equals('octocat'));

      // Compatibility accessors
      expect(rfc.frontmatterType, equals('rfc'));
      expect(rfc.frontmatterRfc, equals('110.0000'));
      expect(rfc.frontmatterTitle, equals('Extract Value Notifier'));
      expect(
        rfc.frontmatterDescription,
        equals('Extract ValueNotifier into a foundation package.'),
      );
      expect(rfc.frontmatterStatus, equals('draft'));
      expect(rfc.frontmatterTags, equals(['110-foundation']));
      expect(rfc.frontmatterAuthors, equals(['https://github.com/octocat']));

      expect(rfc.firstHeadingId, equals('110.0000'));
      expect(rfc.firstHeadingTitle, equals('Extract Value Notifier'));
    });

    test('parses email authors into typed RfcAuthor list', () {
      const emailSample = '''---
type: rfc
rfc: '110.0000'
title: Email Author Test
description: Test with email author.
status: draft
created: 2026-08-27T00:00:00Z
updated: 2026-08-27T00:00:00Z
tags:
  - 110-foundation
authors:
  - '"John McDole" <codefu@google.com>'
  - Jane Doe <jane@flutter.dev>
---

# RFC 110.0000: Email Author Test
''';
      final rfc = RfcFile.parse(
        emailSample,
        path: 'rfc/110.0000-email-author-test.md',
      );

      expect(rfc.hasValidFrontmatter, isTrue);
      expect(rfc.authors?.length, equals(2));
      expect(rfc.authors?[0], isA<EmailAuthor>());
      final a1 = rfc.authors?[0] as EmailAuthor;
      expect(a1.name, equals('John McDole'));
      expect(a1.email, equals('codefu@google.com'));

      expect(rfc.authors?[1], isA<EmailAuthor>());
      final a2 = rfc.authors?[1] as EmailAuthor;
      expect(a2.name, equals('Jane Doe'));
      expect(a2.email, equals('jane@flutter.dev'));
    });

    test(
      'enforces schema during parsing and sets frontmatter to null on failure',
      () {
        const invalidSchemaSample = '''---
type: rfc
rfc: '110.0000'
title: Incomplete Frontmatter
---

# RFC 110.0000: Incomplete Frontmatter
''';
        final rfc = RfcFile.parse(
          invalidSchemaSample,
          path: 'rfc/110.0000-incomplete.md',
        );

        expect(rfc.hasFrontmatter, isTrue);
        expect(rfc.hasValidFrontmatter, isFalse);
        expect(rfc.frontmatter, isNull);
        expect(rfc.authors, isNull);
        expect(rfc.frontmatterErrors, isNotEmpty);
        expect(
          rfc.frontmatterErrors.any((e) => e.contains('description')),
          isTrue,
        );
        expect(rfc.frontmatterErrors.any((e) => e.contains('status')), isTrue);
        expect(rfc.frontmatterErrors.any((e) => e.contains('created')), isTrue);

        // Loose accessors still extract raw YAML values if needed
        expect(rfc.frontmatterTitle, equals('Incomplete Frontmatter'));
        expect(rfc.frontmatterRfc, equals('110.0000'));
        expect(rfc.frontmatterDescription, isNull);

        // Rich feedback provides complete view of errors and expected format
        expect(rfc.frontmatterFeedback, isNotNull);
        expect(rfc.frontmatterFeedback, contains('Invalid RFC frontmatter:'));
        expect(
          rfc.frontmatterFeedback,
          contains('Expected frontmatter format:'),
        );
        expect(
          rfc.frontmatterFeedback,
          contains(RfcFrontmatter.expectedSchemaTemplate.trimRight()),
        );
      },
    );

    test(
      'collects feedback for multiple errors including missing authors and updated timestamps',
      () {
        const sampleMissingAuthorAndUpdated = '''---
type: rfc
rfc: '110.0000'
title: Missing Fields
description: Missing author and updated timestamp.
status: draft
created: 2026-08-27T00:00:00Z
tags:
  - 110-foundation
---

# RFC 110.0000: Missing Fields
''';

        final rfc = RfcFile.parse(
          sampleMissingAuthorAndUpdated,
          path: 'rfc/110.0000-missing-fields.md',
        );

        expect(rfc.hasValidFrontmatter, isFalse);
        expect(rfc.frontmatter, isNull);
        expect(rfc.frontmatterErrors.length, equals(2));

        final updatedErr = rfc.frontmatterErrors.firstWhere(
          (e) => e.contains('"updated"'),
        );
        expect(
          updatedErr,
          contains('Frontmatter "updated" must be an ISO 8601 UTC timestamp.'),
        );
        expect(updatedErr, contains('Expected format: YYYY-MM-DDTHH:MM:SSZ'));

        final authorsErr = rfc.frontmatterErrors.firstWhere(
          (e) => e.contains('"authors"'),
        );
        expect(
          authorsErr,
          contains(
            'Frontmatter "authors" must be a non-empty list of authors.',
          ),
        );
        expect(authorsErr, contains('Expected format:'));

        // Complete view of frontmatter with expected format
        expect(rfc.frontmatterFeedback, isNotNull);
        expect(rfc.frontmatterFeedback, contains('Invalid RFC frontmatter:'));
        expect(rfc.frontmatterFeedback, contains(updatedErr));
        expect(rfc.frontmatterFeedback, contains(authorsErr));
        expect(
          rfc.frontmatterFeedback,
          contains('Expected frontmatter format:'),
        );
        expect(
          rfc.frontmatterFeedback,
          contains(RfcFrontmatter.exampleTemplate.trimRight()),
        );
      },
    );

    test(
      'frontmatterFeedback is null when frontmatter is completely valid',
      () {
        final rfc = RfcFile.parse(
          sample,
          path: 'rfc/110.0000-extract-value-notifier.md',
        );
        expect(rfc.hasValidFrontmatter, isTrue);
        expect(rfc.frontmatterFeedback, isNull);
      },
    );

    test(
      'transformedContent updates frontmatter rfc and header while preserving status and code blocks',
      () {
        final rfc = RfcFile.parse(
          sample,
          path: 'rfc/110.0000-extract-value-notifier.md',
        );

        final fixedTime = DateTime.utc(2026, 9, 1, 12, 0, 0);
        final transformed = rfc.transformedContent(
          newCategory: '110',
          newIndex: '0042',
          updatedTime: fixedTime,
        );

        // Verify frontmatter updates
        expect(transformed, contains("rfc: '110.0042'"));
        expect(transformed, contains('updated: 2026-09-01T12:00:00.000Z'));
        expect(
          transformed,
          contains('status: draft'),
        ); // Preserves draft status!
        expect(transformed, contains('created: 2026-08-27T00:00:00Z'));

        // Verify header update
        expect(transformed, contains('# RFC 110.0042: Extract Value Notifier'));

        // Verify code block is untouched
        expect(
          transformed,
          contains('# RFC 999.9999: Fake Heading in Code Block'),
        );
      },
    );

    test(
      'transformedContent preserves custom user fields and comments in frontmatter',
      () {
        const customSample = '''---
type: rfc
rfc: '110.0000'
title: Extract Value Notifier
description: Extract ValueNotifier into a foundation package.
status: draft
created: 2026-08-27T00:00:00Z
updated: 2026-08-27T00:00:00Z
tags:
  - 110-foundation
authors:
  - https://github.com/octocat
# Custom user rider data:
tracking_issue: https://github.com/flutter/flutter/issues/12345
sponsor:
  team: framework
  lead: jane
custom_flags: [alpha, experimental]
---

# RFC 110.0000: Extract Value Notifier
''';

        final rfc = RfcFile.parse(
          customSample,
          path: 'rfc/110.0000-extract-value-notifier.md',
        );

        final transformed = rfc.transformedContent(
          newCategory: '110',
          newIndex: '0042',
          updatedTime: DateTime.utc(2026, 9, 1, 12, 0, 0),
        );

        expect(transformed, contains("rfc: '110.0042'"));
        expect(transformed, contains('updated: 2026-09-01T12:00:00.000Z'));
        expect(transformed, contains('# Custom user rider data:'));
        expect(
          transformed,
          contains(
            'tracking_issue: https://github.com/flutter/flutter/issues/12345',
          ),
        );
        expect(transformed, contains('  team: framework'));
        expect(transformed, contains('custom_flags: [alpha, experimental]'));
      },
    );

    test('detects invalid filenames', () {
      final rfc1 = RfcFile.parse('', path: 'rfc/110.1-too-short.md');
      expect(rfc1.hasValidFilename, isFalse);

      final rfc2 = RfcFile.parse('', path: 'rfc/110.0001-UPPERCASE.md');
      expect(rfc2.hasValidFilename, isFalse);

      final rfc3 = RfcFile.parse('', path: 'rfc/invalid.md');
      expect(rfc3.hasValidFilename, isFalse);
    });

    test('parses CRLF line endings and transforms properly', () {
      const crlfSample =
          "---\r\ntype: rfc\r\nrfc: '110.0000'\r\ntitle: CRLF Test\r\nstatus: draft\r\n---\r\n\r\n# RFC 110.0000: CRLF Test\r\n";
      final rfc = RfcFile.parse(crlfSample, path: 'rfc/110.0000-crlf-test.md');
      expect(rfc.hasFrontmatter, isTrue);
      expect(rfc.frontmatterTitle, equals('CRLF Test'));
      expect(rfc.firstHeadingTitle, equals('CRLF Test'));

      final transformed = rfc.transformedContent(
        newCategory: '110',
        newIndex: '0005',
        updatedTime: DateTime.utc(2026, 9, 1),
      );
      expect(transformed, contains("rfc: '110.0005'"));
      expect(transformed, contains('# RFC 110.0005: CRLF Test'));
    });

    test('handles trailing whitespace on frontmatter delimiter line', () {
      const trailingSpaceSample =
          "---\ntype: rfc\nrfc: '110.0000'\ntitle: Space Test\nstatus: draft\n---   \n\n# RFC 110.0000: Space Test\n";
      final rfc = RfcFile.parse(
        trailingSpaceSample,
        path: 'rfc/110.0000-space-test.md',
      );
      expect(rfc.hasFrontmatter, isTrue);
      expect(rfc.frontmatterTitle, equals('Space Test'));
      expect(rfc.frontmatterError, isNull);
    });

    test('ignores code blocks that precede the first level-1 heading', () {
      const precedingCodeBlockSample = '''---
type: rfc
rfc: '110.0000'
title: Real Title
description: Test
status: draft
created: 2026-08-27T00:00:00Z
updated: 2026-08-27T00:00:00Z
tags: [110-foundation]
authors: [https://github.com/octocat]
---

Introductory code example:
```markdown
# RFC 999.9999: Code Block Heading Example
```

# RFC 110.0000: Real Title

Content here.
''';

      final rfc = RfcFile.parse(
        precedingCodeBlockSample,
        path: 'rfc/110.0000-real-title.md',
      );

      // Parser must recognize the actual heading, not the code block
      expect(rfc.firstHeadingId, equals('110.0000'));
      expect(rfc.firstHeadingTitle, equals('Real Title'));

      // Transformer must replace the real heading and leave the code block intact
      final transformed = rfc.transformedContent(
        newCategory: '110',
        newIndex: '0002',
      );
      expect(
        transformed,
        contains('# RFC 999.9999: Code Block Heading Example'),
      );
      expect(transformed, contains('# RFC 110.0002: Real Title'));
    });

    test('exposes supersedes and supersededBy accessors', () {
      const supersedesSample = '''---
type: rfc
rfc: '110.0002'
title: Supersedes Test
description: Test
status: stable
created: 2026-08-27T00:00:00Z
updated: 2026-08-27T00:00:00Z
tags: [110-foundation]
authors: [https://github.com/octocat]
supersedes: '110.0001'
superseded_by: '110.0003'
---

# RFC 110.0002: Supersedes Test
''';

      final rfc = RfcFile.parse(
        supersedesSample,
        path: 'rfc/110.0002-supersedes-test.md',
      );
      expect(rfc.index, equals(2));
      expect(rfc.indexString, equals('0002'));
      expect(rfc.frontmatterSupersedes, equals('110.0001'));
      expect(rfc.frontmatterSupersededBy, equals('110.0003'));
      expect(rfc.frontmatter?.supersedes, equals('110.0001'));
      expect(rfc.frontmatter?.supersededBy, equals('110.0003'));
    });

    test('transformedContent validates newCategory and newIndex format', () {
      final rfc = RfcFile.parse(sample, path: 'rfc/110.0000-sample.md');
      expect(
        () => rfc.transformedContent(newCategory: '11', newIndex: '0001'),
        throwsArgumentError,
      );
      expect(
        () => rfc.transformedContent(newCategory: '110', newIndex: '1'),
        throwsArgumentError,
      );
      expect(
        () => rfc.transformedContent(newCategory: -1, newIndex: '0001'),
        throwsArgumentError,
      );
      expect(
        () => rfc.transformedContent(newCategory: 1000, newIndex: '0001'),
        throwsArgumentError,
      );
      expect(
        () => rfc.transformedContent(newCategory: 3.14, newIndex: '0001'),
        throwsArgumentError,
      );
      expect(
        () => rfc.transformedContent(newCategory: '110', newIndex: -1),
        throwsArgumentError,
      );
      expect(
        () => rfc.transformedContent(newCategory: '110', newIndex: 10000),
        throwsArgumentError,
      );
      expect(
        () => rfc.transformedContent(newCategory: '110', newIndex: 3.14),
        throwsArgumentError,
      );
    });

    test(
      'transformedContent accepts int newCategory and newIndex and formats properly',
      () {
        final rfc = RfcFile.parse(sample, path: 'rfc/110.0000-sample.md');
        final transformed = rfc.transformedContent(
          newCategory: 0,
          newIndex: 42,
          updatedTime: DateTime.utc(2026, 9, 1),
        );
        expect(transformed, contains("rfc: '000.0042'"));
        expect(transformed, contains('# RFC 000.0042: Extract Value Notifier'));
      },
    );

    test('parses categoryNumber correctly', () {
      final rfc = RfcFile.parse(sample, path: 'rfc/110.0000-sample.md');
      expect(rfc.categoryNumber, equals(110));
      expect(rfc.category, equals('110'));

      final invalid = RfcFile.parse('', path: 'rfc/invalid.md');
      expect(invalid.categoryNumber, isNull);
    });

    test('transformedContent uses clock.now() when updatedTime is omitted', () {
      final rfc = RfcFile.parse(sample, path: 'rfc/110.0000-sample.md');
      final fixedTime = DateTime.utc(2026, 11, 12, 18, 45, 0);
      withClock(Clock.fixed(fixedTime), () {
        final transformed = rfc.transformedContent(
          newCategory: '110',
          newIndex: '0007',
        );
        expect(transformed, contains('updated: 2026-11-12T18:45:00.000Z'));
      });
    });

    group('RfcNumberFormatting extension', () {
      test('toNNNN formats integers to 4-digit zero-padded strings', () {
        expect(0.toNNNN(), equals('0000'));
        expect(1.toNNNN(), equals('0001'));
        expect(42.toNNNN(), equals('0042'));
        expect(110.toNNNN(), equals('0110'));
        expect(9999.toNNNN(), equals('9999'));
      });

      test('toAAA formats integers to 3-digit zero-padded strings', () {
        expect(0.toAAA(), equals('000'));
        expect(1.toAAA(), equals('001'));
        expect(42.toAAA(), equals('042'));
        expect(110.toAAA(), equals('110'));
        expect(999.toAAA(), equals('999'));
      });
    });
  });
}
