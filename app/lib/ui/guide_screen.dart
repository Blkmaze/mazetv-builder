import 'package:flutter/material.dart';
import '../services/channel_repo.dart';
import 'player_screen.dart';
import 'tv_widgets.dart';

/// Simple "now / next" guide: one row per channel, upcoming programmes across.
class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

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
              : ListView.builder(
                  itemCount: chans.length,
                  itemBuilder: (_, i) {
                    final c = chans[i];
                    final progs = repo.epg.upcoming(c.epgId);
                    return TvTile(
                      autofocus: i == 0,
                      leading: ChannelLogo(c.logo),
                      title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
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
    );
  }

  static String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
