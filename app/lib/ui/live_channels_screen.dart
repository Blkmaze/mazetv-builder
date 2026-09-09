import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/channel.dart';
import '../services/channel_repo.dart';
import '../services/recording_service.dart';
import '../services/storage.dart';
import 'live_preview.dart';
import 'pin_screen.dart';
import 'player_screen.dart';
import 'section_rail.dart';
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
  Set<String> locked = {};
  final previewChannel = ValueNotifier<Channel?>(null);
  int _offsetMin = 0;          // how far the timeline is scrolled ahead of now
  final _listFocus = FocusNode();
  final _catsFocus = FocusNode();
  bool _catsOpen = true;       // categories pane slides away while the guide has focus
  final _railFocus = FocusNode();
  Timer? _clock;

  // Timeline geometry (shared by the header and every row so they line up).
  // A fixed scale — ~100px per half hour, like Ghost — and however many
  // hours fit in the width. Squeezing a fixed 3 hours into whatever was
  // left made 10-minute blocks and overlapping labels on a 1080p TV.
  static const _nameColWidth = 230.0;
  static const _catsWidth = 260.0;

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
    _listFocus.dispose();
    _catsFocus.dispose();
    _railFocus.dispose();
    previewChannel.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    activeProfileId = await Storage.activeProfileId();
    favorites = await Storage.favorites(activeProfileId);
    locked = await Storage.lockedChannels(activeProfileId);
    group = repo.groups.isEmpty ? null : repo.groups.first;
    if (!mounted) return;
    final inGroup = repo.inGroup(group ?? '');
    previewChannel.value = inGroup.isNotEmpty ? inGroup.first : (repo.channels.isEmpty ? null : repo.channels.first);
    setState(() {});
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

  Future<void> _play(List<Channel> list, int index) async {
    if (locked.contains(list[index].id)) {
      final pin = await Storage.settingsPin();
      if (pin != null) {
        if (!mounted) return;
        final entered = await Navigator.push<String>(
            context, MaterialPageRoute(builder: (_) => const PinScreen(title: 'Locked channel — enter PIN')));
        if (entered != pin) {
          if (entered != null && mounted) await showError(context, Exception('Incorrect PIN'));
          return;
        }
      }
    }
    if (!mounted) return;
    // Park the preview while the full player runs — one decoder at a time —
    // and bring it back on the channel we return to.
    final parked = previewChannel.value;
    previewChannel.value = null;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(playlist: list, index: index)));
    if (mounted) previewChannel.value = parked;
  }

  Future<void> _toggleLock(Channel c) async {
    if (!locked.contains(c.id) && await Storage.settingsPin() == null) {
      if (!mounted) return;
      await showError(context, Exception('Set a PIN in Settings first — that PIN unlocks locked channels.'));
      return;
    }
    setState(() {
      if (!locked.remove(c.id)) locked.add(c.id);
    });
    await Storage.setLockedChannels(activeProfileId, locked);
  }

  Future<void> _toggleMultiview(Channel c) async {
    final ids = await Storage.multiviewIds();
    String msg;
    if (ids.contains(c.id)) {
      ids.remove(c.id);
      msg = 'Removed ${c.name} from Multiview';
    } else if (ids.length >= 4) {
      msg = 'Multiview already has 4 channels — remove one first';
    } else {
      ids.add(c.id);
      msg = 'Added ${c.name} to Multiview (${ids.length}/4)';
    }
    await Storage.setMultiviewIds(ids);
    _toast(msg);
  }

  Future<void> _toggleRecord(Channel c) async {
    final rec = RecordingService.I;
    if (rec.isRecording && rec.current?.channelName == c.name) {
      await rec.stop();
      _toast('Stopped recording ${c.name}');
      return;
    }
    final err = await rec.start(c.name, c.streamUrl);
    _toast(err ?? 'Recording ${c.name}');
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
  }

  /// Hold OK on a channel: Ghost-style options box.
  Future<void> _channelMenu(Channel c) async {
    final isFav = favorites.contains(c.id);
    final isLocked = locked.contains(c.id);
    final inMulti = (await Storage.multiviewIds()).contains(c.id);
    final rec = RecordingService.I;
    final recordingThis = rec.isRecording && rec.current?.channelName == c.name;
    if (!mounted) return;

    final action = await showDialog<String>(
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
          titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 10),
          title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          contentPadding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          content: SizedBox(
            width: 320,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _MenuButton(
                icon: isFav ? Icons.favorite : Icons.favorite_border,
                label: isFav ? 'Remove from Favorites' : 'Add to Favorites',
                autofocus: true,
                onPressed: () => Navigator.pop(ctx, 'fav'),
              ),
              _MenuButton(
                icon: isLocked ? Icons.lock_open : Icons.lock_outline,
                label: isLocked ? 'Unlock channel' : 'Lock channel',
                onPressed: () => Navigator.pop(ctx, 'lock'),
              ),
              _MenuButton(
                icon: Icons.grid_view,
                label: inMulti ? 'Remove from Multiview' : 'Add to Multiview',
                onPressed: () => Navigator.pop(ctx, 'multi'),
              ),
              _MenuButton(
                icon: Icons.fiber_manual_record,
                iconColor: Colors.redAccent,
                label: recordingThis ? 'Stop recording' : 'Record',
                onPressed: () => Navigator.pop(ctx, 'rec'),
              ),
            ]),
          ),
          actionsAlignment: MainAxisAlignment.end,
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 24, 14),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              style: TextButton.styleFrom(foregroundColor: primary),
              child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
    switch (action) {
      case 'fav': await _toggleFavorite(c); break;
      case 'lock': await _toggleLock(c); break;
      case 'multi': await _toggleMultiview(c); break;
      case 'rec': await _toggleRecord(c); break;
    }
  }

  void _openSearch() async {
    final c = TextEditingController(text: search);
    final r = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Search channels & programs'),
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
    return DateTime(now.year, now.month, now.day, now.hour, now.minute < 30 ? 0 : 30).add(Duration(minutes: _offsetMin));
  }

  /// ◀ from the categories pane jumps to the section rail; ▶ goes straight
  /// into this category's channel
  /// list (the highlighted channel if there is one, else the first row).
  /// Without this, Flutter's geometry-based traversal often picks the search
  /// icon in the app bar instead, because it's the nearest focusable thing
  /// "to the right" when the category is far down the list.
  KeyEventResult _categoryKeys(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _railFocus.requestFocus(); // ◀ = jump to the section rail
      return KeyEventResult.handled;
    }
    if (e.logicalKey != LogicalKeyboardKey.arrowRight) return KeyEventResult.ignored;
    final rows = _listFocus.traversalDescendants.toList();
    if (rows.isEmpty) return KeyEventResult.handled; // nothing to go to yet — stay put
    FocusNode? target;
    final want = previewChannel.value;
    if (want != null) {
      // Prefer the row whose tile is currently previewed, if it's built.
      for (final n in rows) {
        final ctx = n.context;
        if (ctx != null && _rowChannelOf(ctx)?.id == want.id) { target = n; break; }
      }
    }
    (target ?? rows.first).requestFocus();
    return KeyEventResult.handled;
  }

  /// Walks up from a focus node's context to the TvTile carrying the channel.
  Channel? _rowChannelOf(BuildContext ctx) {
    Channel? found;
    ctx.visitAncestorElements((el) {
      final w = el.widget;
      if (w is _ChannelRowMarker) { found = w.channel; return false; }
      return true;
    });
    return found;
  }

  /// ◀ ▶ while the channel list has focus scroll the timeline by half an
  /// hour; ◀ at "now" falls through so focus can move to the categories.
  KeyEventResult _listKeys(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (_offsetMin < 12 * 60) setState(() => _offsetMin += 30);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (_offsetMin > 0) {
        setState(() => _offsetMin -= 30);
      } else {
        // The pane is collapsed while we're here, so geometry-based
        // traversal can't find it — jump to the selected category by hand.
        _selectedCategoryNode()?.requestFocus();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  FocusNode? _selectedCategoryNode() {
    final nodes = _catsFocus.traversalDescendants.toList();
    for (final n in nodes) {
      final ctx = n.context;
      if (ctx == null) continue;
      var sel = false;
      ctx.visitAncestorElements((el) {
        final w = el.widget;
        if (w is TvTile) { sel = w.selected; return false; }
        return true;
      });
      if (sel) return n;
    }
    return nodes.isEmpty ? null : nodes.first;
  }

  /// Programme search too: a channel matches if its name, or anything on it
  /// in the next 12 hours, contains the query.
  bool _matches(Channel c, String q) {
    if (c.name.toLowerCase().contains(q)) return true;
    for (final p in repo.epg.byChannel[c.epgId] ?? const <Programme>[]) {
      if (p.title.toLowerCase().contains(q)) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final groups = [kFavoritesGroup, ...repo.groups];
    List<Channel> channels;
    if (search.isNotEmpty) {
      final q = search.toLowerCase();
      channels = repo.channels.where((c) => _matches(c, q)).toList();
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
      body: Row(children: [
        SectionRail(current: AppSection.live, railFocus: _railFocus),
        const VerticalDivider(width: 1),
        Expanded(child: Column(children: [
        ValueListenableBuilder<Channel?>(
          valueListenable: previewChannel,
          builder: (_, ch, __) => LivePreviewStrip(key: const ValueKey('live-preview'), channel: ch),
        ),
        const Divider(height: 1),
        Expanded(
          child: Row(children: [
            // ---- categories: full width while browsing them, slid away
            // (still built, so focus can jump back) once the guide has focus
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: _catsOpen ? _catsWidth : 0,
              clipBehavior: Clip.hardEdge,
              decoration: const BoxDecoration(),
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                minWidth: _catsWidth, maxWidth: _catsWidth,
                child: Focus(
                focusNode: _catsFocus,
                canRequestFocus: false,
                skipTraversal: true,
                onFocusChange: (has) { if (has != _catsOpen) setState(() => _catsOpen = has); },
                onKeyEvent: _categoryKeys,
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
              ),
            ),
            const VerticalDivider(width: 1),
            // ---- this category's guide
            Expanded(
              child: Column(children: [
                _TimelineHeader(windowStart: windowStart, nameColWidth: _nameColWidth, scrolled: _offsetMin > 0),
                const Divider(height: 1),
                Expanded(
                  child: channels.isEmpty
                      ? Center(child: Text(search.isNotEmpty
                          ? 'Nothing matches "$search"'
                          : group == kFavoritesGroup ? 'No favorites yet — hold OK on a channel to add one' : 'No channels'))
                      : Focus(
                          focusNode: _listFocus,
                          canRequestFocus: false,
                          skipTraversal: true,
                          onKeyEvent: _listKeys,
                          child: ListView.builder(
                          itemCount: channels.length,
                          itemExtent: 80,
                          itemBuilder: (_, i) {
                            final c = channels[i];
                            final isFav = favorites.contains(c.id);
                            return _ChannelRowMarker(
                              channel: c,
                              child: TvTile(
                              onFocusChange: (has) { if (has) previewChannel.value = c; },
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
                                  child: Text(c.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 14, height: 1.15)),
                                ),
                                Expanded(
                                  child: _TimelineCell(
                                    channel: c,
                                    windowStart: windowStart,
                                  ),
                                ),
                              ]),
                              trailing: SizedBox(
                                width: 24,
                                child: locked.contains(c.id)
                                    ? const Icon(Icons.lock, color: Colors.white54, size: 18)
                                    : isFav ? const Icon(Icons.star, color: Colors.amber, size: 20) : null,
                              ),
                              onSelect: () => _play(channels, i),
                              onLongSelect: () => _channelMenu(c),
                            ),
                            );
                          },
                        ),
                        ),
                ),
              ]),
            ),
          ]),
        ),
        ])),
      ]),
    );
  }
}

/// "Sat, 10:23 PM" over the channel-name column, then half-hour labels
/// across the timeline area — aligned to the same geometry as the rows.
/// Pixels per minute of guide time. 30 min ≈ 100px reads well from a couch.
const double kGuidePxPerMin = 3.4;

class _TimelineHeader extends StatelessWidget {
  final DateTime windowStart;
  final double nameColWidth;
  final bool scrolled;
  const _TimelineHeader({required this.windowStart, required this.nameColWidth, this.scrolled = false});

  // ListTile: 16 padding + 74 leading + 16 gap before the title.
  static const _leadIn = 16.0 + 74 + 16;
  // ListTile: 16 gap + 24 trailing + 16 padding after the title.
  static const _tailOut = 16.0 + 24 + 16;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return SizedBox(
      height: 34,
      child: Row(children: [
        SizedBox(
          width: _leadIn + nameColWidth,
          child: Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(scrolled ? '◀ back to now' : '${_weekday(now)}, ${fmt12(now)}   ▶ later',
                  style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 13, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(builder: (_, box) {
            const slotW = 30 * kGuidePxPerMin;
            final slots = (box.maxWidth / slotW).ceil();
            return ClipRect(child: Stack(children: [
              for (var i = 0; i < slots; i++)
                Positioned(
                  left: i * slotW, top: 0, bottom: 0,
                  child: Builder(builder: (ctx) {
                    final t = windowStart.add(Duration(minutes: 30 * i));
                    final isNow = !now.isBefore(t) && now.isBefore(t.add(const Duration(minutes: 30)));
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Text(fmt12(t),
                          style: TextStyle(color: isNow ? Colors.white : Colors.white54, fontSize: 13,
                              fontWeight: isNow ? FontWeight.bold : FontWeight.normal)),
                    );
                  }),
                ),
            ]));
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
  const _TimelineCell({required this.channel, required this.windowStart});

  @override
  Widget build(BuildContext context) {
    final repo = ChannelRepo.I;
    final accent = Theme.of(context).colorScheme.primary;
    final now = DateTime.now();

    return SizedBox(
      height: 46,
      child: LayoutBuilder(builder: (_, box) {
        const pxPerMin = kGuidePxPerMin;
        final windowEnd = windowStart.add(Duration(minutes: (box.maxWidth / pxPerMin).ceil()));
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
          if (nowX >= 0 && nowX <= box.maxWidth)
            Positioned(left: nowX, top: 0, bottom: 0, width: 3,
                child: Container(color: accent)),
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
      left: left, top: 5, bottom: 5, width: width,
      child: Container(
        margin: const EdgeInsets.only(right: 3),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: onNow ? accent.withOpacity(0.5) : Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: onNow ? accent : Colors.white12, width: 1),
        ),
        alignment: Alignment.centerLeft,
        child: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: onNow ? Colors.white : Colors.white70)),
      ),
    );
  }
}

/// Zero-cost wrapper so key handlers can find which channel a focused row is.
class _ChannelRowMarker extends StatelessWidget {
  final Channel channel;
  final Widget child;
  const _ChannelRowMarker({required this.channel, required this.child});
  @override
  Widget build(BuildContext context) => child;
}

/// One row in the hold-OK channel menu — focusable, lights up on the remote.
class _MenuButton extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String label;
  final bool autofocus;
  final VoidCallback onPressed;
  const _MenuButton({required this.icon, required this.label, required this.onPressed, this.iconColor, this.autofocus = false});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Focus(
        autofocus: autofocus,
        // The remote's OK lands here as a key event, not a tap — the
        // InkWell only sees taps, so activate on select/enter ourselves.
        onKeyEvent: (node, e) {
          if (e is! KeyDownEvent) return KeyEventResult.ignored;
          final k = e.logicalKey;
          if (k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter ||
              k == LogicalKeyboardKey.numpadEnter || k == LogicalKeyboardKey.gameButtonA) {
            onPressed();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Builder(builder: (ctx) {
          final focused = Focus.of(ctx).hasFocus;
          return InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
              decoration: BoxDecoration(
                color: focused ? primary.withOpacity(0.35) : Colors.white.withOpacity(0.07),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: focused ? primary : Colors.transparent, width: 1.5),
              ),
              child: Row(children: [
                Icon(icon, size: 18, color: iconColor ?? (focused ? Colors.white : Colors.white70)),
                const SizedBox(width: 12),
                Expanded(child: Text(label, style: TextStyle(fontSize: 15, fontWeight: focused ? FontWeight.bold : FontWeight.w500))),
              ]),
            ),
          );
        }),
      ),
    );
  }
}
