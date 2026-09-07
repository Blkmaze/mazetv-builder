import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../models/channel.dart';
import '../services/channel_repo.dart';
import '../services/live_stream_tuning.dart';
import 'tv_widgets.dart';

/// Small muted live thumbnail + now-playing line, meant to sit at the top
/// of the main channel list (the way Ghost's home screen keeps a live
/// preview visible while you browse, instead of tucking it behind a
/// separate guide page). Reopening the stream is debounced so arrowing
/// quickly through the list doesn't spam the portal with connections.
class LivePreviewStrip extends StatefulWidget {
  final Channel? channel;
  const LivePreviewStrip({super.key, required this.channel});
  @override
  State<LivePreviewStrip> createState() => _LivePreviewStripState();
}

class _LivePreviewStripState extends State<LivePreviewStrip> {
  late final Player _player = Player(configuration: const PlayerConfiguration(bufferSize: 8 * 1024 * 1024));
  late final VideoController _controller = VideoController(_player);
  StreamSubscription? _errSub;
  Timer? _debounce;
  bool _failed = false;
  int _openToken = 0;

  @override
  void initState() {
    super.initState();
    _player.setVolume(0);
    tuneForLiveTs(_player, preview: true);
    _errSub = _player.stream.error.listen((e) {
      if (mounted && !isTransientPlayerError(e)) setState(() => _failed = true);
    });
    if (widget.channel != null) _open(widget.channel!);
  }

  @override
  void didUpdateWidget(covariant LivePreviewStrip old) {
    super.didUpdateWidget(old);
    if (old.channel?.id != widget.channel?.id && widget.channel != null) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 350), () => _open(widget.channel!));
    }
  }

  Future<void> _open(Channel c) async {
    if (!mounted) return;
    final token = ++_openToken;
    setState(() => _failed = false);
    try {
      await _player.open(Media(c.streamUrl));
    } catch (_) {
      if (mounted && token == _openToken) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _errSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final channel = widget.channel;
    final repo = ChannelRepo.I;
    final now = channel == null ? null : repo.epg.nowPlaying(channel.epgId);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 240, height: 135,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: channel == null
                ? Container(color: Colors.black26)
                : _failed
                    ? Container(color: Colors.black45, child: Center(child: ChannelLogo(channel.logo, size: 44)))
                    : Video(controller: _controller, controls: NoVideoControls),
          ),
        ),
        const SizedBox(width: 18),
        if (channel != null)
          Expanded(
            child: Builder(builder: (context) {
              final accent = Theme.of(context).colorScheme.primary;
              Programme? next;
              for (final p in repo.epg.upcoming(channel.epgId, max: 4)) {
                if (now == null || !p.start.isBefore(now.stop)) { next = p; break; }
              }
              final total = now == null ? 0 : now.stop.difference(now.start).inMinutes;
              final elapsed = now == null ? 0 : DateTime.now().difference(now.start).inMinutes;
              final left = now == null ? 0 : now.stop.difference(DateTime.now()).inMinutes;
              final progress = total <= 0 ? 0.0 : (elapsed / total).clamp(0.0, 1.0);

              return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  ChannelLogo(channel.logo, size: 26),
                  const SizedBox(width: 8),
                  Expanded(child: Text(channel.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                  if (now != null)
                    Text('${fmt12(now.start)} – ${fmt12(now.stop)}',
                        style: const TextStyle(color: Colors.white54, fontSize: 13)),
                ]),
                const SizedBox(height: 6),
                if (now == null)
                  const Text('No programme info', style: TextStyle(color: Colors.white38, fontSize: 14))
                else ...[
                  Text(now.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  if (now.description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(now.description, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.3)),
                  ],
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(value: progress, minHeight: 4, backgroundColor: Colors.white12, color: accent),
                  ),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(
                      child: Text(next == null ? '' : 'Next: ${next.title}', maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    ),
                    if (left > 0) Text('$left min left', style: TextStyle(color: accent, fontSize: 13, fontWeight: FontWeight.w600)),
                  ]),
                ],
              ]);
            }),
          ),
      ]),
    );
  }
}

/// 12-hour clock ("9:30 PM").
String fmt12(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
}
