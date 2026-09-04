// Copyright 2026 The Flutter Authors.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';
import 'package:args/args.dart';
import 'package:file/local.dart';
import 'package:rfc_tools/src/validator.dart';

void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      'base-branch',
      defaultsTo: 'origin/main',
      help: 'Base git branch to check against for collisions.',
    )
    ..addFlag(
      'check-main',
      negatable: false,
      help: 'Check for number collisions against the base git branch.',
    )
    ..addFlag(
      'no-drafts',
      negatable: false,
      help:
          'Reject any ".0000" draft RFCs (required for Merge Queue and main).',
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
    exitCode = 1;
    return;
  }

  if (results.flag('help')) {
    stdout.writeln('RFC Semantic Validator - Flutter RFC Repository Tooling\n');
    stdout.writeln(parser.usage);
    return;
  }

  final checkMain = results.flag('check-main');
  final baseBranch = results.option('base-branch')!;
  final noDrafts = results.flag('no-drafts');
  final githubActions = results.flag('github-actions');

  const fs = LocalFileSystem();
  final validator = RfcValidator(fs: fs);

  final (:isSuccess, :errors) = await validator.validate(
    noDrafts: noDrafts,
    checkMain: checkMain,
    baseBranch: baseBranch,
  );

  if (!isSuccess) {
    stderr.writeln('RFC validation failed with ${errors.length} error(s):\n');
    for (final error in errors) {
      if (githubActions) {
        stderr.writeln(error.toGithubAnnotation());
      } else {
        stderr.writeln('[ERROR] $error');
      }
    }
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'RFC numbers validated cleanly. No collisions or illegal drafts found.',
  );
}
