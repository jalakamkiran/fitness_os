import 'package:blueprint_ui/blueprint_ui.dart';
import 'package:flutter/material.dart';

/// Bronze for Odyssey rewards only (not soft-warn amber).
const Color agonBronzeLight = Color(0xFFA9722B);
const Color agonBronzeDark = Color(0xFFE6BD6A);

Color agonBronzeOf(BuildContext context) {
  final brightness = Theme.of(context).brightness;
  return brightness == Brightness.dark ? agonBronzeDark : agonBronzeLight;
}

/// Capability (dates / course) vs habit (rewards) layer tag.
enum LayerTagKind { cap, habit }

class LayerTag extends StatelessWidget {
  const LayerTag(
    this.label, {
    super.key,
    this.kind = LayerTagKind.cap,
  });

  final String label;
  final LayerTagKind kind;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final bronze = agonBronzeOf(context);
    final color = kind == LayerTagKind.habit
        ? Color.lerp(bronze, colors.ink, 0.15)!
        : Color.lerp(colors.accent, colors.ink, 0.3)!;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: color,
            borderRadius: kind == LayerTagKind.habit
                ? BorderRadius.circular(999)
                : BorderRadius.circular(1),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 0.6,
            fontWeight: FontWeight.w500,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// Shared Agon header: brand mark, title/subtitle, optional Pool only pill.
class AgonAppHeader extends StatelessWidget implements PreferredSizeWidget {
  const AgonAppHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.showPoolPill = true,
    this.onBack,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final bool showPoolPill;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final canPop = onBack != null || Navigator.of(context).canPop();

    return Material(
      color: colors.bg,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: Row(
            children: [
              if (canPop)
                _RoundIcon(
                  colors: colors,
                  onTap: onBack ?? () => Navigator.of(context).maybePop(),
                  child: Icon(Icons.chevron_left, color: colors.ink, size: 22),
                )
              else
                const SizedBox(width: 36),
              const SizedBox(width: 10),
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.accent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'F',
                  style: TextStyle(
                    color: colors.accentInk,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: colors.ink,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.inkFaint,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                  ],
                ),
              ),
              if (showPoolPill) ...[
                const SizedBox(width: 8),
                const PoolOnlyPill(),
              ],
              if (trailing != null) ...[
                const SizedBox(width: 4),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class PoolOnlyPill extends StatelessWidget {
  const PoolOnlyPill({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.accent.withValues(alpha: 0.26),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: colors.accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Pool only',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isDark ? colors.accent : colors.accentInk,
            ),
          ),
        ],
      ),
    );
  }
}

class AgonStepBar extends StatelessWidget {
  const AgonStepBar({super.key, this.active = 1, this.total = 3});

  final int active;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    return Row(
      children: [
        for (var i = 0; i < total; i++) ...[
          if (i > 0) const SizedBox(width: 5),
          Expanded(
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: i < active
                    ? colors.accent
                    : colors.ink.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class AgonCard extends StatelessWidget {
  const AgonCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 14),
    this.radius = 18,
    this.borderColor,
    this.background,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? borderColor;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: background ?? colors.bgElev,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? colors.line),
      ),
      child: child,
    );
  }
}

class AgonChip extends StatelessWidget {
  const AgonChip(this.label, {super.key, this.solid = false});

  final String label;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final colors = FathomColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: solid
            ? colors.accent.withValues(alpha: 0.18)
            : colors.ink.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: solid ? colors.ink : colors.inkDim,
        ),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({
    required this.colors,
    required this.onTap,
    required this.child,
  });

  final FathomColors colors;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.bgElev,
      shape: CircleBorder(side: BorderSide(color: colors.line)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: 36, height: 36, child: Center(child: child)),
      ),
    );
  }
}
