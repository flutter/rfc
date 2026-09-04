// Copyright 2026 The Flutter Authors.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:clock/clock.dart';
import 'package:rfc_tools/src/models/rfc_author.dart';
import 'package:rfc_tools/src/models/rfc_frontmatter.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  group('RfcFrontmatter', () {
    const validYaml = '''
type: rfc
rfc: '110.0001'
title: Foundation Architecture
description: Comprehensive architecture overview for foundation.
status: stable
created: 2026-08-27T00:00:00Z
updated: 2026-09-01T12:00:00Z
tags:
  - 110-foundation
  - 000-meta
authors:
  - https://github.com/octocat
  - '"John McDole" <codefu@google.com>'
''';

    const withSupersedes = '''$validYaml
supersedes: '110.0000'
superseded_by: '110.0002'
''';

    test('parses completely valid frontmatter into typed fields', () {
      final fm = RfcFrontmatter.parse(validYaml);

      expect(fm.type, equals('rfc'));
      expect(fm.rfc, equals('110.0001'));
      expect(fm.title, equals('Foundation Architecture'));
      expect(
        fm.description,
        equals('Comprehensive architecture overview for foundation.'),
      );
      expect(fm.status, equals(RfcStatus.stable));
      expect(fm.created, equals(DateTime.utc(2026, 8, 27)));
      expect(fm.created.isUtc, isTrue);
      expect(fm.updated, equals(DateTime.utc(2026, 9, 1, 12, 0, 0)));
      expect(fm.updated.isUtc, isTrue);
      expect(fm.tags, equals(['110-foundation', '000-meta']));

      expect(fm.authors.length, equals(2));
      expect(fm.authors[0], isA<GitHubAuthor>());
      expect((fm.authors[0] as GitHubAuthor).username, equals('octocat'));
      expect(fm.authors[1], isA<EmailAuthor>());
      expect((fm.authors[1] as EmailAuthor).name, equals('John McDole'));
      expect((fm.authors[1] as EmailAuthor).email, equals('codefu@google.com'));

      expect(fm.supersedes, isNull);
      expect(fm.supersededBy, isNull);
    });

    test('parses optional supersedes and superseded_by fields', () {
      final fm = RfcFrontmatter.parse(withSupersedes);
      expect(fm.supersedes, equals('110.0000'));
      expect(fm.supersededBy, equals('110.0002'));
    });

    test('supports value equality and hashCode', () {
      final fm1 = RfcFrontmatter.parse(validYaml);
      final fm2 = RfcFrontmatter.parse(validYaml);
      expect(fm1, equals(fm2));
      expect(fm1.hashCode, equals(fm2.hashCode));

      final fmDifferent = RfcFrontmatter.parse(
        validYaml.replaceAll('110.0001', '110.0002'),
      );
      expect(fm1, isNot(equals(fmDifferent)));
    });

    group('schema validation errors', () {
      test('rejects missing or invalid type', () {
        final yamlMissing =
            loadYaml(validYaml.replaceAll('type: rfc', '')) as YamlMap;
        final errors1 = RfcFrontmatter.validate(yamlMissing);
        expect(
          errors1.any((e) => e.contains('Frontmatter "type" must be "rfc"')),
          isTrue,
        );

        final yamlInvalid =
            loadYaml(validYaml.replaceAll('type: rfc', 'type: doc')) as YamlMap;
        final errors2 = RfcFrontmatter.validate(yamlInvalid);
        expect(
          errors2.any(
            (e) => e.contains('Frontmatter "type" must be "rfc" (found "doc")'),
          ),
          isTrue,
        );
      });

      test('rejects missing or invalid rfc ID', () {
        final yamlMissing =
            loadYaml(validYaml.replaceAll("rfc: '110.0001'", '')) as YamlMap;
        final errors1 = RfcFrontmatter.validate(yamlMissing);
        expect(
          errors1.any(
            (e) => e.contains('Frontmatter "rfc" field is required.'),
          ),
          isTrue,
        );

        final yamlInvalid =
            loadYaml(validYaml.replaceAll("rfc: '110.0001'", "rfc: '11.1'"))
                as YamlMap;
        final errors2 = RfcFrontmatter.validate(yamlInvalid);
        expect(
          errors2.any(
            (e) => e.contains('Frontmatter "rfc" must match format "AAA.NNNN"'),
          ),
          isTrue,
        );
      });

      test('rejects missing or empty title', () {
        final yamlMissing =
            loadYaml(validYaml.replaceAll('title: Foundation Architecture', ''))
                as YamlMap;
        expect(
          RfcFrontmatter.validate(yamlMissing).any(
            (e) => e.contains(
              'Frontmatter "title" is required and must be a non-empty string.',
            ),
          ),
          isTrue,
        );

        final yamlEmpty =
            loadYaml(
                  validYaml.replaceAll(
                    'title: Foundation Architecture',
                    'title: "   "',
                  ),
                )
                as YamlMap;
        expect(
          RfcFrontmatter.validate(yamlEmpty).any(
            (e) => e.contains(
              'Frontmatter "title" is required and must be a non-empty string.',
            ),
          ),
          isTrue,
        );
      });

      test('rejects missing or empty description', () {
        final yamlMissing =
            loadYaml(
                  validYaml.replaceAll(
                    'description: Comprehensive architecture overview for foundation.',
                    '',
                  ),
                )
                as YamlMap;
        expect(
          RfcFrontmatter.validate(yamlMissing).any(
            (e) => e.contains(
              'Frontmatter "description" is required and must be a non-empty string.',
            ),
          ),
          isTrue,
        );
      });

      test('rejects missing or invalid status', () {
        final yamlMissing =
            loadYaml(validYaml.replaceAll('status: stable', '')) as YamlMap;
        expect(
          RfcFrontmatter.validate(
            yamlMissing,
          ).any((e) => e.contains('Frontmatter "status" must be one of:')),
          isTrue,
        );

        final yamlInvalid =
            loadYaml(
                  validYaml.replaceAll(
                    'status: stable',
                    'status: invalid_status',
                  ),
                )
                as YamlMap;
        expect(
          RfcFrontmatter.validate(
            yamlInvalid,
          ).any((e) => e.contains('(found "invalid_status")')),
          isTrue,
        );
      });

      test('rejects non-UTC timestamps and accepts UTC with z suffix', () {
        final yamlLocal =
            loadYaml(
                  validYaml.replaceAll(
                    'created: 2026-08-27T00:00:00Z',
                    'created: 2026-08-27 12:00:00',
                  ),
                )
                as YamlMap;
        expect(
          RfcFrontmatter.validate(yamlLocal).any(
            (e) => e.contains(
              'Frontmatter "created" must be an ISO 8601 UTC timestamp',
            ),
          ),
          isTrue,
        );

        final yamlNotDate =
            loadYaml(
                  validYaml.replaceAll(
                    'updated: 2026-09-01T12:00:00Z',
                    'updated: "not-a-timestamp"',
                  ),
                )
                as YamlMap;
        expect(
          RfcFrontmatter.validate(yamlNotDate).any(
            (e) => e.contains(
              'Frontmatter "updated" must be an ISO 8601 UTC timestamp',
            ),
          ),
          isTrue,
        );

        // Lowercase z should be accepted as valid UTC
        final yamlLowerZ =
            loadYaml(
                  validYaml.replaceAll(
                    'created: 2026-08-27T00:00:00Z',
                    'created: 2026-08-27T00:00:00z',
                  ),
                )
                as YamlMap;
        expect(RfcFrontmatter.validate(yamlLowerZ), isEmpty);

        // Explicit zero-offset UTC formats (+00:00, -00:00, +0000, -0000)
        for (final offset in [
          '+00:00',
          '-00:00',
          '+0000',
          '-0000',
          '+00',
          '-00',
        ]) {
          final yamlZeroOffset =
              loadYaml(
                    validYaml.replaceAll(
                      'created: 2026-08-27T00:00:00Z',
                      'created: 2026-08-27T00:00:00$offset',
                    ),
                  )
                  as YamlMap;
          expect(RfcFrontmatter.validate(yamlZeroOffset), isEmpty);
        }

        // Rejects non-zero offsets (not UTC)
        for (final nonUtc in ['+02:00', '-05:00', '+14:00', '-12:00']) {
          final yamlNonUtc =
              loadYaml(
                    validYaml.replaceAll(
                      'created: 2026-08-27T00:00:00Z',
                      'created: 2026-08-27T00:00:00$nonUtc',
                    ),
                  )
                  as YamlMap;
          final errors = RfcFrontmatter.validate(yamlNonUtc);
          expect(errors, isNotEmpty);
          expect(
            errors.any(
              (e) => e.contains(
                'Frontmatter "created" must be an ISO 8601 UTC timestamp',
              ),
            ),
            isTrue,
          );
        }
      });

      test(
        'rejects non-string and non-DateTime created/updated timestamp values',
        () {
          final yamlIntCreated = {
            'type': 'rfc',
            'rfc': '000.0001',
            'title': 'Proposal Title',
            'description': 'Description',
            'status': 'draft',
            'created': 123456,
            'updated': '2026-08-27T00:00:00Z',
            'tags': ['000-meta'],
            'authors': ['https://github.com/octocat'],
          };
          final errors = RfcFrontmatter.validate(yamlIntCreated);
          expect(
            errors.any(
              (e) => e.contains(
                'Frontmatter "created" must be an ISO 8601 UTC timestamp. Found "123456"',
              ),
            ),
            isTrue,
          );

          final yamlBoolCreated = {
            'type': 'rfc',
            'rfc': '000.0001',
            'title': 'Proposal Title',
            'description': 'Description',
            'status': 'draft',
            'created': true,
            'updated': '2026-08-27T00:00:00Z',
            'tags': ['000-meta'],
            'authors': ['https://github.com/octocat'],
          };
          final boolErrors = RfcFrontmatter.validate(yamlBoolCreated);
          expect(
            boolErrors.any(
              (e) => e.contains(
                'Frontmatter "created" must be an ISO 8601 UTC timestamp. Found "true"',
              ),
            ),
            isTrue,
          );

          final yamlListUpdated = {
            'type': 'rfc',
            'rfc': '000.0001',
            'title': 'Proposal Title',
            'description': 'Description',
            'status': 'draft',
            'created': '2026-08-27T00:00:00Z',
            'updated': [2026, 8, 27],
            'tags': ['000-meta'],
            'authors': ['https://github.com/octocat'],
          };
          final listErrors = RfcFrontmatter.validate(yamlListUpdated);
          expect(
            listErrors.any(
              (e) => e.contains(
                'Frontmatter "updated" must be an ISO 8601 UTC timestamp. Found "[2026, 8, 27]"',
              ),
            ),
            isTrue,
          );
        },
      );

      test('rejects invalid tags list or empty tag items', () {
        final yamlNotList =
            loadYaml(
                  validYaml.replaceAll(
                    'tags:\n  - 110-foundation\n  - 000-meta',
                    'tags: 110-foundation',
                  ),
                )
                as YamlMap;
        expect(
          RfcFrontmatter.validate(yamlNotList).any(
            (e) => e.contains(
              'Frontmatter "tags" must be a non-empty list of strings.',
            ),
          ),
          isTrue,
        );

        final yamlEmptyList =
            loadYaml(
                  validYaml.replaceAll(
                    'tags:\n  - 110-foundation\n  - 000-meta',
                    'tags: []',
                  ),
                )
                as YamlMap;
        expect(
          RfcFrontmatter.validate(yamlEmptyList).any(
            (e) => e.contains(
              'Frontmatter "tags" must be a non-empty list of strings.',
            ),
          ),
          isTrue,
        );

        final yamlEmptyItem =
            loadYaml(
                  validYaml.replaceAll(
                    'tags:\n  - 110-foundation\n  - 000-meta',
                    'tags: [""]',
                  ),
                )
                as YamlMap;
        expect(
          RfcFrontmatter.validate(yamlEmptyItem).any(
            (e) => e.contains(
              'Frontmatter "tags" items must be non-empty strings.',
            ),
          ),
          isTrue,
        );
      });

      test('rejects invalid authors list or author formats', () {
        final yamlEmptyList =
            loadYaml(
                  validYaml.replaceAll(
                    'authors:\n  - https://github.com/octocat\n  - \'"John McDole" <codefu@google.com>\'',
                    'authors: []',
                  ),
                )
                as YamlMap;
        expect(
          RfcFrontmatter.validate(yamlEmptyList).any(
            (e) => e.contains(
              'Frontmatter "authors" must be a non-empty list of authors.',
            ),
          ),
          isTrue,
        );

        final yamlInvalidAuthor =
            loadYaml(
                  validYaml.replaceAll(
                    'https://github.com/octocat',
                    'not a valid author',
                  ),
                )
                as YamlMap;
        expect(
          RfcFrontmatter.validate(
            yamlInvalidAuthor,
          ).any((e) => e.contains('Author "not a valid author" must be')),
          isTrue,
        );
      });

      test('rejects invalid supersedes / superseded_by formatting', () {
        final yaml =
            loadYaml('''$validYaml
supersedes: 'invalid'
superseded_by: 'invalid'
''')
                as YamlMap;
        final errors = RfcFrontmatter.validate(yaml);
        expect(
          errors.any(
            (e) => e.contains(
              'Frontmatter "supersedes" must match format "AAA.NNNN"',
            ),
          ),
          isTrue,
        );
        expect(
          errors.any(
            (e) => e.contains(
              'Frontmatter "superseded_by" must match format "AAA.NNNN"',
            ),
          ),
          isTrue,
        );
      });

      test('fromYaml throws FormatException on invalid YAML', () {
        final invalidYaml = loadYaml('type: invalid') as YamlMap;
        expect(
          () => RfcFrontmatter.fromYaml(invalidYaml),
          throwsA(isA<FormatException>()),
        );
      });

      test('parse throws FormatException on non-mapping input', () {
        expect(
          () => RfcFrontmatter.parse('just a scalar string'),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('YAML frontmatter must be a key-value mapping.'),
                contains('Expected frontmatter format:'),
                contains(RfcFrontmatter.expectedSchemaTemplate.trimRight()),
              ),
            ),
          ),
        );
      });

      test('parse throws FormatException on malformed YAML syntax', () {
        expect(
          () => RfcFrontmatter.parse('key: [unclosed list'),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('Failed to parse YAML frontmatter:'),
                contains('Expected frontmatter format:'),
                contains(RfcFrontmatter.expectedSchemaTemplate.trimRight()),
              ),
            ),
          ),
        );
      });

      test('validates and parses standard Dart Map input', () {
        final standardMap = <String, dynamic>{
          'type': 'rfc',
          'rfc': '110.0001',
          'title': 'Foundation Architecture',
          'description': 'Comprehensive architecture overview for foundation.',
          'status': 'stable',
          'created': '2026-08-27T00:00:00Z',
          'updated': '2026-09-01T12:00:00+00:00',
          'tags': ['110-foundation', '000-meta'],
          'authors': ['https://github.com/octocat'],
        };

        final fm = RfcFrontmatter.fromYaml(standardMap);
        expect(fm.rfc, equals('110.0001'));
        expect(fm.updated, equals(DateTime.utc(2026, 9, 1, 12, 0, 0)));

        // Unmodifiable collections
        expect(() => fm.tags.add('extra'), throwsUnsupportedError);
        expect(
          () => fm.authors.add(const GitHubAuthor(username: 'hacker')),
          throwsUnsupportedError,
        );
      });

      test('rejects non-string title and description types', () {
        final yamlStr = validYaml
            .replaceAll(
              'title: Foundation Architecture',
              'title: [not, a, string]',
            )
            .replaceAll(
              'description: Comprehensive architecture overview for foundation.',
              'description: 12345',
            );
        final yaml = loadYaml(yamlStr) as YamlMap;
        final errors = RfcFrontmatter.validate(yaml);
        expect(
          errors.any(
            (e) => e.contains(
              'Frontmatter "title" is required and must be a non-empty string.',
            ),
          ),
          isTrue,
        );
        expect(
          errors.any(
            (e) => e.contains(
              'Frontmatter "description" is required and must be a non-empty string.',
            ),
          ),
          isTrue,
        );
      });

      test(
        'tryLoad returns null frontmatter, populated errors, and rich feedback',
        () {
          final invalidYaml = loadYaml('type: invalid') as YamlMap;
          final result = RfcFrontmatter.tryLoad(invalidYaml);
          expect(result.frontmatter, isNull);
          expect(result.errors, isNotEmpty);
          expect(result.feedback, isNotNull);
          expect(result.feedback, contains('Invalid RFC frontmatter:'));
          expect(result.feedback, contains('Expected frontmatter format:'));
        },
      );

      test(
        'collects multiple validation errors together without early-halting (e.g. missing authors and updated)',
        () {
          final yamlMissingBoth =
              loadYaml('''
type: rfc
rfc: '110.0001'
title: Foundation Architecture
description: Comprehensive architecture overview for foundation.
status: stable
created: 2026-08-27T00:00:00Z
tags:
  - 110-foundation
''')
                  as YamlMap;

          final errors = RfcFrontmatter.validate(yamlMissingBoth);

          // Both errors captured together
          expect(errors.length, equals(2));

          final updatedError = errors.firstWhere(
            (e) => e.contains('"updated"'),
          );
          expect(
            updatedError,
            contains(
              'Frontmatter "updated" must be an ISO 8601 UTC timestamp.',
            ),
          );
          expect(updatedError, contains('found "null"'));
          expect(
            updatedError,
            contains('Expected format: YYYY-MM-DDTHH:MM:SSZ'),
          );

          final authorsError = errors.firstWhere(
            (e) => e.contains('"authors"'),
          );
          expect(
            authorsError,
            contains(
              'Frontmatter "authors" must be a non-empty list of authors.',
            ),
          );
          expect(authorsError, contains('found "null"'));
          expect(authorsError, contains('Expected format:'));
          expect(authorsError, contains('https://github.com/<username>'));
        },
      );

      test('collects all errors when all required fields are missing', () {
        final emptyYaml = YamlMap();
        final errors = RfcFrontmatter.validate(emptyYaml);

        expect(errors.any((e) => e.contains('"type"')), isTrue);
        expect(errors.any((e) => e.contains('"rfc"')), isTrue);
        expect(errors.any((e) => e.contains('"title"')), isTrue);
        expect(errors.any((e) => e.contains('"description"')), isTrue);
        expect(errors.any((e) => e.contains('"status"')), isTrue);
        expect(errors.any((e) => e.contains('"created"')), isTrue);
        expect(errors.any((e) => e.contains('"updated"')), isTrue);
        expect(errors.any((e) => e.contains('"tags"')), isTrue);
        expect(errors.any((e) => e.contains('"authors"')), isTrue);
      });

      test(
        'fromYaml throws FormatException containing all errors and expected schema template',
        () {
          final yamlMissingBoth =
              loadYaml('''
type: rfc
rfc: '110.0001'
title: Foundation Architecture
description: Comprehensive architecture overview.
status: stable
created: 2026-08-27T00:00:00Z
tags:
  - 110-foundation
''')
                  as YamlMap;

          expect(
            () => RfcFrontmatter.fromYaml(yamlMissingBoth),
            throwsA(
              isA<FormatException>().having(
                (e) => e.message,
                'message',
                allOf(
                  contains('Invalid RFC frontmatter:'),
                  contains(
                    'Frontmatter "updated" must be an ISO 8601 UTC timestamp',
                  ),
                  contains(
                    'Frontmatter "authors" must be a non-empty list of authors',
                  ),
                  contains('Expected frontmatter format:'),
                  contains(RfcFrontmatter.expectedSchemaTemplate.trimRight()),
                ),
              ),
            ),
          );
        },
      );

      test(
        'formatErrors formats error list and appends expected schema template',
        () {
          final formatted = RfcFrontmatter.formatErrors([
            'Error one.',
            'Error two.',
          ]);
          expect(formatted, contains('Invalid RFC frontmatter:'));
          expect(formatted, contains('  - Error one.'));
          expect(formatted, contains('  - Error two.'));
          expect(formatted, contains('Expected frontmatter format:'));
          expect(formatted, contains('type: rfc'));
          expect(formatted, contains('rfc: \'000.0001\''));
        },
      );

      test(
        'canonical expectedSchemaTemplate and exampleTemplate are valid and parse cleanly',
        () {
          expect(
            RfcFrontmatter.expectedSchemaTemplate,
            equals(RfcFrontmatter.exampleTemplate),
          );
          expect(RfcFrontmatter.expectedSchemaTemplate, contains('type: rfc'));
          expect(
            RfcFrontmatter.expectedSchemaTemplate,
            contains('rfc: \'000.0001\''),
          );
          expect(
            RfcFrontmatter.expectedSchemaTemplate,
            contains('status: draft'),
          );
          expect(RfcFrontmatter.expectedSchemaTemplate, contains('authors:'));

          final parsed = RfcFrontmatter.parse(
            RfcFrontmatter.expectedSchemaTemplate,
          );
          expect(parsed.type, equals('rfc'));
          expect(parsed.rfc, equals('000.0001'));
          expect(parsed.status, equals(RfcStatus.draft));
          expect(parsed.authors, isNotEmpty);
        },
      );

      test(
        'uses clock.now() formatted timestamp in missing updated error feedback',
        () {
          final fixedTime = DateTime.utc(2026, 9, 15, 14, 30, 45);
          withClock(Clock.fixed(fixedTime), () {
            final yamlWithoutUpdated =
                loadYaml('''
type: rfc
rfc: '110.0001'
title: Foundation Architecture
description: Comprehensive architecture overview.
status: draft
created: 2026-08-27T00:00:00Z
tags:
  - 110-foundation
authors:
  - https://github.com/octocat
''')
                    as YamlMap;

            final errors = RfcFrontmatter.validate(yamlWithoutUpdated);
            expect(errors.length, equals(1));
            expect(
              errors.first,
              contains(
                'Frontmatter "updated" must be an ISO 8601 UTC timestamp.',
              ),
            );
            expect(errors.first, contains('(e.g. 2026-09-15T14:30:45.000Z).'));
          });
        },
      );

      test(
        'uses clock.now() formatted timestamp in missing created error feedback',
        () {
          final fixedTime = DateTime.utc(2026, 10, 5, 8, 12, 0);
          withClock(Clock.fixed(fixedTime), () {
            final yamlWithoutCreated =
                loadYaml('''
type: rfc
rfc: '110.0001'
title: Foundation Architecture
description: Comprehensive architecture overview.
status: draft
updated: 2026-08-27T00:00:00Z
tags:
  - 110-foundation
authors:
  - https://github.com/octocat
''')
                    as YamlMap;

            final errors = RfcFrontmatter.validate(yamlWithoutCreated);
            expect(errors.length, equals(1));
            expect(
              errors.first,
              contains(
                'Frontmatter "created" must be an ISO 8601 UTC timestamp.',
              ),
            );
            expect(errors.first, contains('(e.g. 2026-10-05T08:12:00.000Z).'));
          });
        },
      );

      test(
        'uses clock.now() formatted timestamp in invalid timestamp error feedback',
        () {
          final fixedTime = DateTime.utc(2026, 11, 20, 23, 59, 59);
          withClock(Clock.fixed(fixedTime), () {
            final yamlInvalidUpdated =
                loadYaml('''
type: rfc
rfc: '110.0001'
title: Foundation Architecture
description: Comprehensive architecture overview.
status: draft
created: 2026-08-27T00:00:00Z
updated: not-a-valid-date
tags:
  - 110-foundation
authors:
  - https://github.com/octocat
''')
                    as YamlMap;

            final errors = RfcFrontmatter.validate(yamlInvalidUpdated);
            expect(errors.length, equals(1));
            expect(errors.first, contains('Found "not-a-valid-date"'));
            expect(errors.first, contains('(e.g. 2026-11-20T23:59:59.000Z).'));
          });
        },
      );

      test('uses clock.now() in non-UTC DateTime error feedback', () {
        final fixedTime = DateTime.utc(2026, 11, 20, 23, 59, 59);
        final localTime = DateTime(2026, 8, 27, 12, 0);
        withClock(Clock.fixed(fixedTime), () {
          final errors = RfcFrontmatter.validate({
            'type': 'rfc',
            'rfc': '110.0001',
            'title': 'Title',
            'description': 'Description',
            'status': 'draft',
            'created': DateTime(2026, 8, 27, 12, 0), // Local non-UTC DateTime
            'updated': '2026-08-27T00:00:00Z',
            'tags': ['110-foundation'],
            'authors': ['https://github.com/octocat'],
          });
          expect(
            errors,
            contains(
              allOf(
                contains('Found non-UTC'),
                contains('(e.g. ${localTime.toUtc().toIso8601String()}).'),
              ),
            ),
          );
        });
      });

      test(
        'uses clock.now() with non-UTC fixed clock properly converted to UTC',
        () {
          // Clock fixed to a timezone with +14:00 offset
          final fixedNonUtc = DateTime.parse('2026-09-02T02:00:00+14:00');
          withClock(Clock.fixed(fixedNonUtc), () {
            final yamlWithoutUpdated =
                loadYaml('''
type: rfc
rfc: '110.0001'
title: Foundation Architecture
description: Comprehensive architecture overview.
status: draft
created: 2026-08-27T00:00:00Z
tags:
  - 110-foundation
authors:
  - https://github.com/octocat
''')
                    as YamlMap;

            final errors = RfcFrontmatter.validate(yamlWithoutUpdated);
            expect(errors.length, equals(1));
            // 02:00 at +14:00 corresponds to 12:00 on previous day in UTC
            expect(errors.first, contains('(e.g. 2026-09-01T12:00:00.000Z).'));
          });
        },
      );
    });

    group('createdIso and updatedIso', () {
      test('formats created and updated DateTime as ISO 8601 UTC strings', () {
        final frontmatter = RfcFrontmatter(
          type: 'rfc',
          rfc: '110.0001',
          title: 'Title',
          description: 'Description',
          status: RfcStatus.draft,
          created: DateTime.utc(2026, 8, 27, 0, 0, 0),
          updated: DateTime.utc(2026, 9, 1, 12, 0, 0),
          tags: ['110-foundation'],
          authors: [const GitHubAuthor(username: 'octocat')],
        );
        expect(frontmatter.createdIso, equals('2026-08-27T00:00:00.000Z'));
        expect(frontmatter.updatedIso, equals('2026-09-01T12:00:00.000Z'));
      });
    });

    group('RfcStatus', () {
      test('parses all valid status enum values case-insensitively', () {
        expect(RfcStatus.tryParse('draft'), equals(RfcStatus.draft));
        expect(RfcStatus.tryParse('DRAFT'), equals(RfcStatus.draft));
        expect(RfcStatus.tryParse('review'), equals(RfcStatus.review));
        expect(RfcStatus.tryParse('Review'), equals(RfcStatus.review));
        expect(RfcStatus.tryParse('stable'), equals(RfcStatus.stable));
        expect(RfcStatus.tryParse('superseded'), equals(RfcStatus.superseded));
        expect(RfcStatus.tryParse('withdrawn'), equals(RfcStatus.withdrawn));
        expect(RfcStatus.tryParse('rejected'), equals(RfcStatus.rejected));
        expect(RfcStatus.tryParse('deprecated'), equals(RfcStatus.deprecated));
      });

      test('returns null for unknown status', () {
        expect(RfcStatus.tryParse('unknown'), isNull);
        expect(RfcStatus.tryParse(''), isNull);
        expect(RfcStatus.tryParse(null), isNull);
      });

      test('supports switch expressions on status', () {
        final status = RfcStatus.review;
        final label = switch (status) {
          RfcStatus.draft => 'draft',
          RfcStatus.review => 'in-review',
          RfcStatus.stable => 'stable',
          RfcStatus.superseded => 'superseded',
          RfcStatus.withdrawn => 'withdrawn',
          RfcStatus.rejected => 'rejected',
          RfcStatus.deprecated => 'deprecated',
        };
        expect(label, equals('in-review'));
      });
    });
  });
}
