import 'package:flutter/material.dart';
import '../models/channel.dart';
import '../services/channel_repo.dart';
import 'live_preview.dart';
import 'player_screen.dart';
import 'tv_widgets.dart';

/// TV guide: a small live preview strip pinned at the top (same widget as
/// the Home screen's), with the full-width channel + now/next grid below —
/// matching Ghost's layout, where the preview is a shallow corner strip
/// and the guide grid gets the whole screen rather than sharing it with a
/// permanent side panel.
class GuideScreen extends StatefulWidget {
  const GuideScreen({super.key});
  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  Channel? previewChannel;

  @override
  Widget build(BuildContext context) {
    final repo = ChannelRepo.I;
    // Every channel belongs in the guide — not just ones with a matching
    // EPG id. A channel with no listings still shows up, just with a
    // "no listings" placeholder instead of a blank gap in the guide.
    final chans = repo.channels;
    previewChannel ??= chans.isEmpty ? null : chans.first;

    return Scaffold(
      appBar: AppBar(title: const Text('TV Guide')),
      body: chans.isEmpty
          ? const Center(child: Text('No channels loaded'))
          : Column(children: [
              LivePreviewStrip(key: const ValueKey('guide-preview'), channel: previewChannel),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: chans.length,
                  itemBuilder: (_, i) {
                    final c = chans[i];
                    final hasEpg = repo.epg.byChannel.containsKey(c.epgId);
                    final progs = hasEpg ? repo.epg.upcoming(c.epgId) : const [];
                    return TvTile(
                      autofocus: i == 0,
                      leading: ChannelLogo(c.logo),
                      title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onFocusChange: (has) { if (has) setState(() => previewChannel = c); },
                      subtitle: SizedBox(
                        height: 56,
                        child: !repo.epg.loaded
                            ? const Text('Loading guide…', style: TextStyle(color: Colors.white38, fontSize: 13))
                            : !hasEpg || progs.isEmpty
                                ? const Text('No listings available', style: TextStyle(color: Colors.white38, fontSize: 13))
                                : ListView(scrollDirection: Axis.horizontal, children: [
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
            ]),
    );
  }

  static String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
