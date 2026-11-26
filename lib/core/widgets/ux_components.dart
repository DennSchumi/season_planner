import 'dart:math' as math;
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/core/data/enums/subscription_status_enum.dart';
import 'package:season_planner/core/responsive.dart';
import 'package:season_planner/core/theme.dart';
export 'package:season_planner/core/responsive.dart';
import 'package:season_planner/fsAdmin/features/base_admin_view.dart';
import 'package:season_planner/fsAdmin/flight_school_provider.dart';
import 'package:season_planner/fsAdmin/services/flight_school_service.dart';
import 'package:season_planner/user/features/main_scaffold/main_user_scaffold_view.dart';
import 'package:season_planner/user/user_provider.dart';

// ==================== REVOLUT-INSPIRED DESIGN PRIMITIVES ====================

/// Weiße, sanft schattierte Karte mit 20px Radius (ohne harte Material-Rahmen).
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDesktop = context.isDesktop;
    final bg = color ?? cs.surface;
    final br = BorderRadius.circular(radius);
    final effectiveBorder = border ??
        (isDesktop && !isDark
            ? Border.all(color: AppTheme.desktopBorder, width: 1)
            : null);

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: br,
        border: effectiveBorder,
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

/// Kennzeichnet abgesagte Events einheitlich über alle Ansichten:
/// dezentes Ausgrauen + feine rote diagonale Querstreifen mit großem Abstand.
class CanceledEventDecorator extends StatelessWidget {
  final bool isCanceled;
  final Widget child;
  final BorderRadius? borderRadius;
  final double stripeSpacing;
  final double stripeWidth;

  const CanceledEventDecorator({
    super.key,
    required this.isCanceled,
    required this.child,
    this.borderRadius,
    this.stripeSpacing = 32,
    this.stripeWidth = 1.6,
  });

  @override
  Widget build(BuildContext context) {
    if (!isCanceled) return child;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = borderRadius ?? BorderRadius.circular(20);

    return ClipRRect(
      borderRadius: radius,
      child: Stack(
        children: [
          ColorFiltered(
            colorFilter: const ColorFilter.matrix(<double>[
              0.55, 0.35, 0.10, 0, 0,
              0.25, 0.65, 0.10, 0, 0,
              0.25, 0.35, 0.40, 0, 0,
              0, 0, 0, 1, 0,
            ]),
            child: Opacity(
              opacity: isDark ? 0.68 : 0.72,
              child: child,
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _CanceledDiagonalStripesPainter(
                  color: AppTheme.dangerColor.withValues(
                    alpha: isDark ? 0.22 : 0.15,
                  ),
                  tint: (isDark ? Colors.black : Colors.grey)
                      .withValues(alpha: isDark ? 0.12 : 0.06),
                  spacing: stripeSpacing,
                  strokeWidth: stripeWidth,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CanceledDiagonalStripesPainter extends CustomPainter {
  final Color color;
  final Color tint;
  final double spacing;
  final double strokeWidth;

  const _CanceledDiagonalStripesPainter({
    required this.color,
    required this.tint,
    required this.spacing,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = tint,
    );

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    final maxExtent = size.width + size.height;
    for (double x = -size.height; x < maxExtent; x += spacing) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CanceledDiagonalStripesPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.tint != tint ||
      oldDelegate.spacing != spacing ||
      oldDelegate.strokeWidth != strokeWidth;
}

/// Einheitliche Pastell-Status-Pille (helle Füllung, kräftiger Text derselben Farbfamilie).
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

  factory StatusPill.fromEventStatus(String statusName, String label) {
    switch (statusName) {
      case 'provisional':
      case 'confirmed':
        return StatusPill(
          label: label,
          foreground: AppTheme.successColor,
          background: AppTheme.successBg,
        );
      case 'done':
        return StatusPill(
          label: label,
          foreground: AppTheme.swapColor,
          background: AppTheme.swapBg,
        );
      case 'canceled':
      case 'cancelled':
        return StatusPill(
          label: label,
          foreground: AppTheme.dangerColor,
          background: AppTheme.dangerBg,
        );
      case 'scheduled':
      default:
        return StatusPill(
          label: label,
          foreground: AppTheme.infoColor,
          background: AppTheme.infoBg,
        );
    }
  }

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

/// Abgerundetes Pastell-Icon-Badge (10–12px Radius) für Kacheln, Menüs und KPI-Karten.
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

/// Kompakter Datums-Block („21 / NOV“) für Event-Karten in Startseite & Event-Liste.
class DateBadgeBox extends StatelessWidget {
  final DateTime date;
  final Color? accentColor;

  const DateBadgeBox({
    super.key,
    required this.date,
    this.accentColor,
  });

  static const _shortMonths = [
    'JAN',
    'FEB',
    'MÄR',
    'APR',
    'MAI',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OKT',
    'NOV',
    'DEZ',
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? AppTheme.darkCardElevated
        : (accentColor != null
            ? accentColor!.withValues(alpha: 0.08)
            : (context.isDesktop
                ? AppTheme.desktopSurfaceSubtle
                : AppTheme.backgroundColor));

    return Container(
      width: 50,
      height: 54,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            date.day.toString().padLeft(2, '0'),
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              height: 1.05,
              color: accentColor ?? cs.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _shortMonths[date.month - 1],
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Kompakte Kennzahlen-Kachel (Icon-Badge links, Zahl + kurze Caption rechts).
class KpiMetricCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String value;
  final String label;
  final VoidCallback? onTap;

  const KpiMetricCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.value,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SoftCard(
      onTap: onTap,
      radius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          TintedIconBadge(
            icon: icon,
            iconColor: iconColor,
            backgroundColor: iconBg,
            size: 36,
            iconSize: 18,
            radius: 10,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    height: 1.05,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== EXISTING SHARED UX COMPONENTS ====================

/// Einheitliche Empty-State-Komponente mit Icon, kurzem Titel, Erklärung
/// und optionalem Handlungs-Button.
class EmptyStateView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  const EmptyStateView({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TintedIconBadge(
                icon: icon,
                iconColor: cs.primary,
                backgroundColor: AppTheme.primaryTint,
                size: 68,
                iconSize: 32,
                radius: 22,
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  color: cs.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 18),
                FilledButton.tonalIcon(
                  onPressed: onAction,
                  icon: Icon(actionIcon ?? Icons.arrow_forward, size: 18),
                  label: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Einheitlicher Verbindungsstatus-Indikator für die helle/dunkle AppBar.
class ConnectionStatusAction extends StatelessWidget {
  final bool isLoading;
  final bool hasConnection;
  final DateTime? lastUpdated;

  const ConnectionStatusAction({
    super.key,
    required this.isLoading,
    required this.hasConnection,
    required this.lastUpdated,
  });

  String _formatTime(DateTime? d) {
    if (d == null) return 'unbekannt';
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (DesktopShellScope.isInDesktopShell(context)) {
      return const SizedBox.shrink();
    }
    final cs = Theme.of(context).colorScheme;
    final time = _formatTime(lastUpdated);
    final tooltipText = isLoading
        ? 'Synchronisiere Daten...'
        : hasConnection
            ? 'Verbunden (Echtzeit aktiv) · Stand: $time'
            : 'Offline · Letzter Stand: $time';

    final statusColor = hasConnection
        ? AppTheme.successColor
        : AppTheme.warningColor;

    return Tooltip(
      message: tooltipText,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 3),
        child: Material(
          color: cs.surface,
          clipBehavior: Clip.antiAlias,
          shape: StadiumBorder(
            side: BorderSide(color: cs.outlineVariant),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () {
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                SnackBar(
                  content: Text(tooltipText),
                  duration: const Duration(seconds: 3),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isLoading)
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: cs.primary,
                      ),
                    )
                  else
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  const SizedBox(width: 5),
                  Text(
                    isLoading
                        ? 'Sync'
                        : hasConnection
                            ? 'Live'
                            : 'Offline',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Kompakter Kontext-Umschalter „Nutzer ⇄ Admin“ für die AppBar (im modernen
/// Primary-Tint-Pill-Stil – nur sichtbar, wenn der Nutzer Admin ist).
class AppModeSwitchChip extends StatelessWidget {
  final bool isAdminMode;

  const AppModeSwitchChip({
    super.key,
    required this.isAdminMode,
  });

  @override
  Widget build(BuildContext context) {
    if (DesktopShellScope.isInDesktopShell(context)) {
      return const SizedBox.shrink();
    }
    final user = context.watch<UserProvider>().user;
    if (user == null) return const SizedBox.shrink();

    if (!user.isAdmin) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? cs.primaryContainer : AppTheme.primaryTint;
    final fg = isDark ? cs.onPrimaryContainer : AppTheme.primaryColor;

    return Tooltip(
      message: isAdminMode
          ? 'In den Nutzer-Modus wechseln'
          : 'In den Admin-Modus wechseln',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 3),
        child: Material(
          color: bg,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () {
              if (isAdminMode) {
                Navigator.pushAndRemoveUntil(
                  context,
                  fadePageRoute(const MainUserScaffoldView()),
                  (_) => false,
                );
              } else {
                Navigator.push(
                  context,
                  fadePageRoute(const BaseAdminView()),
                );
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isAdminMode
                        ? Icons.person_outline
                        : Icons.admin_panel_settings_outlined,
                    size: 15,
                    color: fg,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    isAdminMode ? 'Nutzer' : 'Admin',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(
                    Icons.swap_horiz,
                    size: 14,
                    color: fg.withValues(alpha: 0.8),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Kompakter Flugschul-Umschalter für die Admin-AppBar.
/// Nur sichtbar, wenn der Benutzer Admin von mindestens zwei Flugschulen ist.
class AdminFlightSchoolSwitcherChip extends StatefulWidget {
  const AdminFlightSchoolSwitcherChip({super.key});

  @override
  State<AdminFlightSchoolSwitcherChip> createState() =>
      _AdminFlightSchoolSwitcherChipState();
}

class _AdminFlightSchoolSwitcherChipState
    extends State<AdminFlightSchoolSwitcherChip> {
  bool _switching = false;

  Future<void> _switchTo(String schoolId) async {
    final fsProvider = context.read<FlightSchoolProvider>();
    if (_switching || fsProvider.flightSchool?.id == schoolId) return;

    setState(() => _switching = true);
    try {
      final fresh = await FlightSchoolService().getFlightSchool(schoolId);
      if (!mounted) return;
      if (fresh == null) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('Flugschule konnte nicht geladen werden.'),
          ),
        );
        return;
      }
      fsProvider.setFlightSchool(fresh);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('Flugschule gewechselt: ${fresh.displayName}'),
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  Widget _schoolMiniLogo(BuildContext context, String logoLink) {
    final cs = Theme.of(context).colorScheme;
    return ClipOval(
      child: logoLink.isEmpty
          ? Container(
              width: 18,
              height: 18,
              color: AppTheme.primaryTint,
              child: Icon(
                Icons.school_outlined,
                size: 11,
                color: cs.primary,
              ),
            )
          : Image.network(
              logoLink,
              width: 18,
              height: 18,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 18,
                height: 18,
                color: AppTheme.primaryTint,
                child: Icon(
                  Icons.school_outlined,
                  size: 11,
                  color: cs.primary,
                ),
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (DesktopShellScope.isInDesktopShell(context)) {
      return const SizedBox.shrink();
    }
    final user = context.watch<UserProvider>().user;
    final activeFs = context.watch<FlightSchoolProvider>().flightSchool;
    if (user == null || activeFs == null) return const SizedBox.shrink();

    final adminSchools = user.adminFlightSchools;
    if (adminSchools.length <= 1) return const SizedBox.shrink();

    final label = activeFs.displayShortName.trim().isNotEmpty
        ? activeFs.displayShortName.trim()
        : activeFs.displayName;
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 3),
      child: Material(
        color: cs.surface,
        clipBehavior: Clip.antiAlias,
        shape: StadiumBorder(
          side: BorderSide(color: cs.outlineVariant),
        ),
        child: PopupMenuButton<String>(
          enabled: !_switching,
          tooltip: 'Flugschule wechseln',
          position: PopupMenuPosition.under,
          onSelected: _switchTo,
          itemBuilder: (_) => adminSchools.map((s) {
            final isCurrent = s.id == activeFs.id;
            return PopupMenuItem<String>(
              value: s.id,
              child: Row(
                children: [
                  ClipOval(
                    child: s.logoLink.isEmpty
                        ? Container(
                            width: 26,
                            height: 26,
                            color: cs.primaryContainer,
                            child: Icon(
                              Icons.school_outlined,
                              size: 15,
                              color: cs.primary,
                            ),
                          )
                        : Image.network(
                            s.logoLink,
                            width: 26,
                            height: 26,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 26,
                              height: 26,
                              color: cs.primaryContainer,
                              child: Icon(
                                Icons.school_outlined,
                                size: 15,
                                color: cs.primary,
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          s.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight:
                                isCurrent ? FontWeight.w800 : FontWeight.w600,
                            fontSize: 13.5,
                          ),
                        ),
                        if (!s.subscriptionStatus.isActive)
                          Text(
                            s.subscriptionStatus.label,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.warningColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (isCurrent) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.check, size: 18, color: cs.primary),
                  ],
                ],
              ),
            );
          }).toList(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_switching)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.primary,
                    ),
                  )
                else
                  _schoolMiniLogo(context, activeFs.logoLink),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 88),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.keyboard_arrow_down,
                  size: 16,
                  color: cs.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dezente Trennlinie zwischen unterschiedlichen AppBar-Aktionen.
class AppBarActionDivider extends StatelessWidget {
  const AppBarActionDivider({super.key});

  @override
  Widget build(BuildContext context) {
    if (DesktopShellScope.isInDesktopShell(context)) {
      return const SizedBox.shrink();
    }
    return Container(
      width: 1,
      height: 18,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

/// Stellt den Scroll-Zustand (`isCompact`) sowie den festen unteren Abstand
/// über der schwebenden Navigationsleiste für Kind-Screens (insb. FABs) bereit.
class FloatingNavScope extends InheritedWidget {
  final bool isCompact;
  final double navBarClearance;

  const FloatingNavScope({
    super.key,
    required this.isCompact,
    this.navBarClearance = 82.0,
    required super.child,
  });

  static FloatingNavScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<FloatingNavScope>();
  }

  @override
  bool updateShouldNotify(covariant FloatingNavScope oldWidget) {
    return oldWidget.isCompact != isCompact ||
        oldWidget.navBarClearance != navBarClearance;
  }
}

/// Schwebender Aktionsbutton, der über einer schwebenden `ModernBottomNavBar`
/// immer sauber oberhalb der Leiste platziert bleibt (ortsfest beim Scrollen)
/// und beim Herunterscrollen analog zur NavBar kompakt auf das Icon schrumpft.
class AdaptiveFloatingActionButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final String? tooltip;

  const AdaptiveFloatingActionButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final scope = FloatingNavScope.maybeOf(context);
    final isCompact = scope?.isCompact ?? false;
    final bottomOffset = scope != null
        ? scope.navBarClearance + MediaQuery.viewPaddingOf(context).bottom
        : 0.0;
    final cs = Theme.of(context).colorScheme;
    final isDisabled = onPressed == null;
    final bg = isDisabled
        ? cs.surfaceContainerHighest
        : cs.primary;
    final fg = isDisabled ? cs.onSurfaceVariant : cs.onPrimary;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomOffset),
      child: Tooltip(
        message: tooltip ?? label,
        child: Material(
          color: bg,
          elevation: isDisabled ? 0 : 4,
          shadowColor: AppTheme.primaryColor.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(18),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              height: isCompact ? 48 : 52,
              padding: EdgeInsets.symmetric(
                horizontal: isCompact ? 13 : 18,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 22, color: fg),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    child: isCompact
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Text(
                              label,
                              style: TextStyle(
                                color: fg,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Eintrag für die moderne, Revolut-inspirierte Bottom-Navigation-Bar.
class ModernNavItem {
  final IconData icon;
  final String label;
  final int badgeCount;
  final bool showBadgeDot;
  final Color? badgeColor;

  const ModernNavItem({
    required this.icon,
    required this.label,
    this.badgeCount = 0,
    this.showBadgeDot = false,
    this.badgeColor,
  });
}

/// Schwebende, Revolut-inspirierte Glassmorphism-Pill-Navigation:
/// - Listen laufen dahinter weiter und blenden über einen weichen Bottom-Fade aus.
/// - Beim Herunterscrollen (`isCompact: true`) schrumpft die Kapsel sanft und
///   blendet die Text-Beschriftungen aus (nur noch Icons).
class ModernBottomNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<ModernNavItem> items;
  final bool isCompact;

  const ModernBottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.items,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = Theme.of(context).scaffoldBackgroundColor;
    final activeBg = isDark ? cs.primaryContainer : AppTheme.primaryTint;
    final activeFg = isDark ? cs.onPrimaryContainer : AppTheme.primaryColor;
    final inactiveFg = cs.onSurfaceVariant;
    final capsuleBg = isDark
        ? AppTheme.darkCardElevated.withValues(alpha: 0.86)
        : Colors.white.withValues(alpha: 0.88);
    final capsuleBorder = isDark
        ? AppTheme.darkBorder.withValues(alpha: 0.85)
        : AppTheme.borderSubtle.withValues(alpha: 0.85);
    final maxBarWidth = items.length >= 5
        ? (isCompact ? 420.0 : 520.0)
        : (isCompact ? 340.0 : 420.0);

    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        // Weicher Fade-Verlauf hinter der schwebenden Navigationsleiste (Revolut-Stil)
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    scaffoldBg.withValues(alpha: 0.0),
                    scaffoldBg.withValues(alpha: 0.52),
                    scaffoldBg.withValues(alpha: 0.90),
                    scaffoldBg,
                  ],
                  stops: const [0.0, 0.42, 0.78, 1.0],
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.fromLTRB(
              16,
              isCompact ? 10 : 12,
              16,
              isCompact ? 10 : 12,
            ),
            child: Center(
              heightFactor: 1.0,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                constraints: BoxConstraints(maxWidth: maxBarWidth),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: isDark
                      ? const [
                          BoxShadow(
                            color: Color(0x40000000),
                            blurRadius: 18,
                            spreadRadius: -2,
                            offset: Offset(0, 6),
                          ),
                        ]
                      : const [
                          BoxShadow(
                            color: Color(0x0D11131A),
                            blurRadius: 6,
                            offset: Offset(0, 1),
                          ),
                          BoxShadow(
                            color: Color(0x1611131A),
                            blurRadius: 20,
                            spreadRadius: -2,
                            offset: Offset(0, 6),
                          ),
                        ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      padding: EdgeInsets.symmetric(
                        horizontal: isCompact ? 5 : 6,
                        vertical: isCompact ? 4 : 5,
                      ),
                      decoration: BoxDecoration(
                        color: capsuleBg,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: capsuleBorder, width: 1),
                      ),
                      child: Row(
                        children: List.generate(items.length, (index) {
                          final item = items[index];
                          final isSelected = index == selectedIndex;

                          Widget iconWidget = Icon(
                            item.icon,
                            size: isCompact ? 22 : 21,
                            color: isSelected ? activeFg : inactiveFg,
                          );

                          if (item.badgeCount > 0) {
                            iconWidget = Badge(
                              backgroundColor:
                                  item.badgeColor ?? AppTheme.dangerColor,
                              label: Text(
                                item.badgeCount > 99
                                    ? '99+'
                                    : '${item.badgeCount}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              child: iconWidget,
                            );
                          } else if (item.showBadgeDot) {
                            iconWidget = Badge(
                              smallSize: 8.5,
                              backgroundColor:
                                  item.badgeColor ?? AppTheme.infoColor,
                              child: iconWidget,
                            );
                          }

                          return Expanded(
                            child: Center(
                              heightFactor: 1.0,
                              child: Material(
                                color: Colors.transparent,
                                shape: const StadiumBorder(),
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  customBorder: const StadiumBorder(),
                                  onTap: () => onSelected(index),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 220),
                                    curve: Curves.easeOutCubic,
                                    constraints: BoxConstraints(
                                      minWidth: isCompact ? 52 : 64,
                                    ),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: isCompact ? 12 : 14,
                                      vertical: isCompact ? 9 : 7,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? activeBg
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        iconWidget,
                                        AnimatedSize(
                                          duration:
                                              const Duration(milliseconds: 200),
                                          curve: Curves.easeOutCubic,
                                          child: isCompact
                                              ? const SizedBox.shrink()
                                              : Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                    top: 2.5,
                                                  ),
                                                  child: Text(
                                                    item.label,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 10.5,
                                                      fontWeight: isSelected
                                                          ? FontWeight.w700
                                                          : FontWeight.w500,
                                                      color: isSelected
                                                          ? activeFg
                                                          : inactiveFg,
                                                      height: 1.1,
                                                    ),
                                                  ),
                                                ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Hilfsfunktion zum Formatieren einer Dauer (z. B. "2 Std.", "1 Std. 30 Min.", "3 Tage").
String formatDurationCompact(DateTime start, DateTime end) {
  final diff = end.difference(start);
  if (diff.isNegative || diff.inMinutes == 0) return '0 Min.';
  final days = diff.inDays;
  final hours = diff.inHours % 24;
  final mins = diff.inMinutes % 60;
  if (days >= 1) {
    if (hours == 0) return '$days ${days == 1 ? "Tag" : "Tage"}';
    return '$days ${days == 1 ? "Tag" : "Tage"} $hours Std.';
  }
  if (hours >= 1 && mins > 0) return '$hours Std. $mins Min.';
  if (hours >= 1) return '$hours Std.';
  return '$mins Min.';
}

/// Weicher Überblendungs-Übergang (Fade + dezenter Scale) zwischen Screens.
PageRoute<T> fadePageRoute<T>(
  Widget page, {
  Duration duration = const Duration(milliseconds: 360),
}) {
  return PageRouteBuilder<T>(
    pageBuilder: (_, __, ___) => page,
    transitionDuration: duration,
    reverseTransitionDuration: const Duration(milliseconds: 260),
    transitionsBuilder: (_, animation, __, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.985, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Sanfter Crossfade-Transition-Builder für `AnimatedSwitcher` (Loading -> Content).
Widget softCrossfadeTransition(Widget child, Animation<double> animation) {
  final curved = CurvedAnimation(
    parent: animation,
    curve: Curves.easeOutCubic,
  );
  return FadeTransition(
    opacity: curved,
    child: ScaleTransition(
      scale: Tween<double>(begin: 0.985, end: 1.0).animate(curved),
      child: child,
    ),
  );
}

/// Moderner Ladescreen mit sanft im Kreis thermikendem Gleitschirm-Icon
/// und weichem Gradient-Spurkreis (ohne harte Schnitte).
class ParagliderLoadingView extends StatefulWidget {
  final String? message;
  final bool asScaffold;

  const ParagliderLoadingView({
    super.key,
    this.message,
    this.asScaffold = true,
  });

  @override
  State<ParagliderLoadingView> createState() => _ParagliderLoadingViewState();
}

class _ParagliderLoadingViewState extends State<ParagliderLoadingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = isDark ? AppTheme.darkPrimary : AppTheme.primaryColor;
    final tint = isDark ? cs.primaryContainer : AppTheme.primaryTint;

    final content = Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              final angle = _ctrl.value * 2 * math.pi;
              final breathe = 0.94 + 0.06 * math.sin(angle);
              const double orbitRadius = 32;
              final dx = math.cos(angle - math.pi / 2) * orbitRadius;
              final dy = math.sin(angle - math.pi / 2) * orbitRadius;

              return SizedBox(
                width: 108,
                height: 108,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Sanft atmender Hintergrund-Kreis
                    Transform.scale(
                      scale: breathe,
                      child: Container(
                        width: 78,
                        height: 78,
                        decoration: BoxDecoration(
                          color: tint.withValues(alpha: isDark ? 0.45 : 0.72),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    // Rotierender Thermik-Spurkreis
                    Transform.rotate(
                      angle: angle,
                      child: CustomPaint(
                        size: const Size(74, 74),
                        painter: _ThermalArcPainter(color: primary),
                      ),
                    ),
                    // Sanft im Kreis gleitendes Gleitschirm-Icon
                    Transform.translate(
                      offset: Offset(dx, dy),
                      child: Transform.rotate(
                        angle: angle,
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: primary,
                            shape: BoxShape.circle,
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x405B3DF5),
                                blurRadius: 12,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.paragliding_rounded,
                            color: Colors.white,
                            size: 19,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          if (widget.message != null && widget.message!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              widget.message!,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ],
      ),
    );

    if (!widget.asScaffold) return content;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: content,
    );
  }
}

class _ThermalArcPainter extends CustomPainter {
  final Color color;
  const _ThermalArcPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - 6) / 2;

    final trackPaint = Paint()
      ..color = color.withValues(alpha: 0.14)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6;
    canvas.drawCircle(center, radius, trackPaint);

    final sweepPaint = Paint()
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: 1.5 * math.pi,
        colors: [
          color.withValues(alpha: 0.0),
          color.withValues(alpha: 0.18),
          color.withValues(alpha: 0.85),
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      1.85 * math.pi,
      false,
      sweepPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ThermalArcPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Einheitliches Status-Farbschema aus AppTheme.
Color eventStatusColor(String statusName) {
  switch (statusName) {
    case 'provisional':
    case 'confirmed':
      return AppTheme.successColor;
    case 'done':
      return AppTheme.swapColor;
    case 'canceled':
    case 'cancelled':
      return AppTheme.dangerColor;
    case 'scheduled':
    default:
      return AppTheme.infoColor;
  }
}

/// Deutlicher Hinweis-Dialog für Nutzer, wenn eine Buchung / Zusage / Bewerbung
/// wegen einer zeitlichen Doppelbesetzung (auch schulübergreifend) nicht möglich ist.
Future<void> showUserBookingConflictDialog(
  BuildContext context, {
  required String reason,
}) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      return AlertDialog(
        title: const Row(
          children: [
            TintedIconBadge(
              icon: Icons.block_rounded,
              iconColor: AppTheme.dangerColor,
              backgroundColor: AppTheme.dangerBg,
              size: 36,
              iconSize: 20,
              radius: 10,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Doppelbelegung nicht möglich',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Du bist in diesem Zeitraum bereits anderweitig verplant oder hast dich auf einen zeitgleichen Einsatz gemeldet.',
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? AppTheme.dangerColor.withValues(alpha: 0.14)
                    : AppTheme.dangerBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.dangerColor.withValues(alpha: 0.30),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.error_outline_rounded,
                      size: 16,
                      color: AppTheme.dangerColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      reason,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                        color: isDark
                            ? const Color(0xFFFCA5A5)
                            : AppTheme.dangerColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Verstanden'),
          ),
        ],
      );
    },
  );
}

/// Einheitlicher Bestätigungsdialog für Admins bei personellen Doppelbesetzungen
/// (z. B. zwei zeitgleiche Events, Event + Tandem oder Terminverschiebung).
/// Gibt `true` zurück, wenn der Admin die Warnung ausdrücklich bestätigt.
Future<bool> showAdminDoubleBookingConfirmDialog(
  BuildContext context, {
  String title = 'Doppelbesetzung bestätigen',
  required String message,
  List<String> conflicts = const [],
  String confirmLabel = 'Trotzdem einteilen',
}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      return AlertDialog(
        title: Row(
          children: [
            const TintedIconBadge(
              icon: Icons.warning_amber_rounded,
              iconColor: AppTheme.dangerColor,
              backgroundColor: AppTheme.dangerBg,
              size: 36,
              iconSize: 20,
              radius: 10,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.4,
                    color: cs.onSurface,
                  ),
                ),
                if (conflicts.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppTheme.dangerColor.withValues(alpha: 0.14)
                          : AppTheme.dangerBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.dangerColor.withValues(alpha: 0.30),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < conflicts.length; i++) ...[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: Icon(
                                  Icons.error_outline_rounded,
                                  size: 15,
                                  color: AppTheme.dangerColor,
                                ),
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  conflicts[i],
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    height: 1.35,
                                    color: isDark
                                        ? const Color(0xFFFCA5A5)
                                        : AppTheme.dangerColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (i != conflicts.length - 1)
                            const SizedBox(height: 6),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.dangerColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return res == true;
}
