// Copyright 2026 The Flutter Authors.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io' show ProcessResult, stderr, stdout;

/// Logs the details of an external [ProcessResult] (exit code, stdout, stderr).
///
/// When [onLog] or [onError] are provided, log lines are dispatched to them;
/// otherwise, exit code and stderr output are sent to [stderr], and stdout
/// output is sent to [stdout].
void logProcessResult(
  ProcessResult result, {
  String command = 'process',
  void Function(String message)? onLog,
  void Function(String message)? onError,
}) {
  final out = onLog ?? stdout.writeln;
  final err = onError ?? stderr.writeln;

  err('exit code: ${result.exitCode}');
  out('$command stdout:');
  out('${result.stdout}');
  err('$command stderr:');
  err('${result.stderr}');
}

/// Logs an exception encountered during process execution.
void logProcessError(
  Object error, {
  String command = 'process',
  void Function(String message)? onError,
}) {
  final err = onError ?? stderr.writeln;
  err('$command exception: $error');
}
