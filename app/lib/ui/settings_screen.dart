import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../config/branding.dart';
import '../services/channel_repo.dart';
import '../services/storage.dart';
import 'login_screen.dart';
import 'appearance_screen.dart';
import 'pin_screen.dart';
import 'profiles_screen.dart';
import 'servers_screen.dart';
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
  String? pin;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((i) {
      if (mounted) setState(() => version = '${i.version} (${i.buildNumber})');
    });
    Storage.settingsPin().then((p) { if (mounted) setState(() => pin = p); });
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
            leading: const Icon(Icons.lock),
            title: const Text('Settings PIN'),
            subtitle: Text(pin == null ? 'Not set' : 'Enabled — change or remove'),
            onSelect: _managePin,
          ),
          TvTile(
            leading: const Icon(Icons.dns),
            title: const Text('Servers'),
            subtitle: const Text('Manage saved portals and failover order'),
            onSelect: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const ServersScreen()));
              if (mounted) setState(() {});
            },
          ),
          TvTile(
            leading: const Icon(Icons.people),
            title: const Text('Profiles'),
            subtitle: const Text('Manage who\'s watching and their favorites'),
            onSelect: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilesScreen(selecting: false)));
              if (mounted) setState(() {});
            },
          ),
          TvTile(
            leading: const Icon(Icons.palette),
            title: const Text('Appearance'),
            subtitle: const Text('Change the accent color'),
            onSelect: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AppearanceScreen())),
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
