import 'package:flutter/material.dart';
import '../models/vod.dart';
import '../services/channel_repo.dart';
import 'tv_widgets.dart';
import 'vod_player_screen.dart';

class MoviesScreen extends StatefulWidget {
  const MoviesScreen({super.key});
  @override
  State<MoviesScreen> createState() => _MoviesScreenState();
}

class _MoviesScreenState extends State<MoviesScreen> {
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
        error = 'Movies need an Xtream login — not available for an M3U playlist source.';
      } else {
        if (repo.vodItems.isEmpty) await repo.loadVod();
        group = repo.vodGroups.isEmpty ? null : repo.vodGroups.first;
      }
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _play(VodItem v) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => VodPlayerScreen(item: v)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Movies')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
                  ),
                )
              : repo.vodItems.isEmpty
                  ? const Center(child: Text('No movies found on this portal'))
                  : Row(children: [
                      SizedBox(
                        width: 260,
                        child: ListView.builder(
                          itemCount: repo.vodGroups.length,
                          itemBuilder: (_, i) {
                            final g = repo.vodGroups[i];
                            return TvTile(
                              autofocus: i == 0,
                              selected: g == group,
                              title: Text(g, maxLines: 1, overflow: TextOverflow.ellipsis),
                              trailing: Text('${repo.vodInGroup(g).length}', style: const TextStyle(color: Colors.white38)),
                              onSelect: () => setState(() => group = g),
                            );
                          },
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: group == null
                            ? const Center(child: Text('No movies found'))
                            : GridView.builder(
                                padding: const EdgeInsets.all(16),
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 5, mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: 0.62),
                                itemCount: repo.vodInGroup(group!).length,
                                itemBuilder: (_, i) {
                                  final v = repo.vodInGroup(group!)[i];
                                  return PosterTile(title: v.name, cover: v.cover, autofocus: i == 0, onSelect: () => _play(v));
                                },
                              ),
                      ),
                    ]),
    );
  }
}
