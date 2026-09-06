/// Video-on-demand item (Xtream "movie" stream).
class VodItem {
  final String id;
  final String name;
  final String group;
  final String cover;
  final String streamUrl;
  final String plot;
  final double rating;   // 0 when the provider gives none
  final int added;       // unix seconds the provider added it; 0 if unknown
  final int year;        // release year; 0 if unknown

  const VodItem({
    required this.id,
    required this.name,
    required this.group,
    required this.cover,
    required this.streamUrl,
    this.plot = '',
    this.rating = 0,
    this.added = 0,
    this.year = 0,
  });
}

/// A TV series (Xtream "series") — episodes are fetched separately via
/// XtreamService.seriesEpisodes(id) since the catalog call doesn't include them.
class SeriesItem {
  final String id;
  final String name;
  final String group;
  final String cover;
  final String plot;
  final double rating;   // 0 when the provider gives none
  final int added;       // unix seconds last modified/added; 0 if unknown
  final int year;        // first-aired year; 0 if unknown

  const SeriesItem({
    required this.id,
    required this.name,
    required this.group,
    required this.cover,
    this.plot = '',
    this.rating = 0,
    this.added = 0,
    this.year = 0,
  });
}

class SeriesEpisode {
  final String id;
  final String title;
  final int season;
  final int episode;
  final String streamUrl;

  const SeriesEpisode({
    required this.id,
    required this.title,
    required this.season,
    required this.episode,
    required this.streamUrl,
  });
}


/// Extra detail Xtream returns from get_vod_info for one movie.
class VodInfo {
  final String plot;
  final String cast;       // comma-separated names as the portal sends them
  final String director;
  final String genre;
  final String duration;   // e.g. "02:10:05" or "130 min" — shown as sent
  final double rating;
  final String backdrop;   // first backdrop image url, if any
  final String trailer;    // YouTube id or url, if any

  const VodInfo({
    this.plot = '', this.cast = '', this.director = '', this.genre = '',
    this.duration = '', this.rating = 0, this.backdrop = '', this.trailer = '',
  });

  List<String> get castList =>
      cast.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).take(12).toList();
}
