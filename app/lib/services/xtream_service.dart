import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/account.dart';
import '../models/channel.dart';
import '../models/vod.dart';

/// Minimal Xtream Codes "player_api.php" client.
class XtreamService {
  final Account acct;
  XtreamService(this.acct);

  String get _base => acct.host.replaceAll(RegExp(r'/+$'), '');

  Uri _api([String? action, Map<String, String>? extra]) => Uri.parse(
      '$_base/player_api.php?username=${Uri.encodeComponent(acct.username)}'
      '&password=${Uri.encodeComponent(acct.password)}'
      '${action == null ? '' : '&action=$action'}'
      '${extra == null ? '' : extra.entries.map((e) => '&${e.key}=${Uri.encodeComponent(e.value)}').join()}');

  Future<dynamic> _get(Uri u) async {
    http.Response r;
    try {
      r = await http.get(u).timeout(const Duration(seconds: 20));
    } catch (e) {
      throw Exception('Could not reach ${u.host}:${u.port} — ${_plain(e)}');
    }
    if (r.statusCode != 200) throw Exception('Portal answered HTTP ${r.statusCode}');
    try {
      return jsonDecode(r.body);
    } catch (_) {
      throw Exception('Portal did not return JSON — check the server URL and port');
    }
  }

  /// Strip the URL (which carries credentials) out of socket error text.
  static String _plain(Object e) =>
      e.toString().replaceAll(RegExp(r',?\s*uri=\S+'), '').replaceFirst('ClientException with ', '');

  /// Throws with a readable message if the login is rejected.
  Future<Map<String, dynamic>> login() async {
    final j = await _get(_api()) as Map<String, dynamic>;
    final info = j['user_info'] as Map<String, dynamic>?;
    if (info == null || info['auth'] != 1) {
      throw Exception('Login rejected by portal (check host, username, password)');
    }
    if (info['status'] != null && info['status'] != 'Active') {
      throw Exception('Account status: ${info['status']}');
    }
    return info;
  }

  Future<List<Channel>> liveChannels() async {
    final cats = await _get(_api('get_live_categories')) as List;
    final catName = {
      for (final c in cats) c['category_id'].toString(): (c['category_name'] ?? '').toString()
    };
    final streams = await _get(_api('get_live_streams')) as List;
    return streams.map((s) {
      final id = s['stream_id'].toString();
      return Channel(
        id: id,
        name: (s['name'] ?? '').toString(),
        group: catName[s['category_id']?.toString()] ?? 'Other',
        logo: (s['stream_icon'] ?? '').toString(),
        streamUrl: '$_base/live/${acct.username}/${acct.password}/$id.ts',
        epgId: (s['epg_channel_id'] ?? '').toString(),
        tvArchive: (s['tv_archive'] ?? 0).toString() == '1',
        tvArchiveDuration: int.tryParse((s['tv_archive_duration'] ?? '0').toString()) ?? 0,
      );
    }).toList();
  }

  String get epgUrl => '$_base/xmltv.php?username=${Uri.encodeComponent(acct.username)}'
      '&password=${Uri.encodeComponent(acct.password)}';

  // ---- VOD (movies) --------------------------------------------------------

  Future<List<VodItem>> vodItems() async {
    final cats = await _get(_api('get_vod_categories')) as List;
    final catName = {
      for (final c in cats) c['category_id'].toString(): (c['category_name'] ?? '').toString()
    };
    final streams = await _get(_api('get_vod_streams')) as List;
    return streams.map((s) {
      final id = s['stream_id'].toString();
      final ext = (s['container_extension'] ?? 'mp4').toString();
      return VodItem(
        id: id,
        name: (s['name'] ?? '').toString(),
        group: catName[s['category_id']?.toString()] ?? 'Other',
        cover: (s['stream_icon'] ?? s['cover'] ?? '').toString(),
        streamUrl: '$_base/movie/${acct.username}/${acct.password}/$id.$ext',
        plot: (s['plot'] ?? '').toString(),
      );
    }).toList();
  }

  // ---- Series ---------------------------------------------------------------

  Future<List<SeriesItem>> seriesItems() async {
    final cats = await _get(_api('get_series_categories')) as List;
    final catName = {
      for (final c in cats) c['category_id'].toString(): (c['category_name'] ?? '').toString()
    };
    final list = await _get(_api('get_series')) as List;
    return list.map((s) {
      return SeriesItem(
        id: s['series_id'].toString(),
        name: (s['name'] ?? '').toString(),
        group: catName[s['category_id']?.toString()] ?? 'Other',
        cover: (s['cover'] ?? '').toString(),
        plot: (s['plot'] ?? '').toString(),
      );
    }).toList();
  }

  /// Episodes for one series, flattened and sorted by season then episode
  /// number. Xtream returns these grouped by season under "episodes".
  Future<List<SeriesEpisode>> seriesEpisodes(String seriesId) async {
    final j = await _get(_api('get_series_info', {'series_id': seriesId})) as Map<String, dynamic>;
    final episodes = <SeriesEpisode>[];
    final eps = j['episodes'];
    if (eps is Map) {
      for (final season in eps.entries) {
        final list = season.value;
        if (list is! List) continue;
        for (final e in list) {
          final id = e['id'].toString();
          final ext = (e['container_extension'] ?? 'mp4').toString();
          episodes.add(SeriesEpisode(
            id: id,
            title: (e['title'] ?? '').toString(),
            season: int.tryParse(season.key.toString()) ?? 0,
            episode: int.tryParse((e['episode_num'] ?? '0').toString()) ?? 0,
            streamUrl: '$_base/series/${acct.username}/${acct.password}/$id.$ext',
          ));
        }
      }
    }
    episodes.sort((a, b) =>
        a.season != b.season ? a.season.compareTo(b.season) : a.episode.compareTo(b.episode));
    return episodes;
  }

  // ---- Catchup / timeshift ----------------------------------------------

  /// URL for [minutes] of catchup on [ch] starting at [start] (portal-local
  /// wall clock — Xtream's timeshift endpoint expects the server's own time,
  /// which for the vast majority of portals is effectively UTC-adjacent; if
  /// a portal returns a shifted result, adjust the channel's server offset
  /// in a future update).
  String catchupUrl(Channel ch, DateTime start, int minutes) {
    final s = start;
    final stamp = '${s.year.toString().padLeft(4, '0')}-${s.month.toString().padLeft(2, '0')}-'
        '${s.day.toString().padLeft(2, '0')}:${s.hour.toString().padLeft(2, '0')}-${s.minute.toString().padLeft(2, '0')}';
    final dur = minutes < 1 ? 1 : minutes;
    return '$_base/timeshift/${acct.username}/${acct.password}/$dur/$stamp/${ch.id}.ts';
  }
}
