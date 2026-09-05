import 'package:flutter/material.dart';
import '../config/branding.dart';
import '../config/theme_controller.dart';
import 'tv_widgets.dart';

const _presets = <Color>[
  Color(0xFFE50914), // red (default-ish)
  Color(0xFFFF9800), // orange
  Color(0xFFFFC107), // amber
  Color(0xFF4CAF50), // green
  Color(0xFF00BCD4), // cyan
  Color(0xFF2196F3), // blue
  Color(0xFF7C4DFF), // violet
  Color(0xFFE91E63), // pink
];

class AppearanceScreen extends StatefulWidget {
  const AppearanceScreen({super.key});
  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  late final hexCtl = TextEditingController(text: _toHex(ThemeController.primaryColor.value));

  void _apply(Color c) {
    ThemeController.setColor(c);
    setState(() => hexCtl.text = _toHex(c));
  }

  void _applyHex() {
    final s = hexCtl.text.trim().replaceAll('#', '');
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(s)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a 6-digit hex color, like E50914')));
      return;
    }
    _apply(Color(int.parse('FF$s', radix: 16)));
  }

  static String _toHex(Color c) =>
      c.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const Text('Accent color', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          Wrap(spacing: 14, runSpacing: 14, children: [
            for (final c in _presets)
              _Swatch(color: c, selected: ThemeController.primaryColor.value.value == c.value, onSelect: () => _apply(c)),
          ]),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(
              child: TextField(
                controller: hexCtl,
                decoration: const InputDecoration(labelText: 'Custom hex (e.g. E50914)', border: OutlineInputBorder(), prefixText: '#'),
                onSubmitted: (_) => _applyHex(),
              ),
            ),
            const SizedBox(width: 12),
            TvButton(label: 'Apply', icon: Icons.check, onPressed: _applyHex),
          ]),
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: () {
              ThemeController.resetToDefault();
              setState(() => hexCtl.text = _toHex(Branding.I.primaryColor));
            },
            icon: const Icon(Icons.restart_alt, color: Colors.white70),
            label: const Text('Reset to this build\'s default color', style: TextStyle(color: Colors.white70)),
          ),
        ]),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onSelect;
  const _Swatch({required this.color, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Focus(
      child: Builder(builder: (ctx) {
        final focused = Focus.of(ctx).hasFocus;
        return InkWell(
          onTap: onSelect,
          borderRadius: BorderRadius.circular(30),
          child: Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: focused ? Colors.white : Colors.transparent, width: 3),
            ),
            child: selected ? const Icon(Icons.check, color: Colors.white) : null,
          ),
        );
      }),
    );
  }
}
