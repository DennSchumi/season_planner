import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/core/data/enums/subscription_status_enum.dart';
import 'package:season_planner/core/theme.dart';
import 'package:season_planner/core/widgets/user_avatar.dart';
import 'package:season_planner/core/widgets/ux_components.dart';
import 'package:season_planner/fsAdmin/features/base_admin_view.dart';
import 'package:season_planner/fsAdmin/flight_school_provider.dart';
import 'package:season_planner/fsAdmin/services/flight_school_service.dart';
import 'package:season_planner/user/features/main_scaffold/main_user_scaffold_view.dart';
import 'package:season_planner/user/user_provider.dart';

/// Ruhige, aufgeräumte Desktop-Shell für PC-Browser (`>= 960 px`):
/// - Feste (optional einklappbare) linke Sidebar auf sehr hellem Warm-Ton (`#F6F6F4`)
/// - Nahezu reinweißer Content-Bereich (`#FCFCFB`) mit begrenzter Lesebreite
/// - Live-Status, Modus-Wechsel (Nutzer ⇄ Admin) und Profil sauber in der Sidebar integriert
class DesktopAppShell extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<ModernNavItem> items;
  final Widget child;
  final bool isAdminMode;
  final bool isLoading;
  final bool hasConnection;
  final DateTime? lastUpdated;
  final double maxContentWidth;
  final VoidCallback? onTapUserProfile;

  const DesktopAppShell({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.items,
    required this.child,
    required this.isAdminMode,
    required this.isLoading,
    required this.hasConnection,
    required this.lastUpdated,
    this.maxContentWidth = 1240,
    this.onTapUserProfile,
  });

  @override
  State<DesktopAppShell> createState() => _DesktopAppShellState();
}

class _DesktopAppShellState extends State<DesktopAppShell> {
  bool _collapsed = false;
  bool _switchingSchool = false;

  String _formatTime(DateTime? d) {
    if (d == null) return 'unbekannt';
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _switchAdminSchool(String schoolId) async {
    final fsProvider = context.read<FlightSchoolProvider>();
    if (_switchingSchool || fsProvider.flightSchool?.id == schoolId) return;

    setState(() => _switchingSchool = true);
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
      if (mounted) setState(() => _switchingSchool = false);
    }
  }

  void _switchMode() {
    if (widget.isAdminMode) {
      Navigator.pushAndRemoveUntil(
        context,
        fadePageRoute(const MainUserScaffoldView()),
        (_) => false,
      );
    } else {
      Navigator.push(context, fadePageRoute(const BaseAdminView()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final user = context.watch<UserProvider>().user;
    final activeFs = widget.isAdminMode
        ? context.watch<FlightSchoolProvider>().flightSchool
        : null;

    final isAdmin =
        user != null &&
        user.flightSchools.any((fs) => fs.adminUserIds.contains(user.id));
    final adminSchools = user == null
        ? const []
        : user.flightSchools
              .where((fs) => fs.adminUserIds.contains(user.id))
              .toList();

    final sidebarBg = isDark ? AppTheme.darkCard : AppTheme.desktopSidebar;
    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.desktopBorder;
    final canvasBg = isDark
        ? AppTheme.darkBackground
        : AppTheme.desktopBackground;
    final sidebarWidth = _collapsed ? 76.0 : 252.0;

    return Scaffold(
      backgroundColor: canvasBg,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ==================== LINKE DESKTOP-SIDEBAR ====================
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            width: sidebarWidth,
            decoration: BoxDecoration(
              color: sidebarBg,
              border: Border(right: BorderSide(color: borderColor, width: 1)),
            ),
            child: SafeArea(
              right: false,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Während der Breiten-Animation von 76 -> 252 px erst dann auf
                  // die ausgeklappten Rows umschalten, wenn genügend Platz da ist
                  // (verhindert RenderFlex-Overflows in Zwischenframes).
                  final compact = _collapsed || constraints.maxWidth < 185;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Brand / Header + Collapse-Toggle
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          compact ? 14 : 16,
                          16,
                          compact ? 14 : 12,
                          12,
                        ),
                        child: compact
                            ? Column(
                                children: [
                                  const _BrandMark(size: 38),
                                  const SizedBox(height: 10),
                                  IconButton(
                                    tooltip: 'Seitenleiste ausklappen',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () =>
                                        setState(() => _collapsed = false),
                                    icon: Icon(
                                      Icons.keyboard_double_arrow_right_rounded,
                                      size: 19,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              )
                            : Row(
                                children: [
                                  const _BrandMark(size: 36),
                                  const SizedBox(width: 11),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'Season Planner',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: -0.3,
                                            color: cs.onSurface,
                                          ),
                                        ),
                                        const SizedBox(height: 1),
                                        Text(
                                          widget.isAdminMode
                                              ? 'Admin-Bereich'
                                              : 'Team-Ansicht',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w600,
                                            color: widget.isAdminMode
                                                ? cs.primary
                                                : cs.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Seitenleiste einklappen',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () =>
                                        setState(() => _collapsed = true),
                                    icon: Icon(
                                      Icons.keyboard_double_arrow_left_rounded,
                                      size: 19,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                      ),

                      // Admin: aktive Flugschule + ggf. Flugschul-Umschalter
                      if (widget.isAdminMode && activeFs != null && !compact)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          child: _SidebarSchoolCard(
                            schoolName: activeFs.displayName,
                            logoLink: activeFs.logoLink,
                            switching: _switchingSchool,
                            adminSchools: adminSchools,
                            activeSchoolId: activeFs.id,
                            onSelectSchool: _switchAdminSchool,
                          ),
                        ),

                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: compact ? 14 : 16,
                        ),
                        child: Divider(color: borderColor, height: 1),
                      ),
                      const SizedBox(height: 10),

                      // Navigationspunkte
                      Expanded(
                        child: ListView.separated(
                          padding: EdgeInsets.symmetric(
                            horizontal: compact ? 10 : 12,
                            vertical: 4,
                          ),
                          itemCount: widget.items.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 4),
                          itemBuilder: (context, index) {
                            final item = widget.items[index];
                            final isSelected = index == widget.selectedIndex;
                            return _SidebarNavTile(
                              item: item,
                              isSelected: isSelected,
                              collapsed: compact,
                              onTap: () => widget.onSelected(index),
                            );
                          },
                        ),
                      ),

                      // Unterer Bereich: Live-Status, Modus-Umschalter, Nutzerprofil
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: compact ? 14 : 16,
                        ),
                        child: Divider(color: borderColor, height: 1),
                      ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          compact ? 10 : 12,
                          12,
                          compact ? 10 : 12,
                          14,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Modus-Wechsel (Nutzer ⇄ Admin) für Admins
                            if (isAdmin) ...[
                              _SidebarModeSwitchButton(
                                isAdminMode: widget.isAdminMode,
                                collapsed: compact,
                                onTap: _switchMode,
                              ),
                              const SizedBox(height: 8),
                            ],

                            // Live-Status-Anzeige
                            _SidebarConnectionBadge(
                              isLoading: widget.isLoading,
                              hasConnection: widget.hasConnection,
                              formattedTime: _formatTime(widget.lastUpdated),
                              collapsed: compact,
                            ),

                            // Nutzer-Profil-Zeile
                            if (user != null) ...[
                              const SizedBox(height: 10),
                              _SidebarUserTile(
                                name: user.name.isEmpty ? 'Gast' : user.name,
                                subtitle: widget.isAdminMode
                                    ? 'Administrator'
                                    : 'Konto & Profil',
                                avatarUrl: user.avatarUrl,
                                collapsed: compact,
                                onTap: widget.onTapUserProfile,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),

          // ==================== HAUPTBEREICH (ZENTRIERTER CANVAS) ====================
          Expanded(
            child: DesktopShellScope(
              isDesktopShell: true,
              child: FloatingNavScope(
                isCompact: false,
                navBarClearance: 0.0,
                child: ColoredBox(
                  color: canvasBg,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: widget.maxContentWidth,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: widget.child,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  final double size;
  const _BrandMark({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppTheme.primaryColor,
        borderRadius: BorderRadius.circular(11),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        'lib/assets/images/logo.png',
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(
          Icons.paragliding_rounded,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }
}

class _SidebarNavTile extends StatelessWidget {
  final ModernNavItem item;
  final bool isSelected;
  final bool collapsed;
  final VoidCallback onTap;

  const _SidebarNavTile({
    required this.item,
    required this.isSelected,
    required this.collapsed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeBg = isDark ? cs.primaryContainer : AppTheme.primaryTint;
    final activeFg = isDark ? cs.onPrimaryContainer : AppTheme.primaryColor;
    final inactiveFg = cs.onSurfaceVariant;
    final badgeBg = item.badgeColor ?? AppTheme.dangerColor;

    Widget iconWidget = Icon(
      item.icon,
      size: 20,
      color: isSelected ? activeFg : inactiveFg,
    );

    if (collapsed) {
      if (item.badgeCount > 0) {
        iconWidget = Badge(
          backgroundColor: badgeBg,
          label: Text(
            item.badgeCount > 99 ? '99+' : '${item.badgeCount}',
            style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700),
          ),
          child: iconWidget,
        );
      } else if (item.showBadgeDot) {
        iconWidget = Badge(
          smallSize: 8,
          backgroundColor: item.badgeColor ?? AppTheme.infoColor,
          child: iconWidget,
        );
      }
    }

    final tile = Material(
      color: isSelected ? activeBg : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        hoverColor: isSelected
            ? activeBg
            : cs.primary.withValues(alpha: isDark ? 0.10 : 0.06),
        child: SizedBox(
          height: 44,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 12),
            child: collapsed
                ? Center(child: iconWidget)
                : Row(
                    children: [
                      iconWidget,
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isSelected ? activeFg : cs.onSurface,
                          ),
                        ),
                      ),
                      if (item.badgeCount > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: badgeBg,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            item.badgeCount > 99 ? '99+' : '${item.badgeCount}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              height: 1.15,
                            ),
                          ),
                        ),
                      ] else if (item.showBadgeDot) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: item.badgeColor ?? AppTheme.infoColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );

    if (!collapsed) return tile;
    return Tooltip(message: item.label, child: tile);
  }
}

class _SidebarSchoolCard extends StatelessWidget {
  final String schoolName;
  final String logoLink;
  final bool switching;
  final List<dynamic> adminSchools;
  final String activeSchoolId;
  final ValueChanged<String> onSelectSchool;

  const _SidebarSchoolCard({
    required this.schoolName,
    required this.logoLink,
    required this.switching,
    required this.adminSchools,
    required this.activeSchoolId,
    required this.onSelectSchool,
  });

  Widget _logo(BuildContext context, String url, double size) {
    final cs = Theme.of(context).colorScheme;
    return ClipOval(
      child: url.isEmpty
          ? Container(
              width: size,
              height: size,
              color: cs.primaryContainer,
              child: Icon(
                Icons.school_outlined,
                size: size * 0.58,
                color: cs.primary,
              ),
            )
          : Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: size,
                height: size,
                color: cs.primaryContainer,
                child: Icon(
                  Icons.school_outlined,
                  size: size * 0.58,
                  color: cs.primary,
                ),
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canSwitch = adminSchools.length > 1;

    final inner = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCardElevated : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : AppTheme.desktopBorder,
        ),
      ),
      child: Row(
        children: [
          if (switching)
            SizedBox(
              width: 24,
              height: 24,
              child: Center(
                child: SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cs.primary,
                  ),
                ),
              ),
            )
          else
            _logo(context, logoLink, 24),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              schoolName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
          ),
          if (canSwitch)
            Icon(
              Icons.unfold_more_rounded,
              size: 16,
              color: cs.onSurfaceVariant,
            ),
        ],
      ),
    );

    if (!canSwitch) return inner;

    return PopupMenuButton<String>(
      enabled: !switching,
      tooltip: 'Flugschule wechseln',
      position: PopupMenuPosition.under,
      onSelected: onSelectSchool,
      itemBuilder: (_) => adminSchools.map((s) {
        final isCurrent = s.id == activeSchoolId;
        final SubscriptionStatusEnum sub = s.subscriptionStatus;
        return PopupMenuItem<String>(
          value: s.id as String,
          child: Row(
            children: [
              _logo(context, s.logoLink as String, 26),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      s.displayName as String,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: isCurrent
                            ? FontWeight.w800
                            : FontWeight.w600,
                        fontSize: 13.5,
                      ),
                    ),
                    if (!sub.isActive)
                      Text(
                        sub.label,
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
      child: inner,
    );
  }
}

class _SidebarModeSwitchButton extends StatelessWidget {
  final bool isAdminMode;
  final bool collapsed;
  final VoidCallback onTap;

  const _SidebarModeSwitchButton({
    required this.isAdminMode,
    required this.collapsed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? cs.primaryContainer : AppTheme.primaryTint;
    final fg = isDark ? cs.onPrimaryContainer : AppTheme.primaryColor;
    final label = isAdminMode ? 'Nutzer-Ansicht' : 'Admin-Bereich';
    final tooltip = isAdminMode
        ? 'In den Nutzer-Modus wechseln'
        : 'In den Admin-Modus wechseln';

    final btn = Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 40,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 12),
            child: collapsed
                ? Center(
                    child: Icon(
                      isAdminMode
                          ? Icons.person_outline_rounded
                          : Icons.admin_panel_settings_outlined,
                      size: 19,
                      color: fg,
                    ),
                  )
                : Row(
                    children: [
                      Icon(
                        isAdminMode
                            ? Icons.person_outline_rounded
                            : Icons.admin_panel_settings_outlined,
                        size: 18,
                        color: fg,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: fg,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.swap_horiz_rounded,
                        size: 16,
                        color: fg.withValues(alpha: 0.8),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );

    return Tooltip(message: tooltip, child: btn);
  }
}

class _SidebarConnectionBadge extends StatelessWidget {
  final bool isLoading;
  final bool hasConnection;
  final String formattedTime;
  final bool collapsed;

  const _SidebarConnectionBadge({
    required this.isLoading,
    required this.hasConnection,
    required this.formattedTime,
    required this.collapsed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final statusColor = hasConnection
        ? AppTheme.successColor
        : AppTheme.warningColor;
    final tooltipText = isLoading
        ? 'Synchronisiere Daten...'
        : hasConnection
        ? 'Verbunden (Echtzeit aktiv) · Stand: $formattedTime'
        : 'Offline · Letzter Stand: $formattedTime';

    final dot = isLoading
        ? SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
          )
        : Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          );

    return Tooltip(
      message: tooltipText,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: collapsed ? 0 : 8,
          vertical: 4,
        ),
        child: collapsed
            ? Center(child: dot)
            : Row(
                children: [
                  dot,
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isLoading
                          ? 'Synchronisiere…'
                          : hasConnection
                          ? 'Live · $formattedTime'
                          : 'Offline · $formattedTime',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _SidebarUserTile extends StatelessWidget {
  final String name;
  final String subtitle;
  final String avatarUrl;
  final bool collapsed;
  final VoidCallback? onTap;

  const _SidebarUserTile({
    required this.name,
    required this.subtitle,
    required this.avatarUrl,
    required this.collapsed,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final avatar = UserAvatar(
      avatarUrl: avatarUrl,
      name: name,
      radius: 16,
      backgroundColor: isDark ? cs.primaryContainer : AppTheme.primaryTint,
      foregroundColor: isDark ? cs.onPrimaryContainer : AppTheme.primaryColor,
    );

    final content = collapsed
        ? Center(child: avatar)
        : Row(
            children: [
              avatar,
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: collapsed ? 0 : 8,
            vertical: 6,
          ),
          child: content,
        ),
      ),
    );
  }
}
