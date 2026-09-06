import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../config/branding.dart';
import '../config/theme_controller.dart';

/// Launch splash: the brand logo scales/fades in over expanding ripple
/// rings, holds a beat, then flies into its spot in the Home header (a
/// Hero with the same tag lives there). Works for any brand — it uses the
/// logo the builder bundled as assets/logo.png.
class SplashScreen extends StatefulWidget {
  final Widget next;
  const SplashScreen({super.key, required this.next});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
  late final Animation<double> _logoScale =
      CurvedAnimation(parent: _c, curve: const Interval(0.0, 0.55, curve: Curves.easeOutBack));
  late final Animation<double> _logoFade =
      CurvedAnimation(parent: _c, curve: const Interval(0.0, 0.35, curve: Curves.easeOut));
  late final Animation<double> _nameFade =
      CurvedAnimation(parent: _c, curve: const Interval(0.45, 0.8, curve: Curves.easeOut));

  @override
  void initState() {
    super.initState();
    _c.forward();
    Future.delayed(const Duration(milliseconds: 1900), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 650),
        pageBuilder: (_, __, ___) => widget.next,
        transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
      ));
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = Branding.I;
    return Scaffold(
      backgroundColor: ThemeController.background.value,
      body: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Stack(alignment: Alignment.center, children: [
          // ripple rings, staggered
          for (var i = 0; i < 3; i++) _Ripple(progress: _c.value, delay: i * 0.18, color: b.primaryColor),
          Column(mainAxisSize: MainAxisSize.min, children: [
            FadeTransition(
              opacity: _logoFade,
              child: ScaleTransition(
                scale: Tween(begin: 0.4, end: 1.0).animate(_logoScale),
                child: Hero(
                  tag: 'brand-logo',
                  child: Image.asset('assets/logo.png', width: 168, height: 168, fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Icon(Icons.tv, size: 120, color: b.primaryColor)),
                ),
              ),
            ),
            const SizedBox(height: 22),
            FadeTransition(
              opacity: _nameFade,
              child: Text(b.appName,
                  style: TextStyle(fontSize: 34, fontWeight: FontWeight.bold, color: b.primaryColor, letterSpacing: 1)),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _Ripple extends StatelessWidget {
  final double progress; // 0..1 overall splash progress
  final double delay;    // 0..1 stagger
  final Color color;
  const _Ripple({required this.progress, required this.delay, required this.color});

  @override
  Widget build(BuildContext context) {
    final t = ((progress - delay) / (1 - delay)).clamp(0.0, 1.0);
    if (t <= 0) return const SizedBox.shrink();
    final size = 180 + 520 * Curves.easeOut.transform(t);
    final opacity = (1 - t) * 0.45;
    return IgnorePointer(
      child: Container(
        width: size, height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color.withOpacity(opacity), width: math.max(1.0, 3.0 * (1 - t))),
        ),
      ),
    );
  }
}
