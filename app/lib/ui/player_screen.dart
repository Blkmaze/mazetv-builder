import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/channel.dart';
import '../services/channel_repo.dart';
import '../services/live_stream_tuning.dart';
import '../services/storage.dart';
import 'tv_widgets.dart';

/// Settings > Player toggle — some Android TV boxes hang with a black
/// picture (audio may or may not play) on certain hardware-decoded streams;
/// forcing software decode is a low-risk workaround to try when that
/// happens. Best-effort: if the installed media_kit version doesn't expose
/// this mpv property the same way, it's silently ignored rather than
/// crashing playback.
const kForceSoftwareDecodeKey = 'force_software_decode';

/// Full-screen live player. Remote: Up/Down = channel +/-, OK = info overlay, Back = exit.
class PlayerScreen extends StatefulWidget {
  final List<Channel> playlist;
  final int index;
  const PlayerScreen({super.key, required this.playlist, required this.index});
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player player = Player(configuration: const PlayerConfiguration(bufferSize: 32 * 1024 * 1024));
  late final VideoController controller = VideoController(player);
  late int idx = widget.index;
  bool overlay = true;
  bool buffering = true;
  Timer? hideTimer;
  Timer? _stallTimer;
  String? error;
  final _digits = Queue<String>();
  Timer? _digitTimer;
  String _digitPreview = '';

  Channel get ch => widget.playlist[idx];

  @override
  void initState() {
    super.initState();
    tuneForLiveTs(player);
    player.stream.error.listen((e) { if (mounted) setState(() => error = e); });
    player.stream.buffering.listen((b) {
      if (!b) _stallTimer?.cancel();
      if (mounted) setState(() => buffering = b);
    });
    _applyDecodePreference();
    _open();
  }

  /// Best-effort: ask libmpv to use software decoding if the user flipped
  /// that switch in Settings > Player. Silently does nothing if this
  /// media_kit version doesn't support direct property access.
  Future<void> _applyDecodePreference() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (p.getBool(kForceSoftwareDecodeKey) != true) return;
      // Reached dynamically (not via a static NativePlayer type) so this
      // still compiles cleanly across media_kit versions that shape the
      // native platform API slightly differently.
      final dynamic platform = player.platform;
      await platform?.setProperty('hwdec', 'no');
    } catch (_) {
      // Best-effort only — never let this block playback.
    }
  }

  Future<void> _open() async {
    setState(() { error = null; overlay = true; buffering = true; });
    Storage.saveLastChannel(ch.id);
    Storage.recordWatch(ch.id);
    _stallTimer?.cancel();
    _stallTimer = Timer(const Duration(seconds: 15), () {
      if (mounted && buffering && error == null) {
        setState(() => error = 'Still loading after 15s — the stream may be down, or try '
            'Settings > Player > Software decoding if the picture is black.');
      }
    });
    await player.open(Media(ch.streamUrl));
    _scheduleHide();
  }

  void _scheduleHide() {
    hideTimer?.cancel();
    hideTimer = Timer(const Duration(seconds: 4), () { if (mounted) setState(() => overlay = false); });
  }

  void _onDigit(String d) {
    _digits.add(d);
    if (_digits.length > 4) _digits.removeFirst();
    _digitTimer?.cancel();
    setState(() => _digitPreview = _digits.join());
    _digitTimer = Timer(const Duration(milliseconds: 1200), _jumpToTyped);
  }

  void _jumpToTyped() {
    final n = int.tryParse(_digits.join());
    _digits.clear();
    setState(() => _digitPreview = '');
    if (n == null) return;
    final target = n - 1;
    if (target >= 0 && target < widget.playlist.length && target != idx) {
      idx = target;
      _open();
    }
  }

  void _step(int d) {
    idx = (idx + d) % widget.playlist.length;
    if (idx < 0) idx += widget.playlist.length;
    _open();
  }

  @override
  void dispose() {
    hideTimer?.cancel();
    _digitTimer?.cancel();
    _stallTimer?.cancel();
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = ChannelRepo.I.epg.nowPlaying(ch.epgId);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: (_, e) {
          if (e is! KeyDownEvent) return KeyEventResult.ignored;
          final k = e.logicalKey;
          if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.channelUp) { _step(-1); return KeyEventResult.handled; }
          if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.channelDown) { _step(1); return KeyEventResult.handled; }
          if (k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.gameButtonA) {
            setState(() => overlay = !overlay); if (overlay) _scheduleHide(); return KeyEventResult.handled;
          }
          final label = e.character;
          if (label != null && RegExp(r'^[0-9]$').hasMatch(label)) { _onDigit(label); return KeyEventResult.handled; }
          return KeyEventResult.ignored;
        },
        child: Stack(fit: StackFit.expand, children: [
          Video(controller: controller, controls: NoVideoControls),
          if (error == null && buffering)
            const Center(child: CircularProgressIndicator()),
          if (error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text('Stream error: $error',
                    textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent, fontSize: 20)),
              ),
            ),
          if (_digitPreview.isNotEmpty)
            Positioned(
              top: 32, right: 32,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
                child: Text(_digitPreview, style: const TextStyle(fontSize: 32, color: Colors.white)),
              ),
            ),
          if (overlay)
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(32, 40, 32, 28),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black87]),
                ),
                child: Row(children: [
                  ChannelLogo(ch.logo, size: 64),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(ch.name, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                      if (now != null)
                        Text('${_hm(now.start)}–${_hm(now.stop)}  ${now.title}',
                            style: const TextStyle(fontSize: 18, color: Colors.white70)),
                    ]),
                  ),
                  Text('${idx + 1} / ${widget.playlist.length}', style: const TextStyle(color: Colors.white54)),
                ]),
              ),
            ),
        ]),
      ),
    );
  }

  static String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
