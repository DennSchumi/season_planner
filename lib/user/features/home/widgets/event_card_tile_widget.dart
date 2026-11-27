import 'package:flutter/material.dart';
import 'package:season_planner/core/data/enums/event_status_enum.dart';
import 'package:season_planner/core/data/enums/event_user_status_enum.dart';
import 'package:season_planner/core/data/models/event_model.dart';
import 'package:season_planner/core/theme.dart';
import 'package:season_planner/core/widgets/ux_components.dart';
import 'package:season_planner/user/data/models/flight_school_model_user_view.dart';

class EventCardTile extends StatelessWidget {
  final Event event;
  final FlightSchoolUserView? flightSchool;
  final String dateText;
  final EventStatusEnum status;
  final VoidCallback onTap;

  const EventCardTile({
    super.key,
    required this.event,
    required this.flightSchool,
    required this.dateText,
    required this.status,
    required this.onTap,
  });

  int get _effectiveStage =>
      flightSchool?.effectiveStageFor(event) ?? event.planningStage;

  bool get _isStage1Preview =>
      _effectiveStage == 1 && !event.isOwnBindingAssignment;

  String _fmtTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  bool get _isConfirmedAssignment =>
      !_isStage1Preview &&
      !(event.swapOffered && !event.isSwapOfferFromOther) &&
      (event.assignmentStatus == EventUserStatusEnum.accepted_user ||
          event.assignmentStatus == EventUserStatusEnum.accepted_flight_school);

  Widget? _buildAssignmentPill() {
    if (_isStage1Preview) {
      return const StatusPill(
        label: 'Stufe 1 – Verfügbarkeit',
        foreground: AppTheme.stage1Color,
        background: AppTheme.stage1Bg,
        fontSize: 10.5,
      );
    }
    if (event.swapOffered && !event.isSwapOfferFromOther) {
      return const StatusPill(
        label: 'Tausch offen',
        icon: Icons.swap_horiz,
        foreground: AppTheme.swapColor,
        background: AppTheme.swapBg,
        fontSize: 10.5,
      );
    }
    switch (event.assignmentStatus) {
      case EventUserStatusEnum.user_requests_change:
        return const StatusPill(
          label: 'Änderung angefragt',
          foreground: AppTheme.warningColor,
          background: AppTheme.warningBg,
          fontSize: 10.5,
        );
      case EventUserStatusEnum.pending_user:
        return const StatusPill(
          label: 'Arbeitseinsatz angefragt',
          foreground: AppTheme.warningColor,
          background: AppTheme.warningBg,
          fontSize: 10.5,
        );
      case EventUserStatusEnum.accepted_user:
      case EventUserStatusEnum.accepted_flight_school:
        // Bestätigte Einsätze werden platzsparend über den dezenten grünen
        // Vertikalstrich direkt hinter dem Datumskästchen markiert.
        return null;
      case EventUserStatusEnum.denied_user:
      case EventUserStatusEnum.denied_flight_school:
        return const StatusPill(
          label: 'Arbeitseinsatz abgelehnt',
          foreground: AppTheme.dangerColor,
          background: AppTheme.dangerBg,
          fontSize: 10.5,
        );
      case EventUserStatusEnum.pending_flight_school:
        return const StatusPill(
          label: 'Beworben',
          foreground: AppTheme.textSecondary,
          background: AppTheme.backgroundColor,
          fontSize: 10.5,
        );
      default:
        return const StatusPill(
          label: 'Offene Stelle',
          foreground: AppTheme.infoColor,
          background: AppTheme.infoBg,
          fontSize: 10.5,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fs = flightSchool;
    final isStage1Preview = _isStage1Preview;
    final isCanceled = status == EventStatusEnum.canceled;
    final fsLabel = (fs?.displayShortName.trim().isNotEmpty == true)
        ? fs!.displayShortName.trim()
        : (fs?.displayName ?? '');

    final sameDay = event.startTime.year == event.endTime.year &&
        event.startTime.month == event.endTime.month &&
        event.startTime.day == event.endTime.day;
    final timeLabel = sameDay
        ? '${_fmtTime(event.startTime)}–${_fmtTime(event.endTime)}'
        : dateText;

    final metaParts = <String>[
      timeLabel,
      if (!isStage1Preview && event.role.isNotEmpty) event.roleLabel,
      if (event.location.isNotEmpty) event.location,
      if (fsLabel.isNotEmpty) fsLabel,
    ];

    final assignmentPill = _buildAssignmentPill();

    return CanceledEventDecorator(
      isCanceled: isCanceled,
      borderRadius: BorderRadius.circular(20),
      child: SoftCard(
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 430;

            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                DateBadgeBox(
                  date: event.startTime,
                  accentColor: isStage1Preview
                      ? AppTheme.stage1Color
                      : eventStatusColor(status.name),
                ),
                if (_isConfirmedAssignment) ...[
                  const SizedBox(width: 10),
                  Tooltip(
                    message: 'Arbeitseinsatz bestätigt',
                    child: Container(
                      width: 3,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppTheme.successColor,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(width: 11),
                ] else
                  const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: cs.onSurface,
                          decoration:
                              isCanceled ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        metaParts.join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: cs.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                      if (!isWide && assignmentPill != null) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 5,
                          children: [assignmentPill],
                        ),
                      ],
                    ],
                  ),
                ),
                if (isWide && assignmentPill != null) ...[
                  const SizedBox(width: 12),
                  assignmentPill,
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
