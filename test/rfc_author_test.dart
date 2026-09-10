// Copyright 2026 The Flutter Authors.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:rfc_tools/src/models/rfc_author.dart';
import 'package:test/test.dart';

void main() {
  group('RfcAuthor', () {
    group('GitHubAuthor', () {
      test('parses valid GitHub profile URL without trailing slash', () {
        final author = RfcAuthor.parse('https://github.com/octocat');
        expect(author, isA<GitHubAuthor>());
        final gh = author as GitHubAuthor;
        expect(gh.username, equals('octocat'));
        expect(gh.url, equals('https://github.com/octocat'));
        expect(gh.raw, equals('https://github.com/octocat'));
      });

      test('parses valid GitHub profile URL with trailing slash', () {
        final author = RfcAuthor.parse('https://github.com/flutter-dev/');
        expect(author, isA<GitHubAuthor>());
        final gh = author as GitHubAuthor;
        expect(gh.username, equals('flutter-dev'));
        expect(gh.url, equals('https://github.com/flutter-dev'));
        expect(gh.raw, equals('https://github.com/flutter-dev/'));
      });

      test('parses GitHub profile URL case-insensitively for domain', () {
        final author = RfcAuthor.parse('https://GitHub.com/octocat');
        expect(author, isA<GitHubAuthor>());
        final gh = author as GitHubAuthor;
        expect(gh.username, equals('octocat'));
      });

      test('supports value equality and hashCode', () {
        final a1 = GitHubAuthor(username: 'octocat');
        final a2 = GitHubAuthor(username: 'octocat');
        final a3 = GitHubAuthor(username: 'different');

        expect(a1, equals(a1));
        expect(a1, equals(a2));
        expect(a1.hashCode, equals(a2.hashCode));
        expect(a1, isNot(equals(a3)));
        expect(a1, isNot(equals(Object())));
        expect(
          a1,
          isNot(
            equals(
              const EmailAuthor(name: 'Octocat', email: 'octocat@github.com'),
            ),
          ),
        );
      });

      test('toString includes username', () {
        final author = GitHubAuthor(username: 'octocat');
        expect(author.toString(), equals('GitHubAuthor(username: octocat)'));
      });
    });

    group('EmailAuthor', () {
      test('parses double-quoted mailbox format', () {
        final author = RfcAuthor.parse('"John McDole" <codefu@google.com>');
        expect(author, isA<EmailAuthor>());
        final em = author as EmailAuthor;
        expect(em.name, equals('John McDole'));
        expect(em.email, equals('codefu@google.com'));
        expect(em.raw, equals('"John McDole" <codefu@google.com>'));
      });

      test('parses single-quoted mailbox format', () {
        final author = RfcAuthor.parse("'Jane Doe' <jane@flutter.dev>");
        expect(author, isA<EmailAuthor>());
        final em = author as EmailAuthor;
        expect(em.name, equals('Jane Doe'));
        expect(em.email, equals('jane@flutter.dev'));
      });

      test('parses unquoted mailbox format', () {
        final author = RfcAuthor.parse('Alice Bob <alice@example.com>');
        expect(author, isA<EmailAuthor>());
        final em = author as EmailAuthor;
        expect(em.name, equals('Alice Bob'));
        expect(em.email, equals('alice@example.com'));
      });

      test('parses mailbox with escaped quotes in display name', () {
        final author = RfcAuthor.parse(
          r'"John \"Jack\" Doe" <jack@example.com>',
        );
        expect(author, isA<EmailAuthor>());
        final em = author as EmailAuthor;
        expect(em.name, equals('John "Jack" Doe'));
        expect(em.email, equals('jack@example.com'));
      });

      test('parses mailbox with non-ASCII Unicode characters', () {
        final author = RfcAuthor.parse('"René François" <rene@example.com>');
        expect(author, isA<EmailAuthor>());
        final em = author as EmailAuthor;
        expect(em.name, equals('René François'));
        expect(em.email, equals('rene@example.com'));
      });

      test(
        'parses mailbox with plus sign in email address (sub-addressing)',
        () {
          final author = RfcAuthor.parse(
            '"Jacque Blanderson" <jacque+blanderson@google.com>',
          );
          expect(author, isA<EmailAuthor>());
          final em = author as EmailAuthor;
          expect(em.name, equals('Jacque Blanderson'));
          expect(em.email, equals('jacque+blanderson@google.com'));
          expect(
            em.raw,
            equals('"Jacque Blanderson" <jacque+blanderson@google.com>'),
          );

          // Case-insensitivity check with plus address
          const a1 = EmailAuthor(
            name: 'Jacque Blanderson',
            email: 'jacque+blanderson@google.com',
          );
          const a2 = EmailAuthor(
            name: 'Jacque Blanderson',
            email: 'JACQUE+BLANDERSON@GOOGLE.COM',
          );
          expect(a1, equals(a2));
          expect(a1.hashCode, equals(a2.hashCode));
        },
      );

      test('rejects bare email address without display name', () {
        expect(RfcAuthor.tryParse('user@example.com'), isNull);
        expect(RfcAuthor.tryParse('<user@example.com>'), isNull);
        expect(
          () => RfcAuthor.parse('user@example.com'),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => RfcAuthor.parse('<user@example.com>'),
          throwsA(isA<FormatException>()),
        );
      });

      test(
        'supports value equality and hashCode case-insensitively for email',
        () {
          const a1 = EmailAuthor(name: 'Alice', email: 'alice@example.com');
          const a2 = EmailAuthor(name: 'Alice', email: 'alice@example.com');
          const a3 = EmailAuthor(name: 'Bob', email: 'bob@example.com');
          const aCase = EmailAuthor(name: 'Alice', email: 'ALICE@EXAMPLE.COM');

          expect(a1, equals(a1));
          expect(a1, equals(a2));
          expect(a1, equals(aCase));
          expect(a1.hashCode, equals(aCase.hashCode));
          expect(a1, isNot(equals(a3)));
          expect(a1, isNot(equals(Object())));
          expect(a1, isNot(equals(const GitHubAuthor(username: 'alice'))));
        },
      );

      test('toString formats correctly with name and email', () {
        const author = EmailAuthor(name: 'Alice', email: 'alice@example.com');
        expect(
          author.toString(),
          equals('EmailAuthor(name: Alice, email: alice@example.com)'),
        );
      });
    });

    group('tryParse & parse edge cases', () {
      test('returns null on invalid formats with tryParse', () {
        expect(RfcAuthor.tryParse(''), isNull);
        expect(RfcAuthor.tryParse('   '), isNull);
        expect(RfcAuthor.tryParse('not an author'), isNull);
        expect(RfcAuthor.tryParse('https://gitlab.com/octocat'), isNull);
        expect(RfcAuthor.tryParse('"No Email" <>'), isNull);
        expect(RfcAuthor.tryParse('Missing Email < >'), isNull);
      });

      test('rejects mismatched angle brackets in bare email', () {
        expect(RfcAuthor.tryParse('<user@example.com'), isNull);
        expect(RfcAuthor.tryParse('user@example.com>'), isNull);
        expect(
          () => RfcAuthor.parse('<user@example.com'),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => RfcAuthor.parse('user@example.com>'),
          throwsA(isA<FormatException>()),
        );
      });

      test('throws FormatException on invalid format with parse', () {
        expect(
          () => RfcAuthor.parse('invalid-author'),
          throwsA(isA<FormatException>()),
        );
      });

      test('supports exhaustive switch pattern matching', () {
        final authors = <RfcAuthor>[
          RfcAuthor.parse('https://github.com/octocat'),
          RfcAuthor.parse('"John McDole" <codefu@google.com>'),
        ];

        final descriptions = authors.map((author) {
          return switch (author) {
            GitHubAuthor(:final username) => 'github:$username',
            EmailAuthor(:final name, :final email) => 'email:$name<$email>',
          };
        }).toList();

        expect(
          descriptions,
          equals(['github:octocat', 'email:John McDole<codefu@google.com>']),
        );
      });
    });
  });
}
