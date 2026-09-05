import 'package:flutter/material.dart';

/// Placeholder. A real watch party (synced playback + chat across separate
/// devices/households) needs a signaling backend — something to broadcast
/// "everyone jump to timestamp X" and relay chat between viewers. The repo
/// already has a small Netlify functions backend (used today for the
/// "sign in with a code" pairing flow); that's the natural place to add a
/// lightweight session/relay endpoint for this. Not built yet, so this
/// screen just explains that rather than faking a feature that doesn't work.
class WatchPartyScreen extends StatelessWidget {
  const WatchPartyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Watch Party')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.groups, size: 56, color: Colors.white24),
            const SizedBox(height: 16),
            const Text('Coming soon', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text(
              'Watching in sync with other people needs a small server to keep everyone\'s '
              'playback lined up and relay a room code — that backend piece isn\'t built yet.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60),
            ),
          ]),
        ),
      ),
    );
  }
}
