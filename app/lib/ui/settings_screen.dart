import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../config/branding.dart';
import '../services/channel_repo.dart';
import '../services/storage.dart';
import 'login_screen.dart';
import 'tv_widgets.dart';
import 'vpn_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String version = '';
  bool refreshing = false;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((i) {
      if (mounted) setState(() => version = '${i.version} (${i.buildNumber})');
    });
  }

  Future<void> _refresh() async {
    setState(() => refreshing = true);
    try {
      final servers = await Storage.loadServers();
      if (servers.isNotEmpty) await ChannelRepo.I.loadFailover(servers, fallbackEpg: Branding.I.epgUrl);
      ChannelRepo.I.loadEpg();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reloaded ${ChannelRepo.I.channels.length} channels')));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(padding: const EdgeInsets.symmetric(vertical: 12), children: [
          TvTile(
            autofocus: true,
            leading: const Icon(Icons.refresh),
            title: const Text('Refresh channels & guide'),
            subtitle: refreshing ? const Text('Reloading…') : const Text('Re-fetch your channel list and EPG'),
            onSelect: refreshing ? () {} : _refresh,
          ),
          TvTile(
            leading: const Icon(Icons.vpn_lock),
            title: const Text('VPN'),
            onSelect: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VpnScreen())),
          ),
          TvTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            onSelect: _signOut,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline, color: Colors.white38),
            title: Text(Branding.I.appName),
            subtitle: Text(version.isEmpty ? ' ' : 'Version $version'),
          ),
        ]),
      ),
    );
  }
}
