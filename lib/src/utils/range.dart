import 'dart:async';

/// Represents a parsed byte range from a Range header
class ByteRange {
  final int start;
  final int? end; // null means "to end of file"

  ByteRange(this.start, this.end);

  /// Get the actual end position given the total file size
  int getEnd(final int fileSize) => end ?? (fileSize - 1);

  /// Get the length of this range given the total file size
  int getLength(final int fileSize) => getEnd(fileSize) - start + 1;

  /// Check if this range is valid for the given file size
  bool isValid(final int fileSize) {
    if (start < 0 || start >= fileSize) return false;
    if (end != null && (end! < start || end! >= fileSize)) return false;
    return true;
  }
}

/// Parse a Range header value (e.g., "bytes=0-499" or "bytes=500-")
/// Returns null if invalid or not a simple byte range request
/// Note: This implementation only supports simple single-range requests
ByteRange? parseRange(final String? header) {
  if (header == null || header.isEmpty) return null;

  // Only support "bytes" unit
  if (!header.startsWith('bytes=')) return null;

  final rangeSpec = header.substring(6).trim();

  // Only support single range (no multi-range like "0-100,200-300")
  if (rangeSpec.contains(',')) return null;

  final parts = rangeSpec.split('-');
  if (parts.length != 2) return null;

  final startStr = parts[0].trim();
  final endStr = parts[1].trim();

  // Handle "bytes=-500" (suffix range) - not supported for simplicity
  if (startStr.isEmpty) return null;

  try {
    final start = int.parse(startStr);

    // Handle "bytes=500-" (from start to end)
    if (endStr.isEmpty) {
      return ByteRange(start, null);
    }

    // Handle "bytes=500-999" (start to end)
    final end = int.parse(endStr);
    return ByteRange(start, end);
  } catch (e) {
    return null;
  }
}

/// Create a stream that reads only the specified byte range from a file
Stream<List<int>> createRangeStream(
  final Stream<List<int>> source,
  final int start,
  final int end,
) async* {
  var position = 0;
  final length = end - start + 1;
  var remaining = length;

  await for (final chunk in source) {
    final chunkStart = position;
    final chunkEnd = position + chunk.length - 1;
    position += chunk.length;

    // Skip chunks entirely before the range
    if (chunkEnd < start) continue;

    // Stop if we've passed the range
    if (chunkStart > end) break;

    // Calculate which part of this chunk to include
    final includeStart = (chunkStart >= start) ? 0 : (start - chunkStart);
    final includeEnd =
        (chunkEnd <= end) ? chunk.length : (end - chunkStart + 1);

    final subchunk = chunk.sublist(includeStart, includeEnd);
    remaining -= subchunk.length;

    yield subchunk;

    if (remaining <= 0) break;
  }
}
