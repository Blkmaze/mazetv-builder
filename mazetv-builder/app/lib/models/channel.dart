class Channel {
  final String id;
  final String name;
  final String group;
  final String logo;
  final String streamUrl;
  final String epgId;

  const Channel({
    required this.id,
    required this.name,
    required this.group,
    required this.logo,
    required this.streamUrl,
    required this.epgId,
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
