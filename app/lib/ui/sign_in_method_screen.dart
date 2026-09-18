import 'package:flutter/material.dart';
import '../config/branding.dart';
import '../config/theme_controller.dart';
import 'code_signin_screen.dart';
import 'login_screen.dart';

/// First screen a new viewer sees: "Choose how you want to sign in."
/// Modeled on the reference app's menu — one primary action (type your
/// portal credentials directly) plus two doors into the same companion-
/// device pairing screen (CodeSignInScreen shows both the 6-digit code and
/// its QR together, so "code" and "QR" just emphasize a different way in).
class SignInMethodScreen extends StatelessWidget {
  const SignInMethodScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final b = Branding.I;
    final accent = ThemeController.primaryColor.value;
    return Scaffold(
      backgroundColor: ThemeController.background.value,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Image.asset('assets/logo.png', width: 76, height: 76, fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Icon(Icons.tv, size: 60, color: accent)),
              const SizedBox(height: 16),
              Text(b.appName, textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: accent, letterSpacing: .4)),
              const SizedBox(height: 6),
              const Text('Choose how you want to sign in.',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 17)),
              const SizedBox(height: 32),
              _MethodButton(
                label: 'Login with credentials',
                icon: Icons.login,
                accent: accent,
                filled: true,
                autofocus: true,
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
              ),
              if (b.pairBaseUrl.isNotEmpty) ...[
                const SizedBox(height: 14),
                _MethodButton(
                  label: 'Login with code',
                  icon: Icons.dialpad,
                  accent: accent,
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CodeSignInScreen())),
                ),
                const SizedBox(height: 14),
                _MethodButton(
                  label: 'Login with QR code',
                  icon: Icons.qr_code_2,
                  accent: accent,
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CodeSignInScreen())),
                ),
              ],
              const SizedBox(height: 28),
              const Text('Use the arrow keys to move, OK to select.',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white38, fontSize: 13)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A full-width pill button that fills solid when focused/pressed (primary)
/// or stays outlined until focus lands on it (secondary) — same idea as the
/// reference menu's highlighted vs. outlined rows, built on plain Focus so
/// it lights up correctly from a D-pad, not just touch.
class _MethodButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color accent;
  final VoidCallback onPressed;
  final bool filled;
  final bool autofocus;
  const _MethodButton({
    required this.label,
    required this.icon,
    required this.accent,
    required this.onPressed,
    this.filled = false,
    this.autofocus = false,
  });

  @override
  State<_MethodButton> createState() => _MethodButtonState();
}

class _MethodButtonState extends State<_MethodButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final lit = widget.filled || _focused;
    return Focus(
      onFocusChange: (has) => setState(() => _focused = has),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          autofocus: widget.autofocus,
          onTap: widget.onPressed,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            decoration: BoxDecoration(
              color: lit ? widget.accent.withOpacity(widget.filled ? 0.92 : 0.16) : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: widget.accent.withOpacity(lit ? 0.9 : 0.5), width: 1.6),
              boxShadow: lit ? [BoxShadow(color: widget.accent.withOpacity(0.35), blurRadius: 18, spreadRadius: 1)] : const [],
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(widget.icon, size: 20, color: widget.filled && lit ? Colors.white : widget.accent),
              const SizedBox(width: 12),
              Text(widget.label,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: widget.filled && lit ? Colors.white : widget.accent,
                  )),
            ]),
          ),
        ),
      ),
    );
  }
}
