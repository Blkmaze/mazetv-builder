import 'package:flutter/material.dart';
import '../models/profile.dart';
import '../services/storage.dart';

const List<Color> kProfileColors = [
  Color(0xFFE50914), Color(0xFF1DB954), Color(0xFF3A86FF),
  Color(0xFFFFB703), Color(0xFF8338EC), Color(0xFFFF5B5B),
];

/// "Who's watching?" — pick a profile. Selecting one sets it active and
/// returns to the caller; managing (add/rename/delete) happens inline here
/// too since there's no separate settings screen for it.
class ProfilesScreen extends StatefulWidget {
  /// If true, picking a profile pops the screen with that Profile (used at
  /// boot to choose who's watching). If false, this is just management.
  final bool selecting;
  const ProfilesScreen({super.key, this.selecting = true});

  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  List<Profile> profiles = [];
  bool loading = true;
  bool editMode = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    profiles = await Storage.loadProfiles();
    if (mounted) setState(() => loading = false);
  }

  Future<void> _addProfile() async {
    final name = await _promptName();
    if (name == null || name.trim().isEmpty) return;
    final p = Profile(
      id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
      name: name.trim(),
      colorSeed: profiles.length % kProfileColors.length,
    );
    profiles.add(p);
    await Storage.saveProfiles(profiles);
    if (mounted) setState(() {});
  }

  Future<void> _deleteProfile(Profile p) async {
    profiles.removeWhere((e) => e.id == p.id);
    await Storage.saveProfiles(profiles);
    if (mounted) setState(() {});
  }

  Future<String?> _promptName() {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('New profile'),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'Name'),
            onSubmitted: (v) => Navigator.pop(context, v)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Add')),
        ],
      ),
    );
  }

  Future<void> _choose(Profile p) async {
    await Storage.setActiveProfileId(p.id);
    if (!mounted) return;
    if (widget.selecting) {
      Navigator.pop(context, p);
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(
        title: const Text("Who's watching?"),
        actions: [
          IconButton(icon: Icon(editMode ? Icons.check : Icons.edit), onPressed: () => setState(() => editMode = !editMode)),
        ],
      ),
      body: Center(
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 24,
          runSpacing: 24,
          children: [
            for (var i = 0; i < profiles.length; i++) _tile(profiles[i], autofocus: i == 0),
            _addTile(),
          ],
        ),
      ),
    );
  }

  Widget _tile(Profile p, {bool autofocus = false}) {
    final color = kProfileColors[p.colorSeed % kProfileColors.length];
    return SizedBox(
      width: 140,
      child: InkWell(
        autofocus: autofocus,
        borderRadius: BorderRadius.circular(12),
        onTap: () => editMode ? _deleteProfile(p) : _choose(p),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(children: [
            Stack(alignment: Alignment.center, children: [
              CircleAvatar(radius: 48, backgroundColor: color, child: Text(
                  p.name.isEmpty ? '?' : p.name[0].toUpperCase(),
                  style: const TextStyle(fontSize: 36, color: Colors.white))),
              if (editMode) const Positioned(right: 0, top: 0, child: Icon(Icons.close, color: Colors.white70)),
            ]),
            const SizedBox(height: 10),
            Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
          ]),
        ),
      ),
    );
  }

  Widget _addTile() => SizedBox(
        width: 140,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _addProfile,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(children: const [
              CircleAvatar(radius: 48, backgroundColor: Colors.white10, child: Icon(Icons.add, size: 36)),
              SizedBox(height: 10),
              Text('Add profile', style: TextStyle(fontSize: 16)),
            ]),
          ),
        ),
      );
}
