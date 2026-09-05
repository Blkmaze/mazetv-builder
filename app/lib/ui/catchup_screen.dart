import 'package:flutter/material.dart';
import '../models/channel.dart';
import '../services/channel_repo.dart';
import 'player_screen.dart';
import 'tv_widgets.dart';

/// Channels whose portal advertises catchup/timeshift (tv_archive=1).
class CatchupScreen extends StatelessWidget {
  const CatchupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final channels = ChannelRepo.I.archiveChannels;
    return Scaffold(
      appBar: AppBar(title: const Text('Catchup')),
      body: channels.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "None of your channels report catchup support (tv_archive) right now.\n"
                  "Refresh channels from Settings after your portal enables it for a channel.",
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.builder(
              itemCount: channels.length,
              itemBuilder: (_, i) {
                final c = channels[i];
                return TvTile(
                  autofocus: i == 0,
                  leading: ChannelLogo(c.logo),
                  title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${c.tvArchiveDuration}h of catchup available'),
                  onSelect: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CatchupPickerScreen(channel: c))),
                );
              },
            ),
    );
  }
}

/// Pick a moment to rewind to for one channel: real EPG entries when we have
/// them (recent past is now kept by EpgService), plus quick "N minutes ago"
/// buttons that always work even without guide data.
class CatchupPickerScreen extends StatelessWidget {
  final Channel channel;
  const CatchupPickerScreen({super.key, required this.channel});

  void _watch(BuildContext context, DateTime start, int minutes) {
    final x = ChannelRepo.I.xtream;
    if (x == null) return;
    final url = x.catchupUrl(channel, start, minutes);
    final ch = Channel(id: '${channel.id}_catchup', name: channel.name, group: channel.group, logo: channel.logo, streamUrl: url, epgId: '');
    Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(playlist: [ch], index: 0)));
  }

  @override
  Widget build(BuildContext context) {
    final past = (ChannelRepo.I.epg.byChannel[channel.epgId] ?? [])
        .where((p) => p.stop.isBefore(DateTime.now()))
        .toList()
      ..sort((a, b) => b.start.compareTo(a.start));
    final maxMinutesAgo = channel.tvArchiveDuration * 60;

    return Scaffold(
      appBar: AppBar(title: Text(channel.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Quick rewind', style: TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final mins in [15, 30, 60, 120, 180])
              if (maxMinutesAgo == 0 || mins <= maxMinutesAgo)
                OutlinedButton(
                  autofocus: mins == 15,
                  onPressed: () => _watch(context, DateTime.now().subtract(Duration(minutes: mins)), 60),
                  child: Text(mins < 60 ? '$mins min ago' : '${mins ~/ 60}h ago'),
                ),
          ]),
          const SizedBox(height: 24),
          if (past.isNotEmpty) ...[
            const Text('From the guide', style: TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(height: 8),
            for (final p in past.take(30))
              TvTile(
                title: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${_hm(p.start)}–${_hm(p.stop)}'),
                onSelect: () => _watch(context, p.start, p.stop.difference(p.start).inMinutes),
              ),
          ] else
            const Text('No recent guide data for this channel — the quick-rewind buttons above still work.',
                style: TextStyle(color: Colors.white38)),
        ],
      ),
    );
  }

  static String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
