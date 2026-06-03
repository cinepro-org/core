import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../models/release_manifest.dart';
import 'hash_service.dart';
import 'log_service.dart';
import 'manifest_verifier.dart';

/// describes whether a release can be installed by the manager
class ManifestLookupResult {
  const ManifestLookupResult({
    required this.release,
    required this.manifest,
    required this.ready,
    this.reason,
  });

  final GitHubRelease release;
  final ReleaseManifest? manifest;
  final bool ready;
  final String? reason;
}

/// describes whether the frontend main branch can be installed
class FrontendLookupResult {
  const FrontendLookupResult({
    required this.snapshot,
    required this.ready,
    this.reason,
  });

  final FrontendSnapshot? snapshot;
  final bool ready;
  final String? reason;
}

/// describes a downloaded frontend archive
class FrontendArchive {
  const FrontendArchive({
    required this.zipPath,
    required this.snapshot,
  });

  final String zipPath;
  final FrontendSnapshot snapshot;
}

/// describes a manager setup update found in github release assets
class ManagerUpdateLookupResult {
  /// @param release github release that was inspected for manager assets
  /// @param asset name of the setup exe asset when one is available
  /// @param url browser download url for the setup exe
  /// @param sha256 checksum read from the matching sha256 asset
  /// @param size expected setup exe byte count from github
  /// @param version parsed manager version from asset name or release name
  /// @param ready whether the setup exe has enough integrity data to download
  /// @param update available whether the parsed version is newer than current
  /// @param reason short reason shown when no update is ready
  ///
  /// stores the result used by the three dot menu update indicator
  const ManagerUpdateLookupResult({
    required this.release,
    required this.ready,
    required this.updateAvailable,
    this.asset,
    this.url,
    this.sha256,
    this.size = 0,
    this.version,
    this.reason,
  });

  final GitHubRelease release;
  final bool ready;
  final bool updateAvailable;
  final String? asset;
  final String? url;
  final String? sha256;
  final int size;
  final String? version;
  final String? reason;
}

/// talks to github releases and downloads verified assets without trusting raw release text
class ReleaseClient {
  /// @param http client shared client used for github api and asset downloads
  /// @param hash service sha256 helper used before an archive can be installed
  /// @param verifier ed25519 manifest verifier for manager ready core releases
  /// @param log manager log sink used for concise download status
  ///
  /// creates a release client for core releases and ui main branch archives
  ReleaseClient({
    required this.httpClient,
    required this.hashService,
    required this.verifier,
    required this.log,
  });

  static final latestReleaseUri = Uri.parse(
    'https://api.github.com/repos/cinepro-org/core/releases/latest',
  );
  static final frontendBranchUri = Uri.parse(
    'https://api.github.com/repos/cinepro-org/ui/branches/main',
  );

  final http.Client httpClient;
  final HashService hashService;
  final ManifestVerifier verifier;
  final LogService log;

  /// reads the latest github release metadata for diagnostics and display
  Future<GitHubRelease> getLatestRelease() async {
    final response = await httpClient.get(
      latestReleaseUri,
      headers: const {
        'accept': 'application/vnd.github+json',
        'user-agent': 'cinepro-manager',
      },
    );
    if (response.statusCode != 200) {
      throw HttpException(
        'github release lookup failed: ${response.statusCode}',
      );
    }
    return GitHubRelease.fromJson(
      jsonDecode(response.body) as Map<String, Object?>,
    );
  }

  /// loads and verifies the signed manager manifest for the latest core release
  Future<ManifestLookupResult> getLatestManagerManifest() async {
    final response = await httpClient.get(
      latestReleaseUri,
      headers: const {
        'accept': 'application/vnd.github+json',
        'user-agent': 'cinepro-manager',
      },
    );
    if (response.statusCode != 200) {
      throw HttpException(
        'github release lookup failed: ${response.statusCode}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, Object?>;
    final release = GitHubRelease.fromJson(json);
    final assets = (json['assets'] as List<Object?>?) ?? const [];
    final manifestAsset = _assetUrl(assets, '.manifest.json');
    final signatureAsset = _assetUrl(assets, '.manifest.sig');

    if (manifestAsset == null || signatureAsset == null) {
      return ManifestLookupResult(
        release: release,
        manifest: null,
        ready: false,
        reason: 'this release has no signed windows manager manifest yet',
      );
    }

    final manifestBytes = await _downloadBytes(manifestAsset);
    final signatureBytes = await _downloadBytes(signatureAsset);
    await verifier.verify(
      manifestBytes: manifestBytes,
      signatureBytes: signatureBytes,
    );
    final manifest = ReleaseManifest.fromBytes(manifestBytes);
    return ManifestLookupResult(
      release: release,
      manifest: manifest,
      ready: true,
    );
  }

  /// checks the frontend main branch commit because the ui repo has no releases yet
  Future<FrontendLookupResult> getFrontendMainSnapshot() async {
    final response = await httpClient.get(
      frontendBranchUri,
      headers: const {
        'accept': 'application/vnd.github+json',
        'user-agent': 'cinepro-manager',
      },
    );
    if (response.statusCode != 200) {
      return FrontendLookupResult(
        snapshot: null,
        ready: false,
        reason: 'frontend main lookup failed: ${response.statusCode}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, Object?>;
    final commit = json['commit'] as Map<String, Object?>?;
    final sha = commit?['sha'] as String?;
    if (sha == null || sha.isEmpty) {
      return const FrontendLookupResult(
        snapshot: null,
        ready: false,
        reason: 'frontend main commit was not found',
      );
    }

    return FrontendLookupResult(
      snapshot: FrontendSnapshot(
        commit: sha,
        branch: 'main',
        archiveUrl:
            'https://github.com/cinepro-org/ui/archive/refs/heads/main.zip',
      ),
      ready: true,
    );
  }

  /// @param asset signed manifest asset entry with url, size, and sha256
  /// @param download dir folder used for the final zip and temporary part file
  /// @param on progress callback that reports received and expected bytes
  ///
  /// downloads a release asset and verifies byte count plus sha256 before returning
  Future<String> downloadVerifiedAsset({
    required ReleaseAsset asset,
    required String downloadDir,
    required void Function(int received, int total) onProgress,
  }) async {
    await Directory(downloadDir).create(recursive: true);
    final targetPath = p.join(downloadDir, asset.name);
    final tempPath = '$targetPath.part';
    final request = http.Request('GET', Uri.parse(asset.url));
    request.headers['user-agent'] = 'cinepro-manager';
    final response = await httpClient.send(request);
    if (response.statusCode != 200) {
      throw HttpException('asset download failed: ${response.statusCode}');
    }

    final sink = File(tempPath).openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        received += chunk.length;
        sink.add(chunk);
        onProgress(received, asset.size);
      }
    } finally {
      await sink.close();
    }

    if (received != asset.size) {
      await File(tempPath).delete();
      throw StateError('download size did not match manifest');
    }

    await hashService.verifySha256(tempPath, asset.sha256);
    final target = File(targetPath);
    if (await target.exists()) {
      await target.delete();
    }
    await File(tempPath).rename(targetPath);
    await log.write('download verified: ${asset.name}');
    return targetPath;
  }

  /// @param snapshot ui main branch snapshot returned by the github branch api
  /// @param download dir folder used for the final zip and temporary part file
  /// @param on progress callback that reports received and expected bytes
  ///
  /// downloads the ui main archive and records its sha256 for the install marker
  Future<FrontendArchive> downloadFrontendArchive({
    required FrontendSnapshot snapshot,
    required String downloadDir,
    required void Function(int received, int total) onProgress,
  }) async {
    await Directory(downloadDir).create(recursive: true);
    final shortCommit = snapshot.commit.substring(0, 12);
    final targetPath = p.join(downloadDir, 'cinepro-ui-$shortCommit.zip');
    final tempPath = '$targetPath.part';
    final request = http.Request('GET', Uri.parse(snapshot.archiveUrl));
    request.headers['user-agent'] = 'cinepro-manager';
    final response = await httpClient.send(request);
    if (response.statusCode != 200) {
      throw HttpException('frontend download failed: ${response.statusCode}');
    }

    final total = response.contentLength ?? 0;
    final sink = File(tempPath).openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        received += chunk.length;
        sink.add(chunk);
        onProgress(received, total);
      }
    } finally {
      await sink.close();
    }

    if (total > 0 && received != total) {
      await File(tempPath).delete();
      throw StateError('frontend download size did not match');
    }

    final sha256 = await hashService.sha256File(tempPath);
    final target = File(targetPath);
    if (await target.exists()) {
      await target.delete();
    }
    await File(tempPath).rename(targetPath);
    await log.write('frontend archive recorded: $shortCommit $sha256');
    return FrontendArchive(
      zipPath: targetPath,
      snapshot: snapshot.copyWith(
        downloadedSha256: sha256,
        downloadedSize: received,
      ),
    );
  }

  /// @param current version current manager version compiled into the app
  ///
  /// checks whether the latest release publishes a verified manager setup exe
  Future<ManagerUpdateLookupResult> getLatestManagerUpdate(
    String currentVersion,
  ) async {
    final response = await httpClient.get(
      latestReleaseUri,
      headers: const {
        'accept': 'application/vnd.github+json',
        'user-agent': 'cinepro-manager',
      },
    );
    if (response.statusCode != 200) {
      throw HttpException(
        'github release lookup failed: ${response.statusCode}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, Object?>;
    final release = GitHubRelease.fromJson(json);
    final assets = (json['assets'] as List<Object?>?) ?? const [];
    final setupAsset = _asset(assets, (name) {
      final lower = name.toLowerCase();
      return lower.startsWith('cinepro-manager-setup') &&
          lower.endsWith('.exe');
    });
    if (setupAsset == null) {
      return ManagerUpdateLookupResult(
        release: release,
        ready: false,
        updateAvailable: false,
        reason: 'no manager setup asset was found in the latest release',
      );
    }

    final setupName = setupAsset['name'] as String;
    final shaAsset = _asset(assets, (name) {
      final lower = name.toLowerCase();
      return lower == '$setupName.sha256'.toLowerCase() ||
          lower == 'cinepro-manager-setup.sha256';
    });
    if (shaAsset == null) {
      return ManagerUpdateLookupResult(
        release: release,
        ready: false,
        updateAvailable: false,
        asset: setupName,
        reason: 'manager setup asset has no sha256 checksum',
      );
    }

    final shaText = utf8.decode(
      await _downloadBytes(shaAsset['browser_download_url'] as String),
    );
    final sha256 = _firstSha256(shaText);
    if (sha256 == null) {
      return ManagerUpdateLookupResult(
        release: release,
        ready: false,
        updateAvailable: false,
        asset: setupName,
        reason: 'manager setup checksum could not be read',
      );
    }

    final version = _versionFrom(setupName) ?? _versionFrom(release.tagName);
    final updateAvailable =
        version == null ? true : _compareVersions(version, currentVersion) > 0;
    return ManagerUpdateLookupResult(
      release: release,
      ready: true,
      updateAvailable: updateAvailable,
      asset: setupName,
      url: setupAsset['browser_download_url'] as String,
      sha256: sha256,
      size: (setupAsset['size'] as num).toInt(),
      version: version,
      reason: updateAvailable ? null : 'manager is already up to date',
    );
  }

  /// @param update verified manager update lookup result
  /// @param download dir folder used for the downloaded setup exe
  /// @param on progress callback that reports received and expected bytes
  ///
  /// downloads the manager setup exe and verifies byte count plus sha256
  Future<String> downloadVerifiedManagerSetup({
    required ManagerUpdateLookupResult update,
    required String downloadDir,
    required void Function(int received, int total) onProgress,
  }) async {
    if (!update.ready ||
        update.asset == null ||
        update.url == null ||
        update.sha256 == null) {
      throw StateError('manager update is not ready');
    }

    final asset = ReleaseAsset(
      name: update.asset!,
      url: update.url!,
      sha256: update.sha256!,
      size: update.size,
    );
    return downloadVerifiedAsset(
      asset: asset,
      downloadDir: downloadDir,
      onProgress: onProgress,
    );
  }

  String? _assetUrl(List<Object?> assets, String suffix) {
    for (final item in assets) {
      if (item is! Map<String, Object?>) continue;
      final name = item['name'] as String?;
      final url = item['browser_download_url'] as String?;
      if (name != null && url != null && name.endsWith(suffix)) {
        return url;
      }
    }
    return null;
  }

  Map<String, Object?>? _asset(
    List<Object?> assets,
    bool Function(String name) accepts,
  ) {
    for (final item in assets) {
      if (item is! Map<String, Object?>) continue;
      final name = item['name'] as String?;
      final url = item['browser_download_url'] as String?;
      if (name != null && url != null && accepts(name)) return item;
    }
    return null;
  }

  Future<List<int>> _downloadBytes(String url) async {
    final response = await httpClient.get(
      Uri.parse(url),
      headers: const {'user-agent': 'cinepro-manager'},
    );
    if (response.statusCode != 200) {
      throw HttpException(
        'manifest asset download failed: ${response.statusCode}',
      );
    }
    return response.bodyBytes;
  }

  String? _firstSha256(String text) {
    final match = RegExp(r'\b[a-fA-F0-9]{64}\b').firstMatch(text);
    return match?.group(0)?.toLowerCase();
  }

  String? _versionFrom(String text) {
    final match = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(text);
    return match?.group(0);
  }

  int _compareVersions(String left, String right) {
    final leftParts = left.split('.').map(int.parse).toList();
    final rightParts = right.split('.').map(int.parse).toList();
    for (var index = 0; index < 3; index++) {
      final difference = leftParts[index] - rightParts[index];
      if (difference != 0) return difference;
    }
    return 0;
  }
}
