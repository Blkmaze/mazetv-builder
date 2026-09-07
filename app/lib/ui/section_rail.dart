import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'catchup_screen.dart';
import 'live_channels_screen.dart';
import 'movies_screen.dart';
import 'multiview_screen.dart';
import 'recordings_screen.dart';
import 'series_screen.dart';
import 'settings_screen.dart';
import 'tv_widgets.dart';
import 'watch_party_screen.dart';

enum AppSection { home, live, catchup, movies, series, watchParty, multiview, recordings }

/// Ghost-style section rail. Home has always had it; now Live, Catchup,
/// Movies and Series carry the same one, so ◀ from the leftmost column lands
/// on the rail and you hop straight to another section instead of pressing
/// Back to Home first.
///
/// Navigation keeps the stack shallow: Home is always the root, and every
/// other section *replaces* the current one, so Back from any section still
/// returns to Home in one press.
class SectionRail extends StatelessWidget {
  final AppSection current;

  /// Given to the tile for [current] so a screen can send focus here
  /// explicitly (◀ from its categories) instead of trusting geometry.
  final FocusNode? railFocus;

  /// Home-only: whether the Home tile should take initial focus.
  final bool homeAutofocus;

  /// Home wires its own search/settings handlers; other screens use the
  /// defaults below.
  final VoidCallback? onSearch;
  final VoidCallback? onSettings;

  /// Home-only: called when a section pushed from Home is popped back to it
  /// (used to refresh the most-watched row).
  final VoidCallback? onReturn;

  const SectionRail({
    super.key,
    required this.current,
    this.railFocus,
    this.homeAutofocus = false,
    this.onSearch,
    this.onSettings,
    this.onReturn,
  });

  Future<void> _go(BuildContext context, AppSection to, WidgetBuilder builder) async {
    if (to == current) return;
    if (to == AppSection.home) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    }
    final route = MaterialPageRoute(builder: builder);
    if (current == AppSection.home) {
      await Navigator.push(context, route); // Home is the root — never replace it
      onReturn?.call();
    } else {
      Navigator.pushReplacement(context, route);
    }
  }

  Future<void> _defaultSearch(BuildContext context) async {
    final c = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Search channels & programs'),
        content: TextField(controller: c, autofocus: true, onSubmitted: (v) => Navigator.pop(ctx, v)),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Search'))],
      ),
    );
    final q = r?.trim() ?? '';
    if (q.isEmpty || !context.mounted) return;
    // Search always lands on Live; from Live itself just refresh in place.
    final route = MaterialPageRoute(builder: (_) => LiveChannelsScreen(initialSearch: q));
    if (current == AppSection.home) {
      await Navigator.push(context, route);
      onReturn?.call();
    } else {
      Navigator.pushReplacement(context, route);
    }
  }

  @override
  Widget build(BuildContext context) {
    FocusNode? nodeFor(AppSection s) => s == current ? railFocus : null;
    return TvNavRail(itemsBuilder: (expanded) => [
      const SizedBox(height: 8),
      TvRailTile(icon: Icons.search, label: 'Search', expanded: expanded,
          onSelect: onSearch ?? () { _defaultSearch(context); }),
      TvRailTile(icon: Icons.home, label: 'Home', expanded: expanded,
          selected: current == AppSection.home, autofocus: homeAutofocus, focusNode: nodeFor(AppSection.home),
          onSelect: () => _go(context, AppSection.home, (_) => const SizedBox())),
      TvRailTile(icon: Icons.live_tv, label: 'Live', expanded: expanded,
          selected: current == AppSection.live, focusNode: nodeFor(AppSection.live),
          onSelect: () => _go(context, AppSection.live, (_) => const LiveChannelsScreen())),
      TvRailTile(icon: Icons.history, label: 'Catchup', expanded: expanded,
          selected: current == AppSection.catchup, focusNode: nodeFor(AppSection.catchup),
          onSelect: () => _go(context, AppSection.catchup, (_) => const CatchupScreen())),
      TvRailTile(icon: Icons.movie, label: 'Movies', expanded: expanded,
          selected: current == AppSection.movies, focusNode: nodeFor(AppSection.movies),
          onSelect: () => _go(context, AppSection.movies, (_) => const MoviesScreen())),
      TvRailTile(icon: Icons.video_library, label: 'Series', expanded: expanded,
          selected: current == AppSection.series, focusNode: nodeFor(AppSection.series),
          onSelect: () => _go(context, AppSection.series, (_) => const SeriesScreen())),
      TvRailTile(icon: Icons.groups, label: 'Watch Party', expanded: expanded,
          selected: current == AppSection.watchParty, focusNode: nodeFor(AppSection.watchParty),
          onSelect: () => _go(context, AppSection.watchParty, (_) => const WatchPartyScreen())),
      TvRailTile(icon: Icons.grid_view, label: 'Multiview', expanded: expanded,
          selected: current == AppSection.multiview, focusNode: nodeFor(AppSection.multiview),
          onSelect: () => _go(context, AppSection.multiview, (_) => const MultiviewScreen())),
      TvRailTile(icon: Icons.fiber_manual_record, label: 'Recordings', expanded: expanded,
          selected: current == AppSection.recordings, focusNode: nodeFor(AppSection.recordings),
          onSelect: () => _go(context, AppSection.recordings, (_) => const RecordingsScreen())),
      const SizedBox(height: 24),
      TvRailTile(icon: Icons.settings, label: 'Settings', expanded: expanded,
          onSelect: onSettings ?? () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
          }),
      const SizedBox(height: 8),
    ]);
  }
}

/// Wrap a screen's leftmost column (its categories list) in this so ◀ from
/// any row jumps to the rail's current-section tile. Flutter's own
/// left-traversal picks whatever focusable widget is geometrically nearest —
/// often the app bar's back arrow or the Settings tile — which is what made
/// "move to another section" feel broken.
class RailLeftEdge extends StatelessWidget {
  final FocusNode railFocus;
  final Widget child;
  const RailLeftEdge({super.key, required this.railFocus, required this.child});

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, e) {
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.arrowLeft) {
          railFocus.requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }
}
