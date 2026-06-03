import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

/// verifies downloaded files with sha256
class HashService {
  /// @param file path file path to hash through a stream
  ///
  /// computes the sha256 hash for a file
  Future<String> sha256File(String filePath) async {
    final digest = await crypto.sha256.bind(File(filePath).openRead()).first;
    return digest.toString();
  }

  /// @param file path downloaded file path to verify
  /// @param expected sha256 hash value from the trusted manifest
  ///
  /// checks a file hash against a manifest value before extraction
  Future<void> verifySha256(String filePath, String expectedSha256) async {
    final actual = await sha256File(filePath);
    if (actual.toLowerCase() != expectedSha256.toLowerCase()) {
      throw StateError('download verification failed');
    }
  }

  /// @param text base64 text from the embedded public key or signature
  ///
  /// decodes base64 text used by release signatures
  List<int> decodeBase64(String text) {
    return base64Decode(text.trim());
  }
}
