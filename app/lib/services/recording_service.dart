import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecordingEntry {
  final String id;
  final String channelName;
  final String filePath;
  final DateTime startedAt;
  int seconds;
  int bytes;

  RecordingEntry({
    required this.id,
    required this.channelName,
    required this.filePath,
    required this.startedAt,
    this.seconds = 0,
    this.bytes = 0,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'channelName': channelName,
        'filePath': filePath,
        'startedAt': startedAt.toIso8601String(),
        'seconds': seconds,
        'bytes': bytes,
      };

  static RecordingEntry fromMap(Map<String, dynamic> m) => RecordingEntry(
        id: m['id'] as String,
        channelName: (m['channelName'] ?? '') as String,
        filePath: (m['filePath'] ?? '') as String,
        startedAt: DateTime.tryParse(m['startedAt'] ?? '') ?? DateTime.now(),
        seconds: (m['seconds'] ?? 0) as int,
        bytes: (m['bytes'] ?? 0) as int,
      );
}

/// A small DVR: streams a live channel URL straight to a file on disk for as
/// long as recording is active, then lists finished recordings for playback.
///
/// This only records while the app is in the foreground — there's no
/// Android foreground service wired up, so the OS can pause/kill it if the
/// app is backgrounded for a long time. Good enough for "record the next
/// hour while I keep the app open"; a real background DVR is future work.
class RecordingService {
  static final RecordingService I = RecordingService._();
  RecordingService._();

  static const _kKey = 'recordings_v1';

  http.Client? _client;
  StreamSubscription<List<int>>? _sub;
  IOSink? _sink;
  RecordingEntry? current;

  final _controller = StreamController<void>.broadcast();
  Stream<void> get onChange => _controller.stream;
  bool get isRecording => current != null;

  Future<List<RecordingEntry>> list() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList(_kKey) ?? [];
    final out = <RecordingEntry>[];
    for (final s in raw) {
      try {
        out.add(RecordingEntry.fromMap(jsonDecode(s) as Map<String, dynamic>));
      } catch (_) {}
    }
    return out;
  }

  Future<void> _save(List<RecordingEntry> entries) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kKey, entries.map((e) => jsonEncode(e.toMap())).toList());
  }

  Future<Directory> _dir() async {
    final dir = await getApplicationDocumentsDirectory();
    final recDir = Directory('${dir.path}/recordings');
    if (!await recDir.exists()) await recDir.create(recursive: true);
    return recDir;
  }

  Future<String?> start(String channelName, String streamUrl) async {
    if (isRecording) return 'A recording is already in progress.';
    try {
      final dir = await _dir();
      final id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      final safeName = channelName.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
      final file = File('${dir.path}/${safeName}_$id.ts');
      final entry = RecordingEntry(
          id: id, channelName: channelName, filePath: file.path, startedAt: DateTime.now());
      current = entry;
      _controller.add(null);

      _client = http.Client();
      _sink = file.openWrite();
      final req = http.Request('GET', Uri.parse(streamUrl));
      final resp = await _client!.send(req);
      if (resp.statusCode != 200) {
        await stop(discard: true);
        return 'Stream answered HTTP ${resp.statusCode}';
      }
      _sub = resp.stream.listen(
        (chunk) {
          _sink?.add(chunk);
          entry.bytes += chunk.length;
          entry.seconds = DateTime.now().difference(entry.startedAt).inSeconds;
          _controller.add(null);
        },
        onError: (_) => stop(),
        onDone: () => stop(),
        cancelOnError: true,
      );
      return null;
    } catch (e) {
      current = null;
      _controller.add(null);
      return e.toString().replaceFirst('Exception: ', '');
    }
  }

  /// Stops the active recording. Pass [discard] to delete the partial file
  /// instead of keeping it in the list (used when start() itself fails).
  Future<void> stop({bool discard = false}) async {
    final finished = current;
    if (finished == null) return;
    current = null;
    await _sub?.cancel();
    _sub = null;
    try {
      await _sink?.flush();
      await _sink?.close();
    } catch (_) {}
    _sink = null;
    _client?.close();
    _client = null;

    if (discard) {
      try {
        await File(finished.filePath).delete();
      } catch (_) {}
    } else if (finished.bytes > 0) {
      final entries = await list();
      entries.insert(0, finished);
      await _save(entries);
    }
    _controller.add(null);
  }

  Future<void> delete(RecordingEntry e) async {
    final entries = await list();
    entries.removeWhere((x) => x.id == e.id);
    await _save(entries);
    try {
      await File(e.filePath).delete();
    } catch (_) {}
    _controller.add(null);
  }

  Future<int> totalBytes() async {
    final entries = await list();
    return entries.fold<int>(0, (sum, e) => sum + e.bytes);
  }

  Future<void> clearAll() async {
    final entries = await list();
    for (final e in entries) {
      try {
        await File(e.filePath).delete();
      } catch (_) {}
    }
    await _save([]);
    _controller.add(null);
  }
}
