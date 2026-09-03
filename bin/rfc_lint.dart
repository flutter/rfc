// Copyright 2026 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';
import 'package:args/args.dart';
import 'package:file/local.dart';
import 'package:rfc_tools/src/git_lister.dart';
import 'package:rfc_tools/src/github_client.dart';
import 'package:rfc_tools/src/linter.dart';
import 'package:rfc_tools/src/taxonomy.dart';

void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addMultiOption(
      'labels',
      help: 'Comma-separated list of GitHub Pull Request labels.',
    )
    ..addFlag(
      'enforce-drafts',
      negatable: false,
      help:
          'Enforce that RFCs under review must use ".0000" unless labeled with "rfc-ready" or "rfc-assigned".',
    )
    ..addFlag(
      'validate-github-users',
      negatable: false,
      help: 'Verify that GitHub profile authors exist via the GitHub API.',
    )
    ..addFlag(
      'github-actions',
      negatable: false,
      help:
          'Output errors in GitHub Actions annotation format (::error file=...::).',
    )
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Show usage instructions.',
    );

  ArgResults results;
  try {
    results = parser.parse(arguments);
  } catch (e) {
    stderr.writeln('Error parsing arguments: $e\n');
    stderr.writeln(parser.usage);
    exit(1);
  }

  if (results.flag('help')) {
    stdout.writeln('RFC Linter - Flutter RFC Repository Tooling\n');
    stdout.writeln(parser.usage);
    exit(0);
  }

  final enforceDrafts = results.flag('enforce-drafts');
  final validateGitHubUsers = results.flag('validate-github-users');
  final githubActions = results.flag('github-actions');

  final labels = <String>{
    for (var label in results.multiOption('labels'))
      if (label.trim() case final trimmed when trimmed.isNotEmpty) trimmed,
  };

  const fs = LocalFileSystem();
  const gh = CliGitHubClient();

  Taxonomy taxonomy;
  try {
    taxonomy = await Taxonomy.load(fs);
  } catch (e) {
    stderr.writeln('Failed to load taxonomy: $e');
    exit(1);
  }

  final filesOnMain = await defaultGitList(baseBranch: 'origin/main');

  final linter = RfcLinter(
    fs: fs,
    gh: gh,
    taxonomy: taxonomy,
    labels: labels,
    validateGitHubUsers: validateGitHubUsers,
    existingFilesOnMain: filesOnMain,
    enforceDrafts: enforceDrafts,
  );

  final issues = <LintIssue>[];
  if (results.rest.isNotEmpty) {
    for (final path in results.rest) {
      issues.addAll(await linter.lintFile(fs.file(path)));
    }
  } else {
    issues.addAll(await linter.lintDirectory(fs.directory('rfc')));
  }

  if (issues.isNotEmpty) {
    stderr.writeln('RFC Lint failed with ${issues.length} issue(s):\n');
    for (final issue in issues) {
      if (githubActions) {
        stderr.writeln(issue.toGithubAnnotation());
      } else {
        stderr.writeln('[ERROR] $issue');
      }
    }
    exit(1);
  }

  stdout.writeln('All RFC documents passed lint checks cleanly.');
  exit(0);
}
