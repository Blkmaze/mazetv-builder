import 'dart:async';
import 'package:flutter/material.dart';
import '../models/channel.dart';
import '../services/channel_repo.dart';
import '../services/storage.dart';
import 'live_preview.dart';
import 'player_screen.dart';
import 'tv_widgets.dart';

const String kFavoritesGroup = '★ Favorites';

/// Live TV, the way Ghost lays it out: categories down the left, and the
/// selected category's channels on the right rendered as a timeline guide —
/// half-hour columns across the top, programme blocks sized by duration,
/// and a vertical "now" line. Every category gets its own guide; it isn't a
/// separate screen. A muted live preview of the highlighted channel sits
/// above it all.
class LiveChannelsScreen extends StatefulWidget {
  final String? initialSearch;
  const LiveChannelsScreen({super.key, this.initialSearch});
  @override
  State<LiveChannelsScreen> createState() => _LiveChannelsScreenState();
}

class _LiveChannelsScreenState extends State<LiveChannelsScreen> {
  final repo = ChannelRepo.I;
  String? group;
  String search = '';
  String? activeProfileId;
  Set<String> favorites = {};
  Channel? previewChannel;
  Timer? _clock;

  // Timeline geometry (shared by the header and every row so they line up).
  static const _nameColWidth = 230.0;
  static const _windowHours = 3;

  @override
  void initState() {
    super.initState();
    search = widget.initialSearch ?? '';
    _boot();
    // Redraw once a minute so the "now" line and the clock stay honest.
    _clock = Timer.periodic(const Duration(minutes: 1), (_) { if (mounted) setState(() {}); });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _boot() async {
    activeProfileId = await Storage.activeProfileId();
    favorites = await Storage.favorites(activeProfileId);
    group = repo.groups.isEmpty ? null : repo.groups.first;
    if (!mounted) return;
    setState(() {
      final inGroup = repo.inGroup(group ?? '');
      previewChannel = inGroup.isNotEmpty ? inGroup.first : (repo.channels.isEmpty ? null : repo.channels.first);
    });
    // Guide data may still be streaming in — repaint when it lands.
    if (!repo.epg.loaded) {
      repo.loadEpg().then((_) { if (mounted) setState(() {}); });
    }
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

  /// Window starts at the most recent half-hour boundary so the "now" line
  /// sits a little way in from the left edge rather than on it.
  DateTime get _windowStart {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, now.hour, now.minute < 30 ? 0 : 30);
  }

  @override
  Widget build(BuildContext context) {
    final groups = [kFavoritesGroup, ...repo.groups];
    List<Channel> channels;
    if (search.isNotEmpty) {
      channels = repo.channels.where((c) => c.name.toLowerCase().contains(search.toLowerCase())).toList();
    } else if (group == kFavoritesGroup || group == null) {
      channels = repo.channels.where((c) => favorites.contains(c.id)).toList();
    } else {
      channels = repo.inGroup(group!);
    }
    final windowStart = _windowStart;

    return Scaffold(
      appBar: AppBar(
        title: Text(search.isNotEmpty ? 'Live — "$search"' : 'Live'),
        actions: [
          if (search.isNotEmpty)
            IconButton(icon: const Icon(Icons.close), tooltip: 'Clear search', onPressed: () => setState(() => search = '')),
          IconButton(icon: const Icon(Icons.search), tooltip: 'Search', onPressed: _openSearch),
        ],
      ),
      body: Column(children: [
        LivePreviewStrip(key: const ValueKey('live-preview'), channel: previewChannel),
        const Divider(height: 1),
        Expanded(
          child: Row(children: [
            // ---- categories
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
            // ---- this category's guide
            Expanded(
              child: Column(children: [
                _TimelineHeader(windowStart: windowStart, hours: _windowHours, nameColWidth: _nameColWidth),
                const Divider(height: 1),
                Expanded(
                  child: channels.isEmpty
                      ? Center(child: Text(group == kFavoritesGroup ? 'No favorites yet — hold OK on a channel to add one' : 'No channels'))
                      : ListView.builder(
                          itemCount: channels.length,
                          itemBuilder: (_, i) {
                            final c = channels[i];
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
                              title: Row(children: [
                                SizedBox(
                                  width: _nameColWidth,
                                  child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                ),
                                Expanded(
                                  child: _TimelineCell(
                                    channel: c,
                                    windowStart: windowStart,
                                    hours: _windowHours,
                                  ),
                                ),
                              ]),
                              trailing: SizedBox(
                                width: 24,
                                child: isFav ? const Icon(Icons.star, color: Colors.amber, size: 20) : null,
                              ),
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
}

/// "Sat, 10:23 PM" over the channel-name column, then half-hour labels
/// across the timeline area — aligned to the same geometry as the rows.
class _TimelineHeader extends StatelessWidget {
  final DateTime windowStart;
  final int hours;
  final double nameColWidth;
  const _TimelineHeader({required this.windowStart, required this.hours, required this.nameColWidth});

  // ListTile: 16 padding + 74 leading + 16 gap before the title.
  static const _leadIn = 16.0 + 74 + 16;
  // ListTile: 16 gap + 24 trailing + 16 padding after the title.
  static const _tailOut = 16.0 + 24 + 16;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final slots = hours * 2;
    return SizedBox(
      height: 34,
      child: Row(children: [
        SizedBox(
          width: _leadIn + nameColWidth,
          child: Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('${_weekday(now)}, ${fmt12(now)}',
                  style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 13, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(builder: (_, box) {
            final slotW = box.maxWidth / slots;
            return Stack(children: [
              for (var i = 0; i < slots; i++)
                Positioned(
                  left: i * slotW, top: 0, bottom: 0,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(fmt12(windowStart.add(Duration(minutes: 30 * i))),
                        style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  ),
                ),
            ]);
          }),
        ),
        const SizedBox(width: _tailOut),
      ]),
    );
  }

  static String _weekday(DateTime t) => const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][t.weekday - 1];
}

/// One channel's programme blocks laid out on the shared time axis, with
/// the vertical "now" line. Blocks are visual only — the whole row is the
/// focus target, so up/down browses channels and OK plays.
class _TimelineCell extends StatelessWidget {
  final Channel channel;
  final DateTime windowStart;
  final int hours;
  const _TimelineCell({required this.channel, required this.windowStart, required this.hours});

  @override
  Widget build(BuildContext context) {
    final repo = ChannelRepo.I;
    final accent = Theme.of(context).colorScheme.primary;
    final windowEnd = windowStart.add(Duration(hours: hours));
    final windowMin = hours * 60;
    final now = DateTime.now();

    return SizedBox(
      height: 40,
      child: LayoutBuilder(builder: (_, box) {
        final pxPerMin = box.maxWidth / windowMin;
        final nowX = now.difference(windowStart).inMinutes * pxPerMin;

        Widget content;
        if (!repo.epg.loaded) {
          content = const Align(alignment: Alignment.centerLeft,
              child: Text('Loading guide…', style: TextStyle(color: Colors.white38, fontSize: 13)));
        } else {
          final progs = (repo.epg.byChannel[channel.epgId] ?? const <Programme>[])
              .where((p) => p.stop.isAfter(windowStart) && p.start.isBefore(windowEnd))
              .toList();
          if (progs.isEmpty) {
            content = const Align(alignment: Alignment.centerLeft,
                child: Text('No programme info', style: TextStyle(color: Colors.white38, fontSize: 13)));
          } else {
            content = Stack(children: [
              for (final p in progs)
                _block(p, windowStart, windowEnd, pxPerMin, box.maxWidth, accent, now),
            ]);
          }
        }

        return Stack(children: [
          Positioned.fill(child: content),
          // the "now" line, drawn on every row so it reads as one continuous line
          Positioned(left: nowX.clamp(0.0, box.maxWidth).toDouble(), top: 0, bottom: 0, width: 2,
              child: Container(color: accent.withOpacity(0.9))),
        ]);
      }),
    );
  }

  Widget _block(Programme p, DateTime ws, DateTime we, double pxPerMin, double maxW, Color accent, DateTime now) {
    final s = p.start.isBefore(ws) ? ws : p.start;
    final e = p.stop.isAfter(we) ? we : p.stop;
    final left = s.difference(ws).inMinutes * pxPerMin;
    final width = (e.difference(s).inMinutes * pxPerMin).clamp(0.0, maxW - left).toDouble();
    final onNow = p.isOnAt(now);
    return Positioned(
      left: left, top: 4, bottom: 4, width: width,
      child: Container(
        margin: const EdgeInsets.only(right: 3),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: onNow ? accent.withOpacity(0.55) : Colors.white12,
          borderRadius: BorderRadius.circular(5),
        ),
        alignment: Alignment.centerLeft,
        child: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: onNow ? Colors.white : Colors.white70)),
      ),
    );
  }
}

/// 12-hour clock like Ghost's ("9:30 PM").
String fmt12(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
}
