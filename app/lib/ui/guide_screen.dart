import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../models/channel.dart';
import '../services/channel_repo.dart';
import 'player_screen.dart';
import 'tv_widgets.dart';

/// TV guide: a channel list on the left, with a live "now playing" preview
/// panel on the right (muted live thumbnail + full programme info) that
/// follows whichever row currently has D-pad focus.
class GuideScreen extends StatefulWidget {
  const GuideScreen({super.key});
  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  int previewIndex = 0;

  @override
  Widget build(BuildContext context) {
    final repo = ChannelRepo.I;
    final chans = repo.channels.where((c) => repo.epg.byChannel.containsKey(c.epgId)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('TV Guide')),
      body: !repo.epg.loaded
          ? const Center(child: Text('Guide still loading (or no EPG available for this playlist)'))
          : chans.isEmpty
              ? const Center(child: Text('No guide data matched your channels'))
              : Row(children: [
                  Expanded(
                    flex: 3,
                    child: ListView.builder(
                      itemCount: chans.length,
                      itemBuilder: (_, i) {
                        final c = chans[i];
                        final progs = repo.epg.upcoming(c.epgId);
                        return TvTile(
                          autofocus: i == 0,
                          selected: i == previewIndex,
                          leading: ChannelLogo(c.logo),
                          title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          onFocusChange: (has) { if (has) setState(() => previewIndex = i); },
                          subtitle: SizedBox(
                            height: 56,
                            child: ListView(scrollDirection: Axis.horizontal, children: [
                              for (final p in progs)
                                Container(
                                  width: 220, margin: const EdgeInsets.only(right: 8, top: 6),
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: p.isOnAt(DateTime.now()) ? Theme.of(context).colorScheme.primary.withOpacity(0.5) : Colors.white10,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(_hm(p.start), style: const TextStyle(fontSize: 12, color: Colors.white70)),
                                    Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
                                  ]),
                                ),
                            ]),
                          ),
                          onSelect: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => PlayerScreen(playlist: chans, index: i))),
                        );
                      },
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    flex: 2,
                    child: _NowPlayingPreview(
                      key: const ValueKey('guide-preview'),
                      channel: chans[previewIndex.clamp(0, chans.length - 1).toInt()],
                    ),
                  ),
                ]),
    );
  }

  static String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

/// The right-hand "live now" panel: a small muted live thumbnail of the
/// focused channel, what's on right now with a progress bar, and up next.
/// Reopening the stream is debounced so arrowing quickly through the list
/// doesn't spam the portal with connection attempts.
class _NowPlayingPreview extends StatefulWidget {
  final Channel channel;
  const _NowPlayingPreview({super.key, required this.channel});
  @override
  State<_NowPlayingPreview> createState() => _NowPlayingPreviewState();
}

class _NowPlayingPreviewState extends State<_NowPlayingPreview> {
  late final Player _player = Player(configuration: const PlayerConfiguration(bufferSize: 8 * 1024 * 1024));
  late final VideoController _controller = VideoController(_player);
  StreamSubscription? _errSub;
  Timer? _debounce;
  bool _previewFailed = false;

  @override
  void initState() {
    super.initState();
    _player.setVolume(0);
    _errSub = _player.stream.error.listen((_) { if (mounted) setState(() => _previewFailed = true); });
    _openPreview(widget.channel);
  }

  @override
  void didUpdateWidget(covariant _NowPlayingPreview old) {
    super.didUpdateWidget(old);
    if (old.channel.id != widget.channel.id) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 350), () => _openPreview(widget.channel));
    }
  }

  Future<void> _openPreview(Channel c) async {
    if (!mounted) return;
    setState(() => _previewFailed = false);
    try {
      await _player.open(Media(c.streamUrl));
    } catch (_) {
      if (mounted) setState(() => _previewFailed = true);
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
    final now = repo.epg.nowPlaying(channel.epgId);
    final next = repo.epg.upcoming(channel.epgId, max: 4);
    final totalSecs = now == null ? 0 : now.stop.difference(now.start).inSeconds;
    final progress = (now == null || totalSecs <= 0)
        ? 0.0
        : (DateTime.now().difference(now.start).inSeconds / totalSecs).clamp(0.0, 1.0);

    return Container(
      color: Colors.black26,
      padding: const EdgeInsets.all(24),
      child: ListView(children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: _previewFailed
                ? Container(color: Colors.black45, child: Center(child: ChannelLogo(channel.logo, size: 56)))
                : Video(controller: _controller, controls: NoVideoControls),
          ),
        ),
        const SizedBox(height: 16),
        Row(children: [
          ChannelLogo(channel.logo, size: 40),
          const SizedBox(width: 12),
          Expanded(child: Text(channel.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
        ]),
        const SizedBox(height: 8),
        if (now == null)
          const Text('No programme info right now', style: TextStyle(color: Colors.white60))
        else ...[
          Text(now.title, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 6),
          Text('${_hm(now.start)} – ${_hm(now.stop)}', style: const TextStyle(color: Colors.white60)),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: progress, minHeight: 6, backgroundColor: Colors.white12),
          ),
          if (now.description.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(now.description, style: const TextStyle(color: Colors.white70)),
          ],
        ],
        if (next.isNotEmpty) ...[
          const SizedBox(height: 24),
          const Text('UP NEXT', style: TextStyle(color: Colors.white38, fontSize: 12, letterSpacing: 1)),
          const SizedBox(height: 8),
          for (final p in next.skip(now == null ? 0 : 1))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 56, child: Text(_hm(p.start), style: const TextStyle(color: Colors.white54))),
                Expanded(child: Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis)),
              ]),
            ),
        ],
        const SizedBox(height: 24),
        TvButton(
          label: 'Watch now',
          icon: Icons.play_arrow,
          onPressed: () {
            final repoChans = repo.channels.where((c) => repo.epg.byChannel.containsKey(c.epgId)).toList();
            final idx = repoChans.indexWhere((c) => c.id == channel.id);
            Navigator.push(context, MaterialPageRoute(
                builder: (_) => PlayerScreen(playlist: repoChans, index: idx < 0 ? 0 : idx)));
          },
        ),
      ]),
    );
  }

  static String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
