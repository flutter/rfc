// Copyright 2026 The Flutter Authors.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// End-to-end verification of `bin/lfs_verify.dart` against a real Git
/// repository and a real `git-lfs` binary.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Absolute path to the package root, so the spawned CLI resolves correctly
/// regardless of the temporary working directory under test.
final String _packageRoot = Directory.current.absolute.path;

Future<ProcessResult> _git(
  Directory repo,
  List<String> arguments, {
  Map<String, String>? environment,
}) => Process.run(
  'git',
  arguments,
  workingDirectory: repo.path,
  environment: environment,
);

/// Runs `bin/lfs_verify.dart` inside [repo] and returns the result.
Future<ProcessResult> _runVerifier(
  Directory repo, {
  List<String> arguments = const [],
}) => Process.run(Platform.resolvedExecutable, [
  p.join(_packageRoot, 'bin', 'lfs_verify.dart'),
  ...arguments,
], workingDirectory: repo.path);

/// Creates an initialized repository that tracks `*.png` via Git LFS.
Future<Directory> _createRepo() async {
  final repo = await Directory.systemTemp.createTemp('lfs_e2e_');
  await _git(repo, ['init', '--quiet', '--initial-branch=main', '.']);
  await _git(repo, ['config', 'user.email', 'test@example.com']);
  await _git(repo, ['config', 'user.name', 'Test']);
  await _git(repo, ['config', 'commit.gpgsign', 'false']);
  await _git(repo, ['lfs', 'install', '--local']);

  File(
    p.join(repo.path, '.gitattributes'),
  ).writeAsStringSync('*.png filter=lfs diff=lfs merge=lfs -text\n');
  await _git(repo, ['add', '.gitattributes']);
  await _git(repo, ['commit', '--quiet', '-m', 'chore: track png via lfs']);
  return repo;
}

/// Stages [name] while disabling the LFS clean filter, reproducing exactly what
/// a contributor without `git-lfs` installed commits: a raw binary blob.
Future<void> _commitRawBinary(Directory repo, String name) async {
  File(
    p.join(repo.path, name),
  ).writeAsBytesSync(List<int>.generate(2048, (i) => i % 256));
  await _git(repo, [
    '-c',
    'filter.lfs.clean=',
    '-c',
    'filter.lfs.process=',
    '-c',
    'filter.lfs.required=false',
    'add',
    name,
  ]);
  await _git(repo, ['commit', '--quiet', '-m', 'feat: add $name']);
}

void main() {
  late Directory repo;

  setUpAll(() async {
    final lfs = await Process.run('git', ['lfs', 'version']);
    if (lfs.exitCode != 0) {
      throw StateError(
        'git-lfs is required for e2e tests. Install it from https://git-lfs.com',
      );
    }
  });

  tearDown(() async {
    if (repo.existsSync()) {
      repo.deleteSync(recursive: true);
    }
  });

  test('passes on a repository with no media files', () async {
    repo = await _createRepo();

    final result = await _runVerifier(repo);

    expect(
      result.exitCode,
      equals(0),
      reason: '${result.stdout}${result.stderr}',
    );
    expect(result.stdout, contains('Git LFS verification passed'));
  });

  test('passes when a png is committed through the LFS clean filter', () async {
    repo = await _createRepo();
    File(
      p.join(repo.path, 'diagram.png'),
    ).writeAsBytesSync(List<int>.generate(2048, (i) => i % 256));
    await _git(repo, ['add', 'diagram.png']);
    await _git(repo, ['commit', '--quiet', '-m', 'feat: add diagram']);

    final result = await _runVerifier(repo);

    expect(
      result.exitCode,
      equals(0),
      reason: '${result.stdout}${result.stderr}',
    );
  });

  test('detects a raw binary committed without git-lfs installed', () async {
    repo = await _createRepo();
    await _commitRawBinary(repo, 'diagram.png');

    final result = await _runVerifier(repo);

    expect(result.exitCode, equals(1));
    expect(result.stderr, contains('diagram.png'));
    expect(result.stderr, contains('bypassed Git LFS'));
    expect(result.stderr, contains('git lfs install'));
  });

  test('emits a GitHub annotation naming the offending file', () async {
    repo = await _createRepo();
    await _commitRawBinary(repo, 'diagram.png');

    final result = await _runVerifier(repo, arguments: ['--github-actions']);

    expect(result.exitCode, equals(1));
    expect(result.stderr, contains('::error file=diagram.png::'));
  });

  test(
    'default PR mode ignores a blob added and removed before HEAD',
    () async {
      repo = await _createRepo();
      await _git(repo, ['checkout', '--quiet', '-b', 'feature']);
      await _commitRawBinary(repo, 'scratch.png');
      await _git(repo, ['rm', '--quiet', '--force', 'scratch.png']);
      await _git(repo, ['commit', '--quiet', '-m', 'chore: drop scratch']);

      final result = await _runVerifier(
        repo,
        arguments: ['--base-branch', 'main'],
      );

      expect(
        result.exitCode,
        equals(0),
        reason: 'squash-merge means the intermediate blob never reaches main',
      );
    },
  );

  test('--audit-intermediate-commits catches the same blob', () async {
    repo = await _createRepo();
    await _git(repo, ['checkout', '--quiet', '-b', 'feature']);
    await _commitRawBinary(repo, 'scratch.png');
    await _git(repo, ['rm', '--quiet', '--force', 'scratch.png']);
    await _git(repo, ['commit', '--quiet', '-m', 'chore: drop scratch']);

    final result = await _runVerifier(
      repo,
      arguments: ['--base-branch', 'main', '--audit-intermediate-commits'],
    );

    expect(result.exitCode, equals(1));
    expect(result.stderr, contains('scratch.png'));
  });

  test('reports an unresolvable base ref without LFS remediation', () async {
    repo = await _createRepo();

    final result = await _runVerifier(
      repo,
      arguments: ['--base-branch', 'does-not-exist-12345'],
    );

    expect(result.exitCode, equals(1));
    expect(result.stderr, contains('Git base ref'));
    expect(result.stderr, isNot(contains('bypassed Git LFS')));
  });
}
