import 'dart:convert';
import 'account.dart';

/// One configured source (Xtream portal or M3U playlist), plus the bits
/// needed to manage a prioritized list of them: a stable [id], a display
/// [nickname], whether it's [enabled], and its failover [priority] (lower
/// runs first).
class ServerConfig {
  final String id;
  final String nickname;
  final Account account;
  final bool enabled;
  final int priority;

  const ServerConfig({
    required this.id,
    required this.nickname,
    required this.account,
    this.enabled = true,
    this.priority = 0,
  });

  ServerConfig copyWith({
    String? nickname,
    Account? account,
    bool? enabled,
    int? priority,
  }) =>
      ServerConfig(
        id: id,
        nickname: nickname ?? this.nickname,
        account: account ?? this.account,
        enabled: enabled ?? this.enabled,
        priority: priority ?? this.priority,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'nickname': nickname,
        'enabled': enabled,
        'priority': priority,
        'account': account.toJson(),
      };

  static ServerConfig fromMap(Map<String, dynamic> m) => ServerConfig(
        id: m['id'] as String,
        nickname: (m['nickname'] ?? '') as String,
        enabled: (m['enabled'] ?? true) as bool,
        priority: (m['priority'] ?? 0) as int,
        account: Account.fromJson(m['account'] as String),
      );

  static String encodeList(List<ServerConfig> list) =>
      jsonEncode(list.map((s) => s.toMap()).toList());

  static List<ServerConfig> decodeList(String s) {
    final l = jsonDecode(s) as List;
    return l.map((e) => ServerConfig.fromMap(e as Map<String, dynamic>)).toList();
  }
}
