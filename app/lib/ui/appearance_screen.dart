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
          const Text('Themes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('One tap sets both the accent and the background.', style: TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 12, children: [
            for (final t in ThemeController.presets)
              _PresetChip(
                preset: t,
                selected: ThemeController.primaryColor.value.value == t.accent.value &&
                    ThemeController.background.value.value == t.background.value,
                onSelect: () async {
                  await ThemeController.applyPreset(t);
                  if (mounted) setState(() => hexCtl.text = _toHex(t.accent));
                },
              ),
          ]),
          const SizedBox(height: 28),
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
          const SizedBox(height: 28),
          const Text('Background', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          Wrap(spacing: 14, runSpacing: 14, children: [
            for (final c in const [
              Color(0xFF0E0E10), Color(0xFF000000), Color(0xFF0F1020), Color(0xFF0A0E16),
              Color(0xFF14110A), Color(0xFF0B1210), Color(0xFF111418), Color(0xFF1A1A1A),
            ])
              _Swatch(color: c, selected: ThemeController.background.value.value == c.value,
                  onSelect: () { ThemeController.setBackground(c); setState(() {}); }),
          ]),
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: () {
              ThemeController.resetToDefault();
              setState(() => hexCtl.text = _toHex(Branding.I.primaryColor));
            },
            icon: const Icon(Icons.restart_alt, color: Colors.white70),
            label: const Text('Reset to this build\'s default look', style: TextStyle(color: Colors.white70)),
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


class _PresetChip extends StatelessWidget {
  final ThemePreset preset;
  final bool selected;
  final VoidCallback onSelect;
  const _PresetChip({required this.preset, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Focus(
      child: Builder(builder: (ctx) {
        final focused = Focus.of(ctx).hasFocus;
        return InkWell(
          onTap: onSelect,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 150,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: preset.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: focused ? Colors.white : (selected ? preset.accent : Colors.white12), width: focused ? 3 : 2),
            ),
            child: Row(children: [
              Container(width: 26, height: 26, decoration: BoxDecoration(color: preset.accent, shape: BoxShape.circle)),
              const SizedBox(width: 10),
              Expanded(child: Text(preset.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
              if (selected) const Icon(Icons.check, size: 16, color: Colors.white70),
            ]),
          ),
        );
      }),
    );
  }
}
