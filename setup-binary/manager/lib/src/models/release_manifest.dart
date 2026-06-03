import 'dart:convert';

/// describes a downloadable release asset from a signed manager manifest
class ReleaseAsset {
  /// @param name expected filename used in the downloads folder
  /// @param url browser download url or runtime archive url
  /// @param sha256 expected sha256 hash checked before extraction
  /// @param size expected byte count used to reject partial downloads
  ///
  /// creates an asset record that must be verified before use
  const ReleaseAsset({
    required this.name,
    required this.url,
    required this.sha256,
    required this.size,
  });

  factory ReleaseAsset.fromJson(Map<String, Object?> json) {
    return ReleaseAsset(
      name: json['name'] as String,
      url: json['url'] as String,
      sha256: json['sha256'] as String,
      size: (json['size'] as num).toInt(),
    );
  }

  final String name;
  final String url;
  final String sha256;
  final int size;

  Map<String, Object?> toJson() {
    return {'name': name, 'url': url, 'sha256': sha256, 'size': size};
  }
}

/// describes the bundled node runtime required by core startup
class RuntimeSpec {
  /// @param node version pinned node version expected by the release package
  /// @param url verified node runtime archive url
  /// @param sha256 expected runtime archive sha256
  /// @param size expected runtime archive byte count
  ///
  /// creates a runtime requirement from the signed release manifest
  const RuntimeSpec({
    required this.nodeVersion,
    required this.url,
    required this.sha256,
    required this.size,
  });

  factory RuntimeSpec.fromJson(Map<String, Object?> json) {
    return RuntimeSpec(
      nodeVersion: json['nodeVersion'] as String,
      url: json['url'] as String,
      sha256: json['sha256'] as String,
      size: (json['size'] as num).toInt(),
    );
  }

  final String nodeVersion;
  final String url;
  final String sha256;
  final int size;

  Map<String, Object?> toJson() {
    return {
      'nodeVersion': nodeVersion,
      'url': url,
      'sha256': sha256,
      'size': size,
    };
  }
}

/// describes the signed release manifest trusted by the manager
class ReleaseManifest {
  /// @param schema manifest schema version
  /// @param name package name for display and diagnostics
  /// @param tag core release tag to install
  /// @param commit exact core commit represented by the package
  /// @param asset verified core archive metadata
  /// @param runtime verified node runtime metadata
  /// @param min manager version oldest manager version allowed to install this release
  /// @param published at release publish timestamp from the manifest
  ///
  /// creates a manager ready core release manifest
  const ReleaseManifest({
    required this.schema,
    required this.name,
    required this.tag,
    required this.commit,
    required this.asset,
    required this.runtime,
    required this.minManagerVersion,
    required this.publishedAt,
  });

  factory ReleaseManifest.fromBytes(List<int> bytes) {
    final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
    return ReleaseManifest.fromJson(decoded);
  }

  factory ReleaseManifest.fromJson(Map<String, Object?> json) {
    return ReleaseManifest(
      schema: (json['schema'] as num).toInt(),
      name: json['name'] as String,
      tag: json['tag'] as String,
      commit: json['commit'] as String,
      asset: ReleaseAsset.fromJson(json['asset'] as Map<String, Object?>),
      runtime: RuntimeSpec.fromJson(json['runtime'] as Map<String, Object?>),
      minManagerVersion: json['minManagerVersion'] as String,
      publishedAt: DateTime.parse(json['publishedAt'] as String),
    );
  }

  final int schema;
  final String name;
  final String tag;
  final String commit;
  final ReleaseAsset asset;
  final RuntimeSpec runtime;
  final String minManagerVersion;
  final DateTime publishedAt;

  Map<String, Object?> toJson() {
    return {
      'schema': schema,
      'name': name,
      'tag': tag,
      'commit': commit,
      'asset': asset.toJson(),
      'runtime': runtime.toJson(),
      'minManagerVersion': minManagerVersion,
      'publishedAt': publishedAt.toIso8601String(),
    };
  }
}

/// describes the current frontend main branch snapshot
class FrontendSnapshot {
  /// @param commit exact ui main branch commit returned by github
  /// @param branch branch name tracked by the manager
  /// @param archive url github branch archive url used for download
  /// @param downloaded sha256 sha256 recorded after the archive is downloaded
  /// @param downloaded size byte count recorded after the archive is downloaded
  ///
  /// creates a ui snapshot that can be recorded in the install marker
  const FrontendSnapshot({
    required this.commit,
    required this.branch,
    required this.archiveUrl,
    this.downloadedSha256,
    this.downloadedSize,
  });

  final String commit;
  final String branch;
  final String archiveUrl;
  final String? downloadedSha256;
  final int? downloadedSize;

  FrontendSnapshot copyWith({String? downloadedSha256, int? downloadedSize}) {
    return FrontendSnapshot(
      commit: commit,
      branch: branch,
      archiveUrl: archiveUrl,
      downloadedSha256: downloadedSha256 ?? this.downloadedSha256,
      downloadedSize: downloadedSize ?? this.downloadedSize,
    );
  }
}

/// describes public github release metadata used for display and diagnostics
class GitHubRelease {
  /// @param tag name github release tag name
  /// @param name github release display name
  /// @param body github release body text
  /// @param html url browser url for the release page
  /// @param published at github release publish timestamp
  ///
  /// creates a lightweight github release model
  const GitHubRelease({
    required this.tagName,
    required this.name,
    required this.body,
    required this.htmlUrl,
    required this.publishedAt,
  });

  factory GitHubRelease.fromJson(Map<String, Object?> json) {
    return GitHubRelease(
      tagName: json['tag_name'] as String,
      name: (json['name'] as String?) ?? json['tag_name'] as String,
      body: (json['body'] as String?) ?? '',
      htmlUrl: json['html_url'] as String,
      publishedAt: DateTime.parse(json['published_at'] as String),
    );
  }

  final String tagName;
  final String name;
  final String body;
  final String htmlUrl;
  final DateTime publishedAt;
}
