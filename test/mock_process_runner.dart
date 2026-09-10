// Copyright 2026 The Flutter Authors.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

typedef MockProcessHandler =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// In-memory mock process runner to record external process invocations and
/// control process outputs hermetically in tests.
class MockProcessRunner {
  final List<({String executable, List<String> arguments})> calls = [];
  MockProcessHandler? handler;
  int exitCode;
  dynamic stdout;
  dynamic stderr;
  Object? exceptionToThrow;

  MockProcessRunner({
    this.exitCode = 0,
    this.stdout = '',
    this.stderr = '',
    this.exceptionToThrow,
    this.handler,
  });

  Future<ProcessResult> run(String executable, List<String> arguments) async {
    calls.add((
      executable: executable,
      arguments: List.unmodifiable(arguments),
    ));
    if (exceptionToThrow != null) {
      throw exceptionToThrow!;
    }
    if (handler != null) {
      return await handler!(executable, arguments);
    }
    return ProcessResult(1234, exitCode, stdout, stderr);
  }

  Future<ProcessResult> call(String executable, List<String> arguments) =>
      run(executable, arguments);
}
