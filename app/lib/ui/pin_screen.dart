import 'package:flutter/material.dart';

/// A 4-digit PIN pad, remote-friendly (D-pad focusable number buttons
/// instead of a soft keyboard). Pops with the entered PIN once 4 digits
/// are in — the caller decides what to do with it (verify, or store as
/// a new/confirmed PIN).
class PinScreen extends StatefulWidget {
  final String title;
  const PinScreen({super.key, required this.title});
  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  String entered = '';

  void _tap(String d) {
    if (entered.length >= 4) return;
    setState(() => entered += d);
    if (entered.length == 4) {
      Future.delayed(const Duration(milliseconds: 180), () {
        if (mounted) Navigator.pop(context, entered);
      });
    }
  }

  void _backspace() {
    if (entered.isEmpty) return;
    setState(() => entered = entered.substring(0, entered.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(widget.title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 28),
          Row(mainAxisSize: MainAxisSize.min, children: [
            for (int i = 0; i < 4; i++)
              Container(
                width: 20, height: 20, margin: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < entered.length ? Theme.of(context).colorScheme.primary : Colors.white24,
                ),
              ),
          ]),
          const SizedBox(height: 36),
          SizedBox(
            width: 280,
            child: GridView.count(
              shrinkWrap: true,
              crossAxisCount: 3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              children: [
                for (final d in ['1','2','3','4','5','6','7','8','9']) _key(d),
                const SizedBox(),
                _key('0'),
                _backspaceKey(),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _key(String d) {
    return Focus(
      child: Builder(builder: (ctx) {
        final focused = Focus.of(ctx).hasFocus;
        return InkWell(
          onTap: () => _tap(d),
          borderRadius: BorderRadius.circular(30),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: focused ? Theme.of(context).colorScheme.primary : Colors.white10,
            ),
            alignment: Alignment.center,
            child: Text(d, style: const TextStyle(fontSize: 22)),
          ),
        );
      }),
    );
  }

  Widget _backspaceKey() {
    return Focus(
      child: Builder(builder: (ctx) {
        final focused = Focus.of(ctx).hasFocus;
        return InkWell(
          onTap: _backspace,
          borderRadius: BorderRadius.circular(30),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: focused ? Theme.of(context).colorScheme.primary : Colors.white10,
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.backspace_outlined, size: 20),
          ),
        );
      }),
    );
  }
}
