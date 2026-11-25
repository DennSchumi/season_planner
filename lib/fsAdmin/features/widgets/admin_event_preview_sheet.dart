import 'package:flutter/material.dart';
import 'package:season_planner/core/data/enums/event_user_status_enum.dart';
import 'package:season_planner/core/data/models/event_model.dart';
import 'package:season_planner/core/theme.dart';
import 'package:season_planner/core/widgets/user_avatar.dart';
import 'package:season_planner/core/widgets/ux_components.dart';
import 'package:season_planner/fsAdmin/data/models/flight_school_model_flight_school_view.dart';

/// Öffnet im Admin-Modus ein kompaktes, halb-Screen-füllendes Vorschau-Popup
/// mit den wichtigsten Infos zum Event. Durch Hochwischen (oder Tipp auf
/// „Bearbeiten“) wird anschließend die vollständige Event-Bearbeitungsseite
/// geöffnet.
Future<void> showAdminEventPreviewSheet(
  BuildContext context, {
  required Event event,
  required FlightSchoolModelFlightSchoolView flightSchool,
  required Future<void> Function() onOpenEdit,
}) async {
  final shouldOpenEdit = await showAdaptiveSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.50),
    wrapDesktopCard: false,
    desktopMaxWidth: 580,
    builder: (ctx) => _AdminEventPreviewSheet(
      event: event,
      flightSchool: flightSchool,
    ),
  );

  if (shouldOpenEdit == true && context.mounted) {
    await onOpenEdit();
  }
}

class _AdminEventPreviewSheet extends StatefulWidget {
  final Event event;
  final FlightSchoolModelFlightSchoolView flightSchool;

  const _AdminEventPreviewSheet({
    required this.event,
    required this.flightSchool,
  });

  @override
  State<_AdminEventPreviewSheet> createState() =>
      _AdminEventPreviewSheetState();
}

class _AdminEventPreviewSheetState extends State<_AdminEventPreviewSheet> {
  double _upwardDragDelta = 0;

  static const _shortWeekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
  static const _shortMonths = [
    'Jan',
    'Feb',
    'Mär',
    'Apr',
    'Mai',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Okt',
    'Nov',
    'Dez',
  ];

  void _openEdit() {
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    final dy = details.delta.dy;
    if (dy < 0) {
      setState(() {
        _upwardDragDelta = (_upwardDragDelta - dy).clamp(0, 90);
      });
    } else if (dy > 0 && _upwardDragDelta > 0) {
      setState(() {
        _upwardDragDelta = (_upwardDragDelta - dy).clamp(0, 90);
      });
    }
  }

  void _handleDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity < -260 || _upwardDragDelta >= 36) {
      _openEdit();
      return;
    }
    if (velocity > 420) {
      Navigator.of(context).pop(false);
      return;
    }
    if (_upwardDragDelta > 0) {
      setState(() => _upwardDragDelta = 0);
    }
  }

  String _fmtDatePart(DateTime d) =>
      '${_shortWeekdays[d.weekday - 1]}, ${d.day}. ${_shortMonths[d.month - 1]}';

  String _fmtTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  String _formatDateRange(DateTime start, DateTime end) {
    final sameDay = start.year == end.year &&
        start.month == end.month &&
        start.day == end.day;
    if (sameDay) {
      return '${_fmtDatePart(start)} · ${_fmtTime(start)} – ${_fmtTime(end)}';
    }
    return '${_fmtDatePart(start)}, ${_fmtTime(start)} – ${_fmtDatePart(end)}, ${_fmtTime(end)}';
  }

  (String label, Color fg, Color bg) _memberStatusStyle(TeamMember tm) {
    if (tm.isSlot || tm.statusEnum == EventUserStatusEnum.open) {
      return ('Offen', AppTheme.dangerColor, AppTheme.dangerBg);
    }
    if (tm.swapOffered) {
      return ('Tausch', AppTheme.swapColor, AppTheme.swapBg);
    }
    switch (tm.statusEnum ?? EventUserStatusEnum.open) {
      case EventUserStatusEnum.accepted_user:
      case EventUserStatusEnum.accepted_flight_school:
        return ('Bestätigt', AppTheme.successColor, AppTheme.successBg);
      case EventUserStatusEnum.pending_user:
        return ('Angefragt', AppTheme.warningColor, AppTheme.warningBg);
      case EventUserStatusEnum.pending_flight_school:
        return ('Bewerbung', AppTheme.infoColor, AppTheme.infoBg);
      case EventUserStatusEnum.user_requests_change:
        return ('Ersatz', AppTheme.warningColor, AppTheme.warningBg);
      case EventUserStatusEnum.denied_user:
      case EventUserStatusEnum.denied_flight_school:
        return ('Abgelehnt', AppTheme.dangerColor, AppTheme.dangerBg);
      case EventUserStatusEnum.open:
        return ('Offen', AppTheme.dangerColor, AppTheme.dangerBg);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ev = widget.event;
    final fs = widget.flightSchool;
    final now = DateTime.now();
    final isRunning = !ev.startTime.isAfter(now) && !ev.endTime.isBefore(now);

    final openCount = ev.team
        .where((t) => t.isSlot || t.statusEnum == EventUserStatusEnum.open)
        .length;
    final staffed = ev.team.length - openCount;
    final liftOffset = -_upwardDragDelta * 0.35;
    final isDesktop = context.isDesktop;
    final maxSheetHeight =
        MediaQuery.sizeOf(context).height * (isDesktop ? 0.84 : 0.62);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragUpdate: isDesktop ? null : _handleDragUpdate,
      onVerticalDragEnd: isDesktop ? null : _handleDragEnd,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        transform: Matrix4.translationValues(0, isDesktop ? 0 : liftOffset, 0),
        child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? AppTheme.darkCard
                : (isDesktop
                    ? AppTheme.desktopBackground
                    : AppTheme.backgroundColor),
            borderRadius: isDesktop
                ? BorderRadius.circular(24)
                : const BorderRadius.vertical(top: Radius.circular(28)),
            border: isDesktop
                ? Border.all(
                    color:
                        isDark ? AppTheme.darkBorder : AppTheme.desktopBorder,
                  )
                : null,
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 28,
                offset: Offset(0, -6),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, isDesktop ? 18 : 10, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Wisch-Griffleiste nur auf Mobilgeräten
                  if (!isDesktop)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragUpdate: _handleDragUpdate,
                      onVerticalDragEnd: _handleDragEnd,
                      onTap: _openEdit,
                      child: Column(
                        children: [
                          Center(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 140),
                              width: _upwardDragDelta > 10 ? 54 : 42,
                              height: 4.5,
                              decoration: BoxDecoration(
                                color: _upwardDragDelta > 10
                                    ? AppTheme.primaryColor
                                    : cs.outline,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.keyboard_arrow_up_rounded,
                                size: 15,
                                color: _upwardDragDelta > 10
                                    ? AppTheme.primaryColor
                                    : cs.onSurfaceVariant
                                        .withValues(alpha: 0.75),
                              ),
                              const SizedBox(width: 2),
                              Text(
                                _upwardDragDelta > 20
                                    ? 'Loslassen zum Bearbeiten'
                                    : 'Nach oben wischen zum Bearbeiten',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _upwardDragDelta > 10
                                      ? AppTheme.primaryColor
                                      : cs.onSurfaceVariant
                                          .withValues(alpha: 0.75),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                        ],
                      ),
                    ),

                  // Status-Pills + Schließen-Button
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (isRunning)
                              const StatusPill(
                                icon: Icons.play_circle_filled_rounded,
                                label: 'Läuft gerade',
                                foreground: AppTheme.successColor,
                                background: AppTheme.successBg,
                              ),
                            StatusPill.fromEventStatus(
                              ev.status.name,
                              ev.status.label,
                            ),
                            if (ev.team.isNotEmpty)
                              StatusPill(
                                label: '$staffed/${ev.team.length} besetzt',
                                foreground: openCount == 0
                                    ? AppTheme.successColor
                                    : AppTheme.warningColor,
                                background: openCount == 0
                                    ? AppTheme.successBg
                                    : AppTheme.warningBg,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Material(
                        color: cs.surface,
                        borderRadius: BorderRadius.circular(10),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => Navigator.of(context).pop(false),
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: cs.outlineVariant),
                            ),
                            child: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // Event-Titel (ebenfalls nach oben wischbar)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragUpdate: _handleDragUpdate,
                    onVerticalDragEnd: _handleDragEnd,
                    child: Text(
                      ev.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        height: 1.15,
                        color: cs.onSurface,
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Scrollbarer Kerninhalt (damit Höhe immer kompakt ~50% bleibt)
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Zeitraum-Kachel
                          SoftCard(
                            radius: 14,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 13,
                              vertical: 11,
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.schedule_outlined,
                                  size: 18,
                                  color: AppTheme.primaryColor,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _formatDateRange(ev.startTime, ev.endTime),
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          if (ev.location.trim().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            SoftCard(
                              radius: 14,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 13,
                                vertical: 11,
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.place_outlined,
                                    size: 18,
                                    color: AppTheme.primaryColor,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      ev.location.trim(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                        color: cs.onSurface,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          // Team-Besetzung kompakt
                          if (ev.team.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Text(
                              'TEAM (${ev.team.length})',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.7,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SoftCard(
                              radius: 15,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: Column(
                                children: [
                                  for (var i = 0; i < ev.team.length; i++) ...[
                                    Builder(
                                      builder: (_) {
                                        final tm = ev.team[i];
                                        final isOpen = tm.isSlot ||
                                            tm.statusEnum ==
                                                EventUserStatusEnum.open;
                                        final name = isOpen
                                            ? 'Offene Stelle'
                                            : (tm.name.trim().isNotEmpty
                                                ? tm.name.trim()
                                                : fs.resolveMemberName(
                                                    tm.userId,
                                                  ));
                                        final avatar = isOpen
                                            ? ''
                                            : (tm.avatarUrl.isNotEmpty
                                                ? tm.avatarUrl
                                                : (fs
                                                        .findMemberByAnyId(
                                                          tm.userId,
                                                        )
                                                        ?.avatarUrl ??
                                                    ''));
                                        final (stLabel, stFg, stBg) =
                                            _memberStatusStyle(tm);
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 5,
                                          ),
                                          child: Row(
                                            children: [
                                              if (isOpen)
                                                CircleAvatar(
                                                  radius: 15,
                                                  backgroundColor:
                                                      AppTheme.dangerBg,
                                                  child: const Icon(
                                                    Icons.person_outline,
                                                    size: 16,
                                                    color: AppTheme.dangerColor,
                                                  ),
                                                )
                                              else
                                                UserAvatar(
                                                  avatarUrl: avatar,
                                                  name: name,
                                                  radius: 15,
                                                ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      name,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: isOpen
                                                            ? AppTheme
                                                                .dangerColor
                                                            : cs.onSurface,
                                                      ),
                                                    ),
                                                    Text(
                                                      tm.roleLabel,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        fontSize: 11.5,
                                                        color:
                                                            cs.onSurfaceVariant,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              StatusPill(
                                                label: stLabel,
                                                foreground: stFg,
                                                background: stBg,
                                                fontSize: 10.5,
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                    if (i != ev.team.length - 1)
                                      Divider(
                                        height: 1,
                                        color: cs.outlineVariant
                                            .withValues(alpha: 0.6),
                                      ),
                                  ],
                                ],
                              ),
                            ),
                          ],

                          if (ev.notes.trim().isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              ev.notes.trim(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.4,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }
}
