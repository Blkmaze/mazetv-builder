class Channel {
  final String id;
  final String name;
  final String group;
  final String logo;
  final String streamUrl;
  final String epgId;
  /// Whether this channel's portal offers catchup/timeshift for it.
  final bool tvArchive;
  /// How many hours of catchup are available, if [tvArchive] is true.
  final int tvArchiveDuration;

  const Channel({
    required this.id,
    required this.name,
    required this.group,
    required this.logo,
    required this.streamUrl,
    required this.epgId,
    this.tvArchive = false,
    this.tvArchiveDuration = 0,
  });
}

class Programme {
  final String channelId;
  final String title;
  final String description;
  final DateTime start;
  final DateTime stop;

  const Programme({
    required this.channelId,
    required this.title,
    required this.description,
    required this.start,
    required this.stop,
  });

  bool isOnAt(DateTime t) => !t.isBefore(start) && t.isBefore(stop);
}
