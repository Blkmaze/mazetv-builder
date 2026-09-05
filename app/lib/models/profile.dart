import 'dart:convert';

/// A household profile ("Who's watching?"). Each profile keeps its own
/// favorite channels; everything else (servers, login) stays shared.
class Profile {
  final String id;
  final String name;
  final int colorSeed; // picks an avatar color, 0..colors.length-1

  const Profile({required this.id, required this.name, this.colorSeed = 0});

  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'colorSeed': colorSeed};

  static Profile fromMap(Map<String, dynamic> m) => Profile(
        id: m['id'] as String,
        name: (m['name'] ?? '') as String,
        colorSeed: (m['colorSeed'] ?? 0) as int,
      );

  static String encodeList(List<Profile> list) => jsonEncode(list.map((p) => p.toMap()).toList());

  static List<Profile> decodeList(String s) {
    final l = jsonDecode(s) as List;
    return l.map((e) => Profile.fromMap(e as Map<String, dynamic>)).toList();
  }
}
