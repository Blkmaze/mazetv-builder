import 'package:media_kit/media_kit.dart';

/// Tunes a libmpv-backed Player for live IPTV over plain HTTP.
///
/// Live TS streams from IPTV portals are a hostile environment: no
/// content-length, no range requests, servers that drop the connection
/// mid-stream, and networks that jitter. Out of the box mpv treats these
/// like local files and stutters or dies at the first hiccup. These
/// settings are the standard remedies:
///
///  * a large read-ahead buffer so a few seconds of network jitter is
///    absorbed silently instead of freezing the picture;
///  * ffmpeg-level auto-reconnect, so a dropped HTTP connection is
///    re-established *inside* the stream without restarting playback — far
///    smoother than the app-level retry, which is now just the fallback;
///  * pause-until-buffered behaviour on underrun, so a stall recovers
///    cleanly rather than stutter-stepping frame by frame.
///
/// Call once right after creating the Player and BEFORE opening media —
/// demuxer/cache options only apply to streams opened after they're set.
/// Pass [preview] for the small muted thumbnails so several of them
/// don't each grab a full-size buffer.
Future<void> tuneForLiveTs(Player player, {bool preview = false}) async {
  final platform = player.platform;
  if (platform is! NativePlayer) return;

  final props = <String, String>{
    // Non-seekable TS otherwise trips "stream error; force-seekable".
    'force-seekable': 'yes',
    // Recover a dropped HTTP connection transparently, mid-stream.
    'stream-lavf-o': 'reconnect=1,reconnect_streamed=1,reconnect_at_eof=1,reconnect_delay_max=5',
    'network-timeout': '15',
    // Buffer generously and let mpv pause-to-refill instead of stuttering.
    'cache': 'yes',
    'cache-pause-initial': 'yes',
    'cache-pause-wait': '2',
    'demuxer-readahead-secs': preview ? '5' : '20',
    'demuxer-max-bytes': preview ? '16MiB' : '150MiB',
    'demuxer-max-back-bytes': preview ? '4MiB' : '50MiB',
  };

  // Each one independently — an option missing on some libmpv build must
  // not stop the rest from applying.
  for (final e in props.entries) {
    try {
      await platform.setProperty(e.key, e.value);
    } catch (_) {
      // best-effort
    }
  }
}
