import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/branding.dart';
import '../models/channel.dart';
import '../models/profile.dart';
import '../services/channel_repo.dart';
import '../services/ota_service.dart';
import '../services/storage.dart';
import 'coming_soon_screen.dart';
import 'guide_screen.dart';
import 'live_preview.dart';
import 'login_screen.dart';
import 'player_screen.dart';
import 'profiles_screen.dart';
import 'servers_screen.dart';
import 'settings_screen.dart';
import 'tv_widgets.dart';

const String kFavoritesGroup = '★ Favorites';

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
  String? activeProfileId;
  Set<String> favorites = {};
  Channel? previewChannel;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    setState(() => loading = true);
    try {
      if (repo.channels.isEmpty) {
        final servers = await Storage.loadServers();
        if (servers.isEmpty) { _logout(); return; }
        await repo.loadFailover(servers, fallbackEpg: Branding.I.epgUrl);
      }

      final profiles = await Storage.loadProfiles();
      if (profiles.length > 1 && mounted) {
        final chosen = await Navigator.push<Profile>(
          context,
          MaterialPageRoute<Profile>(builder: (_) => const ProfilesScreen()),
        );
        if (chosen != null) activeProfileId = chosen.id;
      }
      activeProfileId ??= await Storage.activeProfileId();
      favorites = await Storage.favorites(activeProfileId);

      group = repo.groups.isEmpty ? null : repo.groups.first;
      if (!mounted) return;
      setState(() {
        loading = false;
        final inGroup = repo.inGroup(group ?? '');
        previewChannel = inGroup.isNotEmpty ? inGroup.first : (repo.channels.isEmpty ? null : repo.channels.first);
      });
      repo.loadEpg().then((_) { if (mounted) setState(() {}); });
      _checkForUpdate();
    } catch (e) {
      // Don't wipe a working server list just because it's briefly
      // unreachable — send them to Servers to fix/retry instead of forcing
      // a full re-login every time every server is down at once.
      if (!mounted) return;
      await showError(context, e);
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const ServersScreen()));
      repo.channels = [];
      _boot();
    }
  }

  Future<void> _checkForUpdate() async {
    try {
      final update = await OtaService.check();
      if (update == null || !mounted) return;
      final skipped = await Storage.otaSkippedBuild();
      if (skipped == update.build) return;
      if (!mounted) return;
      final choice = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Update available'),
          content: Text('A newer build of ${Branding.I.appName} is ready (build ${update.build}).'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, 'skip'), child: const Text('Skip this version')),
            TextButton(onPressed: () => Navigator.pop(context, 'later'), child: const Text('Later')),
            TextButton(onPressed: () => Navigator.pop(context, 'update'), child: const Text('Update now')),
          ],
        ),
      );
      if (choice == 'skip') await Storage.setOtaSkippedBuild(update.build);
      if (choice == 'update') {
        await launchUrl(Uri.parse(update.downloadUrl), mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      // OTA check is best-effort; never interrupt normal use over it.
    }
  }

  void _logout() async {
    await Storage.clear();
    repo.channels = [];
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  Future<void> _openSettings() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
    if (mounted) setState(() {});
  }

  Future<void> _toggleFavorite(Channel c) async {
    setState(() {
      if (!favorites.remove(c.id)) favorites.add(c.id);
    });
    await Storage.setFavorites(activeProfileId, favorites);
  }

  void _play(List<Channel> list, int index) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(playlist: list, index: index)));
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final groups = [kFavoritesGroup, ...repo.groups];
    List<Channel> channels;
    if (search.isNotEmpty) {
      channels = repo.channels.where((c) => c.name.toLowerCase().contains(search.toLowerCase())).toList();
    } else if (group == kFavoritesGroup || group == null) {
      channels = repo.channels.where((c) => favorites.contains(c.id)).toList();
    } else {
      channels = repo.inGroup(group!);
    }

    return Scaffold(
      body: Column(children: [
        // ---- top brand bar
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Text(Branding.I.appName,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Branding.I.primaryColor)),
            if (repo.activeServer != null) ...[
              const SizedBox(width: 14),
              Text('via ${repo.activeServer!.nickname}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
            ],
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: Row(children: [
            // ---- collapsible icon nav (expands to labels while focus is inside it)
            TvNavRail(itemsBuilder: (expanded) => [
              const SizedBox(height: 8),
              TvRailTile(icon: Icons.search, label: 'Search', expanded: expanded, onSelect: _openSearch),
              TvRailTile(icon: Icons.home, label: 'Home', expanded: expanded,
                  onSelect: () => setState(() { group = repo.groups.isEmpty ? null : repo.groups.first; search = ''; })),
              TvRailTile(icon: Icons.live_tv, label: 'Live', expanded: expanded,
                  onSelect: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GuideScreen()))),
              TvRailTile(icon: Icons.history, label: 'Catchup', expanded: expanded,
                  onSelect: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ComingSoonScreen(title: 'Catchup', icon: Icons.history)))),
              TvRailTile(icon: Icons.movie, label: 'Movies', expanded: expanded,
                  onSelect: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ComingSoonScreen(title: 'Movies', icon: Icons.movie)))),
              TvRailTile(icon: Icons.video_library, label: 'Series', expanded: expanded,
                  onSelect: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ComingSoonScreen(title: 'Series', icon: Icons.video_library)))),
              TvRailTile(icon: Icons.groups, label: 'Watch Party', expanded: expanded,
                  onSelect: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ComingSoonScreen(title: 'Watch Party', icon: Icons.groups)))),
              TvRailTile(icon: Icons.grid_view, label: 'Multiview', expanded: expanded,
                  onSelect: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ComingSoonScreen(title: 'Multiview', icon: Icons.grid_view)))),
              TvRailTile(icon: Icons.fiber_manual_record, label: 'Recordings', expanded: expanded,
                  onSelect: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ComingSoonScreen(title: 'Recordings', icon: Icons.fiber_manual_record)))),
              const SizedBox(height: 24),
              TvRailTile(icon: Icons.settings, label: 'Settings', expanded: expanded, onSelect: _openSettings),
              const SizedBox(height: 8),
            ]),
            const VerticalDivider(width: 1),
            // ---- categories (always visible, its own column)
            SizedBox(
              width: 260,
              child: ListView.builder(
                itemCount: groups.length,
                itemBuilder: (_, i) {
                  final isFav = groups[i] == kFavoritesGroup;
                  final count = isFav ? favorites.length : repo.inGroup(groups[i]).length;
                  return TvTile(
                    autofocus: i == 0,
                    selected: groups[i] == group && search.isEmpty,
                    leading: isFav ? const Icon(Icons.star, color: Colors.amber, size: 18) : null,
                    title: Text(groups[i], maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Text('$count', style: const TextStyle(color: Colors.white38)),
                    onSelect: () => setState(() { group = groups[i]; search = ''; }),
                  );
                },
              ),
            ),
            const VerticalDivider(width: 1),
            // ---- channel list, with a live preview strip pinned above it
            Expanded(
              child: Column(children: [
                LivePreviewStrip(key: ValueKey(previewChannel?.id), channel: previewChannel),
                const Divider(height: 1),
                Expanded(
                  child: channels.isEmpty
                  ? Center(child: Text(group == kFavoritesGroup ? 'No favorites yet — hold OK on a channel to add one' : 'No channels'))
                  : ListView.builder(
                      itemCount: channels.length,
                      itemBuilder: (_, i) {
                        final c = channels[i];
                        final now = repo.epg.nowPlaying(c.epgId);
                        final isFav = favorites.contains(c.id);
                        return TvTile(
                          onFocusChange: (has) { if (has) setState(() => previewChannel = c); },
                          leading: SizedBox(
                        width: 74,
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          SizedBox(width: 28, child: Text('${i + 1}', textAlign: TextAlign.right,
                              style: const TextStyle(color: Colors.white38, fontSize: 15))),
                          const SizedBox(width: 8),
                          ChannelLogo(c.logo),
                        ]),
                      ),
                      title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: now == null ? null
                          : Text('${_hm(now.start)}–${_hm(now.stop)}  ${now.title}',
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60)),
                      trailing: isFav ? const Icon(Icons.star, color: Colors.amber) : null,
                          onSelect: () => _play(channels, i),
                          onLongSelect: () => _toggleFavorite(c),
                        );
                      },
                    ),
                ),
              ]),
            ),
          ]),
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
