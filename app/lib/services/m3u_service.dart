import 'package:http/http.dart' as http;
import '../models/channel.dart';

class M3uResult {
  final List<Channel> channels;
  final String epgUrl; // from url-tvg / x-tvg-url in the #EXTM3U header
  M3uResult(this.channels, this.epgUrl);
}

class M3uService {
  static final _attr = RegExp(r'([\w-]+)="([^"]*)"');

  static Future<M3uResult> fetch(String url) async {
    final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode} fetching playlist');
    return parse(r.body);
  }

  static M3uResult parse(String text) {
    final lines = text.split(RegExp(r'\r?\n'));
    final out = <Channel>[];
    String epg = '';
    Map<String, String> attrs = {};
    String title = '';
    int n = 0;

    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#EXTM3U')) {
        final m = RegExp(r'(?:url-tvg|x-tvg-url)="([^"]+)"').firstMatch(line);
        if (m != null) epg = m.group(1)!;
      } else if (line.startsWith('#EXTINF')) {
        attrs = {for (final m in _attr.allMatches(line)) m.group(1)!: m.group(2)!};
        final comma = line.lastIndexOf(',');
        title = comma >= 0 ? line.substring(comma + 1).trim() : '';
      } else if (!line.startsWith('#')) {
        n++;
        out.add(Channel(
          id: 'm3u_$n',
          name: title.isEmpty ? (attrs['tvg-name'] ?? 'Channel $n') : title,
          group: attrs['group-title'] ?? 'Other',
          logo: attrs['tvg-logo'] ?? '',
          streamUrl: line,
          epgId: attrs['tvg-id'] ?? '',
        ));
        attrs = {};
        title = '';
      }
    }
    return M3uResult(out, epg);
  }
}
