// Copyright 2026 The Flutter Authors.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io' show ProcessResult;

/// Signature for running an external process asynchronously.
typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);
