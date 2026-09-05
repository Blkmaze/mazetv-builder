import 'package:flutter/material.dart';
import '../config/branding.dart';
import '../models/account.dart';
import '../models/server_config.dart';
import '../services/xtream_service.dart';
import '../services/m3u_service.dart';
import 'tv_widgets.dart';

/// Shared "add / edit a server" form used both for the very first login and
/// for adding extra failover servers later. Tests the connection before
/// returning so a typo doesn't silently get saved.
///
/// Returns the saved [ServerConfig], or null if the user backed out.
Future<ServerConfig?> showServerForm(BuildContext context, {ServerConfig? existing}) {
  return Navigator.push<ServerConfig>(
    context,
    MaterialPageRoute(builder: (_) => _ServerFormScreen(existing: existing)),
  );
}

class _ServerFormScreen extends StatefulWidget {
  final ServerConfig? existing;
  const _ServerFormScreen({this.existing});
  @override
  State<_ServerFormScreen> createState() => _ServerFormScreenState();
}

class _ServerFormScreenState extends State<_ServerFormScreen> {
  late SourceType mode;
  late final TextEditingController nickname;
  late final TextEditingController host;
  late final TextEditingController user;
  late final TextEditingController pass;
  late final TextEditingController m3u;
  late final TextEditingController epg;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    final a = widget.existing?.account;
    mode = a?.type ?? SourceType.xtream;
    nickname = TextEditingController(text: widget.existing?.nickname ?? '');
    host = TextEditingController(text: mode == SourceType.xtream ? (a?.host ?? Branding.I.portalUrl) : '');
    user = TextEditingController(text: a?.username ?? '');
    pass = TextEditingController(text: a?.password ?? '');
    m3u = TextEditingController(text: mode == SourceType.m3u ? (a?.host ?? '') : '');
    epg = TextEditingController(text: a?.epgUrl ?? Branding.I.epgUrl);
  }

  String _norm(String s) {
    s = s.trim();
    if (!s.startsWith('http')) s = 'http://$s';
    return s;
  }

  Future<void> _save() async {
    setState(() => busy = true);
    try {
      final account = mode == SourceType.xtream
          ? Account(type: SourceType.xtream, host: _norm(host.text), username: user.text.trim(), password: pass.text.trim(), epgUrl: epg.text.trim())
          : Account(type: SourceType.m3u, host: m3u.text.trim(), epgUrl: epg.text.trim());

      // Test the connection before saving so a typo doesn't get stored silently.
      if (account.type == SourceType.xtream) {
        await XtreamService(account).login();
      } else {
        await M3uService.fetch(account.host);
      }

      final nick = nickname.text.trim().isEmpty
          ? (mode == SourceType.xtream ? _hostLabel(account.host) : 'M3U playlist')
          : nickname.text.trim();

      final result = widget.existing?.copyWith(nickname: nick, account: account) ??
          ServerConfig(id: DateTime.now().microsecondsSinceEpoch.toRadixString(36), nickname: nick, account: account);

      if (!mounted) return;
      Navigator.pop(context, result);
    } catch (e) {
      if (mounted) await showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  static String _hostLabel(String host) => host.replaceFirst(RegExp(r'^https?://'), '').split('/').first;

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit server' : 'Add server')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: ListView(shrinkWrap: true, children: [
              TvTextField(controller: nickname, label: 'Name for this server (optional)', autofocus: true),
              const SizedBox(height: 14),
              SegmentedButton<SourceType>(
                segments: const [
                  ButtonSegment(value: SourceType.xtream, label: Text('Xtream login'), icon: Icon(Icons.login)),
                  ButtonSegment(value: SourceType.m3u, label: Text('M3U playlist'), icon: Icon(Icons.playlist_play)),
                ],
                selected: {mode},
                onSelectionChanged: (s) => setState(() => mode = s.first),
              ),
              const SizedBox(height: 20),
              if (mode == SourceType.xtream) ...[
                TvTextField(controller: host, label: 'Server URL (http://host:port)'),
                TvTextField(controller: user, label: 'Username'),
                TvTextField(controller: pass, label: 'Password', obscure: true),
              ] else ...[
                TvTextField(controller: m3u, label: 'Playlist URL (.m3u / .m3u8)'),
              ],
              TvTextField(controller: epg, label: 'EPG URL (optional XMLTV)', last: true),
              const SizedBox(height: 20),
              busy
                  ? const Center(child: CircularProgressIndicator())
                  : TvButton(label: editing ? 'Save' : 'Add & test', icon: Icons.check, onPressed: _save),
            ]),
          ),
        ),
      ),
    );
  }
}
