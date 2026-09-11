import 'dart:async';
import 'package:flutter/material.dart';
import '../models/vod.dart';
import '../services/channel_repo.dart';

/// What the Home hero is currently showcasing — whichever movie or series
/// poster the remote is sitting on. Only the cheap list fields live here;
/// the plot/backdrop are fetched lazily by [HomeHero] itself.
class HeroPick {
  final String id;
  final String title;
  final String cover;
  final double rating;
  final int year;
  final bool isSeries;

  const HeroPick({
    required this.id,
    required this.title,
    required this.cover,
    required this.rating,
    required this.year,
    required this.isSeries,
  });

  factory HeroPick.movie(VodItem v) =>
      HeroPick(id: v.id, title: v.name, cover: v.cover, rating: v.rating, year: v.year, isSeries: false);

  factory HeroPick.series(SeriesItem s) =>
      HeroPick(id: s.id, title: s.name, cover: s.cover, rating: s.rating, year: s.year, isSeries: true);

  /// Movie and series ids come from different Xtream tables and can collide.
  String get cacheKey => '${isSeries ? 's' : 'm'}:$id';
}

/// Plot/backdrop for titles the hero has already shown. Capped so a long
/// browsing session on a small TV box doesn't grow it without bound.
class _HeroInfoCache {
  static const int _max = 80;
  static final Map<String, VodInfo> _map = {};

  static VodInfo? get(String key) => _map[key];

  static void put(String key, VodInfo info) {
    if (_map.length >= _max) _map.remove(_map.keys.first);
    _map[key] = info;
  }
}

/// Ghost-style hero banner at the top of Home: wide backdrop on the right,
/// fading into a dark panel on the left with the title, ★rating,
/// "year · Movie/Series" line and a three-line description.
///
/// Updates with focus: Home hands it a new [HeroPick] as the remote moves
/// across posters. The description needs a per-title portal call, so that
/// fetch is debounced — scrubbing fast across a row doesn't fire a request
/// per poster, only for the one you stop on.
class HomeHero extends StatefulWidget {
  static const double height = 210;

  final HeroPick? pick;
  const HomeHero({super.key, required this.pick});

  @override
  State<HomeHero> createState() => _HomeHeroState();
}

class _HomeHeroState extends State<HomeHero> {
  static const Duration _settle = Duration(milliseconds: 350);

  Timer? _debounce;
  VodInfo? _info;
  String _infoFor = '';

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(HomeHero old) {
    super.didUpdateWidget(old);
    if (old.pick?.cacheKey != widget.pick?.cacheKey) _fetch();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _fetch() {
    _debounce?.cancel();
    final p = widget.pick;
    if (p == null) return;
    final key = p.cacheKey;

    final cached = _HeroInfoCache.get(key);
    if (cached != null) {
      _info = cached;
      _infoFor = key;
      return;
    }

    // Clear the old title's plot straight away so it never sits under the
    // new title while the fetch is in flight.
    _info = null;
    _infoFor = '';

    _debounce = Timer(_settle, () async {
      final x = ChannelRepo.I.xtream;
      if (x == null) return;
      try {
        final info = p.isSeries ? await x.seriesInfo(p.id) : await x.vodInfo(p.id);
        _HeroInfoCache.put(key, info);
        // Only apply if the remote is still on this title.
        if (mounted && widget.pick?.cacheKey == key) {
          setState(() {
            _info = info;
            _infoFor = key;
          });
        }
      } catch (_) {
        // The banner is decoration; list data alone is fine.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.pick;
    if (p == null) return const SizedBox.shrink();

    final accent = Theme.of(context).colorScheme.primary;
    final info = _infoFor == p.cacheKey ? _info : null;
    final rating = (info?.rating ?? 0) > 0 ? info!.rating : p.rating;
    final plot = info?.plot ?? '';
    final backdrop = (info?.backdrop.isNotEmpty ?? false) ? info!.backdrop : p.cover;
    const panel = Color(0xFF14171F);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: HomeHero.height,
          child: Stack(fit: StackFit.expand, children: [
            const ColoredBox(color: panel),
            // ---- backdrop, right 60% of the banner, cross-fading per title
            Positioned.fill(
              child: Row(children: [
                const Spacer(flex: 4),
                Expanded(
                  flex: 6,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    child: backdrop.isEmpty
                        ? const SizedBox.shrink()
                        : Image.network(
                            backdrop,
                            key: ValueKey(backdrop),
                            cacheWidth: 900,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                          ),
                  ),
                ),
              ]),
            ),
            // ---- fade: solid panel on the left, clear on the right
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    stops: const [0.0, 0.38, 0.62, 1.0],
                    colors: [panel, panel, panel.withOpacity(0.0), panel.withOpacity(0.0)],
                  ),
                ),
              ),
            ),
            // ---- bottom shade so text stays readable over bright art
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, panel.withOpacity(0.6)],
                  ),
                ),
              ),
            ),
            // ---- text block
            Positioned(
              left: 26, top: 22, bottom: 20,
              width: 420,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, height: 1.1)),
                const SizedBox(height: 8),
                Row(children: [
                  if (rating > 0) ...[
                    const Icon(Icons.star_rounded, color: Colors.amber, size: 20),
                    const SizedBox(width: 3),
                    Text(rating.toStringAsFixed(1),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                    const _Dot(),
                  ],
                  if (p.year > 0) ...[
                    Text('${p.year}', style: const TextStyle(fontSize: 15, color: Colors.white70)),
                    const _Dot(),
                  ],
                  Text(p.isSeries ? 'Series' : 'Movie',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: accent)),
                  if (info != null && info.genre.isNotEmpty) ...[
                    const _Dot(),
                    Flexible(
                      child: Text(info.genre, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15, color: Colors.white70)),
                    ),
                  ],
                ]),
                const SizedBox(height: 10),
                if (info == null)
                  const Text('Loading…', style: TextStyle(fontSize: 14, color: Colors.white38))
                else
                  Text(plot.isEmpty ? 'No description available.' : plot,
                      maxLines: 3, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, height: 1.35, color: Colors.white70)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: Text('·', style: TextStyle(fontSize: 15, color: Colors.white38)),
      );
}

/// Ghost's bottom-right legend: a colored dot per remote button and what it
/// does on Home. Purely a label — the key handling lives on HomeScreen.
class ButtonLegend extends StatelessWidget {
  final bool showRecord;
  const ButtonLegend({super.key, this.showRecord = true});

  static const List<(Color, String)> items = [
    (Color(0xFFE53935), 'Record'),
    (Color(0xFF43A047), 'Search'),
    (Color(0xFFFDD835), 'Movies'),
    (Color(0xFF1E88E5), 'Series'),
  ];

  @override
  Widget build(BuildContext context) {
    final items = showRecord ? ButtonLegend.items : ButtonLegend.items.sublist(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.45),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (int i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 16),
          Container(
            width: 11, height: 11,
            decoration: BoxDecoration(
              color: items[i].$1, shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: items[i].$1.withOpacity(0.7), blurRadius: 6)],
            ),
          ),
          const SizedBox(width: 6),
          Text(items[i].$2,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70)),
        ],
      ]),
    );
  }
}
