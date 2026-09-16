// Copyright 2026 The Flutter Authors.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io' show ProcessResult;

import 'package:rfc_tools/src/process_logger.dart';
import 'package:test/test.dart';

void main() {
  group('process logging utilities', () {
    test('logProcessResult logs exit code, stdout, and stderr', () {
      final outLines = <String>[];
      final errLines = <String>[];
      final result = ProcessResult(1234, 1, 'sample stdout', 'sample stderr');

      logProcessResult(
        result,
        command: 'test-cmd',
        onLog: (m) => outLines.add(m),
        onError: (m) => errLines.add(m),
      );

      expect(errLines, contains('exit code: 1'));
      expect(outLines, contains('test-cmd stdout:'));
      expect(outLines, contains('sample stdout'));
      expect(errLines, contains('test-cmd stderr:'));
      expect(errLines, contains('sample stderr'));
    });

    test('logProcessError logs exception to onError', () {
      final errLines = <String>[];
      final exception = Exception('test failure');

      logProcessError(
        exception,
        command: 'test-fail-cmd',
        onError: (m) => errLines.add(m),
      );

      expect(errLines.first, contains('test-fail-cmd exception:'));
      expect(errLines.first, contains('test failure'));
    });
  });
}
