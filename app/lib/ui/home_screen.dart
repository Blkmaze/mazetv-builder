import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/branding.dart';
import '../models/channel.dart';
import '../models/profile.dart';
import '../models/vod.dart';
import '../services/channel_repo.dart';
import '../services/ota_service.dart';
import '../services/storage.dart';
import 'catchup_screen.dart';
import 'live_channels_screen.dart';
import 'login_screen.dart';
import 'movies_screen.dart';
import 'multiview_screen.dart';
import 'pin_screen.dart';
import 'player_screen.dart';
import 'profiles_screen.dart';
import 'recordings_screen.dart';
import 'series_detail_screen.dart';
import 'series_screen.dart';
import 'servers_screen.dart';
import 'settings_screen.dart';
import 'tv_widgets.dart';
import 'vod_player_screen.dart';
import 'watch_party_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final repo = ChannelRepo.I;
  bool loading = true;
  String? activeProfileId;
  List<Channel> mostWatched = [];

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

      await _loadMostWatched();
      // Posters are the whole point of this page — worth the wait, and the
      // API calls are skipped entirely for an M3U source (supportsVod false).
      if (repo.supportsVod) {
        if (repo.vodItems.isEmpty) await repo.loadVod();
        if (repo.seriesItems.isEmpty) await repo.loadSeries();
      }

      if (!mounted) return;
      setState(() => loading = false);
      repo.loadEpg();
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
        builder: (_) => _UpdateDialog(update: update),
      );
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
    final pin = await Storage.settingsPin();
    if (pin != null) {
      if (!mounted) return;
      final entered = await Navigator.push<String>(
          context, MaterialPageRoute(builder: (_) => const PinScreen(title: 'Enter PIN')));
      if (entered != pin) {
        if (entered != null && mounted) await showError(context, Exception('Incorrect PIN'));
        return;
      }
    }
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
    if (mounted) setState(() {});
  }

  Future<void> _openLive({String? search}) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => LiveChannelsScreen(initialSearch: search)));
    await _loadMostWatched();
  }

  void _openSearch() async {
    final c = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Search channels'),
        content: TextField(controller: c, autofocus: true, onSubmitted: (v) => Navigator.pop(context, v)),
        actions: [TextButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Search'))],
      ),
    );
    if (r != null && r.trim().isNotEmpty) _openLive(search: r.trim());
  }

  Future<void> _playMostWatched(int index) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(playlist: mostWatched, index: index)));
    await _loadMostWatched();
  }

  Future<void> _loadMostWatched() async {
    final ids = await Storage.mostWatchedChannelIds();
    final byId = {for (final c in repo.channels) c.id: c};
    final list = [for (final id in ids) if (byId[id] != null) byId[id]!];
    if (mounted) setState(() => mostWatched = list);
  }

  Future<void> _clearMostWatched() async {
    await Storage.clearMostWatched();
    if (mounted) setState(() => mostWatched = []);
  }

  void _openMovie(VodItem v) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => VodPlayerScreen(item: v)));
  }

  void _openSeries(SeriesItem s) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => SeriesDetailScreen(series: s)));
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      body: Column(children: [
        // ---- top brand bar
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            if (Branding.I.hasCustomLogo) ...[
              Image.asset('assets/logo.png', height: 32, width: 32, fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox()),
              const SizedBox(width: 10),
            ],
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
                  autofocus: !(repo.supportsVod && repo.vodItems.isNotEmpty), onSelect: () {}),
              TvRailTile(icon: Icons.live_tv, label: 'Live', expanded: expanded, onSelect: () => _openLive()),
              TvRailTile(icon: Icons.history, label: 'Catchup', expanded: expanded,
                  onSelect: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CatchupScreen()))),
              TvRailTile(icon: Icons.movie, label: 'Movies', expanded: expanded,
                  onSelect: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MoviesScreen()))),
              TvRailTile(icon: Icons.video_library, label: 'Series', expanded: expanded,
                  onSelect: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SeriesScreen()))),
              TvRailTile(icon: Icons.groups, label: 'Watch Party', expanded: expanded,
                  onSelect: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WatchPartyScreen()))),
              TvRailTile(icon: Icons.grid_view, label: 'Multiview', expanded: expanded,
                  onSelect: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MultiviewScreen()))),
              TvRailTile(icon: Icons.fiber_manual_record, label: 'Recordings', expanded: expanded,
                  onSelect: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RecordingsScreen()))),
              const SizedBox(height: 24),
              TvRailTile(icon: Icons.settings, label: 'Settings', expanded: expanded, onSelect: _openSettings),
              const SizedBox(height: 8),
            ]),
            const VerticalDivider(width: 1),
            // ---- discovery: most-watched channels, then Movies/Series posters
            Expanded(
              child: ListView(padding: const EdgeInsets.symmetric(vertical: 16), children: [
                if (mostWatched.isNotEmpty) ...[
                  _RowHeader(
                    title: 'Your Most Watched Channels',
                    trailing: TextButton.icon(
                      onPressed: _clearMostWatched,
                      icon: const Icon(Icons.delete_outline, size: 18, color: Colors.white54),
                      label: const Text('Clear most watched', style: TextStyle(color: Colors.white54, fontSize: 13)),
                    ),
                  ),
                  SizedBox(
                    height: 96,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      scrollDirection: Axis.horizontal,
                      itemCount: mostWatched.length,
                      itemBuilder: (_, i) => Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: _MostWatchedTile(channel: mostWatched[i], onSelect: () => _playMostWatched(i)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (repo.supportsVod && repo.vodItems.isNotEmpty) ...[
                  const _RowHeader(title: 'Popular Movies'),
                  SizedBox(
                    height: 190,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      scrollDirection: Axis.horizontal,
                      itemCount: repo.vodItems.length.clamp(0, 20).toInt(),
                      itemBuilder: (_, i) {
                        final v = repo.vodItems[i];
                        return Padding(
                          padding: const EdgeInsets.only(right: 14),
                          child: SizedBox(
                            width: 120,
                            child: PosterTile(title: v.name, cover: v.cover, autofocus: i == 0, onSelect: () => _openMovie(v)),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (repo.supportsVod && repo.seriesItems.isNotEmpty) ...[
                  const _RowHeader(title: 'Popular Series'),
                  SizedBox(
                    height: 190,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      scrollDirection: Axis.horizontal,
                      itemCount: repo.seriesItems.length.clamp(0, 20).toInt(),
                      itemBuilder: (_, i) {
                        final s = repo.seriesItems[i];
                        return Padding(
                          padding: const EdgeInsets.only(right: 14),
                          child: SizedBox(
                            width: 120,
                            child: PosterTile(title: s.name, cover: s.cover, onSelect: () => _openSeries(s)),
                          ),
                        );
                      },
                    ),
                  ),
                ],
                if (mostWatched.isEmpty && (!repo.supportsVod || (repo.vodItems.isEmpty && repo.seriesItems.isEmpty)))
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      repo.supportsVod
                          ? 'Watch a few channels to see them here.'
                          : 'Movies and Series need an Xtream login — not available for an M3U playlist source.\n\nWatch a few channels to see them here.',
                      style: const TextStyle(color: Colors.white54),
                    ),
                  ),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _RowHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const _RowHeader({required this.title, this.trailing});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
      child: Row(children: [
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const Spacer(),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// One tile in the "Your Most Watched Channels" row — logo + name,
/// focusable so it's reachable and playable straight from the remote.
class _MostWatchedTile extends StatelessWidget {
  final Channel channel;
  final VoidCallback onSelect;
  const _MostWatchedTile({required this.channel, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      child: Builder(builder: (ctx) {
        final focused = Focus.of(ctx).hasFocus;
        return InkWell(
          onTap: onSelect,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 140,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: focused ? primary.withOpacity(0.25) : Colors.white10,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: focused ? primary : Colors.transparent, width: 2),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              ChannelLogo(channel.logo, size: 40),
              const SizedBox(height: 6),
              Text(channel.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
            ]),
          ),
        );
      }),
    );
  }
}


/// The "update available" dialog. It owns its own FocusNode and forces
/// focus onto "Update now" after the first frame — relying on `autofocus`
/// alone loses a race with the Home screen underneath (which has already
/// grabbed focus by the time the network check finishes), leaving the
/// button visible but unselectable from the remote.
class _UpdateDialog extends StatefulWidget {
  final OtaUpdate update;
  const _UpdateDialog({required this.update});
  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  final _updateFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _updateFocus.dispose();
    super.dispose();
  }

  static String _formatSize(int bytes) =>
      bytes < 1024 * 1024 ? '${(bytes / 1024).round()} KB' : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    final update = widget.update;
    return Dialog(
      backgroundColor: const Color(0xFF15161C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 36, 32, 28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white70, width: 2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.file_download_outlined, color: Colors.white70, size: 30),
          ),
          const SizedBox(height: 20),
          const Text('Update available', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text(
            'A new version (build ${update.build}) is available.'
            '${update.sizeBytes > 0 ? ' (${_formatSize(update.sizeBytes)})' : ''}',
            textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70),
          ),
          Text('You are on build ${Branding.I.buildNumber}.',
              textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: TvButton(
              label: 'Update now',
              icon: Icons.file_download_outlined,
              focusNode: _updateFocus,
              onPressed: () => Navigator.pop(context, 'update'),
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => Navigator.pop(context, 'later'),
            child: const Text('Remind me later', style: TextStyle(color: Colors.white54)),
          ),
        ]),
      ),
    );
  }
}
