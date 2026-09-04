import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../models/channel.dart';
import '../services/channel_repo.dart';
import '../services/storage.dart';
import 'tv_widgets.dart';

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
  Timer? hideTimer;
  String? error;

  Channel get ch => widget.playlist[idx];

  @override
  void initState() {
    super.initState();
    player.stream.error.listen((e) { if (mounted) setState(() => error = e); });
    _open();
  }

  Future<void> _open() async {
    setState(() { error = null; overlay = true; });
    Storage.saveLastChannel(ch.id);
    await player.open(Media(ch.streamUrl));
    _scheduleHide();
  }

  void _scheduleHide() {
    hideTimer?.cancel();
    hideTimer = Timer(const Duration(seconds: 4), () { if (mounted) setState(() => overlay = false); });
  }

  void _step(int d) {
    idx = (idx + d) % widget.playlist.length;
    if (idx < 0) idx += widget.playlist.length;
    _open();
  }

  @override
  void dispose() {
    hideTimer?.cancel();
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
          return KeyEventResult.ignored;
        },
        child: Stack(fit: StackFit.expand, children: [
          Video(controller: controller, controls: NoVideoControls),
          if (error != null)
            Center(child: Text('Stream error: $error', style: const TextStyle(color: Colors.redAccent, fontSize: 20))),
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
