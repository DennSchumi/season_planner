import 'package:flutter/material.dart';
import 'package:season_planner/core/data/models/planning_period_model.dart';
import 'package:season_planner/core/data/models/tandem_model.dart';
import 'package:season_planner/core/services/security_privacy_service.dart';
import 'package:season_planner/core/services/tandem_service.dart';
import 'package:season_planner/core/theme.dart';
import 'package:season_planner/core/widgets/ux_components.dart';
import 'package:season_planner/fsAdmin/data/models/flight_school_model_flight_school_view.dart';
import 'package:season_planner/fsAdmin/data/models/user_summary_flight_school_view.dart';
import 'package:season_planner/user/data/models/flight_school_model_user_view.dart';
import 'package:season_planner/user/data/models/user_model_userView.dart';

String _fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

String _fmtTime(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

DateTime _combine(DateTime day, TimeOfDay t) =>
    DateTime(day.year, day.month, day.day, t.hour, t.minute);

/// Admin-Dialog: Einteilen oder Anfragen eines Tandempiloten für 1 Tag oder Zeitraum.
/// - Zeigt nur Mitglieder mit Tandem-Qualifikation.
/// - Sortiert verfügbar gemeldete Piloten grün hinterlegt ganz oben.
/// - Erlaubt Admins auch Doppelbelegungen (Events & Tandem), jedoch nur nach
///   ausdrücklicher Bestätigung einer Warnung!
Future<bool> showAdminAssignTandemDialog({
  required BuildContext context,
  required FlightSchoolModelFlightSchoolView fs,
  required DateTime initialDate,
  required List<AvailabilitySubmission> teamAvailabilities,
}) async {
  final pilots = fs.tandemPilots;
  if (pilots.isEmpty) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text(
          'Kein Teammitglied hat aktuell die Qualifikation „Tandempilot“.',
        ),
      ),
    );
    return false;
  }

  DateTime startDate =
      DateTime(initialDate.year, initialDate.month, initialDate.day);
  DateTime endDate = startDate;
  bool isFullDay = true;
  TimeOfDay startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay endTime = const TimeOfDay(hour: 17, minute: 0);
  String? selectedPilotId;
  final notesCtrl = TextEditingController();
  bool saving = false;
  Map<String, List<String>> crossConflictsByUserId = {};
  String lastCrossKey = '';
  int crossSeq = 0;

  int availabilityRank(UserSummary m, DateTime s, DateTime e) {
    bool hasAvail = false;
    bool hasBlackout = false;
    for (final a in teamAvailabilities) {
      if (!m.matchesId(a.userId)) continue;
      final aStart = DateTime(a.startDate.year, a.startDate.month, a.startDate.day);
      final aEnd = DateTime(a.endDate.year, a.endDate.month, a.endDate.day);
      if (aEnd.isBefore(s) || aStart.isAfter(e)) continue;
      if (a.kind == AvailabilityKind.available) hasAvail = true;
      if (a.kind == AvailabilityKind.blackout) hasBlackout = true;
    }
    if (hasBlackout) return 2;
    if (hasAvail) return 0;
    return 1;
  }

  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final cs = Theme.of(ctx).colorScheme;
        final effStart = isFullDay
            ? DateTime(startDate.year, startDate.month, startDate.day, 0, 0)
            : _combine(startDate, startTime);
        final effEnd = isFullDay
            ? DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59)
            : _combine(endDate, endTime);

        final crossKey =
            '${effStart.toIso8601String()}_${effEnd.toIso8601String()}';
        if (crossKey != lastCrossKey && !effEnd.isBefore(effStart)) {
          lastCrossKey = crossKey;
          final mySeq = ++crossSeq;
          final allIds = pilots
              .expand((m) => [m.id, if (m.userRowId.isNotEmpty) m.userRowId])
              .toSet()
              .toList();
          SecurityPrivacyService()
              .checkCrossSchoolConflicts(
                flightSchoolId: fs.id,
                userIds: allIds,
                startTime: effStart,
                endTime: effEnd,
                otherSchoolsOnly: true,
              )
              .then((map) {
            if (!ctx.mounted || mySeq != crossSeq) return;
            setLocal(() => crossConflictsByUserId = map);
          });
        }

        List<String> crossFor(UserSummary m) {
          final out = <String>{};
          final a = crossConflictsByUserId[m.id];
          if (a != null) out.addAll(a);
          if (m.userRowId.isNotEmpty) {
            final b = crossConflictsByUserId[m.userRowId];
            if (b != null) out.addAll(b);
          }
          return out.toList();
        }

        final pilotEntries = pilots.map((m) {
          final localConflict = TandemService.findScheduleConflict(
            userId: m.id,
            userRowId: m.userRowId,
            startDate: effStart,
            endDate: effEnd,
            isFullDay: isFullDay,
            events: fs.events,
            tandemDuties: fs.tandemDuties,
          );
          final crossList = crossFor(m);
          final allConflicts = <String>[
            if (localConflict != null) localConflict,
            ...crossList,
          ];
          final conflict =
              allConflicts.isEmpty ? null : allConflicts.join(' · ');
          final availRank = availabilityRank(m, startDate, endDate);
          return (
            member: m,
            conflict: conflict,
            conflicts: allConflicts,
            availRank: availRank,
          );
        }).toList()
          ..sort((a, b) {
            final aBlocked = a.conflict != null ? 1 : 0;
            final bBlocked = b.conflict != null ? 1 : 0;
            if (aBlocked != bBlocked) return aBlocked.compareTo(bBlocked);
            if (a.availRank != b.availRank) {
              return a.availRank.compareTo(b.availRank);
            }
            return a.member.displayName
                .toLowerCase()
                .compareTo(b.member.displayName.toLowerCase());
          });

        // Auswahl gültig halten (freie Piloten bevorzugt vorbelegen, aber alle auswählbar)
        final selectedEntry = pilotEntries
            .where((e) => e.member.id == selectedPilotId)
            .firstOrNull;
        if (selectedEntry == null) {
          final firstFree =
              pilotEntries.where((e) => e.conflict == null).firstOrNull;
          selectedPilotId =
              (firstFree ?? pilotEntries.firstOrNull)?.member.id;
        }
        final activeEntry = pilotEntries
            .where((e) => e.member.id == selectedPilotId)
            .firstOrNull;
        final canSubmit = !saving &&
            activeEntry != null &&
            !effEnd.isBefore(effStart);

        Future<void> submit(TandemDutyStatus status) async {
          if (!canSubmit) return;
          // Live-Absicherung über alle Flugschulen hinweg
          final liveCrossMap = await SecurityPrivacyService()
              .checkCrossSchoolConflicts(
            flightSchoolId: fs.id,
            userIds: [
              activeEntry.member.id,
              if (activeEntry.member.userRowId.isNotEmpty)
                activeEntry.member.userRowId,
            ],
            startTime: effStart,
            endTime: effEnd,
            otherSchoolsOnly: true,
          );
          if (!ctx.mounted) return;
          final finalConflicts = <String>{
            ...activeEntry.conflicts,
            ...liveCrossMap.values.expand((e) => e),
          }.toList();

          if (finalConflicts.isNotEmpty) {
            if (status == TandemDutyStatus.requestedByAdmin) {
              if (liveCrossMap.isNotEmpty) {
                setLocal(() {
                  crossConflictsByUserId = {
                    ...crossConflictsByUserId,
                    ...liveCrossMap,
                  };
                });
              }
              await showDialog<void>(
                context: ctx,
                builder: (dCtx) => AlertDialog(
                  icon: const Icon(
                    Icons.warning_amber_rounded,
                    color: AppTheme.dangerColor,
                    size: 32,
                  ),
                  title: const Text('Anfragen nicht möglich'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${activeEntry.member.displayName} ist im gewählten Zeitraum bereits anderweitig verplant und kann eine Anfrage nutzerseitig nicht bestätigen. Bitte nutze stattdessen „Direkt bestätigen“.',
                      ),
                      const SizedBox(height: 10),
                      ...finalConflicts.map(
                        (c) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '• $c',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppTheme.dangerColor,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    FilledButton(
                      onPressed: () => Navigator.pop(dCtx),
                      child: const Text('Verstanden'),
                    ),
                  ],
                ),
              );
              return;
            }
            final confirmed = await showAdminDoubleBookingConfirmDialog(
              ctx,
              title: 'Doppelbesetzung bestätigen',
              message:
                  '${activeEntry.member.displayName} ist im gewählten Zeitraum bereits anderweitig verplant. Möchtest du die Person trotzdem zusätzlich als Tandempilot einteilen?',
              conflicts: finalConflicts,
              confirmLabel: 'Trotzdem einteilen',
            );
            if (!confirmed || !ctx.mounted) return;
          }
          setLocal(() => saving = true);
          final created = await TandemService().createDuty(
            flightSchoolId: fs.id,
            userId: activeEntry.member.id,
            startDate: effStart,
            endDate: effEnd,
            isFullDay: isFullDay,
            status: status,
            notes: notesCtrl.text,
            pilotName: activeEntry.member.displayName,
          );
          if (!ctx.mounted) return;
          if (created != null) {
            Navigator.pop(ctx, true);
          } else {
            setLocal(() => saving = false);
            ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(
              const SnackBar(
                content: Text(
                  'Speichern fehlgeschlagen. Wurde das Appwrite-Setup für Tandem ausgeführt?',
                ),
              ),
            );
          }
        }

        return AlertDialog(
          title: const Row(
            children: [
              TintedIconBadge(
                icon: Icons.paragliding_rounded,
                iconColor: AppTheme.primaryColor,
                backgroundColor: AppTheme.primaryTint,
                size: 36,
                iconSize: 19,
                radius: 10,
              ),
              SizedBox(width: 10),
              Expanded(child: Text('Tandempilot einteilen')),
            ],
          ),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: Text('Von: ${_fmtDate(startDate)}'),
                          onPressed: saving
                              ? null
                              : () async {
                                  final picked = await showDatePicker(
                                    context: ctx,
                                    initialDate: startDate,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2100),
                                  );
                                  if (picked != null) {
                                    setLocal(() {
                                      startDate = picked;
                                      if (endDate.isBefore(startDate)) {
                                        endDate = startDate;
                                      }
                                    });
                                  }
                                },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.event, size: 16),
                          label: Text('Bis: ${_fmtDate(endDate)}'),
                          onPressed: saving
                              ? null
                              : () async {
                                  final picked = await showDatePicker(
                                    context: ctx,
                                    initialDate: endDate,
                                    firstDate: startDate,
                                    lastDate: DateTime(2100),
                                  );
                                  if (picked != null) {
                                    setLocal(() => endDate = picked);
                                  }
                                },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Ganztägig',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      isFullDay
                          ? 'Standard: kompletter Flugtag'
                          : '${_fmtTime(startTime)} – ${_fmtTime(endTime)} Uhr',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    value: isFullDay,
                    onChanged: saving
                        ? null
                        : (v) => setLocal(() => isFullDay = v),
                  ),
                  if (!isFullDay) ...[
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.schedule, size: 16),
                            label: Text('Ab ${_fmtTime(startTime)}'),
                            onPressed: saving
                                ? null
                                : () async {
                                    final t = await showTimePicker(
                                      context: ctx,
                                      initialTime: startTime,
                                    );
                                    if (t != null) {
                                      setLocal(() => startTime = t);
                                    }
                                  },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.schedule_outlined, size: 16),
                            label: Text('Bis ${_fmtTime(endTime)}'),
                            onPressed: saving
                                ? null
                                : () async {
                                    final t = await showTimePicker(
                                      context: ctx,
                                      initialTime: endTime,
                                    );
                                    if (t != null) {
                                      setLocal(() => endTime = t);
                                    }
                                  },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 8),
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Tandempilot *',
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedPilotId,
                        isExpanded: true,
                        items: pilotEntries.map((entry) {
                          final isBlocked = entry.conflict != null;
                          final isAvail = !isBlocked && entry.availRank == 0;
                          final isBlackout = !isBlocked && entry.availRank == 2;
                          return DropdownMenuItem<String>(
                            value: entry.member.id,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isAvail
                                    ? AppTheme.successBg
                                    : isBlocked
                                        ? AppTheme.dangerBg
                                            .withValues(alpha: 0.55)
                                        : isBlackout
                                            ? AppTheme.warningBg
                                            : null,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isBlocked
                                        ? Icons.warning_amber_rounded
                                        : isAvail
                                            ? Icons.check_circle_outline
                                            : isBlackout
                                                ? Icons.event_busy_outlined
                                                : Icons.person_outline,
                                    size: 16,
                                    color: isBlocked
                                        ? AppTheme.dangerColor
                                        : isAvail
                                            ? AppTheme.successColor
                                            : isBlackout
                                                ? AppTheme.warningColor
                                                : cs.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      isBlocked
                                          ? '${entry.member.displayName} (${entry.conflict})'
                                          : isAvail
                                              ? '${entry.member.displayName} · Verfügbar'
                                              : isBlackout
                                                  ? '${entry.member.displayName} · Abwesend'
                                                  : entry.member.displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: isAvail
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: isBlocked
                                            ? AppTheme.dangerColor
                                            : isAvail
                                                ? AppTheme.successColor
                                                : cs.onSurface,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: saving
                            ? null
                            : (v) => setLocal(() => selectedPilotId = v),
                      ),
                    ),
                  ),
                  if (activeEntry?.conflict != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.dangerBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppTheme.dangerColor.withValues(alpha: 0.30),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            size: 18,
                            color: AppTheme.dangerColor,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Achtung Doppelbesetzung: ${activeEntry!.conflict!} (Anfragen ist deaktiviert – bitte direkt bestätigen)',
                              style: const TextStyle(
                                color: AppTheme.dangerColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (activeEntry == null) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Alle Tandempiloten sind in diesem Zeitraum bereits verplant.',
                      style: TextStyle(
                        color: AppTheme.dangerColor,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Notiz (optional, z. B. Startplatz / Gebiet)',
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen'),
            ),
            Tooltip(
              message: activeEntry?.conflict != null
                  ? 'Bei Doppelbesetzung nicht möglich – bitte direkt bestätigen'
                  : '',
              child: OutlinedButton(
                onPressed: (canSubmit && activeEntry.conflict == null)
                    ? () => submit(TandemDutyStatus.requestedByAdmin)
                    : null,
                child: const Text('Anfragen'),
              ),
            ),
            FilledButton(
              onPressed:
                  canSubmit ? () => submit(TandemDutyStatus.confirmed) : null,
              child: const Text('Direkt bestätigen'),
            ),
          ],
        );
      },
    ),
  );

  notesCtrl.dispose();
  return result == true;
}

/// Nutzer-Dialog: Tandempilot fragt Einteilung für einen Tag oder Zeitraum an
/// (Admin-Freigabe erforderlich, Doppelbelegung streng blockiert).
Future<bool> showPilotRequestTandemDialog({
  required BuildContext context,
  required UserModelUserView user,
  required List<FlightSchoolUserView> eligibleSchools,
  required DateTime initialDate,
}) async {
  if (eligibleSchools.isEmpty) return false;

  String selectedSchoolId = eligibleSchools.first.id;
  DateTime startDate =
      DateTime(initialDate.year, initialDate.month, initialDate.day);
  DateTime endDate = startDate;
  bool isFullDay = true;
  TimeOfDay startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay endTime = const TimeOfDay(hour: 17, minute: 0);
  final notesCtrl = TextEditingController();
  bool saving = false;

  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final cs = Theme.of(ctx).colorScheme;
        final effStart = isFullDay ? startDate : _combine(startDate, startTime);
        final effEnd = isFullDay ? endDate : _combine(endDate, endTime);

        final conflict = TandemService.findScheduleConflict(
          userId: user.id,
          startDate: effStart,
          endDate: effEnd,
          isFullDay: isFullDay,
          events: user.events,
          tandemDuties: user.tandemDuties,
          isUserOwnEventsView: true,
        );

        final canSubmit =
            !saving && conflict == null && !effEnd.isBefore(effStart);

        return AlertDialog(
          title: const Row(
            children: [
              TintedIconBadge(
                icon: Icons.paragliding_rounded,
                iconColor: AppTheme.primaryColor,
                backgroundColor: AppTheme.primaryTint,
                size: 36,
                iconSize: 19,
                radius: 10,
              ),
              SizedBox(width: 10),
              Expanded(child: Text('Als Tandempilot anfragen')),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (eligibleSchools.length > 1) ...[
                    DropdownButtonFormField<String>(
                      initialValue: selectedSchoolId,
                      decoration: const InputDecoration(
                        labelText: 'Flugschule',
                      ),
                      items: eligibleSchools
                          .map(
                            (s) => DropdownMenuItem(
                              value: s.id,
                              child: Text(s.displayName),
                            ),
                          )
                          .toList(),
                      onChanged: saving
                          ? null
                          : (v) {
                              if (v != null) {
                                setLocal(() => selectedSchoolId = v);
                              }
                            },
                    ),
                    const SizedBox(height: 10),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: Text('Von: ${_fmtDate(startDate)}'),
                          onPressed: saving
                              ? null
                              : () async {
                                  final picked = await showDatePicker(
                                    context: ctx,
                                    initialDate: startDate,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2100),
                                  );
                                  if (picked != null) {
                                    setLocal(() {
                                      startDate = picked;
                                      if (endDate.isBefore(startDate)) {
                                        endDate = startDate;
                                      }
                                    });
                                  }
                                },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.event, size: 16),
                          label: Text('Bis: ${_fmtDate(endDate)}'),
                          onPressed: saving
                              ? null
                              : () async {
                                  final picked = await showDatePicker(
                                    context: ctx,
                                    initialDate: endDate,
                                    firstDate: startDate,
                                    lastDate: DateTime(2100),
                                  );
                                  if (picked != null) {
                                    setLocal(() => endDate = picked);
                                  }
                                },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Ganztägig',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      isFullDay
                          ? 'Kompletter Tag (Standard)'
                          : 'Eingeschränkt: ${_fmtTime(startTime)} – ${_fmtTime(endTime)} Uhr',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    value: isFullDay,
                    onChanged: saving
                        ? null
                        : (v) => setLocal(() => isFullDay = v),
                  ),
                  if (!isFullDay) ...[
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.schedule, size: 16),
                            label: Text('Ab ${_fmtTime(startTime)}'),
                            onPressed: saving
                                ? null
                                : () async {
                                    final t = await showTimePicker(
                                      context: ctx,
                                      initialTime: startTime,
                                    );
                                    if (t != null) {
                                      setLocal(() => startTime = t);
                                    }
                                  },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.schedule_outlined, size: 16),
                            label: Text('Bis ${_fmtTime(endTime)}'),
                            onPressed: saving
                                ? null
                                : () async {
                                    final t = await showTimePicker(
                                      context: ctx,
                                      initialTime: endTime,
                                    );
                                    if (t != null) {
                                      setLocal(() => endTime = t);
                                    }
                                  },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (conflict != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.dangerBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.block_rounded,
                            size: 18,
                            color: AppTheme.dangerColor,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Doppelbelegung nicht möglich: $conflict',
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.dangerColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: notesCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Notiz für den Admin (optional)',
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Deine Anfrage wird an die Flugschule gesendet und nach Freigabe verbindlich eingetragen.',
                    style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: canSubmit
                  ? () async {
                      setLocal(() => saving = true);
                      final checkStart = isFullDay
                          ? DateTime(
                              startDate.year,
                              startDate.month,
                              startDate.day,
                              0,
                              0,
                            )
                          : effStart;
                      final checkEnd = isFullDay
                          ? DateTime(
                              endDate.year,
                              endDate.month,
                              endDate.day,
                              23,
                              59,
                              59,
                            )
                          : effEnd;
                      final serverMap = await SecurityPrivacyService()
                          .checkCrossSchoolConflicts(
                        userIds: [user.id],
                        startTime: checkStart,
                        endTime: checkEnd,
                        otherSchoolsOnly: false,
                      );
                      if (!ctx.mounted) return;
                      final serverConflicts =
                          serverMap.values.expand((e) => e).toList();
                      if (serverConflicts.isNotEmpty) {
                        setLocal(() => saving = false);
                        await showUserBookingConflictDialog(
                          ctx,
                          reason: serverConflicts.join(' · '),
                        );
                        return;
                      }
                      final created = await TandemService().createDuty(
                        flightSchoolId: selectedSchoolId,
                        userId: user.id,
                        startDate: effStart,
                        endDate: effEnd,
                        isFullDay: isFullDay,
                        status: TandemDutyStatus.requestedByPilot,
                        notes: notesCtrl.text,
                        pilotName: user.name.isNotEmpty ? user.name : user.mail,
                      );
                      if (!ctx.mounted) return;
                      if (created != null) {
                        Navigator.pop(ctx, true);
                      } else {
                        setLocal(() => saving = false);
                        ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(
                          const SnackBar(
                            content: Text('Anfrage konnte nicht gesendet werden.'),
                          ),
                        );
                      }
                    }
                  : null,
              child: const Text('Anfragen'),
            ),
          ],
        );
      },
    ),
  );

  notesCtrl.dispose();
  return result == true;
}

/// Admin-Dialog zum Anlegen / Bearbeiten eines Tandem-Bedarfszeitraums (Saison + Wochentage).
Future<bool> showTandemDemandDialog({
  required BuildContext context,
  required String flightSchoolId,
  TandemDemand? existing,
  DateTime? initialDate,
}) async {
  final now = initialDate ?? DateTime.now();
  DateTime startDate =
      existing?.startDay ?? DateTime(now.year, now.month, now.day);
  DateTime endDate =
      existing?.endDay ?? startDate.add(const Duration(days: 30));
  int targetPilots = existing?.targetPilots ?? 2;
  final weekdays = Set<int>.from(
    existing?.weekdays ?? const {1, 2, 3, 4, 5, 6, 7},
  );
  final labelCtrl = TextEditingController(text: existing?.label ?? '');
  bool saving = false;

  const wdNames = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        return AlertDialog(
          title: Text(
            existing == null
                ? 'Tandem-Bedarf festlegen'
                : 'Tandem-Bedarf bearbeiten',
          ),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: labelCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Bezeichnung (optional, z. B. Hauptsaison Sa/So)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: Text('Von: ${_fmtDate(startDate)}'),
                          onPressed: saving
                              ? null
                              : () async {
                                  final picked = await showDatePicker(
                                    context: ctx,
                                    initialDate: startDate,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2100),
                                  );
                                  if (picked != null) {
                                    setLocal(() {
                                      startDate = picked;
                                      if (endDate.isBefore(startDate)) {
                                        endDate = startDate;
                                      }
                                    });
                                  }
                                },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.event, size: 16),
                          label: Text('Bis: ${_fmtDate(endDate)}'),
                          onPressed: saving
                              ? null
                              : () async {
                                  final picked = await showDatePicker(
                                    context: ctx,
                                    initialDate: endDate,
                                    firstDate: startDate,
                                    lastDate: DateTime(2100),
                                  );
                                  if (picked != null) {
                                    setLocal(() => endDate = picked);
                                  }
                                },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Benötigte Tandempiloten / Tag',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton.filledTonal(
                        onPressed: targetPilots > 1
                            ? () => setLocal(() => targetPilots--)
                            : null,
                        icon: const Icon(Icons.remove, size: 18),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          '$targetPilots',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton.filledTonal(
                        onPressed: targetPilots < 30
                            ? () => setLocal(() => targetPilots++)
                            : null,
                        icon: const Icon(Icons.add, size: 18),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Wochentage',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ActionChip(
                        label: const Text('Alle', style: TextStyle(fontSize: 11.5)),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setLocal(
                          () => weekdays.addAll(const {1, 2, 3, 4, 5, 6, 7}),
                        ),
                      ),
                      ActionChip(
                        label: const Text('Mo–Fr', style: TextStyle(fontSize: 11.5)),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setLocal(() {
                          weekdays
                            ..clear()
                            ..addAll(const {1, 2, 3, 4, 5});
                        }),
                      ),
                      ActionChip(
                        label: const Text('Sa–So', style: TextStyle(fontSize: 11.5)),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setLocal(() {
                          weekdays
                            ..clear()
                            ..addAll(const {6, 7});
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: List.generate(7, (idx) {
                      final wd = idx + 1;
                      final sel = weekdays.contains(wd);
                      return FilterChip(
                        label: Text(wdNames[idx]),
                        selected: sel,
                        showCheckmark: false,
                        onSelected: (v) => setLocal(() {
                          if (v) {
                            weekdays.add(wd);
                          } else if (weekdays.length > 1) {
                            weekdays.remove(wd);
                          }
                        }),
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: saving || weekdays.isEmpty
                  ? null
                  : () async {
                      setLocal(() => saving = true);
                      bool success;
                      if (existing == null) {
                        final created = await TandemService().createDemand(
                          flightSchoolId: flightSchoolId,
                          startDate: startDate,
                          endDate: endDate,
                          targetPilots: targetPilots,
                          weekdays: weekdays,
                          label: labelCtrl.text,
                        );
                        success = created != null;
                      } else {
                        success = await TandemService().updateDemand(
                          TandemDemand(
                            id: existing.id,
                            flightSchoolId: flightSchoolId,
                            startDate: startDate,
                            endDate: endDate,
                            targetPilots: targetPilots,
                            weekdays: weekdays,
                            label: labelCtrl.text.trim(),
                          ),
                        );
                      }
                      if (!ctx.mounted) return;
                      if (success) {
                        Navigator.pop(ctx, true);
                      } else {
                        setLocal(() => saving = false);
                      }
                    },
              child: const Text('Speichern'),
            ),
          ],
        );
      },
    ),
  );

  labelCtrl.dispose();
  return ok == true;
}
