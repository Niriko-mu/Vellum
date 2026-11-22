import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// Default update/download repository.
///
/// This must be where the release workflow actually publishes, which is GitHub
/// (see .github/workflows/release.yml). It used to point at the older Gitee
/// mirror, whose newest release is 1.0.15 — so every reader who installed a
/// GitHub build checked a repository that would never have a newer version, and
/// 「检查更新」 answered "已是最新" forever. Readers can still point the updater
/// at another repository by hand in 设置 → 更新仓库.
const vellumDefaultRepository = 'github.com/niriko-mu/Vellum';
const vellumDefaultRepositoryUrl = 'https://github.com/niriko-mu/Vellum';

class UpdateCheckException implements Exception {
  const UpdateCheckException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Parsed remote repository reference.
class RepoRef {
  const RepoRef({required this.host, required this.owner, required this.repo});

  final String host;
  final String owner;
  final String repo;

  String get slug => '$owner/$repo';
  bool get isGitee => host == 'gitee.com';

  String get webUrl => 'https://$host/$owner/$repo';

  String get latestReleaseApi => isGitee
      ? 'https://gitee.com/api/v5/repos/$owner/$repo/releases/latest'
      : 'https://api.github.com/repos/$owner/$repo/releases/latest';

  String get releasesApi => isGitee
      ? 'https://gitee.com/api/v5/repos/$owner/$repo/releases?per_page=10'
      : 'https://api.github.com/repos/$owner/$repo/releases?per_page=10';

  @override
  String toString() => '$host/$owner/$repo';
}

RepoRef? parseUpdateRepository(String input) {
  var value = input.trim();
  if (value.isEmpty) return null;
  value = value.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
  value = value.replaceFirst(RegExp(r'^www\.', caseSensitive: false), '');
  value = value.replaceAll(RegExp(r'/+$'), '');

  // A bare `owner/repo` is read as GitHub, matching the default repository.
  // Gitee is still accepted when the host is spelled out.
  var host = 'github.com';
  if (value.toLowerCase().startsWith('github.com/')) {
    value = value.substring('github.com/'.length);
  } else if (value.toLowerCase().startsWith('gitee.com/')) {
    host = 'gitee.com';
    value = value.substring('gitee.com/'.length);
  }

  final parts = value.split('/').where((p) => p.isNotEmpty).toList();
  if (parts.length < 2) return null;
  return RepoRef(host: host, owner: parts[0], repo: parts[1]);
}

String? normalizeUpdateRepository(String input) =>
    parseUpdateRepository(input)?.toString();

class VellumReleaseInfo {
  const VellumReleaseInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.notes,
    required this.releaseUrl,
    required this.assets,
    this.repository = vellumDefaultRepository,
  });

  final String currentVersion;
  final String latestVersion;
  final String notes;
  final String releaseUrl;
  final Map<String, String> assets;
  final String repository;

  bool get hasUpdate => _isNewer(latestVersion, currentVersion);

  /// APK assets grouped by ABI label (`arm64-v8a`, `armeabi-v7a`, `x86_64`…).
  ///
  /// Each entry keeps the original asset name and download URL.
  List<UpdateApkAsset> get apkAssets => apkAssetsFor(null);

  /// APK assets with [preferredAbi] moved to the front, then the usual
  /// `arm64-v8a → armeabi-v7a → x86_64 → 通用` fallback order.
  List<UpdateApkAsset> apkAssetsFor(String? preferredAbi) {
    final list = <UpdateApkAsset>[];
    for (final entry in assets.entries) {
      final abi = detectAbiFromAssetName(entry.key);
      list.add(UpdateApkAsset(name: entry.key, url: entry.value, abi: abi));
    }
    list.sort((a, b) {
      final rank = _abiRank(a.abi).compareTo(_abiRank(b.abi));
      if (rank != 0) return rank;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    if (preferredAbi == null) return list;
    final preferred = <UpdateApkAsset>[
      for (final asset in list)
        if (asset.abi == preferredAbi) asset,
    ];
    if (preferred.isEmpty) return list;
    return [
      ...preferred,
      for (final asset in list)
        if (asset.abi != preferredAbi) asset,
    ];
  }

  static int _abiRank(String? abi) {
    switch (abi) {
      case 'arm64-v8a':
        return 0;
      case 'armeabi-v7a':
        return 1;
      case 'x86_64':
        return 2;
      case 'x86':
        return 3;
      default:
        return 9;
    }
  }

  static bool _isNewer(String latest, String current) {
    List<int> parse(String value) => value
        .replaceFirst(RegExp(r'^[vV]'), '')
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList();
    final remote = parse(latest);
    final local = parse(current);
    final length = remote.length > local.length ? remote.length : local.length;
    for (var index = 0; index < length; index++) {
      final a = index < remote.length ? remote[index] : 0;
      final b = index < local.length ? local[index] : 0;
      if (a != b) return a > b;
    }
    return false;
  }
}

class UpdateApkAsset {
  const UpdateApkAsset({
    required this.name,
    required this.url,
    required this.abi,
  });

  final String name;
  final String url;

  /// `arm64-v8a` / `armeabi-v7a` / `x86_64` / `x86`, or null when unknown.
  final String? abi;

  String get label => abi ?? '通用';
}

/// Detects ABI from release asset filenames such as
/// `Vellum-V1.0.2-arm64-v8a.apk` or `app-armeabi-v7a-release.apk`.
String? detectAbiFromAssetName(String name) {
  final lower = name.toLowerCase();
  if (lower.contains('arm64') || lower.contains('aarch64')) return 'arm64-v8a';
  if (lower.contains('armeabi') ||
      lower.contains('arm-v7') ||
      lower.contains('armv7') ||
      lower.contains('arm-32')) {
    return 'armeabi-v7a';
  }
  if (lower.contains('x86_64') ||
      lower.contains('x86-64') ||
      lower.contains('amd64')) {
    return 'x86_64';
  }
  if (RegExp(r'(^|[^0-9])x86([^0-9_]|$)').hasMatch(lower)) return 'x86';
  return null;
}

/// Maps a device ABI entry (from `android.os.Build.SUPPORTED_ABIS`) onto the
/// labels used in release asset names.
String? normalizeAbiName(String name) {
  switch (name.trim().toLowerCase()) {
    case 'arm64-v8a':
    case 'arm64':
    case 'aarch64':
      return 'arm64-v8a';
    case 'armeabi-v7a':
    case 'armeabi':
    case 'armv7l':
      return 'armeabi-v7a';
    case 'x86_64':
    case 'x86-64':
    case 'amd64':
      return 'x86_64';
    case 'x86':
    case 'i386':
    case 'i686':
      return 'x86';
    default:
      return null;
  }
}

/// Short explanation shown next to each variant in the update sheet.
String abiDescription(String? abi) {
  switch (abi) {
    case 'arm64-v8a':
      return '64 位 · 绝大多数手机';
    case 'armeabi-v7a':
      return '32 位 · 较老机型';
    case 'x86_64':
      return 'x86 平板 / 模拟器';
    case 'x86':
      return '32 位模拟器';
    default:
      return '通用包 · 体积更大';
  }
}

/// Turns a transport failure into something a reader can act on.
///
/// Returns null when the failure is not recognisable as a network problem, so
/// the caller can fall back to a generic message rather than claiming the
/// network is down when it might be something else.
String? updateNetworkHint(Object error) {
  final text = error.toString().toLowerCase();
  if (text.contains('failed host lookup') ||
      text.contains('no address associated') ||
      text.contains('name or service not known')) {
    return '解析不了域名，请检查网络是否可用（离线时需要联网才能检查更新）。';
  }
  if (text.contains('timeout') || text.contains('timed out')) {
    return '连接超时，请检查网络后重试。';
  }
  if (text.contains('connection refused') ||
      text.contains('connection reset') ||
      text.contains('network is unreachable')) {
    return '连不上更新服务器，请检查网络后重试。';
  }
  if (text.contains('certificate') || text.contains('handshake')) {
    return '安全连接失败，请检查系统时间或代理设置。';
  }
  return null;
}

class VellumUpdateService {
  const VellumUpdateService();

  static const _headers = {
    'Accept': 'application/json',
    'User-Agent': 'Vellum-App',
  };

  Future<VellumReleaseInfo?> check({String? repository}) async {
    final ref =
        parseUpdateRepository(repository ?? '') ??
        parseUpdateRepository(vellumDefaultRepository)!;
    final package = await PackageInfo.fromPlatform();

    Map<String, dynamic>? data;
    try {
      data = await _fetchLatest(ref);
    } on UpdateCheckException catch (error) {
      // Already user-facing ("HTTP 403"), so it stays as it is.
      throw UpdateCheckException('无法访问 ${ref.host}：${error.message}');
    } catch (error) {
      // Everything else is a transport failure whose `toString` is a wall of
      // ClientException / SocketException text with the full URL in it. On a
      // phone with no network that is all the reader would see; say the one
      // thing they can act on instead, and keep the detail in the log.
      throw UpdateCheckException(
        updateNetworkHint(error) ??
            '无法访问 ${ref.host}，请检查网络后重试。${ref.webUrl}',
      );
    }
    if (data == null) {
      throw UpdateCheckException('未能读取 ${ref.toString()} 的 Release，请确认仓库名与网络。');
    }

    final tag = (data['tag_name'] as String? ?? '').trim();
    if (tag.isEmpty) {
      throw UpdateCheckException('仓库 ${ref.toString()} 没有可用的 Release 标签。');
    }

    final assets = <String, String>{};
    final rawAssets = data['assets'];
    if (rawAssets is List<dynamic>) {
      for (final value in rawAssets) {
        if (value is! Map) continue;
        final asset = value.cast<String, dynamic>();
        final name = asset['name'] as String? ?? '';
        final url =
            (asset['browser_download_url'] as String?) ??
            (asset['download_url'] as String?) ??
            '';
        if (name.toLowerCase().endsWith('.apk') && url.isNotEmpty) {
          assets[name] = url;
        }
      }
    }

    final htmlUrl = data['html_url'] as String? ?? ref.webUrl;
    return VellumReleaseInfo(
      currentVersion: package.version,
      latestVersion: tag.replaceFirst(RegExp(r'^[vV]'), ''),
      notes: data['body'] as String? ?? data['name'] as String? ?? '',
      releaseUrl: htmlUrl,
      assets: assets,
      repository: ref.toString(),
    );
  }

  Future<Map<String, dynamic>?> _fetchLatest(RepoRef ref) async {
    final latest = await _getJson(ref.latestReleaseApi);
    if (latest != null) return latest;
    // Fallback: some hosts (or private repos) 404 on /latest — use the list.
    final list = await _getJsonList(ref.releasesApi);
    if (list == null || list.isEmpty) return null;
    for (final item in list) {
      final prerelease = item['prerelease'] == true;
      final draft = item['draft'] == true;
      if (!draft && !prerelease) return item;
    }
    return list.first;
  }

  Future<Map<String, dynamic>?> _getJson(String url) async {
    final response = await http
        .get(Uri.parse(url), headers: _headers)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw UpdateCheckException('HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) return decoded;
    return null;
  }

  Future<List<Map<String, dynamic>>?> _getJsonList(String url) async {
    final response = await http
        .get(Uri.parse(url), headers: _headers)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw UpdateCheckException('HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is List) {
      return [
        for (final item in decoded)
          if (item is Map<String, dynamic>) item,
      ];
    }
    return null;
  }
}
