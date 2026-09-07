import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// One trending title from TMDB, reduced to what we need for matching.
class TrendingTitle {
  final String title;
  final int year;
  final double popularity;
  final String key;
  TrendingTitle({required this.title, required this.year, required this.popularity}) : key = norm(title);

  /// Lowercase, no year/brackets/punctuation — so "Spider-Man: Brand New
  /// Day (2026)" and "SPIDER MAN BRAND NEW DAY" compare equal.
  static String norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), ' ')
      .replaceAll(RegExp(r'\b(19|20)\d{2}\b'), ' ')
      .replaceAll(RegExp(r'\b(4k|uhd|fhd|hd|multi|multisub|dual|latino|vostfr|en|fr|es)\b'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');

}

/// Pulls TMDB's "trending this week" for movies and TV. Cached for 12 hours
/// so it costs one request per list per half-day, not one per launch.
/// Without an API key every call returns an empty list and the app falls
/// back to newest-first — nothing breaks, the rows are just less "popular".
class TmdbService {
  static const _base = 'https://api.themoviedb.org/3';
  static const _cacheTtl = Duration(hours: 12);

  static Future<List<TrendingTitle>> trendingMovies(String apiKey) => _trending(apiKey, 'movie');
  static Future<List<TrendingTitle>> trendingTv(String apiKey) => _trending(apiKey, 'tv');

  static Future<List<TrendingTitle>> _trending(String apiKey, String kind) async {
    if (apiKey.isEmpty) return const [];
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'tmdb_trending_$kind';
    final stampKey = '${cacheKey}_at';
    final stamp = prefs.getInt(stampKey) ?? 0;
    final cached = prefs.getString(cacheKey);
    if (cached != null && DateTime.now().millisecondsSinceEpoch - stamp < _cacheTtl.inMilliseconds) {
      return _parse(cached);
    }
    try {
      // Two pages = 40 titles; enough to find a decent overlap with a provider.
      final out = <Map<String, dynamic>>[];
      for (final page in [1, 2]) {
        final u = Uri.parse('$_base/trending/$kind/week?api_key=$apiKey&page=$page');
        final r = await http.get(u).timeout(const Duration(seconds: 15));
        if (r.statusCode != 200) break;
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        out.addAll(((j['results'] as List?) ?? const []).cast<Map<String, dynamic>>());
      }
      final slim = jsonEncode(out.map((m) => {
        't': (m['title'] ?? m['name'] ?? '').toString(),
        'y': _year((m['release_date'] ?? m['first_air_date'] ?? '').toString()),
        'p': (m['popularity'] as num?)?.toDouble() ?? 0,
      }).toList());
      await prefs.setString(cacheKey, slim);
      await prefs.setInt(stampKey, DateTime.now().millisecondsSinceEpoch);
      return _parse(slim);
    } catch (_) {
      return cached != null ? _parse(cached) : const [];
    }
  }

  static int _year(String date) => int.tryParse(date.length >= 4 ? date.substring(0, 4) : '') ?? 0;

  static List<TrendingTitle> _parse(String json) {
    try {
      final list = (jsonDecode(json) as List).cast<Map<String, dynamic>>();
      return [for (final m in list)
        TrendingTitle(
          title: (m['t'] ?? '').toString(),
          year: (m['y'] as num?)?.toInt() ?? 0,
          popularity: (m['p'] as num?)?.toDouble() ?? 0,
        )]..sort((a, b) => b.popularity.compareTo(a.popularity));
    } catch (_) {
      return const [];
    }
  }
}
