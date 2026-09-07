import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'ota_service.dart';

/// Downloads an OTA update into the app's cache and hands the file to
/// Android's package installer. Handing the raw download URL to the system
/// (launchUrl) works on a phone with a browser, but a Fire Stick has nothing
/// to catch it — the button appears to do nothing and the app comes back
/// still on the old build. This is how real self-updating TV apps do it.
///
/// Requires REQUEST_INSTALL_PACKAGES in the manifest (added by brand.py).
/// On first use Android asks the user to allow this app to install unknown
/// apps — that prompt is the system's, not ours, and it's expected.
class OtaInstaller {
  /// Reports progress in 0.0–1.0 as the download streams in. Throws with a
  /// readable message on any failure. Resolves once the installer has been
  /// launched (the install itself happens in Android's own UI).
  static Future<void> downloadAndInstall(
    OtaUpdate update, {
    required void Function(double progress) onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${update.assetName}');
    if (await file.exists()) await file.delete();

    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(update.downloadUrl));
      final resp = await client.send(req).timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) {
        throw Exception('Download failed (HTTP ${resp.statusCode})');
      }
      final total = resp.contentLength ?? update.sizeBytes;
      var received = 0;
      var lastPct = -1;
      final sink = file.openWrite();
      try {
        await for (final chunk in resp.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) {
            final pct = (received * 100 ~/ total);
            if (pct != lastPct) { lastPct = pct; onProgress((received / total).clamp(0.0, 1.0)); }
          }
        }
      } finally {
        await sink.close();
      }
      if (total > 0 && received < total) {
        throw Exception('Download ended early (${_mb(received)} of ${_mb(total)}) — check your connection and try again');
      }
    } finally {
      client.close();
    }

    final result = await OpenFilex.open(file.path, type: 'application/vnd.android.package-archive');
    if (result.type != ResultType.done) {
      throw Exception(
        'Downloaded, but the installer would not open (${result.message}). '
        'Enable "Install unknown apps" for this app in your TV settings, then try again.',
      );
    }
  }

  static String _mb(int b) => '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
}
