import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A list row that visibly highlights when the D-pad focus lands on it.
class TvTile extends StatelessWidget {
  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback onSelect;
  final bool autofocus;
  final bool selected;

  const TvTile({
    super.key,
    required this.title,
    required this.onSelect,
    this.subtitle,
    this.leading,
    this.trailing,
    this.autofocus = false,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    // Outer Focus only observes; the InkWell owns the real focus node so
    // OK/Enter on the remote fires onSelect.
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      child: Builder(builder: (ctx) {
        final focused = Focus.of(ctx).hasFocus;
        return InkWell(
          autofocus: autofocus,
          onFocusChange: (has) {
            // Keep the focused row on screen when the remote moves focus
            // past the edge of what's currently visible.
            if (has) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (ctx.mounted) {
                  Scrollable.maybeOf(ctx)?.position.ensureVisible(
                        ctx.findRenderObject()!,
                        alignment: 0.5,
                        duration: const Duration(milliseconds: 150),
                      );
                }
              });
            }
          },
          onTap: onSelect,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              color: focused
                  ? primary.withOpacity(0.85)
                  : selected
                      ? Colors.white.withOpacity(0.08)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListTile(
              leading: leading,
              title: title,
              subtitle: subtitle,
              trailing: trailing,
              textColor: focused ? Colors.white : null,
            ),
          ),
        );
      }),
    );
  }
}

class TvButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onPressed;
  final bool autofocus;
  const TvButton({super.key, required this.label, required this.onPressed, this.icon, this.autofocus = false});

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      autofocus: autofocus,
      onPressed: onPressed,
      icon: Icon(icon ?? Icons.chevron_right),
      label: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        child: Text(label, style: const TextStyle(fontSize: 20)),
      ),
    );
  }
}

class ChannelLogo extends StatelessWidget {
  final String url;
  final double size;
  const ChannelLogo(this.url, {super.key, this.size = 44});
  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return Icon(Icons.tv, size: size * 0.8);
    return SizedBox(
      width: size, height: size,
      child: Image.network(url, fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Icon(Icons.tv, size: size * 0.8)),
    );
  }
}

Future<void> showError(BuildContext context, Object e) => showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Something went wrong'),
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        actions: [TextButton(autofocus: true, onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );

/// TextField that behaves on a remote: Up/Down move to the previous/next
/// field instead of moving the text cursor, and the keyboard's Next key
/// also advances. Left/Right still move the cursor.
class TvTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final bool obscure;
  final bool autofocus;
  final bool last;
  const TvTextField({super.key, required this.controller, required this.label,
      this.obscure = false, this.autofocus = false, this.last = false});
  @override
  State<TvTextField> createState() => _TvTextFieldState();
}

class _TvTextFieldState extends State<TvTextField> {
  late final FocusNode node = FocusNode(onKeyEvent: (n, e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.arrowDown) { n.nextFocus(); return KeyEventResult.handled; }
    if (e.logicalKey == LogicalKeyboardKey.arrowUp) { n.previousFocus(); return KeyEventResult.handled; }
    return KeyEventResult.ignored;
  });

  @override
  void dispose() { node.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: widget.controller,
        focusNode: node,
        obscureText: widget.obscure,
        autofocus: widget.autofocus,
        textInputAction: widget.last ? TextInputAction.done : TextInputAction.next,
        onSubmitted: (_) => widget.last ? node.unfocus() : node.nextFocus(),
        style: const TextStyle(fontSize: 20),
        decoration: InputDecoration(labelText: widget.label, border: const OutlineInputBorder()),
      ),
    );
  }
}
