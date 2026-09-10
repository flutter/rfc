import 'dart:io' show ProcessResult;

/// Signature for running an external process asynchronously.
typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);
