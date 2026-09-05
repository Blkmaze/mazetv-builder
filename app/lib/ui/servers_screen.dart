import 'package:flutter/material.dart';
import '../models/server_config.dart';
import '../services/storage.dart';
import 'server_form.dart';
import 'tv_widgets.dart';

/// Manage the prioritized list of servers/DNS endpoints used for failover.
/// List order *is* the failover order (top = tried first among enabled
/// ones) — there's no separate "active" pointer to keep in sync with it.
/// The caller (HomeScreen) always reloads with the current list after this
/// screen pops.
class ServersScreen extends StatefulWidget {
  const ServersScreen({super.key});
  @override
  State<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends State<ServersScreen> {
  List<ServerConfig> servers = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    servers = await Storage.loadServers();
    servers.sort((a, b) => a.priority.compareTo(b.priority));
    if (mounted) setState(() => loading = false);
  }

  Future<void> _persist() async {
    for (var i = 0; i < servers.length; i++) {
      servers[i] = servers[i].copyWith(priority: i);
    }
    await Storage.saveServers(servers);
    final p = _primary();
    if (p != null) await Storage.setActiveServerId(p.id);
    if (mounted) setState(() {});
  }

  /// The server failover will actually try first: the highest-priority
  /// (topmost) *enabled* one.
  ServerConfig? _primary() {
    for (final s in servers) {
      if (s.enabled) return s;
    }
    return null;
  }

  Future<void> _add() async {
    final s = await showServerForm(context);
    if (s == null) return;
    servers.add(s);
    await _persist();
  }

  Future<void> _edit(ServerConfig s) async {
    final updated = await showServerForm(context, existing: s);
    if (updated == null) return;
    final i = servers.indexWhere((e) => e.id == s.id);
    if (i != -1) servers[i] = updated;
    await _persist();
  }

  Future<void> _delete(ServerConfig s) async {
    servers.removeWhere((e) => e.id == s.id);
    await _persist();
  }

  Future<void> _toggleEnabled(ServerConfig s, bool v) async {
    final i = servers.indexWhere((e) => e.id == s.id);
    servers[i] = s.copyWith(enabled: v);
    await _persist();
  }

  Future<void> _move(int index, int delta) async {
    final j = index + delta;
    if (j < 0 || j >= servers.length) return;
    final tmp = servers[index];
    servers[index] = servers[j];
    servers[j] = tmp;
    await _persist();
  }

  /// Convenience: jump a server straight to the top of the failover order
  /// (and make sure it's enabled), instead of clicking the up arrow N times.
  Future<void> _makePrimary(ServerConfig s) async {
    servers.removeWhere((e) => e.id == s.id);
    servers.insert(0, s.enabled ? s : s.copyWith(enabled: true));
    await _persist();
  }

  @override
  Widget build(BuildContext context) {
    final primary = _primary();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Servers'),
        actions: [IconButton(icon: const Icon(Icons.add), tooltip: 'Add server', onPressed: _add)],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : servers.isEmpty
              ? Center(
                  child: TvButton(label: 'Add your first server', icon: Icons.add, autofocus: true, onPressed: _add),
                )
              : Column(children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Top = tried first. Tap a server to make it primary.',
                          style: TextStyle(color: Colors.white54, fontSize: 13)),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      itemCount: servers.length,
                      itemBuilder: (_, i) {
                        final s = servers[i];
                        final isPrimary = primary != null && s.id == primary.id;
                        return TvTile(
                          autofocus: i == 0,
                          leading: Icon(isPrimary ? Icons.star : Icons.dns, color: isPrimary ? Colors.amber : null),
                          title: Text(s.nickname),
                          subtitle: Text(
                            '${s.account.type.name.toUpperCase()} · ${s.account.host}'
                            '${isPrimary ? '  ·  primary' : (s.enabled ? '' : '  ·  disabled')}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(icon: const Icon(Icons.arrow_upward), onPressed: i == 0 ? null : () => _move(i, -1)),
                            IconButton(icon: const Icon(Icons.arrow_downward), onPressed: i == servers.length - 1 ? null : () => _move(i, 1)),
                            Switch(value: s.enabled, onChanged: (v) => _toggleEnabled(s, v)),
                            IconButton(icon: const Icon(Icons.edit), onPressed: () => _edit(s)),
                            IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(s)),
                          ]),
                          onSelect: () => _makePrimary(s),
                        );
                      },
                    ),
                  ),
                ]),
    );
  }
}
