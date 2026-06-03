import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

/// signs a release manifest with the private ed25519 key from the environment
Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln(
      'usage: dart run tool/sign_release_manifest.dart manifest.json manifest.sig',
    );
    exitCode = 64;
    return;
  }

  final publicKeyBase64 =
      Platform.environment['CINEPRO_RELEASE_PUBLIC_KEY_BASE64'];
  final privateKeyBase64 =
      Platform.environment['CINEPRO_RELEASE_PRIVATE_KEY_BASE64'];
  if (publicKeyBase64 == null || privateKeyBase64 == null) {
    stderr.writeln(
      'set CINEPRO_RELEASE_PUBLIC_KEY_BASE64 and CINEPRO_RELEASE_PRIVATE_KEY_BASE64',
    );
    exitCode = 64;
    return;
  }

  final manifest = File(arguments[0]);
  final signature = File(arguments[1]);
  final manifestBytes = await manifest.readAsBytes();
  final publicKeyBytes = base64Decode(publicKeyBase64);
  final privateKeyBytes = base64Decode(privateKeyBase64);
  final keyPair = SimpleKeyPairData(
    privateKeyBytes,
    publicKey: SimplePublicKey(
      publicKeyBytes,
      type: KeyPairType.ed25519,
    ),
    type: KeyPairType.ed25519,
  );
  final signed = await Ed25519().sign(manifestBytes, keyPair: keyPair);
  await signature.writeAsBytes(signed.bytes, flush: true);
  stdout.writeln('signed ${manifest.path}');
  stdout.writeln('wrote ${signature.path}');
}
