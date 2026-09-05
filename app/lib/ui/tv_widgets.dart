import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A list row that visibly highlights when the D-pad focus lands on it.
class TvTile extends StatelessWidget {
  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback onSelect;
  final VoidCallback? onLongSelect;
  final ValueChanged<bool>? onFocusChange;
  final bool autofocus;
  final bool selected;

  const TvTile({
    super.key,
    required this.title,
    required this.onSelect,
    this.onLongSelect,
    this.onFocusChange,
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
            onFocusChange?.call(has);
          },
          onTap: onSelect,
          onLongPress: onLongSelect,
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

/// One entry in a collapsible icon nav rail (see [TvNavRail]) — just an
/// icon when collapsed, icon + label when expanded.
class TvRailTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool expanded;
  final VoidCallback onSelect;
  final bool autofocus;
  final bool selected;

  const TvRailTile({
    super.key,
    required this.icon,
    required this.label,
    required this.expanded,
    required this.onSelect,
    this.autofocus = false,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      child: Builder(builder: (ctx) {
        final focused = Focus.of(ctx).hasFocus;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              autofocus: autofocus,
              onTap: onSelect,
              borderRadius: BorderRadius.circular(8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: focused
                      ? primary.withOpacity(0.85)
                      : selected
                          ? Colors.white.withOpacity(0.08)
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  Icon(icon, color: focused ? Colors.white : Colors.white70, size: 22),
                  if (expanded) ...[
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: focused ? Colors.white : Colors.white70, fontSize: 16)),
                    ),
                  ],
                ]),
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// A vertical icon rail that expands to show labels while D-pad focus is
/// anywhere inside it, and collapses back to icon-only once focus moves on
/// (e.g. into the categories list or channel grid) — like a typical TV app's
/// side nav.
class TvNavRail extends StatefulWidget {
  final List<Widget> Function(bool expanded) itemsBuilder;
  const TvNavRail({super.key, required this.itemsBuilder});

  @override
  State<TvNavRail> createState() => _TvNavRailState();
}

class _TvNavRailState extends State<TvNavRail> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (has) => setState(() => expanded = has),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: expanded ? 220 : 76,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: widget.itemsBuilder(expanded),
          ),
        ),
      ),
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

/// A focus-aware poster tile for grid browsing (Movies/Series covers).
class PosterTile extends StatelessWidget {
  final String title;
  final String cover;
  final VoidCallback onSelect;
  final bool autofocus;
  const PosterTile({super.key, required this.title, required this.cover, required this.onSelect, this.autofocus = false});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      child: Builder(builder: (ctx) {
        final focused = Focus.of(ctx).hasFocus;
        return InkWell(
          autofocus: autofocus,
          onTap: onSelect,
          borderRadius: BorderRadius.circular(8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.white10,
                  border: Border.all(color: focused ? primary : Colors.transparent, width: 3),
                ),
                child: cover.isEmpty
                    ? const Center(child: Icon(Icons.movie, color: Colors.white24, size: 40))
                    : Image.network(cover, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.movie, color: Colors.white24, size: 40))),
              ),
            ),
            const SizedBox(height: 6),
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13)),
          ]),
        );
      }),
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
