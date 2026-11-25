import 'package:flutter/material.dart';
import 'package:inventar_manager/core/theme.dart';

/// Weiße (im Dark Mode dunkle), sanft schattierte Karte mit 20px Radius.
class SoftCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final Color? color;
  final Border? border;
  final double radius;

  const SoftCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.color,
    this.border,
    this.radius = 20,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = color ?? cs.surface;
    final br = BorderRadius.circular(radius);

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: br,
        border: border,
        boxShadow: AppTheme.cardShadow(context),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: br,
        clipBehavior: Clip.antiAlias,
        child: onTap != null
            ? InkWell(
                onTap: onTap,
                borderRadius: br,
                child: padding != null
                    ? Padding(padding: padding!, child: child)
                    : child,
              )
            : (padding != null
                ? Padding(padding: padding!, child: child)
                : child),
      ),
    );
  }
}

/// Einheitliche Pastell-Status-Pille (helle Füllung, kräftiger Text).
class StatusPill extends StatelessWidget {
  final String label;
  final Color foreground;
  final Color background;
  final IconData? icon;
  final double fontSize;

  const StatusPill({
    super.key,
    required this.label,
    required this.foreground,
    required this.background,
    this.icon,
    this.fontSize = 11.5,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? foreground.withValues(alpha: 0.18) : background;
    final fg = isDark
        ? Color.lerp(foreground, Colors.white, 0.35) ?? foreground
        : foreground;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: fontSize + 1.5, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              color: fg,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }
}

/// Abgerundetes Pastell-Icon-Badge (10–12px Radius) für Kacheln und Menüs.
class TintedIconBadge extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;
  final double size;
  final double iconSize;
  final double radius;

  const TintedIconBadge({
    super.key,
    required this.icon,
    this.iconColor = AppTheme.primaryColor,
    this.backgroundColor = AppTheme.primaryTint,
    this.size = 40,
    this.iconSize = 20,
    this.radius = 12,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? iconColor.withValues(alpha: 0.18) : backgroundColor;
    final fg = isDark
        ? Color.lerp(iconColor, Colors.white, 0.30) ?? iconColor
        : iconColor;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(icon, size: iconSize, color: fg),
    );
  }
}

/// Sanfter Fade-Übergang zwischen Top-Level-Screens (z. B. Login ↔ App).
Route<T> fadePageRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, _, _) => page,
    transitionsBuilder: (_, animation, _, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      );
    },
  );
}
