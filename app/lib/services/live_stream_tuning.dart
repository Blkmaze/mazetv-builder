import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'storage.dart';

/// Settings > Player "software decoding" switch, cached so a player can pick
/// its render path the moment it's created (SharedPreferences is async).
class DecodePrefs {
  static const key = 'force_software_decode';
  static bool forceSoftware = false;
  static Future<void> load() async {
    forceSoftware = (await SharedPreferences.getInstance()).getBool(key) ?? false;
  }
}

/// How video frames reach the screen.
///
/// Default path: decode with a hardware decoder, copy each frame out, upload
/// it to the GPU, scale it with mpv's default (bilinear) filter, composite.
/// On a Fire TV Cube that's a soft picture and a busy CPU.
///
/// `mediacodec_embed`: the hardware decoder writes straight into the video
/// surface — no copy, no GPU resample. It's what the sharp-looking players
/// on the same box do. Only valid with hardware decoding, so the software
/// switch falls back to the default path.
VideoControllerConfiguration bestVideoConfig() => DecodePrefs.forceSoftware
    ? const VideoControllerConfiguration()
    : const VideoControllerConfiguration(vo: 'mediacodec_embed', hwdec: 'mediacodec');

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

  // Settings → Player → Buffer size. Small suits low-RAM sticks; large rides
  // out rough connections at the cost of a slower channel start.
  final level = await Storage.bufferLevel();
  final secs = preview ? '4' : ['6', '12', '20'][level.clamp(0, 2)];
  final fwd  = preview ? '8MiB' : ['24MiB', '48MiB', '96MiB'][level.clamp(0, 2)];
  final back = preview ? '2MiB' : ['4MiB', '8MiB', '16MiB'][level.clamp(0, 2)];

  final smooth = await Storage.smoothMotion();
  final altAudio = await Storage.altAudio();

  final props = <String, String>{
    // Judder fix for 25/50fps channels on a 60Hz TV: keep video on the
    // display clock and gently resample audio to match, instead of
    // dropping/duplicating frames. Off by default; toggle in Settings.
    if (smooth) 'video-sync': 'display-resample',
    if (smooth) 'interpolation': 'no',
    // Some boxes keep better A/V sync on the OpenSL ES path.
    if (altAudio) 'ao': 'opensles',
    // If the audio output can't be opened, keep the video going silently
    // rather than failing the whole stream.
    'audio-fallback-to-null': 'yes',
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
    'demuxer-readahead-secs': secs,
    'demuxer-max-bytes': fwd,
    'demuxer-max-back-bytes': back,
    // Match the render path: the full-screen players use the direct surface
    // output (bestVideoConfig), which needs the real mediacodec decoder.
    // Previews and multiview keep the default output, so they keep the
    // safe list — plain 'mediacodec' can't render there.
    'hwdec': DecodePrefs.forceSoftware ? 'no' : (preview ? 'auto-safe' : 'mediacodec'),
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

/// True for mpv error lines that describe a recoverable glitch (a corrupt
/// packet, a decode hiccup) rather than a dead stream. These must not be
/// surfaced as fatal errors — mpv keeps playing right through them.
bool isTransientPlayerError(String e) {
  final lower = e.toLowerCase();
  return lower.contains('decoding audio') ||
      lower.contains('decoding video') ||
      lower.contains('invalid data') ||
      lower.contains('audio device underrun') ||
      lower.contains('could not update timestamps');
}
