import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/branding.dart';
import '../config/theme_controller.dart';
import '../services/ota_installer.dart';
import '../services/ota_service.dart';
import 'tv_widgets.dart';

/// Full-screen "update available" page — the same shape as Ghost's, and a
/// normal route rather than a dialog. Dialogs proved unreliable for remote
/// focus on TV; ordinary screens (login, PIN) never had that problem.
///
/// As a belt-and-braces measure the page also listens for OK/Enter itself,
/// so even if focus somehow isn't on the button, pressing OK still starts
/// the update, and Back/Down reaches "Remind me later".
class UpdateScreen extends StatefulWidget {
  final OtaUpdate update;
  const UpdateScreen({super.key, required this.update});
  @override
  State<UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends State<UpdateScreen> {
  final _pageFocus = FocusNode();
  final _updateFocus = FocusNode();
  bool _downloading = false;
  double _progress = 0;
  String? _error;

  static const _activate = {
    LogicalKeyboardKey.select, LogicalKeyboardKey.enter, LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.gameButtonA, LogicalKeyboardKey.space,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _updateFocus.requestFocus(); });
  }

  @override
  void dispose() {
    _pageFocus.dispose();
    _updateFocus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    // If the button already has focus, let it handle OK normally.
    if (_activate.contains(e.logicalKey) && !_updateFocus.hasFocus && !_downloading) {
      _startUpdate();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _startUpdate() async {
    if (_downloading) return;
    setState(() { _downloading = true; _progress = 0; _error = null; });
    try {
      await OtaInstaller.downloadAndInstall(
        widget.update,
        onProgress: (p) { if (mounted) setState(() => _progress = p); },
      );
      // Android's installer is now on screen; leave this page so the app is
      // in a clean state when it relaunches on the new build.
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() { _downloading = false; _error = scrubSecrets(e); });
        WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _updateFocus.requestFocus(); });
      }
    }
  }

  static String _fmt(int bytes) =>
      bytes < 1024 * 1024 ? '${(bytes / 1024).round()} KB' : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    final u = widget.update;
    final b = Branding.I;
    return Focus(
      focusNode: _pageFocus,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: ThemeController.background.value,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white70, width: 2.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.file_download_outlined, color: Colors.white70, size: 40),
                ),
                const SizedBox(height: 28),
                const Text('Update available', style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
                const SizedBox(height: 14),
                Text(
                  'A new version (build ${u.build}) is available.'
                  '${u.sizeBytes > 0 ? ' (${_fmt(u.sizeBytes)})' : ''}',
                  textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 18),
                ),
                Text('You are on build ${b.buildNumber}.',
                    textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 18)),
                const SizedBox(height: 32),
                if (_downloading) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(value: _progress, minHeight: 12, backgroundColor: Colors.white12),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _progress >= 1.0 ? 'Opening installer…' : 'Downloading… ${(_progress * 100).round()}%',
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                ] else ...[
                  if (_error != null) ...[
                    Text(_error!, textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 14)),
                    const SizedBox(height: 16),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: TvButton(
                      label: _error == null ? 'Update now' : 'Try again',
                      icon: Icons.file_download_outlined,
                      autofocus: true,
                      focusNode: _updateFocus,
                      onPressed: _startUpdate,
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Remind me later', style: TextStyle(color: Colors.white54, fontSize: 16)),
                  ),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
