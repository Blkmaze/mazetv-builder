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
    tuneForLiveTs(_player);
    _errSub = _player.stream.error.listen((_) { if (mounted) setState(() => _failed = true); });
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
          width: 220, height: 124,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: channel == null
                ? Container(color: Colors.black26)
                : _failed
                    ? Container(color: Colors.black45, child: Center(child: ChannelLogo(channel.logo, size: 44)))
                    : Video(controller: _controller, controls: NoVideoControls),
          ),
        ),
        const SizedBox(width: 16),
        if (channel != null)
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(channel.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              if (now != null)
                Text(now.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 15))
              else
                const Text('No programme info right now', style: TextStyle(color: Colors.white38, fontSize: 14)),
            ]),
          ),
      ]),
    );
  }
}
