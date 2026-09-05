import 'package:shared_preferences/shared_preferences.dart';
import '../models/account.dart';
import '../models/profile.dart';
import '../models/server_config.dart';

class Storage {
  static const _kAccount = 'account'; // legacy single-account key, migrated into servers
  static const _kLastChannel = 'last_channel';
  static const _kServers = 'servers_v1';
  static const _kActiveServer = 'active_server_id';
  static const _kProfiles = 'profiles_v1';
  static const _kActiveProfile = 'active_profile_id';
  static const _kFavPrefix = 'favorites_v1_'; // + profileId (or 'shared')
  static const _kOtaSkip = 'ota_skip_build';

  // ---- legacy single-account shim (kept so old saved logins still work) ----
  static Future<Account?> loadAccount() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_kAccount);
    return s == null ? null : Account.fromJson(s);
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kAccount);
    await p.remove(_kServers);
    await p.remove(_kActiveServer);
  }

  static Future<void> saveLastChannel(String id) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kLastChannel, id);
  }

  static Future<String?> lastChannel() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kLastChannel);
  }

  // ---- servers (multi-source / failover) ----------------------------------

  /// Returns the saved server list, migrating a legacy single [_kAccount]
  /// into it the first time this runs after an update.
  static Future<List<ServerConfig>> loadServers() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kServers);
    if (raw != null) return ServerConfig.decodeList(raw);

    final legacy = p.getString(_kAccount);
    if (legacy == null) return [];
    final migrated = [
      ServerConfig(id: _newId(), nickname: 'My Server', account: Account.fromJson(legacy)),
    ];
    await saveServers(migrated);
    await setActiveServerId(migrated.first.id);
    return migrated;
  }

  static Future<void> saveServers(List<ServerConfig> servers) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kServers, ServerConfig.encodeList(servers));
  }

  static Future<String?> activeServerId() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kActiveServer);
  }

  static Future<void> setActiveServerId(String id) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kActiveServer, id);
  }

  static Future<void> addServer(ServerConfig s) async {
    final list = await loadServers();
    list.add(s);
    await saveServers(list);
  }

  static Future<void> updateServer(ServerConfig s) async {
    final list = await loadServers();
    final i = list.indexWhere((e) => e.id == s.id);
    if (i == -1) {
      list.add(s);
    } else {
      list[i] = s;
    }
    await saveServers(list);
  }

  static Future<void> deleteServer(String id) async {
    final list = await loadServers();
    list.removeWhere((e) => e.id == id);
    await saveServers(list);
  }

  static String _newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  // ---- profiles ("Who's watching") -----------------------------------------

  static Future<List<Profile>> loadProfiles() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kProfiles);
    return raw == null ? [] : Profile.decodeList(raw);
  }

  static Future<void> saveProfiles(List<Profile> profiles) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kProfiles, Profile.encodeList(profiles));
  }

  static Future<String?> activeProfileId() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kActiveProfile);
  }

  static Future<void> setActiveProfileId(String id) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kActiveProfile, id);
  }

  // ---- per-profile favorites -------------------------------------------

  static Future<Set<String>> favorites(String? profileId) async {
    final p = await SharedPreferences.getInstance();
    return (p.getStringList(_kFavPrefix + (profileId ?? 'shared')) ?? []).toSet();
  }

  static Future<void> setFavorites(String? profileId, Set<String> ids) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kFavPrefix + (profileId ?? 'shared'), ids.toList());
  }

  // ---- OTA: "skip this version" ------------------------------------------

  static Future<int?> otaSkippedBuild() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_kOtaSkip);
  }

  static Future<void> setOtaSkippedBuild(int build) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kOtaSkip, build);
  }
}
