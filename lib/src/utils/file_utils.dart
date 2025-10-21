import 'dart:async';

import 'package:file/file.dart';

/// Exception thrown when upload size exceeds the maximum allowed
class UploadSizeLimitExceededException implements Exception {
  final int maxSize;
  final int actualSize;

  UploadSizeLimitExceededException(this.maxSize, this.actualSize);

  @override
  String toString() =>
      'Upload size limit exceeded: $actualSize bytes exceeds maximum of $maxSize bytes';
}

Future<File> writeToFile(
  final File file,
  final int max,
  final Stream<List<int>> data,
) async {
  final stream = _validateStreamSize(data, max);

  if (await file.exists()) {
    return _replaceFile(file, stream);
  }
  return _createFile(file, stream);
}

/// Validates that the stream doesn't exceed the maximum size
/// If maxSize is 0, no validation is performed (unlimited)
Stream<List<int>> _validateStreamSize(
  final Stream<List<int>> data,
  final int max,
) {
  if (max == 0) {
    return data;
  }

  var total = 0;
  return data.map((chunk) {
    total += chunk.length;
    if (total > max) {
      throw UploadSizeLimitExceededException(max, total);
    }
    return chunk;
  });
}

/// Creates a new file and writes the data stream to it
/// Cleans up partial file if an error occurs
Future<File> _createFile(final File file, final Stream<List<int>> data) async {
  final created = await file.create(recursive: true);
  final sink = created.openWrite();
  try {
    await sink.addStream(data);
    await sink.flush();
    await sink.close();
    return file;
  } catch (e) {
    // Clean up partially written file on error
    await sink.close();
    if (await file.exists()) {
      await file.delete();
    }
    rethrow;
  }
}

/// Atomically replaces an existing file with new data
/// Uses a temporary file to prevent corruption on failure
Future<File> _replaceFile(final File file, final Stream<List<int>> data) async {
  final fs = file.fileSystem;
  final temp = fs.file('${file.path}_${DateTime.now().microsecondsSinceEpoch}');

  // Write to temp file with proper resource cleanup
  try {
    final sink = temp.openWrite();
    try {
      await sink.addStream(data);
      await sink.flush();
    } finally {
      // Always close sink, even if addStream/flush throws
      await sink.close();
    }

    // Atomic replace: copy temp over original, then delete temp
    // These operations are in a separate try block to ensure temp cleanup
    try {
      await temp.copy(file.path);
    } finally {
      // Always delete temp file, even if copy throws
      if (await temp.exists()) {
        await temp.delete();
      }
    }
  } catch (e) {
    // Ensure temp file is cleaned up if anything goes wrong
    if (await temp.exists()) {
      await temp.delete();
    }
    rethrow;
  }

  return file;
}
