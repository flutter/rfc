// Copyright 2026 The Flutter Authors.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';
import 'package:args/args.dart';
import 'package:file/local.dart';
import 'package:rfc_tools/src/assigner.dart';

void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      'target-file',
      help:
          'Specific RFC file path to assign (defaults to auto-detecting draft .0000).',
    )
    ..addFlag(
      'dry-run',
      negatable: false,
      help: 'Simulate assignment without modifying files.',
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
    stdout.writeln('RFC Number Assigner - Flutter RFC Repository Tooling\n');
    stdout.writeln(parser.usage);
    return;
  }

  final targetFile = results.rest.firstOrNull ?? results.option('target-file');
  final dryRun = results.flag('dry-run');

  const fs = LocalFileSystem();
  final assigner = RfcAssigner(fs: fs);

  try {
    stdout.writeln('Assigning RFC number...');
    final result = await assigner.assign(
      targetPath: targetFile,
      dryRun: dryRun,
    );

    if (result.dryRun) {
      stdout.writeln(
        '[DRY RUN] Would assign RFC identifier: ${result.newRfcId}',
      );
      stdout.writeln('[DRY RUN] Target file: ${result.oldPath}');
      stdout.writeln('[DRY RUN] Rename to:   ${result.newPath}');
    } else {
      stdout.writeln(
        'Successfully assigned RFC identifier: ${result.newRfcId}',
      );
      stdout.writeln('File: ${result.newPath}');

      final githubOutput = Platform.environment['GITHUB_OUTPUT'];
      if (githubOutput != null && githubOutput.isNotEmpty) {
        await fs
            .file(githubOutput)
            .writeAsString(
              'rfc_id=${result.newRfcId}\nnew_path=${result.newPath}\n',
              mode: FileMode.append,
            );
      }
    }
  } catch (e) {
    stderr.writeln('Assignment failed: $e');
    exitCode = 1;
    return;
  }
}
