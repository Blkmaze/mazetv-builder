import 'dart:isolate';
import '../models/account.dart';
import '../models/channel.dart';
import '../models/server_config.dart';
import '../models/vod.dart';
import 'epg_service.dart';
import 'm3u_service.dart';
import 'tmdb_service.dart';
import 'xtream_service.dart';

/// One place that knows how to turn an Account into channels + EPG, and how
/// to fail over across a prioritized list of [ServerConfig]s when one is
/// down.
class ChannelRepo {
  static final ChannelRepo I = ChannelRepo._();
  ChannelRepo._();

  /// Everything the server sent. [channels] is this after [hdOnly] filtering.
  List<Channel> allChannels = [];
  List<Channel> channels = [];

  /// When on, hide SD duplicates and keep only channels tagged HD/FHD/UHD/4K.
  /// If a provider doesn't tag quality at all, the filter would empty the
  /// list — in that case it quietly leaves everything visible.
  bool hdOnly = false;
  static final _hdTag = RegExp(r'\b(HD|FHD|UHD|4K|8K|1080p?|2160p?|720p?)\b', caseSensitive: false);
  static final _sdTag = RegExp(r'\bSD\b', caseSensitive: false);

  void applyFilters() {
    if (!hdOnly) { channels = List.of(allChannels); return; }
    final kept = allChannels.where((c) => _hdTag.hasMatch(c.name) && !_sdTag.hasMatch(c.name)).toList();
    channels = kept.length >= allChannels.length * 0.15 ? kept : List.of(allChannels);
  }
  final EpgService epg = EpgService();
  String epgUrl = '';

  /// The server that actually served [channels], once [loadFailover] succeeds.
  ServerConfig? activeServer;

  Future<void> load(Account a, {String fallbackEpg = ''}) async {
    if (a.type == SourceType.xtream) {
      final x = XtreamService(a);
      await x.login();
      allChannels = await x.liveChannels();
      applyFilters();
      epgUrl = a.epgUrl.isNotEmpty ? a.epgUrl : x.epgUrl;
    } else {
      final r = await M3uService.fetch(a.host);
      allChannels = r.channels;
      applyFilters();
      epgUrl = a.epgUrl.isNotEmpty ? a.epgUrl : (r.epgUrl.isNotEmpty ? r.epgUrl : fallbackEpg);
    }
  }

  /// Tries each enabled server in priority order (lowest first) until one
  /// loads successfully. Throws with every server's error attached if all of
  /// them fail.
  Future<void> loadFailover(List<ServerConfig> servers, {String fallbackEpg = ''}) async {
    final ordered = servers.where((s) => s.enabled).toList()
      ..sort((a, b) => a.priority.compareTo(b.priority));
    if (ordered.isEmpty) {
      throw Exception(servers.isEmpty ? 'No servers configured.' : 'All servers are disabled.');
    }

    final failures = <String>[];
    for (final s in ordered) {
      try {
        await load(s.account, fallbackEpg: fallbackEpg);
        activeServer = s;
        return;
      } catch (e) {
        failures.add('${s.nickname}: ${_scrub(e.toString().replaceFirst('Exception: ', ''))}');
      }
    }
    activeServer = null;
    throw Exception('All servers failed —\n${failures.join('\n')}');
  }

  /// Last-resort backstop: strip anything that looks like a full URL or a
  /// raw uri=/address=.../port=... fragment before this ever reaches the
  /// screen, in case a future error path forgets to sanitize at the source.
  static String _scrub(String s) => s
      .replaceAll(RegExp(r'https?://\S+'), '[server]')
      .replaceAll(RegExp(r',?\s*uri=\S+'), '')
      .replaceAll(RegExp(r',?\s*address\s*=\s*[^,]+,?\s*port\s*=\s*\d+'), '');

  /// Fire-and-forget; UI listens via [onEpgLoaded].
  Future<void> loadEpg() async {
    final ids = channels.map((c) => c.epgId).where((e) => e.isNotEmpty).toSet();
    try {
      await epg.load(epgUrl, ids);
    } catch (_) {
      // EPG is optional; never block playback on it.
    }
  }

  /// Groups with English-speaking country categories surfaced first — USA
  /// ranked above UK, which ranks above the rest — since that's what most
  /// viewers on this build are looking for. Everything else keeps its
  /// original relative order after that. Lower rank = shown first.
  static const _priorityRanks = <String, int>{
    'USA': 0, 'US ': 0, 'US:': 0,
    'UK ': 1, 'UK:': 1, 'GB ': 1,
    'CANADA': 2,
    'AUSTRALIA': 3, 'AU ': 3,
    'NEW ZEALAND': 4, 'NZ ': 4,
    'IRELAND': 5, 'IE ': 5,
  };

  /// Lower is higher priority; null means "not a priority group at all".
  int? _priorityRank(String group) {
    final g = group.trim().toUpperCase();
    for (final entry in _priorityRanks.entries) {
      if (g.startsWith(entry.key)) return entry.value;
    }
    return null;
  }

  List<String> get groups {
    final seen = <String>{};
    final all = [for (final c in channels) if (seen.add(c.group)) c.group];
    // (rank, original index, name) so equal-rank groups keep the provider's
    // original relative order — List.sort isn't guaranteed stable.
    final ranked = <(int, int, String)>[];
    final rest = <String>[];
    for (var i = 0; i < all.length; i++) {
      final r = _priorityRank(all[i]);
      if (r == null) { rest.add(all[i]); } else { ranked.add((r, i, all[i])); }
    }
    ranked.sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
    return [...ranked.map((e) => e.$3), ...rest];
  }

  List<Channel> inGroup(String g) => channels.where((c) => c.group == g).toList();

  // ---- VOD / Series (Xtream-only) -----------------------------------------

  List<VodItem> vodItems = [];
  List<SeriesItem> seriesItems = [];

  /// Movies/Series/Catchup all need a real Xtream login (not available for a
  /// plain M3U playlist source).
  bool get supportsVod => activeServer?.account.type == SourceType.xtream;

  /// The active server's Xtream client, or null for M3U sources.
  XtreamService? get xtream {
    final a = activeServer?.account;
    if (a == null || a.type != SourceType.xtream) return null;
    return XtreamService(a);
  }

  Future<void> loadVod() async {
    final x = xtream;
    vodItems = x == null ? [] : await x.vodItems();
    _popMovies = null;
  }

  Future<void> loadSeries() async {
    final x = xtream;
    seriesItems = x == null ? [] : await x.seriesItems();
    _popSeries = null;
  }

  // Cached: these were re-sorting the whole catalog on every Home rebuild
  // (every focus change), which is a lot of work on a TV box.
  List<VodItem>? _popMovies;
  List<SeriesItem>? _popSeries;

  List<String> get vodGroups {
    final seen = <String>{};
    return [for (final v in vodItems) if (seen.add(v.group)) v.group];
  }

  List<VodItem> vodInGroup(String g) => vodItems.where((v) => v.group == g).toList();

  List<String> get seriesGroups {
    final seen = <String>{};
    return [for (final s in seriesItems) if (seen.add(s.group)) s.group];
  }

  List<SeriesItem> seriesInGroup(String g) => seriesItems.where((s) => s.group == g).toList();

  /// "Popular" without a popularity feed: recent titles first (last two
  /// years, or newly added by the provider), ranked by rating. Unrated
  /// items sink to the bottom. Falls back to newest-added when a provider
  /// sends no years at all, so the row never comes back empty.
  static List<T> _popular<T>(List<T> items, {
    required int Function(T) year, required int Function(T) added, required double Function(T) rating,
    required String Function(T) id,
    int take = 20,
  }) {
    if (items.isEmpty) return const [];
    int numId(T i) => int.tryParse(id(i)) ?? 0;
    final anyYear = items.any((i) => year(i) > 0);
    final anyAdded = items.any((i) => added(i) > 0);

    // Newest first. Year if the provider gives one; else when it was added;
    // else the stream id — Xtream ids count up as titles are added, so the
    // highest ids are the newest arrivals. Rating only breaks ties, so it
    // can't drag decades-old classics to the top the way it did.
    int cmp(T a, T b) {
      if (anyYear) { final y = year(b).compareTo(year(a)); if (y != 0) return y; }
      if (anyAdded) { final ad = added(b).compareTo(added(a)); if (ad != 0) return ad; }
      final n = numId(b).compareTo(numId(a));
      if (n != 0) return n;
      return rating(b).compareTo(rating(a));
    }

    // Prefer genuinely recent titles when we can tell what "recent" is.
    final cutoffYear = DateTime.now().year - 1;
    final cutoffAdded = DateTime.now().subtract(const Duration(days: 120)).millisecondsSinceEpoch ~/ 1000;
    final recent = items.where((i) => (anyYear && year(i) >= cutoffYear) || (anyAdded && added(i) >= cutoffAdded)).toList();
    final pool = recent.length >= 8 ? recent : items;
    final sorted = [...pool]..sort(cmp);
    return sorted.take(take).toList();
  }

  /// TMDB-trending matches when we have a good handful; otherwise newest-first.
  List<VodItem> get popularMovies => _trendingMovies.length >= 5
      ? _trendingMovies.take(20).toList()
      : _popMovies ??= _popular(vodItems, year: (v) => v.year, added: (v) => v.added, rating: (v) => v.rating, id: (v) => v.id);

  List<SeriesItem> get popularSeries => _trendingSeries.length >= 5
      ? _trendingSeries.take(20).toList()
      : _popSeries ??= _popular(seriesItems, year: (s) => s.year, added: (s) => s.added, rating: (s) => s.rating, id: (s) => s.id);

  /// True when the Popular rows are coming from TMDB trending.
  bool get popularIsTrending => _trendingMovies.length >= 5 || _trendingSeries.length >= 5;

  // ---- "Popular" via TMDB trending, matched against the provider's catalog --

  List<VodItem> _trendingMovies = [];
  List<SeriesItem> _trendingSeries = [];

  /// Fetch TMDB's weekly trending lists and keep the titles this provider
  /// actually has, in TMDB's popularity order. No key → nothing happens and
  /// the newest-first ranking stays in charge.
  Future<void> loadTrending(String apiKey) async {
    if (apiKey.isEmpty || !supportsVod) return;
    final movies = await TmdbService.trendingMovies(apiKey);
    final tv = await TmdbService.trendingTv(apiKey);
    // Title normalization runs five regexes over every catalog entry —
    // tens of thousands of them — so match in a worker isolate and only
    // bring back the winning indexes.
    final vodNames = [for (final v in vodItems) v.name], vodYears = [for (final v in vodItems) v.year];
    final serNames = [for (final s in seriesItems) s.name], serYears = [for (final s in seriesItems) s.year];
    final mi = await Isolate.run(() => _matchTrending(movies, vodNames, vodYears));
    final si = await Isolate.run(() => _matchTrending(tv, serNames, serYears));
    _trendingMovies = [for (final i in mi) if (i < vodItems.length) vodItems[i]];
    _trendingSeries = [for (final i in si) if (i < seriesItems.length) seriesItems[i]];
  }

  /// Returns catalog indexes, in TMDB popularity order.
  static List<int> _matchTrending(List<TrendingTitle> trending, List<String> names, List<int> years) {
    if (trending.isEmpty || names.isEmpty) return const [];
    int year(int i) => years[i];
    // index the catalog by normalized title once
    final byKey = <String, List<int>>{};
    for (var i = 0; i < names.length; i++) {
      final k = TrendingTitle.norm(names[i]);
      if (k.length < 3) continue;
      byKey.putIfAbsent(k, () => []).add(i);
    }
    final out = <int>[];
    final seen = <int>{};
    for (final t in trending) {
      var hits = byKey[t.key] ?? const [];
      if (hits.isEmpty && t.key.length >= 6) {
        // tolerate provider prefixes/suffixes: "EN | Spider-Man Brand New Day 4K"
        hits = [for (final e in byKey.entries) if (e.key.contains(t.key)) ...e.value];
      }
      // prefer a year match when the provider gives years
      hits = [...hits]..sort((a, b) {
        final da = (year(a) == 0 || t.year == 0) ? 0 : (year(a) - t.year).abs();
        final db = (year(b) == 0 || t.year == 0) ? 0 : (year(b) - t.year).abs();
        return da.compareTo(db);
      });
      for (final h in hits) {
        if (year(h) != 0 && t.year != 0 && (year(h) - t.year).abs() > 1) continue;
        if (seen.add(h)) { out.add(h); break; }
      }
    }
    return out;
  }

  /// Live channels with catchup/timeshift available.
  List<Channel> get archiveChannels => channels.where((c) => c.tvArchive).toList();
}
