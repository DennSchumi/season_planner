import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/core/data/enums/event_user_status_enum.dart';
import 'package:season_planner/core/data/models/tandem_model.dart';
import 'package:season_planner/core/theme.dart';
import 'package:season_planner/fsAdmin/flight_school_provider.dart';
import 'package:season_planner/fsAdmin/services/flight_school_service.dart';

class MemberStatisticsView extends StatefulWidget {
  const MemberStatisticsView({super.key});

  @override
  State<MemberStatisticsView> createState() => _MemberStatisticsViewState();
}

class _MemberStatisticsViewState extends State<MemberStatisticsView> {
  int? _selectedYear;
  bool _loadingArchive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureFullHistory());
  }

  Future<void> _ensureFullHistory() async {
    if (_loadingArchive) return;
    final fsProvider = context.read<FlightSchoolProvider>();
    final current = fsProvider.flightSchool;
    if (current == null || current.hasLoadedArchive) return;

    setState(() => _loadingArchive = true);
    try {
      fsProvider.setIncludeArchive(true);
      final svc = FlightSchoolService();
      final results = await Future.wait([
        svc.refreshEventsOnly(current, includeArchive: true),
        svc.refreshTandemOnly(current, includeArchive: true),
      ]);
      if (!mounted) return;
      var updated = current.copyWith(hasLoadedArchive: true);
      if (results[0] != null) {
        updated = updated.copyWith(events: results[0]!.events);
      }
      if (results[1] != null) {
        updated = updated.copyWith(
          tandemDuties: results[1]!.tandemDuties,
          tandemDemands: results[1]!.tandemDemands,
        );
      }
      fsProvider.applyPartialUpdate(updated);
    } finally {
      if (mounted) setState(() => _loadingArchive = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fs = context.watch<FlightSchoolProvider>().flightSchool;
    if (fs == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final yearSet = <int>{
      ...fs.events.map((e) => e.startTime.year),
      if (fs.tandemEnabled)
        ...fs.tandemDuties
            .where((d) => d.status == TandemDutyStatus.confirmed)
            .expand((d) => {d.startDay.year, d.endDay.year}),
    };
    final years = yearSet.toList()..sort((a, b) => b.compareTo(a));

    final filteredEvents =
        _selectedYear == null
            ? fs.events
            : fs.events
                .where((e) => e.startTime.year == _selectedYear)
                .toList();

    final Map<
      String,
      ({int count, int days, int tandemDays, Map<String, int> roles})
    >
    stats = {};

    for (final m in fs.members) {
      stats[m.id] = (count: 0, days: 0, tandemDays: 0, roles: <String, int>{});
    }

    for (final ev in filteredEvents) {
      final eventDays =
          ev.endTime
              .difference(
                DateTime(
                  ev.startTime.year,
                  ev.startTime.month,
                  ev.startTime.day,
                ),
              )
              .inDays +
          1;
      for (final tm in ev.team) {
        if (tm.isSlot) continue;
        final status = tm.statusEnum;
        final accepted =
            status == EventUserStatusEnum.accepted_user ||
            status == EventUserStatusEnum.accepted_flight_school;
        if (!accepted) continue;

        final canonicalId = fs.findMemberByAnyId(tm.userId)?.id ?? tm.userId;
        final prev =
            stats[canonicalId] ??
            (count: 0, days: 0, tandemDays: 0, roles: <String, int>{});
        final roleLabel = tm.roleLabel;
        final nextRoles = Map<String, int>.from(prev.roles);
        nextRoles[roleLabel] = (nextRoles[roleLabel] ?? 0) + 1;
        stats[canonicalId] = (
          count: prev.count + 1,
          days: prev.days + (eventDays > 0 ? eventDays : 1),
          tandemDays: prev.tandemDays,
          roles: nextRoles,
        );
      }
    }

    // Bestätigte Tandem-Tage getrennt mitzählen (sofern Tandemplanung aktiv)
    if (fs.tandemEnabled) {
      for (final duty in fs.tandemDuties) {
        if (duty.status != TandemDutyStatus.confirmed) continue;
        DateTime effStart = duty.startDay;
        DateTime effEnd = duty.endDay;
        if (_selectedYear != null) {
          final yearStart = DateTime(_selectedYear!, 1, 1);
          final yearEnd = DateTime(_selectedYear!, 12, 31);
          if (effEnd.isBefore(yearStart) || effStart.isAfter(yearEnd)) continue;
          if (effStart.isBefore(yearStart)) effStart = yearStart;
          if (effEnd.isAfter(yearEnd)) effEnd = yearEnd;
        }
        final daysInRange = effEnd.difference(effStart).inDays + 1;
        if (daysInRange <= 0) continue;

        final canonicalId =
            fs.findMemberByAnyId(duty.userId)?.id ?? duty.userId;
        final prev =
            stats[canonicalId] ??
            (count: 0, days: 0, tandemDays: 0, roles: <String, int>{});
        stats[canonicalId] = (
          count: prev.count,
          days: prev.days,
          tandemDays: prev.tandemDays + daysInRange,
          roles: prev.roles,
        );
      }
    }

    final sortedIds =
        stats.keys.toList()..sort((a, b) {
          final sa = stats[a]!;
          final sb = stats[b]!;
          final totalCmp = (sb.days + sb.tandemDays).compareTo(
            sa.days + sa.tandemDays,
          );
          if (totalCmp != 0) return totalCmp;
          return sb.count.compareTo(sa.count);
        });

    return Scaffold(
      appBar: AppBar(title: const Text('Statistik & Einsätze')),
      body: SafeArea(
        child: Column(
          children: [
            if (_loadingArchive) const LinearProgressIndicator(minHeight: 2),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: DropdownButtonFormField<int?>(
                initialValue: _selectedYear,
                decoration: const InputDecoration(labelText: 'Saison / Jahr'),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Alle Jahre'),
                  ),
                  ...years.map(
                    (y) => DropdownMenuItem<int?>(
                      value: y,
                      child: Text('Saison $y'),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() => _selectedYear = v),
              ),
            ),
            Expanded(
              child:
                  sortedIds.isEmpty
                      ? const Center(
                        child: Text(
                          'Keine bestätigten Einsätze im gewählten Zeitraum.',
                          style: TextStyle(color: Colors.black54),
                        ),
                      )
                      : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: sortedIds.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final uid = sortedIds[index];
                          final s = stats[uid]!;
                          final name = fs.resolveMemberName(uid);
                          final totalDays = s.days + s.tandemDays;

                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ),
                                      Chip(
                                        label: Text(
                                          fs.tandemEnabled && s.tandemDays > 0
                                              ? '${s.count} Events · $totalDays Tage gesamt'
                                              : '${s.count} Einsätze · ${s.days} Tage',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (s.roles.isNotEmpty ||
                                      (fs.tandemEnabled &&
                                          s.tandemDays > 0)) ...[
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        if (fs.tandemEnabled &&
                                            s.tandemDays > 0)
                                          Chip(
                                            visualDensity:
                                                VisualDensity.compact,
                                            backgroundColor:
                                                AppTheme.primaryTint,
                                            avatar: const Icon(
                                              Icons.paragliding_rounded,
                                              size: 15,
                                              color: AppTheme.primaryColor,
                                            ),
                                            label: Text(
                                              'Tandem: ${s.tandemDays} ${s.tandemDays == 1 ? 'Tag' : 'Tage'}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: AppTheme.primaryColor,
                                              ),
                                            ),
                                          ),
                                        ...s.roles.entries.map(
                                          (e) => Chip(
                                            visualDensity:
                                                VisualDensity.compact,
                                            label: Text(
                                              '${e.key}: ${e.value}×',
                                              style: const TextStyle(
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
            ),
          ],
        ),
      ),
    );
  }
}
