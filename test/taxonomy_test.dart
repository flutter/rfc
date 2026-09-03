// Copyright 2026 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/memory.dart';
import 'package:rfc_tools/src/taxonomy.dart';
import 'package:test/test.dart';

void main() {
  group('Taxonomy', () {
    test('parses section headers and list items from markdown', () {
      const sample = '''
# RFC 000.0001: Architecture Taxonomy

### 000 – General, Process, & Meta
Governance and how the Flutter project itself functions.

* **000:** RFC Process & Templates
* **010:** Governance & Steering Committees

### 100 – Flutter Framework Core
The Dart-side architecture of Flutter.

* **110:** Foundation & Low-level
* **120:** Rendering Layer
''';

      final taxonomy = Taxonomy.fromMarkdown(sample);
      expect(
        taxonomy.categories,
        containsAll(['000', '010', '100', '110', '120']),
      );
      expect(taxonomy.isValidCategory('000'), isTrue);
      expect(taxonomy.isValidCategory('010'), isTrue);
      expect(taxonomy.isValidCategory('110'), isTrue);
      expect(taxonomy.isValidCategory('999'), isFalse);
      expect(taxonomy.isValidCategory('abc'), isFalse);
    });

    test('loads successfully from FileSystem', () async {
      final fs = MemoryFileSystem();
      final file = fs.file(
        'rfc/000.0001-flutter-architecture-and-reference-taxonomy.md',
      );
      await file.create(recursive: true);
      await file.writeAsString('''
# RFC 000.0001: Taxonomy
### 100 – Core
* **110:** Foundation
''');

      final taxonomy = await Taxonomy.load(fs);
      expect(taxonomy.isValidCategory('110'), isTrue);
      expect(taxonomy.isValidCategory('999'), isFalse);
    });

    test('throws StateError when taxonomy document does not exist', () async {
      final fs = MemoryFileSystem();
      await fs.directory('rfc').create(recursive: true);

      expect(() => Taxonomy.load(fs), throwsStateError);
    });
  });
}
