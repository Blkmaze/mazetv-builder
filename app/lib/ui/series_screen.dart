import 'package:flutter/material.dart';
import '../models/vod.dart';
import '../services/channel_repo.dart';
import 'series_detail_screen.dart';
import 'tv_widgets.dart';

class SeriesScreen extends StatefulWidget {
  const SeriesScreen({super.key});
  @override
  State<SeriesScreen> createState() => _SeriesScreenState();
}

class _SeriesScreenState extends State<SeriesScreen> {
  final repo = ChannelRepo.I;
  bool loading = true;
  String? error;
  String? group;

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
      if (!repo.supportsVod) {
        error = 'Series need an Xtream login — not available for an M3U playlist source.';
      } else {
        if (repo.seriesItems.isEmpty) await repo.loadSeries();
        group = repo.seriesGroups.isEmpty ? null : repo.seriesGroups.first;
      }
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _open(SeriesItem s) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => SeriesDetailScreen(series: s)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Series')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
                  ),
                )
              : repo.seriesItems.isEmpty
                  ? const Center(child: Text('No series found on this portal'))
                  : Row(children: [
                      SizedBox(
                        width: 260,
                        child: ListView.builder(
                          itemCount: repo.seriesGroups.length,
                          itemBuilder: (_, i) {
                            final g = repo.seriesGroups[i];
                            return TvTile(
                              autofocus: i == 0,
                              selected: g == group,
                              title: Text(g, maxLines: 1, overflow: TextOverflow.ellipsis),
                              trailing: Text('${repo.seriesInGroup(g).length}', style: const TextStyle(color: Colors.white38)),
                              onSelect: () => setState(() => group = g),
                            );
                          },
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: group == null
                            ? const Center(child: Text('No series found'))
                            : GridView.builder(
                                padding: const EdgeInsets.all(16),
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 5, mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: 0.62),
                                itemCount: repo.seriesInGroup(group!).length,
                                itemBuilder: (_, i) {
                                  final s = repo.seriesInGroup(group!)[i];
                                  return PosterTile(title: s.name, cover: s.cover, autofocus: i == 0, onSelect: () => _open(s));
                                },
                              ),
                      ),
                    ]),
    );
  }
}
