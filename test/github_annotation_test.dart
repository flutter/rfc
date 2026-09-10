// Copyright 2026 The Flutter Authors.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:rfc_tools/src/github_annotation.dart';
import 'package:rfc_tools/src/linter.dart';
import 'package:rfc_tools/src/validator.dart';
import 'package:test/test.dart';

void main() {
  group('GithubAnnotationExtension on String', () {
    group('toGithubWorkflowValue', () {
      test('leaves clean strings unchanged', () {
        expect(
          'Simple message'.toGithubWorkflowValue(),
          equals('Simple message'),
        );
      });

      test('percent-encodes % as %25', () {
        expect(
          'Progress: 100%'.toGithubWorkflowValue(),
          equals('Progress: 100%25'),
        );
      });

      test('percent-encodes \\n as %0A', () {
        expect(
          'Line 1\nLine 2'.toGithubWorkflowValue(),
          equals('Line 1%0ALine 2'),
        );
      });

      test('percent-encodes \\r as %0D', () {
        expect(
          'Line 1\rLine 2'.toGithubWorkflowValue(),
          equals('Line 1%0DLine 2'),
        );
      });

      test('percent-encodes combination of %, \\r, and \\n', () {
        const input = '100% complete\r\nNext line: 50%';
        expect(
          input.toGithubWorkflowValue(),
          equals('100%25 complete%0D%0ANext line: 50%25'),
        );
      });
    });

    group('toGithubAnnotation', () {
      test('formats file-only annotation', () {
        final annotation = 'File error'.toGithubAnnotation(
          filePath: 'rfc/000.0001-sample.md',
        );
        expect(
          annotation,
          equals('::error file=rfc/000.0001-sample.md::File error'),
        );
      });

      test('formats file + line + col annotation', () {
        final annotation = 'Syntax error'.toGithubAnnotation(
          filePath: 'rfc/000.0001-sample.md',
          line: 15,
          column: 3,
        );
        expect(
          annotation,
          equals(
            '::error file=rfc/000.0001-sample.md,line=15,col=3::Syntax error',
          ),
        );
      });

      test('formats file + line only annotation', () {
        final annotation = 'Line error'.toGithubAnnotation(
          filePath: 'rfc/000.0001-sample.md',
          line: 20,
        );
        expect(
          annotation,
          equals('::error file=rfc/000.0001-sample.md,line=20::Line error'),
        );
      });

      test('formats custom annotation type (warning, notice)', () {
        final warning = 'Warning message'.toGithubAnnotation(
          filePath: 'rfc/000.0001-sample.md',
          type: 'warning',
        );
        expect(
          warning,
          equals('::warning file=rfc/000.0001-sample.md::Warning message'),
        );

        final notice = 'Notice message'.toGithubAnnotation(
          filePath: 'rfc/000.0001-sample.md',
          type: 'notice',
        );
        expect(
          notice,
          equals('::notice file=rfc/000.0001-sample.md::Notice message'),
        );
      });

      test('formats title parameter when provided', () {
        final annotation = 'Schema violation'.toGithubAnnotation(
          filePath: 'rfc/000.0001-sample.md',
          title: 'BadFrontmatter',
        );
        expect(
          annotation,
          equals(
            '::error file=rfc/000.0001-sample.md,title=BadFrontmatter::Schema violation',
          ),
        );
      });

      test('percent-encodes multiline messages in annotation output', () {
        const multiline = 'Line 1\nLine 2 100%';
        final annotation = multiline.toGithubAnnotation(
          filePath: 'rfc/000.0001-sample.md',
          line: 5,
          column: 1,
        );
        expect(annotation.contains('\n'), isFalse);
        expect(annotation.contains('\r'), isFalse);
        expect(
          annotation,
          equals(
            '::error file=rfc/000.0001-sample.md,line=5,col=1::Line 1%0ALine 2 100%25',
          ),
        );
      });
    });
  });

  group('GithubAnnotatable interface conformance', () {
    test('LintIssue implements GithubAnnotatable', () {
      const issue = LintIssue(
        filePath: 'rfc/110.0000-draft.md',
        line: 2,
        column: 1,
        message: 'Invalid type',
      );
      expect(issue, isA<GithubAnnotatable>());
      expect(
        issue.toGithubAnnotation(),
        equals('::error file=rfc/110.0000-draft.md,line=2,col=1::Invalid type'),
      );
    });

    test('ValidationError implements GithubAnnotatable', () {
      const error = ValidationError(
        filePath: 'rfc/110.0001-feature.md',
        message: 'Collision detected',
      );
      expect(error, isA<GithubAnnotatable>());
      expect(
        error.toGithubAnnotation(),
        equals('::error file=rfc/110.0001-feature.md::Collision detected'),
      );
    });

    test('ValidationError supports optional line and column', () {
      const error = ValidationError(
        filePath: 'rfc/110.0001-feature.md',
        line: 42,
        column: 5,
        message: 'Positioned error',
      );
      expect(
        error.toGithubAnnotation(),
        equals(
          '::error file=rfc/110.0001-feature.md,line=42,col=5::Positioned error',
        ),
      );
      expect(
        error.toString(),
        equals('rfc/110.0001-feature.md:42:5: Positioned error'),
      );
    });
  });
}
