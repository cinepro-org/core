import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// verifies signed release manifests
class ManifestVerifier {
  ManifestVerifier({required this.publicKeyBase64});

  final String publicKeyBase64;

  /// verifies a signed release manifest before any asset is trusted
  Future<void> verify({
    required List<int> manifestBytes,
    required List<int> signatureBytes,
  }) async {
    final publicKeyBytes = base64Decode(publicKeyBase64);
    final publicKey = SimplePublicKey(
      publicKeyBytes,
      type: KeyPairType.ed25519,
    );
    final signature = Signature(signatureBytes, publicKey: publicKey);
    final ok = await Ed25519().verify(manifestBytes, signature: signature);
    if (!ok) {
      throw StateError('release manifest signature is not valid');
    }
  }
}
