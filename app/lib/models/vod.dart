/// Video-on-demand item (Xtream "movie" stream).
class VodItem {
  final String id;
  final String name;
  final String group;
  final String cover;
  final String streamUrl;
  final String plot;

  const VodItem({
    required this.id,
    required this.name,
    required this.group,
    required this.cover,
    required this.streamUrl,
    this.plot = '',
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

  const SeriesItem({
    required this.id,
    required this.name,
    required this.group,
    required this.cover,
    this.plot = '',
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
