// Copyright 2026 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/file.dart';

/// Represents the dynamic taxonomy of Flutter subsystems extracted from RFC 000.0001.
class Taxonomy {
  /// Set of all valid 3-digit category strings (e.g. "000", "010", "110", "210").
  final Set<String> categories;

  /// Optional mapping from category string to human-readable title.
  final Map<String, String> categoryNames;

  const Taxonomy(this.categories, [this.categoryNames = const {}]);

  /// Checks whether [category] is a recognized subsystem classification.
  bool isValidCategory(String category) => categories.contains(category);

  /// Parses taxonomy categories from markdown content of RFC 000.0001.
  static Taxonomy fromMarkdown(String markdown) {
    final categories = <String>{};
    final categoryNames = <String, String>{};

    // Match section headers: ### 000 – General, Process, & Meta
    final sectionHeaderRegex = RegExp(
      r'^###\s+([0-9]{3})\s+[–—-]\s*(.*)$',
      multiLine: true,
    );
    for (final match in sectionHeaderRegex.allMatches(markdown)) {
      final code = match.group(1)!;
      final name = match.group(2)?.trim() ?? '';
      categories.add(code);
      categoryNames[code] = name;
    }

    // Match list items: * **110:** Foundation & Low-level
    final listItemRegex = RegExp(
      r'^\*\s+\*\*([0-9]{3}):?\*\*:?\s*(.*)$',
      multiLine: true,
    );
    for (final match in listItemRegex.allMatches(markdown)) {
      final code = match.group(1)!;
      final name = match.group(2)?.trim() ?? '';
      categories.add(code);
      if (name.isNotEmpty) {
        categoryNames[code] = name;
      }
    }

    return Taxonomy(categories, categoryNames);
  }

  /// Loads the taxonomy from RFC 000.0001 on the given [fs].
  static Future<Taxonomy> load(FileSystem fs) async {
    File? file;

    const defaultPath =
        'rfc/000.0001-flutter-architecture-and-reference-taxonomy.md';
    file = fs.file(defaultPath);

    if (!await file.exists()) {
      throw StateError(
        'Could not locate RFC 000.0001 taxonomy document in "rfc". '
        'Ensure rfc/000.0001-flutter-architecture-and-reference-taxonomy.md exists.',
      );
    }

    final content = await file.readAsString();
    return Taxonomy.fromMarkdown(content);
  }
}
