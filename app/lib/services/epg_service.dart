import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:xml/xml_events.dart';
import '../models/channel.dart';

/// Streams an XMLTV feed and keeps only programmes that matter:
/// channels we actually have, and a window of [hoursAhead] from now.
class EpgService {
  final Map<String, List<Programme>> byChannel = {};
  bool loaded = false;

  Future<void> load(String url, Set<String> wantedIds, {int hoursAhead = 12}) async {
    byChannel.clear();
    loaded = false;
    if (url.isEmpty || wantedIds.isEmpty) return;

    final now = DateTime.now().toUtc();
    final windowEnd = now.add(Duration(hours: hoursAhead));

    final req = http.Request('GET', Uri.parse(url));
    final resp = await req.send().timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) throw Exception('EPG HTTP ${resp.statusCode}');

    String? ch, startS, stopS;
    String title = '', desc = '';
    String? textTarget; // 'title' | 'desc'
    bool keep = false;

    await for (final ev in resp.stream.transform(utf8.decoder).toXmlEvents().flatten()) {
      if (ev is XmlStartElementEvent) {
        if (ev.name == 'programme') {
          ch = _a(ev, 'channel');
          startS = _a(ev, 'start');
          stopS = _a(ev, 'stop');
          title = '';
          desc = '';
          keep = ch != null && wantedIds.contains(ch);
        } else if (keep && ev.name == 'title') {
          textTarget = 'title';
        } else if (keep && ev.name == 'desc') {
          textTarget = 'desc';
        }
      } else if (ev is XmlTextEvent || ev is XmlCDATAEvent) {
        if (!keep || textTarget == null) continue;
        final t = ev is XmlTextEvent ? ev.value : (ev as XmlCDATAEvent).value;
        if (textTarget == 'title') title += t; else desc += t;
      } else if (ev is XmlEndElementEvent) {
        if (ev.name == 'title' || ev.name == 'desc') {
          textTarget = null;
        } else if (ev.name == 'programme' && keep) {
          final s = _parseTime(startS), e = _parseTime(stopS);
          if (s != null && e != null && e.isAfter(now) && s.isBefore(windowEnd)) {
            byChannel.putIfAbsent(ch!, () => []).add(Programme(
              channelId: ch, title: title.trim(), description: desc.trim(),
              start: s.toLocal(), stop: e.toLocal(),
            ));
          }
          keep = false;
        }
      }
    }
    for (final l in byChannel.values) {
      l.sort((a, b) => a.start.compareTo(b.start));
    }
    loaded = true;
  }

  Programme? nowPlaying(String epgId) {
    final l = byChannel[epgId];
    if (l == null) return null;
    final t = DateTime.now();
    for (final p in l) {
      if (p.isOnAt(t)) return p;
    }
    return null;
  }

  List<Programme> upcoming(String epgId, {int max = 6}) {
    final l = byChannel[epgId] ?? const [];
    final t = DateTime.now();
    return l.where((p) => p.stop.isAfter(t)).take(max).toList();
  }

  static String? _a(XmlStartElementEvent e, String name) {
    for (final a in e.attributes) {
      if (a.name == name) return a.value;
    }
    return null;
  }

  /// XMLTV time: 20260904180000 +0000
  static DateTime? _parseTime(String? s) {
    if (s == null || s.length < 14) return null;
    try {
      final y = int.parse(s.substring(0, 4)), mo = int.parse(s.substring(4, 6)),
          d = int.parse(s.substring(6, 8)), h = int.parse(s.substring(8, 10)),
          mi = int.parse(s.substring(10, 12)), se = int.parse(s.substring(12, 14));
      var dt = DateTime.utc(y, mo, d, h, mi, se);
      final tz = RegExp(r'([+-])(\d{2})(\d{2})').firstMatch(s.substring(14));
      if (tz != null) {
        final off = Duration(hours: int.parse(tz.group(2)!), minutes: int.parse(tz.group(3)!));
        dt = tz.group(1) == '+' ? dt.subtract(off) : dt.add(off);
      }
      return dt;
    } catch (_) {
      return null;
    }
  }
}
