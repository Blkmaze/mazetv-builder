import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:openvpn_flutter/openvpn_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/branding.dart';
import 'tv_widgets.dart';

/// Built-in OpenVPN. The .ovpn profile comes from the branded config URL
/// (set by the builder) or one the user enters here.
class VpnScreen extends StatefulWidget {
  const VpnScreen({super.key});
  @override
  State<VpnScreen> createState() => _VpnScreenState();
}

class _VpnScreenState extends State<VpnScreen> {
  late final OpenVPN vpn;
  VPNStage stage = VPNStage.disconnected;
  VpnStatus? status;
  final urlCtl = TextEditingController();
  final userCtl = TextEditingController();
  final passCtl = TextEditingController();
  bool busy = false;

  @override
  void initState() {
    super.initState();
    vpn = OpenVPN(
      onVpnStatusChanged: (s) { if (mounted) setState(() => status = s); },
      onVpnStageChanged: (s, _) { if (mounted) setState(() => stage = s); },
    );
    vpn.initialize(
      groupIdentifier: 'group.mazetv.vpn',
      providerBundleIdentifier: 'mazetv.vpn.extension',
      localizedDescription: '${Branding.I.appName} VPN',
    );
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final p = await SharedPreferences.getInstance();
    urlCtl.text = p.getString('vpn_url') ?? Branding.I.vpnConfigUrl;
    userCtl.text = p.getString('vpn_user') ?? '';
    passCtl.text = p.getString('vpn_pass') ?? '';
    setState(() {});
  }

  Future<void> _connect() async {
    setState(() => busy = true);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('vpn_url', urlCtl.text.trim());
      await p.setString('vpn_user', userCtl.text.trim());
      await p.setString('vpn_pass', passCtl.text.trim());

      final r = await http.get(Uri.parse(urlCtl.text.trim()));
      if (r.statusCode != 200) throw Exception('Could not download VPN profile (HTTP ${r.statusCode})');
      await vpn.requestPermissionAndroid();
      vpn.connect(r.body, Branding.I.appName,
          username: userCtl.text.trim(), password: passCtl.text.trim(), certIsRequired: false);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = stage == VPNStage.connected;
    return Scaffold(
      appBar: AppBar(title: const Text('VPN')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(padding: const EdgeInsets.all(32), shrinkWrap: true, children: [
            Row(children: [
              Icon(connected ? Icons.lock : Icons.lock_open, size: 40,
                  color: connected ? Colors.greenAccent : Colors.white54),
              const SizedBox(width: 16),
              Text(stage.name.toUpperCase(), style: const TextStyle(fontSize: 24)),
            ]),
            if (status != null && connected)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('↓ ${status!.byteIn}   ↑ ${status!.byteOut}   ${status!.duration}',
                    style: const TextStyle(color: Colors.white60)),
              ),
            const SizedBox(height: 24),
            TvTextField(
              controller: urlCtl,
              label: '.ovpn profile URL',
              autofocus: true,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TvTextField(
              controller: userCtl,
              label: 'VPN username (if required)',
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TvTextField(
              controller: passCtl,
              label: 'VPN password (if required)',
              obscureText: true,
              textInputAction: TextInputAction.done,
              onSubmitted: () { if (!busy) _connect(); },
            ),
            const SizedBox(height: 24),
            busy
                ? const Center(child: CircularProgressIndicator())
                : connected
                    ? TvButton(label: 'Disconnect', icon: Icons.stop, onPressed: vpn.disconnect)
                    : TvButton(label: 'Connect', icon: Icons.vpn_key, onPressed: _connect),
          ]),
        ),
      ),
    );
  }
}
