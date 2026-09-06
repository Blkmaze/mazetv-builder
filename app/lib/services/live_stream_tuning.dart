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
    // Buffer ahead and let mpv pause-to-refill instead of stuttering. Sizes
    // are deliberately modest: TV boxes have little RAM, and a 150MiB+ cache
    // gets the whole app killed by the low-memory killer mid-playback —
    // which looks exactly like a random crash.
    'cache': 'yes',
    'cache-pause-initial': 'yes',
    'cache-pause-wait': '2',
    'demuxer-readahead-secs': preview ? '4' : '12',
    'demuxer-max-bytes': preview ? '8MiB' : '48MiB',
    'demuxer-max-back-bytes': preview ? '2MiB' : '8MiB',
    // Only use hardware decoders known to be safe; "auto" will happily pick
    // a broken vendor decoder and take the app down with it.
    'hwdec': 'auto-safe',
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
