import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

/// generates the ed25519 release key pair used by manager manifests
Future<void> main() async {
  final algorithm = Ed25519();
  final keyPair = await algorithm.newKeyPair();
  final privateKey = await keyPair.extractPrivateKeyBytes();
  final publicKey = await keyPair.extractPublicKey();

  stdout.writeln(
    'CINEPRO_RELEASE_PUBLIC_KEY_BASE64=${base64Encode(publicKey.bytes)}',
  );
  stdout.writeln(
    'CINEPRO_RELEASE_PRIVATE_KEY_BASE64=${base64Encode(privateKey)}',
  );
  stdout.writeln('');
  stdout.writeln('put the public key in manager_controller.dart');
  stdout.writeln('put the private key in github actions secrets only');
}
