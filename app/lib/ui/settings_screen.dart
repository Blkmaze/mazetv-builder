import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/branding.dart';
import '../services/channel_repo.dart';
import '../services/recording_service.dart';
import '../services/storage.dart';
import 'appearance_screen.dart';
import 'login_screen.dart';
import 'pin_screen.dart';
import 'player_screen.dart';
import 'profiles_screen.dart';
import 'servers_screen.dart';
import 'tv_widgets.dart';
import 'vpn_screen.dart';

const _kResumeLastChannel = 'resume_last_channel';

/// Settings, grouped into sections (General/Connection/Player/Playback/
/// Appearance/Security/Account/Storage) — same idea as most TV IPTV apps'
/// settings screens. Entry to this whole screen is PIN-gated from
/// HomeScreen when a PIN is set, so individual items here don't re-prompt.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String version = '';
  bool refreshing = false;
  bool softwareDecode = false;
  bool resumeLastChannel = false;
  String? pin;
  int recordingCount = 0;
  int recordingBytes = 0;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((i) {
      if (mounted) setState(() => version = '${i.version} (${i.buildNumber})');
    });
    _loadPrefs();
    _loadStorageStats();
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    final savedPin = await Storage.settingsPin();
    if (!mounted) return;
    setState(() {
      softwareDecode = p.getBool(kForceSoftwareDecodeKey) ?? false;
      resumeLastChannel = p.getBool(_kResumeLastChannel) ?? false;
      pin = savedPin;
    });
  }

  Future<void> _loadStorageStats() async {
    final entries = await RecordingService.I.list();
    if (!mounted) return;
    setState(() {
      recordingCount = entries.length;
      recordingBytes = entries.fold<int>(0, (sum, e) => sum + e.bytes);
    });
  }

  Future<void> _setBool(String key, bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(key, value);
  }

  Future<void> _refresh() async {
    setState(() => refreshing = true);
    try {
      final servers = await Storage.loadServers();
      if (servers.isNotEmpty) await ChannelRepo.I.loadFailover(servers, fallbackEpg: Branding.I.epgUrl);
      ChannelRepo.I.loadEpg();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Reloaded ${ChannelRepo.I.channels.length} channels')));
      }
    } catch (e) {
      if (mounted) await showError(context, e);
    } finally {
      if (mounted) setState(() => refreshing = false);
    }
  }

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You\'ll need your login details again next time.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(autofocus: true, onPressed: () => Navigator.pop(context, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (ok != true) return;
    await Storage.clear();
    ChannelRepo.I.channels = [];
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  Future<void> _managePin() async {
    if (pin != null) {
      final entered = await Navigator.push<String>(
          context, MaterialPageRoute(builder: (_) => const PinScreen(title: 'Enter current PIN')));
      if (entered != pin) {
        if (entered != null && mounted) await showError(context, Exception('Incorrect PIN'));
        return;
      }
    }
    if (!mounted) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Settings PIN'),
        content: Text(pin == null
            ? 'Set a 4-digit PIN so channel surfing doesn\'t accidentally land in Settings.'
            : 'Change or remove your Settings PIN.'),
        actions: [
          if (pin != null)
            TextButton(onPressed: () => Navigator.pop(context, 'remove'), child: const Text('Remove PIN')),
          TextButton(autofocus: true, onPressed: () => Navigator.pop(context, 'set'),
              child: Text(pin == null ? 'Set PIN' : 'Change PIN')),
          TextButton(onPressed: () => Navigator.pop(context, 'cancel'), child: const Text('Cancel')),
        ],
      ),
    );
    if (choice == 'remove') {
      await Storage.clearSettingsPin();
      if (mounted) setState(() => pin = null);
      return;
    }
    if (choice == 'set') {
      if (!mounted) return;
      final p1 = await Navigator.push<String>(
          context, MaterialPageRoute(builder: (_) => const PinScreen(title: 'Choose a 4-digit PIN')));
      if (p1 == null || !mounted) return;
      final p2 = await Navigator.push<String>(
          context, MaterialPageRoute(builder: (_) => const PinScreen(title: 'Confirm PIN')));
      if (p2 != p1) {
        if (mounted) await showError(context, Exception('PINs did not match — try again'));
        return;
      }
      await Storage.setSettingsPin(p1);
      if (mounted) setState(() => pin = p1);
    }
  }

  Future<void> _clearRecordings() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete all recordings?'),
        content: const Text('This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete all')),
        ],
      ),
    );
    if (ok == true) {
      await RecordingService.I.clearAll();
      _loadStorageStats();
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = Branding.I;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(padding: const EdgeInsets.symmetric(vertical: 12), children: [
          const _SectionHeader('General'),
          TvTile(
            autofocus: true,
            leading: const Icon(Icons.refresh),
            title: const Text('Refresh channels & guide'),
            subtitle: refreshing ? const Text('Reloading…') : const Text('Re-fetch your channel list and EPG'),
            onSelect: refreshing ? () {} : _refresh,
          ),
          ListTile(
            leading: const Icon(Icons.info_outline, color: Colors.white38),
            title: Text(b.appName),
            subtitle: Text(version.isEmpty ? ' ' : 'Version $version'
                '${b.buildNumber > 0 ? ' · build ${b.buildNumber}' : ''}'),
          ),
          const _SectionHeader('Connection'),
          TvTile(
            leading: const Icon(Icons.dns),
            title: const Text('Servers'),
            subtitle: const Text('Manage Xtream/M3U sources and failover order'),
            onSelect: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const ServersScreen()));
              if (mounted) setState(() {});
            },
          ),
          TvTile(
            leading: const Icon(Icons.vpn_lock),
            title: const Text('VPN'),
            onSelect: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VpnScreen())),
          ),
          const _SectionHeader('Player'),
          SwitchListTile(
            secondary: const Icon(Icons.developer_board),
            title: const Text('Software decoding'),
            subtitle: const Text('Turn on if playback shows a black screen on some channels'),
            value: softwareDecode,
            onChanged: (v) {
              setState(() => softwareDecode = v);
              _setBool(kForceSoftwareDecodeKey, v);
            },
          ),
          const _SectionHeader('Playback'),
          SwitchListTile(
            secondary: const Icon(Icons.play_circle_outline),
            title: const Text('Resume last channel on launch'),
            value: resumeLastChannel,
            onChanged: (v) {
              setState(() => resumeLastChannel = v);
              _setBool(_kResumeLastChannel, v);
            },
          ),
          const _SectionHeader('Appearance'),
          TvTile(
            leading: CircleAvatar(backgroundColor: b.primaryColor, radius: 12),
            title: const Text('Accent color'),
            subtitle: const Text('Change the app\'s color — no rebuild needed'),
            onSelect: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AppearanceScreen())),
          ),
          const _SectionHeader('Security'),
          TvTile(
            leading: Icon(pin == null ? Icons.lock_open : Icons.lock),
            title: Text(pin == null ? 'Set a Settings PIN' : 'Change or remove PIN'),
            subtitle: const Text('Locks this whole Settings screen behind a 4-digit code'),
            onSelect: _managePin,
          ),
          const _SectionHeader('Account'),
          TvTile(
            leading: const Icon(Icons.people),
            title: const Text('Profiles'),
            onSelect: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilesScreen(selecting: false)));
              if (mounted) setState(() {});
            },
          ),
          TvTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            onSelect: _signOut,
          ),
          const _SectionHeader('Storage'),
          ListTile(
            leading: const Icon(Icons.sd_storage_outlined),
            title: const Text('Recordings'),
            subtitle: Text('$recordingCount recording${recordingCount == 1 ? '' : 's'} · ${_size(recordingBytes)}'),
            trailing: recordingCount == 0 ? null : TextButton(onPressed: _clearRecordings, child: const Text('Clear all')),
          ),
        ]),
      ),
    );
  }

  static String _size(int b) =>
      b < 1024 * 1024 ? '${(b / 1024).round()} KB' : '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader(this.label);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(label.toUpperCase(),
          style: TextStyle(fontSize: 12, letterSpacing: 1.1, fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary)),
    );
  }
}
