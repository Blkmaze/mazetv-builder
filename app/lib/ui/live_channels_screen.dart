import 'package:flutter/material.dart';
import '../models/channel.dart';
import '../services/channel_repo.dart';
import '../services/storage.dart';
import 'guide_screen.dart';
import 'live_preview.dart';
import 'player_screen.dart';
import 'tv_widgets.dart';

const String kFavoritesGroup = '★ Favorites';

/// Category + channel-list browsing, with a live preview strip pinned above
/// the list — this is what "Home" used to be, before Home became the
/// Movies/Series discovery page. The full timeline TV Guide is one tap away
/// via the app bar action, so nothing that was here before is lost.
class LiveChannelsScreen extends StatefulWidget {
  final String? initialSearch;
  const LiveChannelsScreen({super.key, this.initialSearch});
  @override
  State<LiveChannelsScreen> createState() => _LiveChannelsScreenState();
}

class _LiveChannelsScreenState extends State<LiveChannelsScreen> {
  final repo = ChannelRepo.I;
  String? group;
  String search = '';
  String? activeProfileId;
  Set<String> favorites = {};
  Channel? previewChannel;

  @override
  void initState() {
    super.initState();
    search = widget.initialSearch ?? '';
    _boot();
  }

  Future<void> _boot() async {
    activeProfileId = await Storage.activeProfileId();
    favorites = await Storage.favorites(activeProfileId);
    group = repo.groups.isEmpty ? null : repo.groups.first;
    if (!mounted) return;
    setState(() {
      final inGroup = repo.inGroup(group ?? '');
      previewChannel = inGroup.isNotEmpty ? inGroup.first : (repo.channels.isEmpty ? null : repo.channels.first);
    });
  }

  Future<void> _toggleFavorite(Channel c) async {
    setState(() {
      if (!favorites.remove(c.id)) favorites.add(c.id);
    });
    await Storage.setFavorites(activeProfileId, favorites);
  }

  void _play(List<Channel> list, int index) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(playlist: list, index: index)));
  }

  void _openSearch() async {
    final c = TextEditingController(text: search);
    final r = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Search channels'),
        content: TextField(controller: c, autofocus: true, onSubmitted: (v) => Navigator.pop(context, v)),
        actions: [TextButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Search'))],
      ),
    );
    if (r != null) setState(() => search = r.trim());
  }

  @override
  Widget build(BuildContext context) {
    final groups = [kFavoritesGroup, ...repo.groups];
    List<Channel> channels;
    if (search.isNotEmpty) {
      channels = repo.channels.where((c) => c.name.toLowerCase().contains(search.toLowerCase())).toList();
    } else if (group == kFavoritesGroup || group == null) {
      channels = repo.channels.where((c) => favorites.contains(c.id)).toList();
    } else {
      channels = repo.inGroup(group!);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live'),
        actions: [
          IconButton(
            icon: const Icon(Icons.grid_view),
            tooltip: 'Full TV Guide',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GuideScreen())),
          ),
          IconButton(icon: const Icon(Icons.search), tooltip: 'Search', onPressed: _openSearch),
        ],
      ),
      body: Row(children: [
        // ---- categories
        SizedBox(
          width: 260,
          child: ListView.builder(
            itemCount: groups.length,
            itemBuilder: (_, i) {
              final isFav = groups[i] == kFavoritesGroup;
              final count = isFav ? favorites.length : repo.inGroup(groups[i]).length;
              return TvTile(
                autofocus: i == 0,
                selected: groups[i] == group && search.isEmpty,
                leading: isFav ? const Icon(Icons.star, color: Colors.amber, size: 18) : null,
                title: Text(groups[i], maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Text('$count', style: const TextStyle(color: Colors.white38)),
                onSelect: () => setState(() { group = groups[i]; search = ''; }),
              );
            },
          ),
        ),
        const VerticalDivider(width: 1),
        // ---- channel list, with a live preview strip pinned above it
        Expanded(
          child: Column(children: [
            LivePreviewStrip(key: const ValueKey('live-preview'), channel: previewChannel),
            const Divider(height: 1),
            Expanded(
              child: channels.isEmpty
                  ? Center(child: Text(group == kFavoritesGroup ? 'No favorites yet — hold OK on a channel to add one' : 'No channels'))
                  : ListView.builder(
                      itemCount: channels.length,
                      itemBuilder: (_, i) {
                        final c = channels[i];
                        final now = repo.epg.nowPlaying(c.epgId);
                        final isFav = favorites.contains(c.id);
                        return TvTile(
                          onFocusChange: (has) { if (has) setState(() => previewChannel = c); },
                          leading: SizedBox(
                            width: 74,
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              SizedBox(width: 28, child: Text('${i + 1}', textAlign: TextAlign.right,
                                  style: const TextStyle(color: Colors.white38, fontSize: 15))),
                              const SizedBox(width: 8),
                              ChannelLogo(c.logo),
                            ]),
                          ),
                          title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: now == null ? null
                              : Text('${_hm(now.start)}–${_hm(now.stop)}  ${now.title}',
                                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60)),
                          trailing: isFav ? const Icon(Icons.star, color: Colors.amber) : null,
                          onSelect: () => _play(channels, i),
                          onLongSelect: () => _toggleFavorite(c),
                        );
                      },
                    ),
            ),
          ]),
        ),
      ]),
    );
  }

  static String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
