import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Values stamped in by the builder (assets/branding.json).
class Branding {
  final String appName;
  final Color primaryColor;
  final String portalUrl;      // optional pre-filled Xtream host
  final String epgUrl;         // optional XMLTV url for M3U users
  final String vpnConfigUrl;   // optional .ovpn download url
  final String supportText;

  const Branding({
    required this.appName,
    required this.primaryColor,
    required this.portalUrl,
    required this.epgUrl,
    required this.vpnConfigUrl,
    required this.supportText,
  });

  static Branding? _instance;
  static Branding get I => _instance!;

  static Future<void> load() async {
    final raw = await rootBundle.loadString('assets/branding.json');
    final j = jsonDecode(raw) as Map<String, dynamic>;
    _instance = Branding(
      appName: j['app_name'] ?? 'MazeTV',
      primaryColor: _hex(j['primary_color'] ?? '#E50914'),
      portalUrl: j['portal_url'] ?? '',
      epgUrl: j['epg_url'] ?? '',
      vpnConfigUrl: j['vpn_config_url'] ?? '',
      supportText: j['support_text'] ?? '',
    );
  }

  static Color _hex(String s) {
    var h = s.replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    return Color(int.parse(h, radix: 16));
  }
}
