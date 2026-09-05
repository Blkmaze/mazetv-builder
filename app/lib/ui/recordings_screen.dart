import 'dart:async';
import 'package:flutter/material.dart';
import '../models/channel.dart';
import '../services/channel_repo.dart';
import '../services/recording_service.dart';
import 'player_screen.dart';
import 'tv_widgets.dart';

class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({super.key});
  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> {
  final svc = RecordingService.I;
  List<RecordingEntry> entries = [];
  StreamSubscription? _sub;
  Channel? recordingChannel;

  @override
  void initState() {
    super.initState();
    _refresh();
    _sub = svc.onChange.listen((_) => _refresh());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final list = await svc.list();
    if (mounted) setState(() => entries = list);
  }

  Future<void> _startPicker() async {
    final c = await Navigator.push<Channel>(
      context,
      MaterialPageRoute(builder: (_) => const _RecordChannelPicker()),
    );
    if (c == null) return;
    setState(() => recordingChannel = c);
    final err = await svc.start(c.name, c.streamUrl);
    if (err != null && mounted) {
      setState(() => recordingChannel = null);
      await showError(context, err);
    }
  }

  Future<void> _stop() async {
    await svc.stop();
    setState(() => recordingChannel = null);
  }

  void _play(RecordingEntry e) {
    final ch = Channel(id: 'rec_${e.id}', name: e.channelName, group: 'Recordings', logo: '', streamUrl: 'file://${e.filePath}', epgId: '');
    Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(playlist: [ch], index: 0)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recordings')),
      body: Column(children: [
        if (svc.isRecording)
          Container(
            width: double.infinity,
            color: Colors.red.withOpacity(0.15),
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              const Icon(Icons.fiber_manual_record, color: Colors.red),
              const SizedBox(width: 10),
              Expanded(child: Text('Recording ${recordingChannel?.name ?? svc.current?.channelName ?? ''} — ${svc.current?.seconds ?? 0}s')),
              TextButton(onPressed: _stop, child: const Text('Stop')),
            ]),
          )
        else
          Padding(
            padding: const EdgeInsets.all(16),
            child: TvButton(label: 'Record a live channel', icon: Icons.fiber_manual_record, autofocus: true, onPressed: _startPicker),
          ),
        const Divider(height: 1),
        Expanded(
          child: entries.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No recordings yet. Recording only runs while the app stays open in the '
                      'foreground — there\'s no background DVR service yet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (_, i) {
                    final e = entries[i];
                    return TvTile(
                      leading: const Icon(Icons.movie_creation_outlined),
                      title: Text(e.channelName, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${_dur(e.seconds)} · ${_size(e.bytes)} · ${_when(e.startedAt)}'),
                      trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => svc.delete(e)),
                      onSelect: () => _play(e),
                    );
                  },
                ),
        ),
      ]),
    );
  }

  static String _dur(int s) => s < 60 ? '${s}s' : '${(s / 60).floor()}m ${s % 60}s';
  static String _size(int b) => b < 1024 * 1024 ? '${(b / 1024).round()} KB' : '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  static String _when(DateTime t) => '${t.month}/${t.day} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

class _RecordChannelPicker extends StatelessWidget {
  const _RecordChannelPicker();
  @override
  Widget build(BuildContext context) {
    final channels = ChannelRepo.I.channels;
    return Scaffold(
      appBar: AppBar(title: const Text('Record which channel?')),
      body: ListView.builder(
        itemCount: channels.length,
        itemBuilder: (_, i) {
          final c = channels[i];
          return TvTile(
            autofocus: i == 0,
            leading: ChannelLogo(c.logo),
            title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            onSelect: () => Navigator.pop(context, c),
          );
        },
      ),
    );
  }
}
