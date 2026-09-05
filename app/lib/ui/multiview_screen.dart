import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../models/channel.dart';
import '../services/channel_repo.dart';
import 'tv_widgets.dart';

/// Pick up to 4 live channels to watch at once. Only the tapped cell has
/// audio; the rest are muted. Playing several streams at once is heavier on
/// the device than a single full-screen channel — if it stutters, try 2
/// channels instead of 4.
class MultiviewScreen extends StatefulWidget {
  const MultiviewScreen({super.key});
  @override
  State<MultiviewScreen> createState() => _MultiviewScreenState();
}

class _MultiviewScreenState extends State<MultiviewScreen> {
  final List<Channel> picked = [];

  void _pickChannels() async {
    final repo = ChannelRepo.I;
    final result = await Navigator.push<List<Channel>>(
      context,
      MaterialPageRoute(builder: (_) => _ChannelPickerScreen(initiallyPicked: picked, allChannels: repo.channels)),
    );
    if (result != null) setState(() => picked
      ..clear()
      ..addAll(result));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Multiview'),
        actions: [IconButton(icon: const Icon(Icons.add), tooltip: 'Pick channels', onPressed: _pickChannels)],
      ),
      body: picked.isEmpty
          ? Center(
              child: TvButton(label: 'Pick up to 4 channels', icon: Icons.add, autofocus: true, onPressed: _pickChannels),
            )
          : GridView.count(
              crossAxisCount: picked.length <= 1 ? 1 : 2,
              padding: const EdgeInsets.all(8),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 16 / 9,
              children: [for (var i = 0; i < picked.length; i++) _MultiCell(channel: picked[i], initiallyLive: i == 0)],
            ),
    );
  }
}

class _MultiCell extends StatefulWidget {
  final Channel channel;
  final bool initiallyLive;
  const _MultiCell({required this.channel, required this.initiallyLive});
  @override
  State<_MultiCell> createState() => _MultiCellState();
}

class _MultiCellState extends State<_MultiCell> {
  late final Player player = Player(configuration: const PlayerConfiguration(bufferSize: 16 * 1024 * 1024));
  late final VideoController controller = VideoController(player);
  bool live = false;

  @override
  void initState() {
    super.initState();
    live = widget.initiallyLive;
    player.open(Media(widget.channel.streamUrl));
    player.setVolume(live ? 100 : 0);
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  void _makeLive() {
    setState(() => live = true);
    player.setVolume(100);
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: _makeLive,
      child: Container(
        decoration: BoxDecoration(border: Border.all(color: live ? primary : Colors.white24, width: live ? 3 : 1)),
        child: Stack(fit: StackFit.expand, children: [
          Video(controller: controller, controls: NoVideoControls),
          Positioned(
            left: 6, bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              color: Colors.black54,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (live) Icon(Icons.volume_up, size: 12, color: primary),
                if (live) const SizedBox(width: 4),
                Text(widget.channel.name, style: const TextStyle(fontSize: 11, color: Colors.white70)),
              ]),
            ),
          ),
        ]),
      ),
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
