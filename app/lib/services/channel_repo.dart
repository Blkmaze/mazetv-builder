import '../models/account.dart';
import '../models/channel.dart';
import 'epg_service.dart';
import 'm3u_service.dart';
import 'xtream_service.dart';

/// One place that knows how to turn an Account into channels + EPG.
class ChannelRepo {
  static final ChannelRepo I = ChannelRepo._();
  ChannelRepo._();

  List<Channel> channels = [];
  final EpgService epg = EpgService();
  String epgUrl = '';

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

  /// Fire-and-forget; UI listens via [onEpgLoaded].
  Future<void> loadEpg() async {
    final ids = channels.map((c) => c.epgId).where((e) => e.isNotEmpty).toSet();
    try {
      await epg.load(epgUrl, ids);
    } catch (_) {
      // EPG is optional; never block playback on it.
    }
  }

  List<String> get groups {
    final seen = <String>{};
    return [for (final c in channels) if (seen.add(c.group)) c.group];
  }

  List<Channel> inGroup(String g) => channels.where((c) => c.group == g).toList();
}
