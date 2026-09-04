// Copyright 2026 The Flutter Authors.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Interface for objects that can be formatted as GitHub Actions workflow annotations.
abstract interface class GithubAnnotatable {
  /// Formats this object as a GitHub Actions workflow annotation string.
  String toGithubAnnotation();
}

/// Extension on [String] for GitHub Actions workflow command formatting.
extension GithubAnnotationExtension on String {
  /// Encodes special characters (`%`, `\r`, `\n`) in this string per GitHub Actions
  /// workflow command specifications so multiline formatting is preserved.
  String toGithubWorkflowValue() {
    return replaceAll(
      '%',
      '%25',
    ).replaceAll('\r', '%0D').replaceAll('\n', '%0A');
  }

  /// Formats this string message as a GitHub Actions workflow annotation.
  ///
  /// Example:
  /// ```dart
  /// 'File not found'.toGithubAnnotation(filePath: 'rfc/110.0001.md');
  ///   => '::error file=rfc/110.0001.md::File not found'
  ///
  /// 'Syntax error'.toGithubAnnotation(
  ///   filePath: 'rfc/110.0001.md',
  ///   line: 12,
  ///   column: 4,
  /// );
  ///   => '::error file=rfc/110.0001.md,line=12,col=4::Syntax error'
  /// ```
  String toGithubAnnotation({
    required String filePath,
    int? line,
    int? column,
    String type = 'error',
    String? title,
  }) {
    final encoded = toGithubWorkflowValue();
    final params = <String>[
      'file=$filePath',
      if (line != null) 'line=$line',
      if (column != null) 'col=$column',
      if (title != null) 'title=$title',
    ].join(',');

    return '::$type $params::$encoded';
  }
}
