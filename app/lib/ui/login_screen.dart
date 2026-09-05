import 'package:flutter/material.dart';
import '../config/branding.dart';
import '../models/account.dart';
import '../models/server_config.dart';
import '../services/channel_repo.dart';
import '../services/storage.dart';
import 'code_signin_screen.dart';
import 'home_screen.dart';
import 'tv_widgets.dart';

/// First-run screen: adds your one and only server to start with. Extra
/// servers (for failover) are added later from Home → Servers.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  SourceType mode = SourceType.xtream;
  final host = TextEditingController(text: Branding.I.portalUrl);
  final user = TextEditingController();
  final pass = TextEditingController();
  final m3u = TextEditingController();
  final epg = TextEditingController(text: Branding.I.epgUrl);
  bool busy = false;
  bool manualHost = false; // "Other server" was picked from the provider list
  Portal? picked;

  @override
  void initState() {
    super.initState();
    final portals = Branding.I.portals;
    if (portals.isNotEmpty) { picked = portals.first; host.text = picked!.host; }
  }

  Future<void> _go() async {
    setState(() => busy = true);
    try {
      var a = mode == SourceType.xtream
          ? Account(type: SourceType.xtream, host: _norm(host.text), username: user.text.trim(), password: pass.text.trim(), epgUrl: epg.text.trim())
          : Account(type: SourceType.m3u, host: m3u.text.trim(), epgUrl: epg.text.trim());
      try {
        await ChannelRepo.I.load(a, fallbackEpg: Branding.I.epgUrl);
      } catch (e) {
        // Most portals are plain http; if the user typed https and it refused, retry once on http.
        if (mode == SourceType.xtream && a.host.startsWith('https://') && e.toString().contains('Could not reach')) {
          a = Account(type: a.type, host: a.host.replaceFirst('https://', 'http://'),
              username: a.username, password: a.password, epgUrl: a.epgUrl);
          await ChannelRepo.I.load(a, fallbackEpg: Branding.I.epgUrl);
        } else {
          rethrow;
        }
      }

      final server = ServerConfig(
        id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
        nickname: mode == SourceType.xtream ? _hostLabel(a.host) : 'M3U playlist',
        account: a,
      );
      await Storage.addServer(server);
      await Storage.setActiveServerId(server.id);
      ChannelRepo.I.activeServer = server;

      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
    } catch (e) {
      if (mounted) await showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _norm(String s) {
    s = s.trim();
    if (!s.startsWith('http')) s = 'http://$s';
    return s;
  }

  static String _hostLabel(String host) => host.replaceFirst(RegExp(r'^https?://'), '').split('/').first;

  @override
  Widget build(BuildContext context) {
    final b = Branding.I;
    final hasPortals = b.portals.isNotEmpty;
    final hasPairing = b.pairBaseUrl.isNotEmpty;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: ListView(shrinkWrap: true, children: [
              Text(b.appName, textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 44, fontWeight: FontWeight.bold, color: b.primaryColor)),
              const SizedBox(height: 24),
              SegmentedButton<SourceType>(
                segments: const [
                  ButtonSegment(value: SourceType.xtream, label: Text('Xtream login'), icon: Icon(Icons.login)),
                  ButtonSegment(value: SourceType.m3u, label: Text('M3U playlist'), icon: Icon(Icons.playlist_play)),
                ],
                selected: {mode},
                onSelectionChanged: (s) => setState(() => mode = s.first),
              ),
              const SizedBox(height: 24),
              if (mode == SourceType.xtream) ...[
                if (hasPortals) ...[
                  DropdownButtonFormField<Portal?>(
                    initialValue: manualHost ? null : picked,
                    decoration: const InputDecoration(labelText: 'Server', border: OutlineInputBorder()),
                    dropdownColor: const Color(0xFF20242f),
                    items: [
                      for (final p in b.portals) DropdownMenuItem(value: p, child: Text(p.name)),
                      const DropdownMenuItem(value: null, child: Text('Other server…')),
                    ],
                    onChanged: (p) => setState(() {
                      if (p == null) { manualHost = true; host.text = ''; }
                      else { manualHost = false; picked = p; host.text = p.host; }
                    }),
                  ),
                  const SizedBox(height: 14),
                  if (manualHost) TvTextField(controller: host, label: 'Server URL (http://host:port)', autofocus: true),
                ] else
                  TvTextField(controller: host, label: 'Server URL (http://host:port)', autofocus: true),
                TvTextField(controller: user, label: 'Username', autofocus: hasPortals && !manualHost),
                TvTextField(controller: pass, label: 'Password', obscure: true),
              ] else ...[
                TvTextField(controller: m3u, label: 'Playlist URL (.m3u / .m3u8)', autofocus: true),
              ],
              TvTextField(controller: epg, label: 'EPG URL (optional XMLTV)', last: true),
              const SizedBox(height: 20),
              busy
                  ? const Center(child: CircularProgressIndicator())
                  : TvButton(label: 'Sign in', icon: Icons.play_arrow, onPressed: _go),
              if (hasPairing) ...[
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CodeSignInScreen())),
                  icon: const Icon(Icons.qr_code, color: Colors.white70),
                  label: const Text('Sign in with a code instead', style: TextStyle(color: Colors.white70)),
                ),
              ],
              const SizedBox(height: 8),
              Text(b.supportText, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54)),
            ]),
          ),
        ),
      ),
    );
  }
}
