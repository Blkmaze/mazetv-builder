import '../models/account.dart';
import '../models/channel.dart';
import '../models/server_config.dart';
import '../models/vod.dart';
import 'epg_service.dart';
import 'm3u_service.dart';
import 'xtream_service.dart';

/// One place that knows how to turn an Account into channels + EPG, and how
/// to fail over across a prioritized list of [ServerConfig]s when one is
/// down.
class ChannelRepo {
  static final ChannelRepo I = ChannelRepo._();
  ChannelRepo._();

  List<Channel> channels = [];
  final EpgService epg = EpgService();
  String epgUrl = '';

  /// The server that actually served [channels], once [loadFailover] succeeds.
  ServerConfig? activeServer;

  Future<void> load(Account a, {String fallbackEpg = ''}) async {
    if (a.type == SourceType.xtream) {
      final x = XtreamService(a);
      await x.login();
      channels = await x.liveChannels();
      epgUrl = a.epgUrl.isNotEmpty ? a.epgUrl : x.epgUrl;
    } else {
      final r = await M3uService.fetch(a.host);
      channels = r.channels;
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
  }

  Future<void> loadSeries() async {
    final x = xtream;
    seriesItems = x == null ? [] : await x.seriesItems();
  }

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

  /// Live channels with catchup/timeshift available.
  List<Channel> get archiveChannels => channels.where((c) => c.tvArchive).toList();
}
