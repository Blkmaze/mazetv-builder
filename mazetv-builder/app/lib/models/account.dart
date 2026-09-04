import 'dart:convert';

enum SourceType { xtream, m3u }

class Account {
  final SourceType type;
  final String host;      // xtream: http://host:port   m3u: playlist url
  final String username;
  final String password;
  final String epgUrl;    // optional override

  const Account({
    required this.type,
    required this.host,
    this.username = '',
    this.password = '',
    this.epgUrl = '',
  });

  String toJson() => jsonEncode({
        'type': type.name,
        'host': host,
        'username': username,
        'password': password,
        'epgUrl': epgUrl,
      });

  static Account fromJson(String s) {
    final j = jsonDecode(s) as Map<String, dynamic>;
    return Account(
      type: SourceType.values.byName(j['type']),
      host: j['host'],
      username: j['username'] ?? '',
      password: j['password'] ?? '',
      epgUrl: j['epgUrl'] ?? '',
    );
  }
}
