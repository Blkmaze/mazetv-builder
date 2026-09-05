import 'package:media_kit/media_kit.dart';

/// Some IPTV portals serve raw MPEG-TS over plain HTTP with no
/// content-length / range support, which libmpv reports as "not
/// seekable" — and certain demuxer paths then fail outright with
/// "stream error; you can force it with --force-seekable=yes" instead
/// of just warning. Telling mpv up front to treat these as seekable
/// avoids that failure. Call this once, right after creating a Player
/// and before opening any media on it.
Future<void> tuneForLiveTs(Player player) async {
  final platform = player.platform;
  if (platform is NativePlayer) {
    try {
      await platform.setProperty('force-seekable', 'yes');
    } catch (_) {
      // Best-effort tuning; never block playback if the property isn't
      // available on this build of libmpv.
    }
  }
}
