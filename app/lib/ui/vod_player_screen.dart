import 'dart:async';
import 'package:flutter/material.dart';
import '../services/live_stream_tuning.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../models/vod.dart';
import '../services/storage.dart';
import 'tv_widgets.dart';

/// Full-screen movie player with remote-friendly controls.
///   OK / Enter      play ⇄ pause (and shows the overlay)
///   ◀ ▶             skip 10 s back / forward   (hold-repeat works)
///   ▲ ▼             skip 60 s back / forward
///   ⏪ ⏩ ⏯          same, if the remote has them
///   Back            leave (position is remembered for Resume)
/// The overlay (title, progress bar, time) shows on any key and hides after
/// a few seconds. Position is saved every few seconds and on exit; finishing
/// the movie clears it so it won't offer to resume from the credits.
class VodPlayerScreen extends StatefulWidget {
  final VodItem item;
  final int startAtSeconds;
  const VodPlayerScreen({super.key, required this.item, this.startAtSeconds = 0});
  @override
  State<VodPlayerScreen> createState() => _VodPlayerScreenState();
}

class _VodPlayerScreenState extends State<VodPlayerScreen> {
  late final Player player = Player(configuration: const PlayerConfiguration(bufferSize: 48 * 1024 * 1024));
  late final VideoController controller = VideoController(player);
  final _subs = <StreamSubscription>[];
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  bool playing = true;
  bool buffering = true;
  bool overlay = true;
  bool _seekedToStart = false;
  String? error;
  Timer? _hide;
  Timer? _saveTimer;

  static final _activate = {
    LogicalKeyboardKey.select, LogicalKeyboardKey.enter, LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.gameButtonA, LogicalKeyboardKey.space, LogicalKeyboardKey.mediaPlayPause,
  };

  @override
  void initState() {
    super.initState();
    _subs.add(player.stream.error.listen((e) {
      if (mounted && !isTransientPlayerError(e)) setState(() => error = e);
    }));
    _subs.add(player.stream.position.listen((p) { if (mounted) setState(() => position = p); }));
    _subs.add(player.stream.duration.listen((d) {
      if (!mounted) return;
      setState(() => duration = d);
      // Resume once we know the media is loaded (duration known).
      if (!_seekedToStart && d > Duration.zero) {
        _seekedToStart = true;
        if (widget.startAtSeconds > 0) player.seek(Duration(seconds: widget.startAtSeconds));
      }
    }));
    _subs.add(player.stream.playing.listen((p) { if (mounted) setState(() => playing = p); }));
    _subs.add(player.stream.buffering.listen((b) { if (mounted) setState(() => buffering = b); }));
    _subs.add(player.stream.completed.listen((done) {
      if (done) Storage.clearResumePosition(widget.item.id);
    }));
    player.open(Media(widget.item.streamUrl));
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) => _savePosition());
    _scheduleHide();
  }

  void _savePosition() {
    if (duration == Duration.zero) return;
    final secs = position.inSeconds;
    // Don't remember the first minute (nothing to resume) or the last two
    // (effectively finished).
    if (secs < 60 || secs > duration.inSeconds - 120) {
      Storage.clearResumePosition(widget.item.id);
    } else {
      Storage.setResumePosition(widget.item.id, secs);
    }
  }

  void _scheduleHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 4), () { if (mounted && playing) setState(() => overlay = false); });
  }

  void _showOverlay() {
    if (!overlay) setState(() => overlay = true);
    _scheduleHide();
  }

  void _seekBy(int seconds) {
    var target = position + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;
    player.seek(target);
    _showOverlay();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (_activate.contains(k)) { player.playOrPause(); _showOverlay(); return KeyEventResult.handled; }
    if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.mediaRewind) { _seekBy(-10); return KeyEventResult.handled; }
    if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.mediaFastForward) { _seekBy(10); return KeyEventResult.handled; }
    if (k == LogicalKeyboardKey.arrowUp) { _seekBy(60); return KeyEventResult.handled; }
    if (k == LogicalKeyboardKey.arrowDown) { _seekBy(-60); return KeyEventResult.handled; }
    if (k == LogicalKeyboardKey.mediaPlay) { player.play(); _showOverlay(); return KeyEventResult.handled; }
    if (k == LogicalKeyboardKey.mediaPause) { player.pause(); _showOverlay(); return KeyEventResult.handled; }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _savePosition();
    _hide?.cancel();
    _saveTimer?.cancel();
    for (final s in _subs) { s.cancel(); }
    // Native crash guard: on Fire OS the app segfaults (SIGSEGV on the
    // main thread, inside libmpv) if the player is freed while the hardware
    // decoder is still tearing down. Stop first, free after it settles.
    final p = player;
    p.stop().then((_) => p.dispose(), onError: (_) => p.dispose());
    super.dispose();
  }

  static String _t(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    final ms = '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return h > 0 ? '$h:$ms' : ms;
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final progress = duration.inMilliseconds == 0 ? 0.0 : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Stack(fit: StackFit.expand, children: [
          Video(controller: controller, controls: NoVideoControls),
          if (buffering && error == null)
            const Center(child: CircularProgressIndicator()),
          if (error != null)
            Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Playback error: ${scrubSecrets(error!)}', textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 18)),
            )),
          if (!playing && !buffering && error == null)
            Center(child: Icon(Icons.pause_circle_filled, size: 96, color: Colors.white.withOpacity(0.85))),
          if (overlay)
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(32, 48, 32, 24),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black87]),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(widget.item.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: progress, minHeight: 6, backgroundColor: Colors.white24, color: accent),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Icon(playing ? Icons.pause : Icons.play_arrow, size: 20, color: Colors.white),
                    const SizedBox(width: 8),
                    Text('${_t(position)} / ${_t(duration)}', style: const TextStyle(fontSize: 14, color: Colors.white)),
                    const Spacer(),
                    const Text('OK play/pause   ◀ ▶ 10s   ▲ ▼ 1 min', style: TextStyle(fontSize: 12, color: Colors.white54)),
                  ]),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}
