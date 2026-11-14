import 'package:flutter/material.dart';

import 'field_guide_theme.dart';

/// Open or Closed pill. Open has a 6 dp leading dot, Closed has none.
class StatusPill extends StatelessWidget {
  const StatusPill({required this.closed, super.key});
  final bool closed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = !closed
        ? scheme.primaryContainer
        : scheme.surfaceContainerHighest;
    final foreground = !closed
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: background,
        shape: const StadiumBorder(),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!closed) ...[
              ExcludeSemantics(
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: foreground,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              closed ? 'Closed' : 'Open',
              style: FieldGuideType.facts.copyWith(color: foreground),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bookmark icon plus the text "Saved", both in the secondary color.
class SavedMark extends StatelessWidget {
  const SavedMark({super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.secondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(child: Icon(Icons.bookmark, size: 16, color: color)),
        const SizedBox(width: 4),
        Text('Saved', style: FieldGuideType.facts.copyWith(color: color)),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.icon,
    required this.background,
    required this.foreground,
    required this.child,
  });
  final IconData icon;
  final Color background, foreground;
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: Icon(icon, size: 20, color: foreground)),
          const SizedBox(width: 12),
          Expanded(
            child: DefaultTextStyle.merge(
              style: FieldGuideType.facts.copyWith(color: foreground),
              child: child,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Warning-style panel: stale walks, failed refresh with cached walks.
class NoticePanel extends StatelessWidget {
  const NoticePanel({required this.message, super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Panel(
      icon: Icons.info,
      background: scheme.secondaryContainer,
      foreground: scheme.onSecondaryContainer,
      child: Text(message),
    );
  }
}

/// Error panel: initial load failure, save failure.
class ErrorPanel extends StatelessWidget {
  const ErrorPanel({required this.message, this.headline, super.key});
  final String message;

  /// Optional first line, shown above [message] as its own text.
  final String? headline;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Panel(
      icon: Icons.warning,
      background: scheme.errorContainer,
      foreground: scheme.onErrorContainer,
      child: headline == null
          ? Text(message)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline!,
                  style: FieldGuideType.factValue.copyWith(
                    color: scheme.onErrorContainer,
                  ),
                ),
                const SizedBox(height: 4),
                Text(message),
              ],
            ),
    );
  }
}

/// Centered body text with no container: no matches, walk unavailable.
class QuietMessage extends StatelessWidget {
  const QuietMessage({required this.message, super.key});
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 32),
    child: Text(
      message,
      textAlign: TextAlign.center,
      style: FieldGuideType.body.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

/// Three equal captioned columns between hairlines. At large text scales the
/// columns stack as caption and value pairs so nothing overflows (stacked when
/// the text scale is 1.3 or more).
class FactsRow extends StatelessWidget {
  const FactsRow({
    required this.duration,
    required this.distance,
    required this.terrain,
    super.key,
  });
  final String duration, distance, terrain;

  Widget _fact(BuildContext context, String caption, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          caption,
          style: FieldGuideType.facts.copyWith(color: scheme.onSurfaceVariant),
        ),
        Text(
          value,
          style: FieldGuideType.factValue.copyWith(color: scheme.onSurface),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hairline = BorderSide(color: scheme.outlineVariant);
    final stacked = MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    final facts = [
      _fact(context, 'Time', duration),
      _fact(context, 'Distance', distance),
      _fact(context, 'Terrain', terrain),
    ];
    Widget divider() => Container(
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: scheme.outlineVariant,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: hairline, bottom: hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < facts.length; i++) ...[
                    if (i > 0)
                      Container(
                        height: 1,
                        margin: const EdgeInsets.symmetric(vertical: 12),
                        color: scheme.outlineVariant,
                      ),
                    facts[i],
                  ],
                ],
              )
            : IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: facts[0]),
                    divider(),
                    Expanded(child: facts[1]),
                    divider(),
                    Expanded(child: facts[2]),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Static loading placeholder in the shape of a walk card. Callers exclude it
/// from semantics.
class PlaceholderCard extends StatelessWidget {
  const PlaceholderCard({super.key});

  @override
  Widget build(BuildContext context) {
    final block = Theme.of(context).colorScheme.surfaceContainerHighest;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: block,
        borderRadius: BorderRadius.circular(22),
      ),
      child: const SizedBox(height: 240, width: double.infinity),
    );
  }
}

/// 40 dp circular opaque surface button with a hairline rim, pinned over the
/// hero image and the content that scrolls beneath it.
class HeroIconButton extends StatelessWidget {
  const HeroIconButton({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    super.key,
  });
  final String tooltip;
  final VoidCallback? onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        backgroundColor: scheme.surface,
        side: BorderSide(color: scheme.outlineVariant),
        foregroundColor: scheme.onSurface,
        fixedSize: const Size(40, 40),
        minimumSize: const Size(40, 40),
        padding: EdgeInsets.zero,
      ),
    );
  }
}
