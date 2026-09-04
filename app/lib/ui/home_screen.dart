import 'package:flutter/material.dart';
import '../config/branding.dart';
import '../models/channel.dart';
import '../services/channel_repo.dart';
import '../services/storage.dart';
import 'guide_screen.dart';
import 'login_screen.dart';
import 'player_screen.dart';
import 'tv_widgets.dart';
import 'vpn_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final repo = ChannelRepo.I;
  bool loading = true;
  String? group;
  String search = '';

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      if (repo.channels.isEmpty) {
        final a = await Storage.loadAccount();
        if (a == null) { _logout(); return; }
        await repo.load(a, fallbackEpg: Branding.I.epgUrl);
      }
      group = repo.groups.isEmpty ? null : repo.groups.first;
      setState(() => loading = false);
      repo.loadEpg().then((_) { if (mounted) setState(() {}); });
    } catch (e) {
      if (!mounted) return;
      await showError(context, e);
      _logout();
    }
  }

  void _logout() async {
    await Storage.clear();
    repo.channels = [];
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  void _play(List<Channel> list, int index) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(playlist: list, index: index)));
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final groups = repo.groups;
    final channels = search.isEmpty
        ? (group == null ? repo.channels : repo.inGroup(group!))
        : repo.channels.where((c) => c.name.toLowerCase().contains(search.toLowerCase())).toList();

    return Scaffold(
      body: Row(children: [
        // ---- left rail: menu + categories
        SizedBox(
          width: 300,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
              child: Text(Branding.I.appName,
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Branding.I.primaryColor)),
            ),
            TvTile(leading: const Icon(Icons.grid_view), title: const Text('TV Guide'),
                onSelect: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GuideScreen()))),
            TvTile(leading: const Icon(Icons.vpn_lock), title: const Text('VPN'),
                onSelect: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VpnScreen()))),
            TvTile(leading: const Icon(Icons.search), title: const Text('Search'), onSelect: _openSearch),
            TvTile(leading: const Icon(Icons.logout), title: const Text('Sign out'), onSelect: _logout),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: groups.length,
                itemBuilder: (_, i) => TvTile(
                  autofocus: i == 0,
                  selected: groups[i] == group && search.isEmpty,
                  title: Text(groups[i], maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Text('${repo.inGroup(groups[i]).length}', style: const TextStyle(color: Colors.white38)),
                  onSelect: () => setState(() { group = groups[i]; search = ''; }),
                ),
              ),
            ),
          ]),
        ),
        const VerticalDivider(width: 1),
        // ---- right: channel list
        Expanded(
          child: channels.isEmpty
              ? const Center(child: Text('No channels'))
              : ListView.builder(
                  itemCount: channels.length,
                  itemBuilder: (_, i) {
                    final c = channels[i];
                    final now = repo.epg.nowPlaying(c.epgId);
                    return TvTile(
                      leading: ChannelLogo(c.logo),
                      title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: now == null ? null
                          : Text('${_hm(now.start)}–${_hm(now.stop)}  ${now.title}',
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60)),
                      onSelect: () => _play(channels, i),
                    );
                  },
                ),
        ),
      ]),
    );
  }

  void _openSearch() async {
    final c = TextEditingController(text: search);
    final r = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Search channels'),
        content: TextField(controller: c, autofocus: true, onSubmitted: (v) => Navigator.pop(context, v)),
        actions: [TextButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Search'))],
      ),
    );
    if (r != null) setState(() => search = r.trim());
  }

  static String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
