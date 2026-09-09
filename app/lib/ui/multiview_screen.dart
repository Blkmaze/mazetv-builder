import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../models/channel.dart';
import '../services/channel_repo.dart';
import '../services/storage.dart';
import '../services/live_stream_tuning.dart';
import 'tv_widgets.dart';

/// Pick up to 4 live channels to watch at once.
///
/// Remote:
///   grid      — D-pad moves the highlight; OK expands that cell to full
///               screen and gives it the audio.
///   fullscreen — ◀ ▶ switch to the previous/next channel; OK or Back
///               returns to the grid.
///
/// All streams keep playing while one is expanded (the others are kept
/// alive off-screen), so switching back and forth is instant. Four streams
/// at once is heavy on a small box — if it stutters, try 2.
class MultiviewScreen extends StatefulWidget {
  const MultiviewScreen({super.key});
  @override
  State<MultiviewScreen> createState() => _MultiviewScreenState();
}

class _MultiviewScreenState extends State<MultiviewScreen> {
  final List<Channel> picked = [];
  final List<GlobalKey<_MultiCellState>> keys = [];
  int liveIndex = 0;   // which cell has audio
  int? expanded;       // which cell is full screen, if any

  static final _activate = {
    LogicalKeyboardKey.select, LogicalKeyboardKey.enter, LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.gameButtonA, LogicalKeyboardKey.space,
  };

  @override
  void initState() {
    super.initState();
    _restore();
  }

  /// Picks survive leaving the screen — and "Add to Multiview" from the
  /// channel menu lands here too.
  Future<void> _restore() async {
    final ids = await Storage.multiviewIds();
    final byId = {for (final c in ChannelRepo.I.channels) c.id: c};
    final list = [for (final id in ids) if (byId[id] != null) byId[id]!];
    if (!mounted || list.isEmpty) return;
    _apply(list);
  }

  void _apply(List<Channel> list) {
    setState(() {
      picked..clear()..addAll(list.take(4));
      keys..clear()..addAll(List.generate(picked.length, (_) => GlobalKey<_MultiCellState>()));
      liveIndex = 0;
      expanded = null;
    });
  }

  void _pickChannels() async {
    final repo = ChannelRepo.I;
    final result = await Navigator.push<List<Channel>>(
      context,
      MaterialPageRoute(builder: (_) => _ChannelPickerScreen(initiallyPicked: picked, allChannels: repo.channels)),
    );
    if (result == null) return;
    await Storage.setMultiviewIds([for (final c in result) c.id]);
    _apply(result);
  }

  void _expand(int i) => setState(() { liveIndex = i; expanded = i; });
  void _collapse() => setState(() => expanded = null);
  void _step(int d) {
    if (picked.isEmpty) return;
    setState(() {
      liveIndex = (liveIndex + d) % picked.length;
      if (liveIndex < 0) liveIndex += picked.length;
      expanded = liveIndex;
    });
  }

  KeyEventResult _fullscreenKeys(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.channelDown) { _step(-1); return KeyEventResult.handled; }
    if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.channelUp) { _step(1); return KeyEventResult.handled; }
    if (_activate.contains(k)) { _collapse(); return KeyEventResult.handled; }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    // Same cell widgets whether in the grid or expanded — the GlobalKeys let
    // Flutter move them between layouts without restarting the streams.
    final cells = [
      for (var i = 0; i < picked.length; i++)
        _MultiCell(key: keys[i], channel: picked[i], live: liveIndex == i, expanded: expanded == i,
            onSelect: () => _expand(i)),
    ];

    return PopScope(
      canPop: expanded == null,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) _collapse(); },
      child: Scaffold(
        appBar: expanded != null ? null : AppBar(
          title: const Text('Multiview'),
          actions: [IconButton(icon: const Icon(Icons.add), tooltip: 'Pick channels', onPressed: _pickChannels)],
        ),
        body: picked.isEmpty
            ? Center(child: TvButton(label: 'Pick up to 4 channels', icon: Icons.add, autofocus: true, onPressed: _pickChannels))
            : expanded == null
                ? GridView.count(
                    crossAxisCount: picked.length <= 1 ? 1 : 2,
                    padding: const EdgeInsets.all(8),
                    mainAxisSpacing: 8, crossAxisSpacing: 8,
                    childAspectRatio: 16 / 9,
                    children: cells,
                  )
                : Focus(
                    autofocus: true,
                    onKeyEvent: _fullscreenKeys,
                    child: Stack(fit: StackFit.expand, children: [
                      cells[expanded!],
                      // keep the others alive, just off-screen
                      Offstage(offstage: true, child: Row(children: [
                        for (var i = 0; i < cells.length; i++) if (i != expanded) SizedBox(width: 1, height: 1, child: cells[i]),
                      ])),
                      Positioned(
                        right: 16, bottom: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                          child: Text('${expanded! + 1}/${picked.length}   ◀ ▶ switch   OK / Back: grid',
                              style: const TextStyle(fontSize: 12, color: Colors.white70)),
                        ),
                      ),
                    ]),
                  ),
      ),
    );
  }
}

class _MultiCell extends StatefulWidget {
  final Channel channel;
  final bool live;      // has the audio
  final bool expanded;  // shown full screen
  final VoidCallback onSelect;
  const _MultiCell({super.key, required this.channel, required this.live, required this.expanded, required this.onSelect});
  @override
  State<_MultiCell> createState() => _MultiCellState();
}

class _MultiCellState extends State<_MultiCell> {
  late final Player player = Player(configuration: const PlayerConfiguration(bufferSize: 16 * 1024 * 1024));
  late final VideoController controller = VideoController(player);

  @override
  void initState() {
    super.initState();
    tuneForLiveTs(player, preview: true);
    player.open(Media(widget.channel.streamUrl));
    player.setVolume(widget.live ? 100 : 0);
  }

  @override
  void didUpdateWidget(covariant _MultiCell old) {
    super.didUpdateWidget(old);
    if (old.live != widget.live) player.setVolume(widget.live ? 100 : 0);
    if (old.channel.id != widget.channel.id) player.open(Media(widget.channel.streamUrl));
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    if (widget.expanded) {
      return Stack(fit: StackFit.expand, children: [
        Video(controller: controller, controls: NoVideoControls),
        Positioned(
          left: 16, bottom: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            color: Colors.black54,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.volume_up, size: 14, color: primary), const SizedBox(width: 6),
              Text(widget.channel.name, style: const TextStyle(fontSize: 14, color: Colors.white)),
            ]),
          ),
        ),
      ]);
    }
    return Focus(
      canRequestFocus: false, skipTraversal: true,
      child: Builder(builder: (ctx) {
        final focused = Focus.of(ctx).hasFocus;
        return InkWell(
          onTap: widget.onSelect,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: focused ? Colors.white : (widget.live ? primary : Colors.white24),
                width: focused ? 4 : (widget.live ? 3 : 1),
              ),
            ),
            child: Stack(fit: StackFit.expand, children: [
              Video(controller: controller, controls: NoVideoControls),
              Positioned(
                left: 6, bottom: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  color: Colors.black54,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (widget.live) Icon(Icons.volume_up, size: 12, color: primary),
                    if (widget.live) const SizedBox(width: 4),
                    Text(widget.channel.name, style: const TextStyle(fontSize: 11, color: Colors.white70)),
                  ]),
                ),
              ),
              if (focused)
                const Positioned(
                  right: 6, bottom: 6,
                  child: Text('OK: full screen', style: TextStyle(fontSize: 10, color: Colors.white70)),
                ),
            ]),
          ),
        );
      }),
    );
  }
}

class _ChannelPickerScreen extends StatefulWidget {
  final List<Channel> initiallyPicked;
  final List<Channel> allChannels;
  const _ChannelPickerScreen({required this.initiallyPicked, required this.allChannels});
  @override
  State<_ChannelPickerScreen> createState() => _ChannelPickerScreenState();
}

class _ChannelPickerScreenState extends State<_ChannelPickerScreen> {
  late final List<Channel> picked = [...widget.initiallyPicked];

  void _toggle(Channel c) {
    setState(() {
      final has = picked.any((p) => p.id == c.id);
      if (has) {
        picked.removeWhere((p) => p.id == c.id);
      } else if (picked.length < 4) {
        picked.add(c);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Pick channels (${picked.length}/4)'),
        actions: [TextButton(onPressed: () => Navigator.pop(context, picked), child: const Text('Done'))],
      ),
      body: ListView.builder(
        itemCount: widget.allChannels.length,
        itemBuilder: (_, i) {
          final c = widget.allChannels[i];
          final isPicked = picked.any((p) => p.id == c.id);
          return TvTile(
            autofocus: i == 0,
            leading: ChannelLogo(c.logo),
            title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: isPicked ? const Icon(Icons.check_circle) : null,
            selected: isPicked,
            onSelect: () => _toggle(c),
          );
        },
      ),
    );
  }
}
