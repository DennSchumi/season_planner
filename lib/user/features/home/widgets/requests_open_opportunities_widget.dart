import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/core/data/enums/event_status_enum.dart';
import 'package:season_planner/core/data/enums/event_user_status_enum.dart';
import 'package:season_planner/core/data/enums/membership_status_enum.dart';
import 'package:season_planner/core/data/models/event_model.dart';
import 'package:season_planner/core/data/models/tandem_model.dart';
import 'package:season_planner/core/services/notification_service.dart';
import 'package:season_planner/core/services/security_privacy_service.dart';
import 'package:season_planner/core/services/tandem_service.dart';
import 'package:season_planner/core/theme.dart';
import 'package:season_planner/core/widgets/ux_components.dart';
import 'package:season_planner/user/data/models/flight_school_model_user_view.dart';
import 'package:season_planner/user/features/home/widgets/event_preview_sheet.dart';
import 'package:season_planner/user/services/database_service.dart';
import 'package:season_planner/user/user_provider.dart';

class RequestsOpportunitiesWidget extends StatelessWidget {
  final List<Event> events;
  final List<TandemDuty> tandemRequests;

  const RequestsOpportunitiesWidget({
    super.key,
    required this.events,
    this.tandemRequests = const [],
  });

  String _eventKey(Event e) =>
      (e.eventDocId != null && e.eventDocId!.isNotEmpty) ? e.eventDocId! : e.id;

  int _entryPriority(Event event, int stage) {
    if (stage == 1) return 5;
    if (event.assignmentStatus == EventUserStatusEnum.pending_user) return 0;
    if (event.assignmentStatus == EventUserStatusEnum.pending_flight_school) {
      return 1;
    }
    if (event.isSwapOfferFromOther) return 2;
    if (event.assignmentStatus == EventUserStatusEnum.open) return 3;
    return 4;
  }

  String _groupBadgeLabel(List<Event> group, int stage) {
    if (stage == 1) return 'Stufe 1: Geplant';
    if (group.any((e) => e.assignmentStatus == EventUserStatusEnum.pending_user)) {
      return 'Direktanfrage';
    }
    if (group.any(
      (e) => e.assignmentStatus == EventUserStatusEnum.pending_flight_school,
    )) {
      return 'Bewerbung offen';
    }
    if (group.every((e) => e.isSwapOfferFromOther)) {
      return group.length == 1 ? 'Tauschplatz' : '${group.length} Tauschplätze';
    }
    final openOrSwapCount = group
        .where(
          (e) =>
              e.isSwapOfferFromOther ||
              e.assignmentStatus == EventUserStatusEnum.open,
        )
        .length;
    if (openOrSwapCount > 1) {
      return '$openOrSwapCount offene Stellen';
    }
    if (openOrSwapCount == 1) {
      return 'Offene Stelle';
    }
    if (group.any(
      (e) =>
          e.assignmentStatus == EventUserStatusEnum.denied_user ||
          e.assignmentStatus == EventUserStatusEnum.denied_flight_school,
    )) {
      return 'Abgelehnt';
    }
    return 'Anfrage';
  }

  Color _groupBadgeColor(List<Event> group, int stage) {
    if (stage == 1) return AppTheme.stage1Color;
    if (group.any(
      (e) =>
          e.assignmentStatus == EventUserStatusEnum.pending_user ||
          e.assignmentStatus == EventUserStatusEnum.pending_flight_school,
    )) {
      return AppTheme.warningColor;
    }
    if (group.every((e) => e.isSwapOfferFromOther)) {
      return AppTheme.swapColor;
    }
    if (group.any(
      (e) =>
          e.isSwapOfferFromOther ||
          e.assignmentStatus == EventUserStatusEnum.open,
    )) {
      return AppTheme.infoColor;
    }
    if (group.any(
      (e) =>
          e.assignmentStatus == EventUserStatusEnum.denied_user ||
          e.assignmentStatus == EventUserStatusEnum.denied_flight_school,
    )) {
      return AppTheme.dangerColor;
    }
    return Colors.grey;
  }

  IconData _groupBadgeIcon(List<Event> group, int stage) {
    if (stage == 1) return Icons.calendar_today;
    if (group.any(
      (e) =>
          e.assignmentStatus == EventUserStatusEnum.pending_user ||
          e.assignmentStatus == EventUserStatusEnum.pending_flight_school,
    )) {
      return Icons.notifications_active;
    }
    if (group.every((e) => e.isSwapOfferFromOther)) {
      return Icons.swap_horiz;
    }
    if (group.any(
      (e) =>
          e.isSwapOfferFromOther ||
          e.assignmentStatus == EventUserStatusEnum.open,
    )) {
      return Icons.public;
    }
    return Icons.block;
  }

  Color _slotColor(Event e) {
    if (e.isSwapOfferFromOther) return AppTheme.swapColor;
    switch (e.assignmentStatus) {
      case EventUserStatusEnum.pending_user:
      case EventUserStatusEnum.pending_flight_school:
        return AppTheme.warningColor;
      case EventUserStatusEnum.denied_user:
      case EventUserStatusEnum.denied_flight_school:
        return AppTheme.dangerColor;
      case EventUserStatusEnum.open:
      default:
        return AppTheme.infoColor;
    }
  }

  IconData _slotIcon(Event e) {
    if (e.isSwapOfferFromOther) return Icons.swap_horiz;
    switch (e.assignmentStatus) {
      case EventUserStatusEnum.pending_user:
        return Icons.notifications_active_outlined;
      case EventUserStatusEnum.pending_flight_school:
        return Icons.hourglass_top;
      case EventUserStatusEnum.denied_user:
      case EventUserStatusEnum.denied_flight_school:
        return Icons.block;
      case EventUserStatusEnum.open:
      default:
        return Icons.badge_outlined;
    }
  }

  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserProvider>().user;

    if (user == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final Map<String, FlightSchoolUserView> fsById = {
      for (final fs in user.flightSchools) fs.id: fs,
    };

    // Alle verbindlich eingeplanten (nicht abgesagten) Events des Nutzers ermitteln.
    // Ist man in einem Event oder einem zeitlich parallelen Event bereits eingeplant,
    // werden weitere offene Positionen bzw. parallele Events ausgeblendet.
    final scheduledEvents = user.events
        .where(
          (e) =>
              e.isOwnBindingAssignment && e.status != EventStatusEnum.canceled,
        )
        .toList();
    final scheduledKeys = scheduledEvents.map(_eventKey).toSet();

    bool isBlockedBySchedule(Event candidate) {
      if (scheduledKeys.contains(_eventKey(candidate))) return true;
      final isOwnApplied = !candidate.isSwapOfferFromOther &&
          candidate.assignmentStatus == EventUserStatusEnum.pending_flight_school;
      // Bereits eingereichte eigene Bewerbungen bleiben sichtbar, blockieren aber
      // alle anderen zeitgleichen Events/Stellen (und Tandem-Einsätze blockieren ebenfalls).
      if (isOwnApplied) return false;
      final conflict = TandemService.findUserEventBookingConflict(
        userId: user.id,
        startTime: candidate.startTime,
        endTime: candidate.endTime,
        userEvents: user.events,
        userTandemDuties: user.tandemDuties,
        ignoreEventKey: _eventKey(candidate),
      );
      return conflict != null;
    }

    final visibleEvents = events.where((event) {
      final fs = fsById[event.flightSchoolId];
      if (fs == null) return false;
      if (fs.membershipStatus != MembershipStatusEnum.active) return false;

      // Im selben Event oder zeitlich parallel bereits eingeplant -> ausblenden
      if (isBlockedBySchedule(event)) return false;

      // Reine Tandempiloten & Erweitertes Team: keine offenen Stellen / Tauschplätze,
      // nur direkte Anfragen durch den Admin (oder ggf. bestehende eigene Bewerbungen).
      if (fs.isTandemOnly || fs.isExtendedTeam) {
        return !event.isSwapOfferFromOther &&
            (event.assignmentStatus == EventUserStatusEnum.pending_user ||
                event.assignmentStatus ==
                    EventUserStatusEnum.pending_flight_school);
      }

      // In Stufe 1 sehen alle aktiven Mitglieder den Zeitraum (ohne Rollenfilter)
      if (fs.effectiveStageFor(event) == 1) return true;

      // Eigene direkte Anfragen / Bewerbungen anzeigen
      if (!event.isSwapOfferFromOther &&
          event.assignmentStatus != EventUserStatusEnum.open) {
        return true;
      }

      // Offene Stellen & Tauschplätze nur für passende Rolle des Mitglieds
      return fs.hasRole(event.role);
    }).toList();

    // Nach Event gruppieren: genau 1 Kachel pro Event
    final Map<String, List<Event>> grouped = {};
    for (final ev in visibleEvents) {
      final key = _eventKey(ev);
      grouped.putIfAbsent(key, () => []).add(ev);
    }

    final eventGroups = grouped.values.toList();
    for (final group in eventGroups) {
      final fs = fsById[group.first.flightSchoolId];
      final stage = fs?.effectiveStageFor(group.first) ?? group.first.planningStage;
      group.sort((a, b) {
        final p = _entryPriority(a, stage).compareTo(_entryPriority(b, stage));
        if (p != 0) return p;
        return a.roleLabel.toLowerCase().compareTo(b.roleLabel.toLowerCase());
      });
    }
    eventGroups.sort(
      (a, b) => a.first.startTime.compareTo(b.first.startTime),
    );

    if (eventGroups.isEmpty && tandemRequests.isEmpty) {
      return const EmptyStateView(
        icon: Icons.inbox_outlined,
        title: 'Keine offenen Anfragen oder Stellen',
        subtitle:
            'Neue Direktanfragen, offene Einsatzrollen, Tandem-Anfragen und Tauschplätze erscheinen hier automatisch.',
      );
    }

    Future<void> reloadUser() async {
      final updated = await DatabaseService().getUserInformation();
      if (updated != null && context.mounted) {
        context.read<UserProvider>().setUser(updated);
      }
    }

    Future<void> decideTandem(TandemDuty duty, bool approve) async {
      if (approve) {
        String? conflict = TandemService.findScheduleConflict(
          userId: user.id,
          startDate: duty.startDate,
          endDate: duty.endDate,
          isFullDay: duty.isFullDay,
          events: user.events,
          tandemDuties: user.tandemDuties,
          ignoreDutyId: duty.id,
          isUserOwnEventsView: true,
        );
        if (conflict == null) {
          final serverMap = await SecurityPrivacyService()
              .checkCrossSchoolConflicts(
            userIds: [user.id],
            startTime: duty.effectiveStart,
            endTime: duty.effectiveEnd,
            ignoreDutyId: duty.id,
            otherSchoolsOnly: false,
          );
          if (!context.mounted) return;
          final serverList = serverMap.values.expand((e) => e).toList();
          if (serverList.isNotEmpty) {
            conflict = serverList.join(' · ');
          }
        }
        if (conflict != null) {
          await showUserBookingConflictDialog(context, reason: conflict);
          return;
        }
      }
      final ok = await TandemService().updateDutyStatus(
        flightSchoolId: duty.flightSchoolId,
        dutyId: duty.id,
        newStatus:
            approve ? TandemDutyStatus.confirmed : TandemDutyStatus.declined,
        summary: 'Tandem ${duty.dateRangeLabel}',
      );
      if (ok && context.mounted) {
        if (approve) {
          NotificationService().markKeyAsSeen('u_tandem_confirmed:${duty.id}');
        }
        await reloadUser();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                approve
                    ? 'Tandem-Einsatz zugesagt.'
                    : 'Tandem-Anfrage abgelehnt.',
              ),
            ),
          );
        }
      }
    }

    Future<void> withdrawTandem(TandemDuty duty) async {
      final ok = await TandemService().deleteDuty(
        flightSchoolId: duty.flightSchoolId,
        dutyId: duty.id,
        summary: 'Tandem-Anfrage zurückgezogen (${duty.dateRangeLabel})',
      );
      if (ok && context.mounted) {
        await reloadUser();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Tandem-Anfrage zurückgezogen.')),
          );
        }
      }
    }

    final totalCount = tandemRequests.length + eventGroups.length;

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 104),
      itemCount: totalCount,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index < tandemRequests.length) {
          final duty = tandemRequests[index];
          final fs = fsById[duty.flightSchoolId];
          final isAdminReq = duty.status == TandemDutyStatus.requestedByAdmin;
          final badgeColor =
              isAdminReq ? AppTheme.warningColor : const Color(0xFF4B5563);
          final schoolLabel = fs == null
              ? ''
              : (fs.displayShortName.isNotEmpty
                  ? fs.displayShortName
                  : fs.displayName);
          final cs = Theme.of(context).colorScheme;

          return Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const TintedIconBadge(
                        icon: Icons.paragliding_rounded,
                        iconColor: AppTheme.primaryColor,
                        backgroundColor: AppTheme.primaryTint,
                        size: 38,
                        iconSize: 20,
                        radius: 12,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              schoolLabel.isNotEmpty
                                  ? 'Tandempilot · $schoolLabel'
                                  : 'Tandempilot',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${duty.dateRangeLabel} · ${duty.timeWindowLabel}',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      StatusPill(
                        label: isAdminReq
                            ? 'Arbeitseinsatz angefragt'
                            : 'Wartet auf Freigabe',
                        foreground: badgeColor,
                        background: badgeColor.withValues(alpha: 0.14),
                        fontSize: 11,
                      ),
                    ],
                  ),
                  if (duty.notes.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      duty.notes,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  if (isAdminReq)
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => decideTandem(duty, true),
                            icon: const Icon(Icons.check, size: 17),
                            label: const Text('Zusagen'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.dangerColor,
                            ),
                            onPressed: () => decideTandem(duty, false),
                            icon: const Icon(Icons.close, size: 17),
                            label: const Text('Ablehnen'),
                          ),
                        ),
                      ],
                    )
                  else
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.dangerColor,
                        ),
                        onPressed: () => withdrawTandem(duty),
                        icon: const Icon(Icons.delete_outline, size: 17),
                        label: const Text('Anfrage zurückziehen'),
                      ),
                    ),
                ],
              ),
            ),
          );
        }

        final group = eventGroups[index - tandemRequests.length];
        final primary = group.first;
        final fs = fsById[primary.flightSchoolId];
        final stage = fs?.effectiveStageFor(primary) ?? primary.planningStage;
        final badgeColor = _groupBadgeColor(group, stage);
        final badgeLabel = _groupBadgeLabel(group, stage);
        final badgeIcon = _groupBadgeIcon(group, stage);
        final cs = Theme.of(context).colorScheme;
        final logo = fs?.logoLink ?? '';

        void openEvent(Event selected) {
          showEventPreviewSheet(
            context,
            event: selected,
            siblingOpportunities: group,
          );
        }

        // Doppelte identische offene Rollen (z. B. 2× Startplatz mit gleichem Status)
        // in der Kachel übersichtlich zusammenfassen, aber weiterhin direkt antippbar halten.
        final List<({Event sample, int count})> displaySlots = [];
        if (stage >= 2) {
          final Map<String, ({Event sample, int count})> bucket = {};
          for (final item in group) {
            if (item.role.trim().isEmpty) continue;
            final sig =
                '${item.roleLabel.toLowerCase()}|${item.assignmentStatus.name}|${item.isSwapOfferFromOther}';
            final existing = bucket[sig];
            if (existing == null) {
              bucket[sig] = (sample: item, count: 1);
            } else {
              bucket[sig] = (sample: existing.sample, count: existing.count + 1);
            }
          }
          displaySlots.addAll(bucket.values);
        }

        return Card(
          elevation: 1.5,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => openEvent(primary),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: cs.surfaceContainerHighest,
                        child: logo.isEmpty
                            ? Icon(Icons.flight, color: cs.onSurfaceVariant)
                            : ClipOval(
                                child: Image.network(
                                  logo,
                                  width: 40,
                                  height: 40,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Icon(
                                    Icons.flight,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    primary.displayName,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: badgeColor.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: badgeColor),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        badgeIcon,
                                        size: 13,
                                        color: badgeColor,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        badgeLabel,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: badgeColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Wrap(
                              spacing: 10,
                              runSpacing: 4,
                              children: [
                                _MetaChip(
                                  icon: Icons.calendar_today_outlined,
                                  text:
                                      '${_formatDate(primary.startTime)} – ${_formatDate(primary.endTime)}',
                                ),
                                if (primary.location.isNotEmpty)
                                  _MetaChip(
                                    icon: Icons.place_outlined,
                                    text: primary.location,
                                  ),
                                if (stage >= 2)
                                  _MetaChip(
                                    icon: Icons.flag_outlined,
                                    text: primary.status.label,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (displaySlots.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.6)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: displaySlots.map((entry) {
                        final item = entry.sample;
                        final color = _slotColor(item);
                        final countPrefix =
                            entry.count > 1 ? '${entry.count}× ' : '';
                        final statusSuffix = item.isSwapOfferFromOther
                            ? ' (Tausch)'
                            : item.assignmentStatus ==
                                    EventUserStatusEnum.pending_flight_school
                                ? ' (Beworben)'
                                : item.assignmentStatus ==
                                        EventUserStatusEnum.pending_user
                                    ? ' (Angefragt)'
                                    : '';

                        return ActionChip(
                          avatar: Icon(
                            _slotIcon(item),
                            size: 15,
                            color: color,
                          ),
                          label: Text(
                            '$countPrefix${item.roleLabel}$statusSuffix',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: color,
                            ),
                          ),
                          backgroundColor: color.withValues(alpha: 0.10),
                          side: BorderSide(color: color.withValues(alpha: 0.4)),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => openEvent(item),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MetaChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: cs.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}
