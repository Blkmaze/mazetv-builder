import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/account.dart';
import '../models/channel.dart';

/// Minimal Xtream Codes "player_api.php" client.
class XtreamService {
  final Account acct;
  XtreamService(this.acct);

  String get _base => acct.host.replaceAll(RegExp(r'/+$'), '');

  Uri _api([String? action]) => Uri.parse(
      '$_base/player_api.php?username=${Uri.encodeComponent(acct.username)}'
      '&password=${Uri.encodeComponent(acct.password)}'
      '${action == null ? '' : '&action=$action'}');

  Future<dynamic> _get(Uri u) async {
    final r = await http.get(u).timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode} from portal');
    return jsonDecode(r.body);
  }

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
      );
    }).toList();
  }

  String get epgUrl => '$_base/xmltv.php?username=${Uri.encodeComponent(acct.username)}'
      '&password=${Uri.encodeComponent(acct.password)}';
}
