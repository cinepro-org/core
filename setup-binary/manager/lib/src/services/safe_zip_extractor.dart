import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

/// extracts zip files only after path, count, symlink, and size checks
class SafeZipExtractor {
  /// @param max files maximum number of archive entries accepted during extraction
  /// @param max expanded bytes maximum total expanded bytes accepted before extraction fails
  ///
  /// creates a guarded extractor with conservative limits for manager packages
  const SafeZipExtractor({
    this.maxFiles = 12000,
    this.maxExpandedBytes = 900 * 1024 * 1024,
  });

  final int maxFiles;
  final int maxExpandedBytes;

  /// @param zip path verified archive path to extract from
  /// @param destination path staging folder that will be recreated before extraction
  ///
  /// extracts a zip after validating every destination path stays in staging
  Future<void> extract({
    required String zipPath,
    required String destinationPath,
  }) async {
    final destination = Directory(destinationPath);
    if (await destination.exists()) {
      await destination.delete(recursive: true);
    }
    await destination.create(recursive: true);

    final root = p.normalize(p.absolute(destinationPath));
    final input = InputFileStream(zipPath);
    final archive = ZipDecoder().decodeStream(input);
    var fileCount = 0;
    var expandedBytes = 0;

    for (final entry in archive) {
      fileCount++;
      if (fileCount > maxFiles) {
        throw StateError('archive contains too many files');
      }

      final entryName = entry.name.replaceAll('\\', '/');
      _validateEntryName(entryName);

      if (entry.isSymbolicLink) {
        throw StateError('archive contains a symbolic link');
      }

      expandedBytes += entry.size;
      if (expandedBytes > maxExpandedBytes) {
        throw StateError('archive expands beyond the allowed size');
      }

      final targetPath = p.normalize(p.join(root, entryName));
      if (!_isInside(root, targetPath)) {
        throw StateError('archive path escapes the install folder');
      }

      if (entry.isDirectory) {
        await Directory(targetPath).create(recursive: true);
        continue;
      }

      if (entry.isFile) {
        await Directory(p.dirname(targetPath)).create(recursive: true);
        final output = OutputFileStream(targetPath);
        entry.writeContent(output);
        output.closeSync();
      }
    }
  }

  void _validateEntryName(String name) {
    if (name.isEmpty || name.contains('\u0000')) {
      throw StateError('archive contains an invalid path');
    }
    if (name.startsWith('/') || name.startsWith(r'\')) {
      throw StateError('archive contains an absolute path');
    }
    if (RegExp(r'^[a-zA-Z]:').hasMatch(name)) {
      throw StateError('archive contains a drive path');
    }
    final parts = p.posix.split(name);
    if (parts.any((part) => part == '..')) {
      throw StateError('archive contains a parent path');
    }
  }

  bool _isInside(String root, String targetPath) {
    return targetPath == root || p.isWithin(root, targetPath);
  }
}
