// Copyright 2026 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Represents an author attribution in RFC frontmatter.
sealed class RfcAuthor {
  /// The raw author string representation.
  final String raw;

  const RfcAuthor({required this.raw});

  /// Regex pattern for GitHub user profile URLs:
  /// `https://github.com/<username>`
  static final RegExp githubUrlPattern = RegExp(
    r'^https:\/\/github\.com\/([a-zA-Z0-9](?:[a-zA-Z0-9]|-(?=[a-zA-Z0-9])){0,38})\/?$',
    caseSensitive: false,
  );

  /// Regex pattern for RFC 5322 mailbox format:
  /// `"Display Name" <user@example.com>` or `'Display Name' <user@example.com>` or `Display Name <user@example.com>`
  static final RegExp mailboxPattern = RegExp(
    r'^(?:"((?:[^"\\]|\\.)+)"|'
    "'"
    r"((?:[^'\\]|\\.)+)'"
    r'|([^<]+))\s+<([^@\s>]+@[^@\s>]+\.[^@\s>]+)>$',
  );

  /// Attempts to parse an author string into a [GitHubAuthor] or [EmailAuthor].
  ///
  /// Returns `null` if the format is unrecognized or invalid.
  static RfcAuthor? tryParse(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;

    final ghMatch = githubUrlPattern.firstMatch(trimmed);
    if (ghMatch != null) {
      return GitHubAuthor(username: ghMatch.group(1)!, raw: trimmed);
    }

    final mbMatch = mailboxPattern.firstMatch(trimmed);
    if (mbMatch != null) {
      var name = (mbMatch.group(1) ?? mbMatch.group(2) ?? mbMatch.group(3))
          ?.trim();
      if (name != null) {
        name = name.replaceAll(r'\"', '"').replaceAll(r"\'", "'");
      }
      final email = mbMatch.group(4)?.trim();
      if (name != null &&
          name.isNotEmpty &&
          email != null &&
          email.isNotEmpty) {
        return EmailAuthor(name: name, email: email, raw: trimmed);
      }
    }

    return null;
  }

  /// Parses an author string into a [GitHubAuthor] or [EmailAuthor].
  ///
  /// Throws [FormatException] if the author string cannot be parsed.
  factory RfcAuthor.parse(String value) {
    final author = tryParse(value);
    if (author == null) {
      throw FormatException(
        'Author "$value" must be a GitHub profile URL ("https://github.com/<username>") '
        'or RFC 5322 mailbox (\'"Display Name" <user@example.com>\').',
      );
    }
    return author;
  }
}

/// An author represented by a GitHub profile.
final class GitHubAuthor extends RfcAuthor {
  /// The GitHub username.
  final String username;

  const GitHubAuthor({required this.username, String? raw})
    : super(raw: raw ?? 'https://github.com/$username');

  /// Canonical GitHub user profile URL.
  String get url => 'https://github.com/$username';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GitHubAuthor && username == other.username;

  @override
  int get hashCode => username.hashCode;

  @override
  String toString() => 'GitHubAuthor(username: $username)';
}

/// An author represented by an RFC 5322 mailbox.
final class EmailAuthor extends RfcAuthor {
  /// The display name of the author (e.g. "John McDole").
  final String name;

  /// The email address of the author (e.g. "codefu@google.com").
  final String email;

  const EmailAuthor({required this.name, required this.email, String? raw})
    : super(raw: raw ?? '"$name" <$email>');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EmailAuthor &&
          name == other.name &&
          email.toLowerCase() == other.email.toLowerCase();

  @override
  int get hashCode => Object.hash(name, email.toLowerCase());

  @override
  String toString() => 'EmailAuthor(name: $name, email: $email)';
}
