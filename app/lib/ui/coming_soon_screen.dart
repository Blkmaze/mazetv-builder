import 'package:flutter/material.dart';

/// Placeholder for nav-rail sections that mirror Ghost's layout but aren't
/// built yet (Catchup, Movies, Series, Watch Party, Multiview, Recordings).
/// Honest about what's here rather than faking content.
class ComingSoonScreen extends StatelessWidget {
  final String title;
  final IconData icon;
  const ComingSoonScreen({super.key, required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 64, color: Colors.white24),
          const SizedBox(height: 16),
          Text('$title is coming soon', style: const TextStyle(fontSize: 20, color: Colors.white60)),
        ]),
      ),
    );
  }
}
