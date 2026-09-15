// Copyright 2026 The Flutter Authors.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:args/args.dart';
import 'package:rfc_tools/src/lfs_verifier.dart';

final parser = ArgParser()
  ..addOption(
    'base-branch',
    abbr: 'b',
    help: 'Git base branch or ref to compare against in pull request mode.',
  )
  ..addFlag(
    'audit-intermediate-commits',
    negatable: false,
    help:
        'Audit every commit in the PR branch for raw binaries.\n'
        'Only needed for repositories that do not enforce squash merges\n'
        '(e.g. merge-commit or rebase-merge).',
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

void main(List<String> arguments) async {
  ArgResults results;
  try {
    results = parser.parse(arguments);
  } catch (e) {
    stderr.writeln('Error parsing arguments: $e\n');
    stderr.writeln(parser.usage);
    exitCode = 1;
    return;
  }

  if (results.flag('help')) {
    stdout.writeln('Git LFS Verifier - Flutter RFC Repository Tooling\n');
    stdout.writeln(parser.usage);
    return;
  }

  if (results.rest.isNotEmpty) {
    stderr.writeln(
      'Error: Positional file arguments are not supported. Git LFS verification audits trees.\n',
    );
    stderr.writeln(parser.usage);
    exitCode = 1;
    return;
  }

  final baseBranch = switch (results.option('base-branch')?.trim()) {
    null || '' => null,
    final branch => branch,
  };
  final githubActions = results.flag('github-actions');
  final auditIntermediateCommits = results.flag('audit-intermediate-commits');
  final verifier = LfsVerifier(onLog: stdout.writeln, onError: stderr.writeln);

  final (:isSuccess, :issues) = await verifier.verify(
    baseBranch: baseBranch,
    auditIntermediateCommits: auditIntermediateCommits,
  );

  if (!isSuccess) {
    _reportVerificationErrors(issues: issues, githubActions: githubActions);
    exitCode = 1;
    return;
  }

  stdout.writeln('✅ Git LFS verification passed.');
}

void _reportVerificationErrors({
  required List<LfsIssue> issues,
  required bool githubActions,
}) {
  stderr.writeln(
    'Git LFS verification failed with ${issues.length} issue(s):\n',
  );
  for (final issue in issues) {
    stderr.writeln(githubActions ? issue.toGithubAnnotation() : '$issue');
  }

  // Only suppress the remediation block when *every* issue is repository-level
  // (e.g. a bad base ref); a single unresolvable file still warrants the steps.
  if (issues.every((issue) => issue.filePath.isEmpty)) {
    return;
  }

  stderr.writeln('''

❌ ERROR: One or more files bypassed Git LFS!
To resolve this:
  1. Ensure Git LFS is installed and initialized:
       git lfs install
  2. Re-normalize files so Git LFS clean filters are applied:
       git add --renormalize .
       git commit -m "Fix: properly serialize LFS files"

This repository squash-merges, so fixing the tip commit is sufficient.
If you are not squash-merging, you must edit history instead:
       git lfs migrate import --include="*.png" --everything
''');
}
