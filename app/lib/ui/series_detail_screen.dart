import 'package:flutter/material.dart';
import '../models/channel.dart';
import '../models/vod.dart';
import '../services/channel_repo.dart';
import 'player_screen.dart';
import 'tv_widgets.dart';

/// Episode list for one series. Episodes are handed to [PlayerScreen] as a
/// single flat playlist (sorted by season/episode) so the remote's
/// channel-up/down keys naturally step to the next/previous episode.
class SeriesDetailScreen extends StatefulWidget {
  final SeriesItem series;
  const SeriesDetailScreen({super.key, required this.series});
  @override
  State<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends State<SeriesDetailScreen> {
  final repo = ChannelRepo.I;
  bool loading = true;
  String? error;
  List<SeriesEpisode> episodes = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final x = repo.xtream;
      episodes = x == null ? [] : await x.seriesEpisodes(widget.series.id);
      if (episodes.isEmpty) error = 'No episodes returned for this series.';
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _play(int index) {
    final playlist = episodes
        .map((e) => Channel(
              id: 'ep_${e.id}',
              name: 'S${e.season}E${e.episode} · ${e.title}',
              group: widget.series.name,
              logo: widget.series.cover,
              streamUrl: e.streamUrl,
              epgId: '',
            ))
        .toList();
    Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(playlist: playlist, index: index)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.series.name)),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(error!, textAlign: TextAlign.center)))
              : ListView.builder(
                  itemCount: episodes.length,
                  itemBuilder: (_, i) {
                    final e = episodes[i];
                    return TvTile(
                      autofocus: i == 0,
                      leading: SizedBox(
                        width: 56,
                        child: Text('S${e.season}E${e.episode}', style: const TextStyle(color: Colors.white54, fontSize: 13)),
                      ),
                      title: Text(e.title.isEmpty ? 'Episode ${e.episode}' : e.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onSelect: () => _play(i),
                    );
                  },
                ),
    );
  }
}
