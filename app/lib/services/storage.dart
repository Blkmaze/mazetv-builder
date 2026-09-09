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

  // ---- most-watched channels ("Your Most Watched Channels" row) ----------
  // Recency-ordered, not frequency-counted: watching a channel moves it to
  // the front. Simple, and matches what a viewer expects from "recently
  // watched" — the thing they saw last is the thing at the top.
  static const _kMostWatched = 'most_watched_channels_v1';
  static const _kMostWatchedCap = 10;

  static Future<void> recordWatch(String channelId) async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(_kMostWatched) ?? [];
    list.remove(channelId);
    list.insert(0, channelId);
    if (list.length > _kMostWatchedCap) list.removeRange(_kMostWatchedCap, list.length);
    await p.setStringList(_kMostWatched, list);
  }

  static Future<List<String>> mostWatchedChannelIds() async {
    final p = await SharedPreferences.getInstance();
    return p.getStringList(_kMostWatched) ?? [];
  }

  static Future<void> clearMostWatched() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kMostWatched);
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

  // ---- locked channels (per profile, like favorites) ---------------------
  static const _kLockPrefix = 'locked_v1_';
  static Future<Set<String>> lockedChannels(String? profileId) async {
    final p = await SharedPreferences.getInstance();
    return (p.getStringList(_kLockPrefix + (profileId ?? 'shared')) ?? []).toSet();
  }

  static Future<void> setLockedChannels(String? profileId, Set<String> ids) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kLockPrefix + (profileId ?? 'shared'), ids.toList());
  }

  // ---- multiview: the up-to-4 channels last picked -----------------------
  static const _kMultiview = 'multiview_v1';
  static Future<List<String>> multiviewIds() async =>
      (await SharedPreferences.getInstance()).getStringList(_kMultiview) ?? [];
  static Future<void> setMultiviewIds(List<String> ids) async =>
      (await SharedPreferences.getInstance()).setStringList(_kMultiview, ids);

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

  // ---- appearance: user-chosen accent color, overriding the build default --
  static const _kColorOverride = 'color_override_argb';

  static Future<int?> colorOverride() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_kColorOverride);
  }

  static Future<void> setColorOverride(int argb) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kColorOverride, argb);
  }

  static Future<void> clearColorOverride() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kColorOverride);
  }

  // ---- appearance: background color override -------------------------------
  static const _kBgOverride = 'bg_override_argb';
  static Future<int?> bgOverride() async => (await SharedPreferences.getInstance()).getInt(_kBgOverride);
  static Future<void> setBgOverride(int argb) async => (await SharedPreferences.getInstance()).setInt(_kBgOverride, argb);
  static Future<void> clearBgOverride() async => (await SharedPreferences.getInstance()).remove(_kBgOverride);

  // ---- playback preferences ----------------------------------------------
  static const _kHdOnly = 'hd_only_channels';
  static Future<bool> hdOnly() async => (await SharedPreferences.getInstance()).getBool(_kHdOnly) ?? false;
  static Future<void> setHdOnly(bool v) async => (await SharedPreferences.getInstance()).setBool(_kHdOnly, v);

  /// 0 = small, 1 = medium (default), 2 = large.
  static const _kBufferLevel = 'buffer_level';
  static Future<int> bufferLevel() async => (await SharedPreferences.getInstance()).getInt(_kBufferLevel) ?? 1;
  static Future<void> setBufferLevel(int v) async => (await SharedPreferences.getInstance()).setInt(_kBufferLevel, v);

  // ---- VOD resume positions (seconds), keyed by movie/episode id ------------
  static Future<int?> resumePosition(String id) async => (await SharedPreferences.getInstance()).getInt('resume_$id');
  static Future<void> setResumePosition(String id, int seconds) async =>
      (await SharedPreferences.getInstance()).setInt('resume_$id', seconds);
  static Future<void> clearResumePosition(String id) async => (await SharedPreferences.getInstance()).remove('resume_$id');

  // ---- playback tuning toggles --------------------------------------------
  static const _kSmoothMotion = 'smooth_motion';
  static Future<bool> smoothMotion() async => (await SharedPreferences.getInstance()).getBool(_kSmoothMotion) ?? false;
  static Future<void> setSmoothMotion(bool v) async => (await SharedPreferences.getInstance()).setBool(_kSmoothMotion, v);

  static const _kAltAudio = 'alt_audio_output';
  static Future<bool> altAudio() async => (await SharedPreferences.getInstance()).getBool(_kAltAudio) ?? false;
  static Future<void> setAltAudio(bool v) async => (await SharedPreferences.getInstance()).setBool(_kAltAudio, v);

  // ---- Settings PIN lock --------------------------------------------------
  static const _kPin = 'settings_pin';

  static Future<String?> settingsPin() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kPin);
  }

  static Future<void> setSettingsPin(String pin) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kPin, pin);
  }

  static Future<void> clearSettingsPin() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kPin);
  }
}
