import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/branding.dart';
import '../models/account.dart';
import '../models/server_config.dart';
import '../services/channel_repo.dart';
import '../services/storage.dart';
import 'home_screen.dart';
import 'tv_widgets.dart';

/// Companion-device sign-in: the viewer types the code shown on the TV into
/// a phone/browser page (or scans the QR there), and this screen polls
/// until those credentials show up, then logs in automatically.
class CodeSignInScreen extends StatefulWidget {
  const CodeSignInScreen({super.key});
  @override
  State<CodeSignInScreen> createState() => _CodeSignInScreenState();
}

class _CodeSignInScreenState extends State<CodeSignInScreen> {
  String code = '------';
  Timer? poll;
  String status = 'Getting a code…';

  @override
  void initState() {
    super.initState();
    _requestCode();
  }

  Uri _fn(String name) => Uri.parse('${Branding.I.pairBaseUrl}/.netlify/functions/$name');

  Future<void> _requestCode() async {
    try {
      final r = await http.post(_fn('pair-create'));
      final j = jsonDecode(r.body);
      setState(() { code = j['code']; status = 'Enter this code on your phone or computer'; });
      poll = Timer.periodic(const Duration(seconds: 3), (_) => _checkCode());
    } catch (e) {
      setState(() => status = 'Could not reach the pairing service');
    }
  }

  Future<void> _checkCode() async {
    try {
      final r = await http.get(_fn('pair-check').replace(queryParameters: {'code': code}));
      if (r.statusCode == 404) return; // not claimed yet
      final j = jsonDecode(r.body);
      poll?.cancel();
      var a = Account(
        type: j['type'] == 'm3u' ? SourceType.m3u : SourceType.xtream,
        host: j['host'] ?? '', username: j['username'] ?? '', password: j['password'] ?? '',
      );
      setState(() => status = 'Signing in…');
      await ChannelRepo.I.load(a, fallbackEpg: Branding.I.epgUrl);

      final server = ServerConfig(
        id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
        nickname: a.type == SourceType.xtream
            ? a.host.replaceFirst(RegExp(r'^https?://'), '').split('/').first
            : 'M3U playlist',
        account: a,
      );
      await Storage.addServer(server);
      await Storage.setActiveServerId(server.id);
      ChannelRepo.I.activeServer = server;

      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
    } catch (e) {
      if (mounted) setState(() => status = 'Sign-in failed: ${e.toString().replaceFirst('Exception: ', '')}');
    }
  }

  @override
  void dispose() { poll?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(Branding.I.appName, style: TextStyle(fontSize: 28, color: Branding.I.primaryColor, fontWeight: FontWeight.bold)),
          const SizedBox(height: 32),
          Text(code, style: const TextStyle(fontSize: 64, fontWeight: FontWeight.bold, letterSpacing: 8)),
          const SizedBox(height: 20),
          Text(status, style: const TextStyle(color: Colors.white60, fontSize: 18)),
          const SizedBox(height: 40),
          TvButton(label: 'Back', icon: Icons.arrow_back, autofocus: true, onPressed: () => Navigator.pop(context)),
        ]),
      ),
    );
  }
}
