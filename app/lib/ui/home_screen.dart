import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
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
import 'update_screen.dart';
import 'movie_detail_screen.dart';
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
  String _backdrop = '';

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
        repo.hdOnly = await Storage.hdOnly();
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
      if (!mounted) return;
      setState(() => loading = false);
      // Catalogs can be thousands of titles — never hold the whole screen
      // hostage for them. The rows fill in as each one lands.
      _loadCatalogs();
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
      await Navigator.push(context, MaterialPageRoute(builder: (_) => UpdateScreen(update: update)));
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

  /// Back on the Home screen: Ghost-style "Exit?" box instead of just quitting.
  Future<void> _confirmExit() async {
    final leave = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final primary = Theme.of(ctx).colorScheme.primary;
        return AlertDialog(
          backgroundColor: const Color(0xFF14171F),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: primary.withOpacity(0.5), width: 1.5),
          ),
          contentPadding: const EdgeInsets.fromLTRB(28, 26, 28, 10),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Image.asset('assets/logo.png', height: 44, width: 44, fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Icon(Icons.power_settings_new, size: 44, color: primary)),
            const SizedBox(height: 14),
            Text('Exit ${Branding.I.appName}?',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Are you sure you want to close the app?',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white60, fontSize: 15)),
          ]),
          actionsAlignment: MainAxisAlignment.center,
          actionsPadding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          actions: [
            _ExitButton(label: 'Cancel', autofocus: true, onPressed: () => Navigator.pop(ctx, false)),
            const SizedBox(width: 12),
            _ExitButton(label: 'Exit', filled: true, onPressed: () => Navigator.pop(ctx, true)),
          ],
        );
      },
    );
    if (leave == true) SystemNavigator.pop();
  }

  void _openSearch() async {
    final c = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Search channels & programs'),
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

  bool _catalogsLoading = false;
  String? _catalogError;

  Future<void> _loadCatalogs() async {
    if (!repo.supportsVod || _catalogsLoading) return;
    _catalogsLoading = true;
    _catalogError = null;
    if (mounted) setState(() {});
    try {
      if (repo.vodItems.isEmpty) {
        try { await repo.loadVod(); } catch (e) { _catalogError = 'Movies: ${scrubSecrets(e)}'; }
        if (mounted) setState(() {});
      }
      if (repo.seriesItems.isEmpty) {
        try { await repo.loadSeries(); } catch (e) {
          _catalogError = '${_catalogError == null ? '' : '$_catalogError\n'}Series: ${scrubSecrets(e)}';
        }
        if (mounted) setState(() {});
      }
      // Real "popular": TMDB's weekly trending, filtered to what this
      // provider has. Silently skipped when no key was baked into the build.
      try { await repo.loadTrending(Branding.I.tmdbApiKey); } catch (_) {}
      if (mounted) setState(() {});
    } finally {
      _catalogsLoading = false;
      if (mounted) setState(() {});
    }
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
    Navigator.push(context, MaterialPageRoute(builder: (_) => MovieDetailScreen(item: v)));
  }

  void _openSeries(SeriesItem s) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => SeriesDetailScreen(series: s)));
  }

  void _setBackdrop(String cover) {
    if (cover != _backdrop && mounted) setState(() => _backdrop = cover);
  }

  /// Top bar: logo (Hero landing spot for the splash), app name, active server.
  Widget _brandBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Hero(
          tag: 'brand-logo',
          child: Image.asset('assets/logo.png', height: 32, width: 32, fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox()),
        ),
        const SizedBox(width: 10),
        Text(Branding.I.appName,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Branding.I.primaryColor)),
        if (repo.activeServer != null) ...[
          const SizedBox(width: 14),
          Text('via ${repo.activeServer!.nickname}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Scaffold(
        body: Column(children: [
          _brandBar(),
          const Divider(height: 1),
          const Expanded(child: Center(child: CircularProgressIndicator())),
        ]),
      );
    }
    final popularMovies = repo.supportsVod ? repo.popularMovies : const <VodItem>[];
    final popularSeries = repo.supportsVod ? repo.popularSeries : const <SeriesItem>[];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
      body: Stack(children: [
        // ---- blurred backdrop of whichever poster is highlighted (Ghost-style)
        Positioned.fill(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: _backdrop.isEmpty
                ? const SizedBox.shrink()
                : SizedBox.expand(
                    key: ValueKey(_backdrop),
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                      child: Opacity(
                        opacity: 0.6,
                        // explicit size: inside the fade animation the image would
                        // otherwise shrink to its own dimensions and show as a "card"
                        child: Image.network(_backdrop, fit: BoxFit.cover, width: double.infinity, height: double.infinity,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                      ),
                    ),
                  ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Colors.black.withOpacity(0.15), Colors.black.withOpacity(0.85)],
              ),
            ),
          ),
        ),
        Column(children: [
        _brandBar(),
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
                  const _RowHeader(title: 'Your Most Watched Channels'),
                  SizedBox(
                    height: _MostWatchedTile.rowHeight,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      scrollDirection: Axis.horizontal,
                      itemCount: mostWatched.length,
                      itemBuilder: (_, i) => Padding(
                        padding: const EdgeInsets.only(right: 14),
                        child: _MostWatchedTile(channel: mostWatched[i], onSelect: () => _playMostWatched(i)),
                      ),
                    ),
                  ),
                  // Ghost puts "Clear most watched" under the row, on the left.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 6, 20, 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _clearMostWatched,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white70,
                          overlayColor: Theme.of(context).colorScheme.primary,
                        ),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Clear most watched', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ],
                if (repo.supportsVod && popularMovies.isNotEmpty) ...[
                  _RowHeader(title: repo.popularIsTrending ? 'Popular Movies' : 'New Movies'),
                  SizedBox(
                    height: 190,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      scrollDirection: Axis.horizontal,
                      itemCount: popularMovies.length,
                      itemBuilder: (_, i) {
                        final v = popularMovies[i];
                        return Padding(
                          padding: const EdgeInsets.only(right: 14),
                          child: SizedBox(
                            width: 120,
                            child: PosterTile(
                              title: v.year > 0 && !v.name.contains('${v.year}') ? '${v.name} (${v.year})' : v.name,
                              cover: v.cover,
                              autofocus: i == 0,
                              onFocusChange: (has) { if (has) _setBackdrop(v.cover); },
                              onSelect: () => _openMovie(v),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (repo.supportsVod && popularSeries.isNotEmpty) ...[
                  _RowHeader(title: repo.popularIsTrending ? 'Popular Series' : 'New Series'),
                  SizedBox(
                    height: 190,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      scrollDirection: Axis.horizontal,
                      itemCount: popularSeries.length,
                      itemBuilder: (_, i) {
                        final s = popularSeries[i];
                        return Padding(
                          padding: const EdgeInsets.only(right: 14),
                          child: SizedBox(
                            width: 120,
                            child: PosterTile(
                              title: s.year > 0 && !s.name.contains('${s.year}') ? '${s.name} (${s.year})' : s.name,
                              cover: s.cover,
                              onFocusChange: (has) { if (has) _setBackdrop(s.cover); },
                              onSelect: () => _openSeries(s),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
                if (repo.supportsVod && _catalogsLoading && popularMovies.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 24, 20, 8),
                    child: Row(children: [
                      SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 12),
                      Text('Loading movies & series…', style: TextStyle(color: Colors.white54)),
                    ]),
                  ),
                if (_catalogError != null && !_catalogsLoading)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Row(children: [
                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                      const SizedBox(width: 10),
                      Expanded(child: Text('Couldn\'t load the catalog — $_catalogError',
                          maxLines: 3, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white70, fontSize: 13))),
                      const SizedBox(width: 12),
                      TvButton(label: 'Retry', icon: Icons.refresh, onPressed: _loadCatalogs),
                    ]),
                  ),
                if (mostWatched.isEmpty && popularMovies.isEmpty && popularSeries.isEmpty && !_catalogsLoading && _catalogError == null)
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
      ]),
      ),
    );
  }
}

/// Focusable button for the exit box — plain outline for Cancel, accent fill for Exit.
class _ExitButton extends StatelessWidget {
  final String label;
  final bool filled;
  final bool autofocus;
  final VoidCallback onPressed;
  const _ExitButton({required this.label, required this.onPressed, this.filled = false, this.autofocus = false});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Focus(
      autofocus: autofocus,
      child: Builder(builder: (ctx) {
        final focused = Focus.of(ctx).hasFocus;
        return InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 130,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: filled ? (focused ? primary : primary.withOpacity(0.7)) : (focused ? Colors.white12 : Colors.transparent),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: focused ? Colors.white : Colors.white24, width: focused ? 2 : 1),
            ),
            child: Text(label, textAlign: TextAlign.center,
                style: TextStyle(fontSize: 17, fontWeight: focused ? FontWeight.bold : FontWeight.w500)),
          ),
        );
      }),
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

/// One tile in the "Your Most Watched Channels" row, styled like Ghost's:
/// a slate card with the channel logo filling it, the channel name in small
/// text underneath (outside the card), and an accent border + glow when the
/// remote lands on it. Playable straight from the remote.
class _MostWatchedTile extends StatelessWidget {
  static const double cardWidth = 150;
  static const double cardHeight = 112;
  static const double rowHeight = cardHeight + 32; // card + name line + breathing room

  final Channel channel;
  final VoidCallback onSelect;
  const _MostWatchedTile({required this.channel, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Focus(
      child: Builder(builder: (ctx) {
        final focused = Focus.of(ctx).hasFocus;
        return SizedBox(
          width: cardWidth,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            InkWell(
              onTap: onSelect,
              borderRadius: BorderRadius.circular(10),
              child: AnimatedScale(
                scale: focused ? 1.05 : 1.0,
                duration: const Duration(milliseconds: 140),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  width: cardWidth,
                  height: cardHeight,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF232838),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: focused ? primary : Colors.transparent, width: 2),
                    boxShadow: focused
                        ? [BoxShadow(color: primary.withOpacity(0.55), blurRadius: 18, spreadRadius: 1)]
                        : const [],
                  ),
                  child: Center(
                    child: channel.logo.isEmpty
                        ? const Icon(Icons.tv, size: 44, color: Colors.white70)
                        : Image.network(channel.logo, fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Icon(Icons.tv, size: 44, color: Colors.white70)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(channel.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                      color: focused ? Colors.white : Colors.white70)),
            ),
          ]),
        );
      }),
    );
  }
}
