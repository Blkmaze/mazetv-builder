import 'package:flutter/material.dart';
import '../config/branding.dart';
import '../models/account.dart';
import '../services/channel_repo.dart';
import '../services/storage.dart';
import 'home_screen.dart';
import 'tv_widgets.dart';

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

  Future<void> _go() async {
    setState(() => busy = true);
    try {
      final a = mode == SourceType.xtream
          ? Account(type: SourceType.xtream, host: _norm(host.text), username: user.text.trim(), password: pass.text.trim(), epgUrl: epg.text.trim())
          : Account(type: SourceType.m3u, host: m3u.text.trim(), epgUrl: epg.text.trim());
      await ChannelRepo.I.load(a, fallbackEpg: Branding.I.epgUrl);
      await Storage.saveAccount(a);
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

  @override
  Widget build(BuildContext context) {
    final b = Branding.I;
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
                _field(host, 'Server URL (http://host:port)', autofocus: true),
                _field(user, 'Username'),
                _field(pass, 'Password', obscure: true),
              ] else ...[
                _field(m3u, 'Playlist URL (.m3u / .m3u8)', autofocus: true),
              ],
              _field(epg, 'EPG URL (optional XMLTV)', last: true),
              const SizedBox(height: 20),
              busy
                  ? const Center(child: CircularProgressIndicator())
                  : TvButton(label: 'Sign in', icon: Icons.play_arrow, onPressed: _go),
              const SizedBox(height: 20),
              Text(b.supportText, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, {bool obscure = false, bool autofocus = false, bool last = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TvTextField(
          controller: c,
          label: label,
          obscureText: obscure,
          autofocus: autofocus,
          textInputAction: last ? TextInputAction.done : TextInputAction.next,
          onSubmitted: last ? _go : null,
        ),
      );
}
