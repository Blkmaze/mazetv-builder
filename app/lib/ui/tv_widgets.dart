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

/// A TextField built for D-pad remotes.
///
/// Plain [TextField]s swallow Up/Down as text-editing shortcuts (moving the
/// cursor) instead of letting them bubble up to focus traversal, so on a TV
/// remote focus gets stuck in the field and OK just reopens the on-screen
/// keyboard. This widget gives the field its own [FocusNode] with
/// `onKeyEvent` wired directly to it, which runs before the built-in text
/// editing shortcuts and lets us hand Up/Down back to [FocusScope] to move
/// to the previous/next field. The on-screen keyboard's "Next" action does
/// the same thing (or triggers [onSubmitted] on the last field in a group).
class TvTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final bool obscureText;
  final bool autofocus;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  final VoidCallback? onSubmitted;

  const TvTextField({
    super.key,
    required this.controller,
    required this.label,
    this.obscureText = false,
    this.autofocus = false,
    this.keyboardType,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
  });

  @override
  State<TvTextField> createState() => _TvTextFieldState();
}

class _TvTextFieldState extends State<TvTextField> {
  late final FocusNode _node;

  @override
  void initState() {
    super.initState();
    _node = FocusNode(onKeyEvent: _handleKey);
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      FocusScope.of(context).nextFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      FocusScope.of(context).previousFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _advance() {
    if (widget.onSubmitted != null) {
      widget.onSubmitted!();
    } else if (widget.textInputAction == TextInputAction.done) {
      _node.unfocus();
    } else {
      FocusScope.of(context).nextFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      focusNode: _node,
      obscureText: widget.obscureText,
      autofocus: widget.autofocus,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      style: const TextStyle(fontSize: 20),
      decoration: InputDecoration(labelText: widget.label, border: const OutlineInputBorder()),
      onSubmitted: (_) => _advance(),
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
