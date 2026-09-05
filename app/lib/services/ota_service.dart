import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/branding.dart';

class OtaUpdate {
  final int build;
  final String downloadUrl;
  final String assetName;
  final int sizeBytes;
  const OtaUpdate({required this.build, required this.downloadUrl, required this.assetName, this.sizeBytes = 0});
}

/// Checks this brand's GitHub repo for a newer signed APK than the one
/// currently installed. Every brand built from the same builder repo shares
/// one release list (tag `build-<run number>`), so this matches by asset
/// filename ("<SafeAppName>-tv.apk") rather than by release tag alone.
class OtaService {
  /// Returns an available update, or null if this is already the newest
  /// build (or the repo isn't known / reachable).
  static Future<OtaUpdate?> check() async {
    final b = Branding.I;
    if (b.repo.isEmpty || b.buildNumber <= 0) return null;

    final expectedAsset = _safeAssetName(b.appName);
    final uri = Uri.parse('https://api.github.com/repos/${b.repo}/releases?per_page=30');
    final http.Response r;
    try {
      r = await http.get(uri, headers: const {'Accept': 'application/vnd.github+json'})
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      return null; // offline / blocked — just skip the check
    }
    if (r.statusCode != 200) return null;

    final releases = jsonDecode(r.body) as List;
    OtaUpdate? best;
    for (final rel in releases) {
      final tag = (rel['tag_name'] ?? '').toString();
      final m = RegExp(r'^build-(\d+)$').firstMatch(tag);
      if (m == null) continue;
      final build = int.parse(m.group(1)!);
      if (build <= b.buildNumber) continue;
      if (best != null && build <= best.build) continue;

      final assets = (rel['assets'] as List?) ?? const [];
      for (final a in assets) {
        final name = (a['name'] ?? '').toString();
        if (name == expectedAsset) {
          best = OtaUpdate(
            build: build,
            downloadUrl: (a['browser_download_url'] ?? '').toString(),
            assetName: name,
            sizeBytes: (a['size'] as num?)?.toInt() ?? 0,
          );
          break;
        }
      }
    }
    return best;
  }

  static String _safeAssetName(String appName) {
    final safe = appName.replaceAll(RegExp('[^A-Za-z0-9]'), '');
    return '${safe.isEmpty ? 'app' : safe}-tv.apk';
  }
}
