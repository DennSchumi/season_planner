import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/core/data/models/planning_period_model.dart';
import 'package:season_planner/core/data/models/tandem_model.dart';
import 'package:season_planner/core/services/planning_service.dart';
import 'package:season_planner/core/services/security_privacy_service.dart';
import 'package:season_planner/core/services/tandem_service.dart';
import 'package:season_planner/core/theme.dart';
import 'package:season_planner/core/widgets/tandem_dialogs.dart';
import 'package:season_planner/core/widgets/user_avatar.dart';
import 'package:season_planner/core/widgets/ux_components.dart';
import 'package:season_planner/fsAdmin/flight_school_provider.dart';
import 'package:season_planner/fsAdmin/services/flight_school_service.dart';

class ManageTandemView extends StatefulWidget {
  const ManageTandemView({super.key});

  @override
  State<ManageTandemView> createState() => _ManageTandemViewState();
}

class _ManageTandemViewState extends State<ManageTandemView> {
  final _tandemService = TandemService();
  final _fsService = FlightSchoolService();
  bool _busy = false;
  List<AvailabilitySubmission> _teamAvailabilities = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAvailabilities());
  }

  Future<void> _loadAvailabilities() async {
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null) return;
    final list = await PlanningService().listSchoolSubmissions(fs.id);
    if (mounted) setState(() => _teamAvailabilities = list);
  }

  Future<void> _reloadSchool() async {
    await context
        .read<FlightSchoolProvider>()
        .reloadFlightSchool(_fsService.getFlightSchool);
    if (mounted) await _loadAvailabilities();
  }

  Future<void> _toggleTandemEnabled(bool enabled) async {
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null || _busy) return;
    setState(() => _busy = true);
    try {
      final ok = await _tandemService.setTandemEnabled(
        flightSchoolId: fs.id,
        enabled: enabled,
      );
      if (!mounted) return;
      if (ok) {
        await _reloadSchool();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              enabled
                  ? 'Tandemplanung wurde aktiviert.'
                  : 'Tandemplanung wurde für ${fs.displayName} deaktiviert.',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Einstellung konnte nicht gespeichert werden. Bitte Appwrite-Setup prüfen.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decideDuty(TandemDuty duty, bool approve) async {
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null || _busy) return;
    setState(() => _busy = true);
    try {
      final isCancelReq = duty.status == TandemDutyStatus.cancellationRequested;
      if (!isCancelReq && approve) {
        final member = fs.findMemberByAnyId(duty.userId);
        final localConflict = TandemService.findScheduleConflict(
          userId: duty.userId,
          userRowId: member?.userRowId,
          startDate: duty.startDate,
          endDate: duty.endDate,
          isFullDay: duty.isFullDay,
          events: fs.events,
          tandemDuties: fs.tandemDuties,
          ignoreDutyId: duty.id,
        );
        final crossMap = await SecurityPrivacyService()
            .checkCrossSchoolConflicts(
          flightSchoolId: fs.id,
          userIds: [
            member?.id ?? duty.userId,
            if (member != null && member.userRowId.isNotEmpty) member.userRowId,
          ],
          startTime: duty.effectiveStart,
          endTime: duty.effectiveEnd,
          ignoreDutyId: duty.id,
          otherSchoolsOnly: true,
        );
        if (!mounted) return;
        final conflicts = <String>{
          if (localConflict != null) localConflict,
          ...crossMap.values.expand((e) => e),
        }.toList();
        if (conflicts.isNotEmpty) {
          final confirmed = await showAdminDoubleBookingConfirmDialog(
            context,
            title: 'Doppelbesetzung bestätigen',
            message:
                '${fs.resolveMemberName(duty.userId)} ist im Zeitraum ${duty.dateRangeLabel} bereits anderweitig verplant. Möchtest du die Tandem-Anfrage trotzdem freigeben?',
            conflicts: conflicts,
            confirmLabel: 'Trotzdem freigeben',
          );
          if (!confirmed || !mounted) return;
        }
      }
      final nextStatus = isCancelReq
          ? (approve ? TandemDutyStatus.declined : TandemDutyStatus.confirmed)
          : (approve ? TandemDutyStatus.confirmed : TandemDutyStatus.declined);
      final ok = await _tandemService.updateDutyStatus(
        flightSchoolId: fs.id,
        dutyId: duty.id,
        newStatus: nextStatus,
        summary:
            '${fs.resolveMemberName(duty.userId)} (${duty.dateRangeLabel})',
      );
      if (ok && mounted) await _reloadSchool();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteDuty(TandemDuty duty) async {
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null || _busy) return;
    setState(() => _busy = true);
    try {
      final ok = await _tandemService.deleteDuty(
        flightSchoolId: fs.id,
        dutyId: duty.id,
        summary:
            '${fs.resolveMemberName(duty.userId)} (${duty.dateRangeLabel})',
      );
      if (ok && mounted) await _reloadSchool();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteDemand(TandemDemand demand) async {
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null || _busy) return;
    setState(() => _busy = true);
    try {
      final ok = await _tandemService.deleteDemand(
        flightSchoolId: fs.id,
        demandId: demand.id,
      );
      if (ok && mounted) await _reloadSchool();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fs = context.watch<FlightSchoolProvider>().flightSchool;
    if (fs == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final upcomingDuties = fs.tandemDuties
        .where(
          (d) =>
              d.status != TandemDutyStatus.declined && !d.endDay.isBefore(today),
        )
        .toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));

    final pilotRequests = upcomingDuties
        .where(
          (d) =>
              d.status == TandemDutyStatus.requestedByPilot ||
              d.status == TandemDutyStatus.cancellationRequested,
        )
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tandemplanung'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _reloadSchool,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
                  children: [
                    // 1) Ein/Aus-Schalter für Flugschulen ohne Tandem
                    SoftCard(
                      padding: const EdgeInsets.all(14),
                      child: SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        secondary: TintedIconBadge(
                          icon: Icons.paragliding_rounded,
                          iconColor: fs.tandemEnabled
                              ? AppTheme.primaryColor
                              : cs.onSurfaceVariant,
                          backgroundColor: fs.tandemEnabled
                              ? AppTheme.primaryTint
                              : AppTheme.backgroundColor,
                        ),
                        title: const Text(
                          'Tandemplanung aktivieren',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        subtitle: Text(
                          fs.tandemEnabled
                              ? 'Aktiv · ${fs.tandemPilots.length} qualifizierte Tandempiloten im Team'
                              : 'Deaktiviert – Tandem-Kalender & Anfragen sind für diese Flugschule ausgeblendet',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        value: fs.tandemEnabled,
                        onChanged: _busy ? null : _toggleTandemEnabled,
                      ),
                    ),

                    if (fs.tandemEnabled) ...[
                      const SizedBox(height: 16),

                      // Quick Actions
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: AppTheme.primaryGlow,
                              ),
                              child: FilledButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () async {
                                        final ok =
                                            await showAdminAssignTandemDialog(
                                          context: context,
                                          fs: fs,
                                          initialDate: today,
                                          teamAvailabilities:
                                              _teamAvailabilities,
                                        );
                                        if (ok && mounted) await _reloadSchool();
                                      },
                                icon: const Icon(Icons.person_add_alt_1, size: 18),
                                label: const Text('Pilot einteilen'),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      final ok = await showTandemDemandDialog(
                                        context: context,
                                        flightSchoolId: fs.id,
                                      );
                                      if (ok && mounted) await _reloadSchool();
                                    },
                              icon: const Icon(Icons.date_range_outlined, size: 18),
                              label: const Text('Bedarf festlegen'),
                            ),
                          ),
                        ],
                      ),

                      // Offene Piloten-Anfragen
                      if (pilotRequests.isNotEmpty) ...[
                        const SizedBox(height: 22),
                        Text(
                          'OFFENE ANFRAGEN & ABSAGEN (${pilotRequests.length})',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.7,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...pilotRequests.map((duty) {
                          final name = fs.resolveMemberName(duty.userId);
                          final avatar =
                              fs.findMemberByAnyId(duty.userId)?.avatarUrl ?? '';
                          final isCancelReq = duty.status ==
                              TandemDutyStatus.cancellationRequested;
                          return SoftCard(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    UserAvatar(
                                      avatarUrl: avatar,
                                      name: name,
                                      radius: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            isCancelReq
                                                ? '$name · Absage angefragt'
                                                : name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14.5,
                                            ),
                                          ),
                                          Text(
                                            '${duty.dateRangeLabel} · ${duty.timeWindowLabel}',
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              color: cs.onSurfaceVariant,
                                            ),
                                          ),
                                          if (duty.notes.isNotEmpty)
                                            Text(
                                              duty.notes,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: cs.onSurfaceVariant,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    FilledButton.icon(
                                      style: isCancelReq
                                          ? FilledButton.styleFrom(
                                              backgroundColor:
                                                  AppTheme.dangerColor,
                                              foregroundColor: Colors.white,
                                            )
                                          : null,
                                      onPressed: _busy
                                          ? null
                                          : () => _decideDuty(duty, true),
                                      icon: const Icon(Icons.check, size: 17),
                                      label: Text(
                                        isCancelReq
                                            ? 'Absage bestätigen'
                                            : 'Annehmen',
                                      ),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: _busy
                                          ? null
                                          : () => _decideDuty(duty, false),
                                      icon: const Icon(Icons.close, size: 17),
                                      label: Text(
                                        isCancelReq
                                            ? 'Bleibt aktiv'
                                            : 'Ablehnen',
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }),
                      ],

                      // Bedarfszeiträume (Option B)
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'BEDARFSZEITRÄUME (${fs.tandemDemands.length})',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.7,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (fs.tandemDemands.isEmpty)
                        SoftCard(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'Noch kein Tandem-Bedarf hinterlegt. Lege Zeiträume mit Wochentagen fest (z. B. Hauptsaison Sa–So: 3 Piloten), damit offene Tage im Kalender farblich markiert werden.',
                            style: TextStyle(
                              fontSize: 13,
                              color: cs.onSurfaceVariant,
                              height: 1.4,
                            ),
                          ),
                        )
                      else
                        ...fs.tandemDemands.map(
                          (dem) => SoftCard(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                            onTap: () async {
                              final ok = await showTandemDemandDialog(
                                context: context,
                                flightSchoolId: fs.id,
                                existing: dem,
                              );
                              if (ok && mounted) await _reloadSchool();
                            },
                            child: Row(
                              children: [
                                TintedIconBadge(
                                  icon: Icons.groups_outlined,
                                  iconColor: AppTheme.stage1Color,
                                  backgroundColor: AppTheme.stage1Bg,
                                  size: 38,
                                  iconSize: 19,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        dem.label.isNotEmpty
                                            ? dem.label
                                            : dem.dateRangeLabel,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${dem.dateRangeLabel} · ${dem.weekdaysLabel}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                StatusPill(
                                  label: '${dem.targetPilots} Piloten',
                                  foreground: AppTheme.primaryColor,
                                  background: AppTheme.primaryTint,
                                ),
                                IconButton(
                                  tooltip: 'Löschen',
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 19,
                                    color: AppTheme.dangerColor,
                                  ),
                                  onPressed:
                                      _busy ? null : () => _deleteDemand(dem),
                                ),
                              ],
                            ),
                          ),
                        ),

                      // Aktive / geplante Tandem-Einteilungen
                      const SizedBox(height: 22),
                      Text(
                        'BEVORSTEHENDE EINTEILUNGEN (${upcomingDuties.length})',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.7,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (upcomingDuties.isEmpty)
                        SoftCard(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'Aktuell keine bevorstehenden Tandem-Einteilungen. Tippe oben auf „Pilot einteilen“ oder klicke direkt im Kalender auf einen Tag.',
                            style: TextStyle(
                              fontSize: 13,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        )
                      else
                        ...upcomingDuties.map((duty) {
                          final name = fs.resolveMemberName(duty.userId);
                          final avatar =
                              fs.findMemberByAnyId(duty.userId)?.avatarUrl ?? '';
                          final (Color fg, Color bg) = switch (duty.status) {
                            TandemDutyStatus.confirmed => (
                                AppTheme.successColor,
                                AppTheme.successBg,
                              ),
                            TandemDutyStatus.requestedByPilot => (
                                AppTheme.infoColor,
                                AppTheme.infoBg,
                              ),
                            TandemDutyStatus.requestedByAdmin => (
                                AppTheme.warningColor,
                                AppTheme.warningBg,
                              ),
                            TandemDutyStatus.cancellationRequested => (
                                AppTheme.dangerColor,
                                AppTheme.dangerBg,
                              ),
                            TandemDutyStatus.declined => (
                                AppTheme.dangerColor,
                                AppTheme.dangerBg,
                              ),
                          };
                          return SoftCard(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.fromLTRB(14, 11, 8, 11),
                            child: Row(
                              children: [
                                UserAvatar(
                                  avatarUrl: avatar,
                                  name: name,
                                  radius: 19,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                        ),
                                      ),
                                      Text(
                                        '${duty.dateRangeLabel} · ${duty.timeWindowLabel}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                StatusPill(
                                  label: duty.status.label,
                                  foreground: fg,
                                  background: bg,
                                  fontSize: 10.5,
                                ),
                                IconButton(
                                  tooltip: 'Entfernen',
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 19,
                                    color: AppTheme.dangerColor,
                                  ),
                                  onPressed:
                                      _busy ? null : () => _deleteDuty(duty),
                                ),
                              ],
                            ),
                          );
                        }),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
