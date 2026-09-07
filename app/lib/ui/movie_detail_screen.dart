import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/vod.dart';
import '../services/channel_repo.dart';
import '../services/storage.dart';
import 'tv_widgets.dart';
import 'vod_player_screen.dart';

/// Movie detail page, Ghost-style: blurred backdrop, poster, title with
/// year / rating / duration / genre badges, Play + Trailer, Overview, Cast
/// (initials avatars — no photo source without TMDB), Director.
class MovieDetailScreen extends StatefulWidget {
  final VodItem item;
  const MovieDetailScreen({super.key, required this.item});
  @override
  State<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends State<MovieDetailScreen> {
  VodInfo? info;
  bool loading = true;
  int resumeAt = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    resumeAt = await Storage.resumePosition(widget.item.id) ?? 0;
    try {
      final x = ChannelRepo.I.xtream;
      if (x != null) info = await x.vodInfo(widget.item.id);
    } catch (_) {
      // Detail is a bonus; the page still works from what the list gave us.
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _play({int from = 0}) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => VodPlayerScreen(item: widget.item, startAtSeconds: from)));
    // Back from the player: refresh the Resume offer.
    resumeAt = await Storage.resumePosition(widget.item.id) ?? 0;
    if (mounted) setState(() {});
  }

  static String _clock(int secs) {
    final h = secs ~/ 3600, m = (secs % 3600) ~/ 60, s = secs % 60;
    final ms = '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return h > 0 ? '$h:$ms' : ms;
  }

  Future<void> _trailer() async {
    final t = info?.trailer ?? '';
    if (t.isEmpty) return;
    final url = t.startsWith('http') ? t : 'https://www.youtube.com/watch?v=$t';
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No app on this device can play the trailer')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.item;
    final accent = Theme.of(context).colorScheme.primary;
    final plot = (info?.plot.isNotEmpty ?? false) ? info!.plot : v.plot;
    final rating = (info?.rating ?? 0) > 0 ? info!.rating : v.rating;
    final backdrop = (info?.backdrop.isNotEmpty ?? false) ? info!.backdrop : v.cover;
    final badges = <String>[
      if (v.year > 0) '${v.year}',
      if (info != null && info!.genre.isNotEmpty) info!.genre,
      if (info != null && info!.duration.isNotEmpty) info!.duration,
      if (rating > 0) '★ ${rating.toStringAsFixed(1)}',
    ];

    return Scaffold(
      body: Stack(children: [
        if (backdrop.isNotEmpty)
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Opacity(opacity: 0.5,
                  child: Image.network(backdrop, fit: BoxFit.cover, width: double.infinity, height: double.infinity,
                      errorBuilder: (_, __, ___) => const SizedBox())),
            ),
          ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Colors.black.withOpacity(0.3), Colors.black.withOpacity(0.85)]),
            ),
          ),
        ),
        SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(40, 24, 40, 40), children: [
            Row(children: [
              IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
              const Spacer(),
            ]),
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 200, height: 300,
                  child: v.cover.isEmpty
                      ? Container(color: Colors.white10, child: const Icon(Icons.movie, size: 64, color: Colors.white38))
                      : Image.network(v.cover, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(color: Colors.white10,
                              child: const Icon(Icons.movie, size: 64, color: Colors.white38))),
                ),
              ),
              const SizedBox(width: 32),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(v.name, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final b in badges)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white12, borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Text(b, style: const TextStyle(fontSize: 13, color: Colors.white70)),
                      ),
                  ]),
                  const SizedBox(height: 22),
                  Wrap(spacing: 14, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    if (resumeAt > 0) ...[
                      TvButton(label: 'Resume from ${_clock(resumeAt)}', icon: Icons.play_arrow, autofocus: true,
                          onPressed: () => _play(from: resumeAt)),
                      OutlinedButton.icon(
                        onPressed: () => _play(),
                        icon: const Icon(Icons.replay),
                        label: const Padding(padding: EdgeInsets.symmetric(vertical: 14, horizontal: 6),
                            child: Text('Play from start', style: TextStyle(fontSize: 18))),
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: BorderSide(color: accent)),
                      ),
                    ] else
                      TvButton(label: 'Play', icon: Icons.play_arrow, autofocus: true, onPressed: () => _play()),
                    if (info?.trailer.isNotEmpty ?? false)
                      OutlinedButton.icon(
                        onPressed: _trailer,
                        icon: const Icon(Icons.ondemand_video),
                        label: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14, horizontal: 6),
                          child: Text('Trailer', style: TextStyle(fontSize: 20)),
                        ),
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: BorderSide(color: accent)),
                      ),
                  ]),
                  const SizedBox(height: 26),
                  const Text('Overview', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white70)),
                  const SizedBox(height: 6),
                  if (loading && plot.isEmpty)
                    const Text('Loading…', style: TextStyle(color: Colors.white38))
                  else
                    Text(plot.isEmpty ? 'No description available.' : plot,
                        style: const TextStyle(fontSize: 16, height: 1.4, color: Colors.white)),
                  if (info != null && info!.castList.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    const Text('Cast', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white70)),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 96,
                      child: ListView(scrollDirection: Axis.horizontal, children: [
                        for (final name in info!.castList)
                          Padding(
                            padding: const EdgeInsets.only(right: 16),
                            child: SizedBox(
                              width: 84,
                              child: Column(children: [
                                CircleAvatar(
                                  radius: 28, backgroundColor: accent.withOpacity(0.25),
                                  child: Text(_initials(name),
                                      style: TextStyle(color: accent, fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(height: 6),
                                Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 11, color: Colors.white70)),
                              ]),
                            ),
                          ),
                      ]),
                    ),
                  ],
                  if (info != null && info!.director.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text('Director', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white70)),
                    const SizedBox(height: 4),
                    Text(info!.director, style: const TextStyle(color: Colors.white)),
                  ],
                ]),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }

  static String _initials(String name) {
    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}
