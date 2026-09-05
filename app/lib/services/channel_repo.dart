import '../models/account.dart';
import '../models/channel.dart';
import '../models/server_config.dart';
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
        failures.add('${s.nickname}: ${e.toString().replaceFirst('Exception: ', '')}');
      }
    }
    activeServer = null;
    throw Exception('All servers failed —\n${failures.join('\n')}');
  }

  /// Fire-and-forget; UI listens via [onEpgLoaded].
  Future<void> loadEpg() async {
    final ids = channels.map((c) => c.epgId).where((e) => e.isNotEmpty).toSet();
    try {
      await epg.load(epgUrl, ids);
    } catch (_) {
      // EPG is optional; never block playback on it.
    }
  }

  /// Groups with English-speaking country categories (USA, UK, Canada,
  /// Australia, New Zealand, Ireland) surfaced first, since that's what
  /// most viewers on this build are looking for — everything else keeps
  /// its original relative order after that.
  static const _priorityPrefixes = [
    'USA', 'US ', 'US:', 'UK ', 'UK:', 'GB ', 'CANADA', 'AUSTRALIA', 'AU ',
    'NEW ZEALAND', 'NZ ', 'IRELAND', 'IE ',
  ];

  bool _isPriority(String group) {
    final g = group.trim().toUpperCase();
    return _priorityPrefixes.any((p) => g.startsWith(p));
  }

  List<String> get groups {
    final seen = <String>{};
    final all = [for (final c in channels) if (seen.add(c.group)) c.group];
    final priority = all.where(_isPriority).toList();
    final rest = all.where((g) => !_isPriority(g)).toList();
    return [...priority, ...rest];
  }

  List<Channel> inGroup(String g) => channels.where((c) => c.group == g).toList();
}
