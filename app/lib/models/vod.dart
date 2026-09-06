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
