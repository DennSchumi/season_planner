import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/core/data/models/event_model.dart';
import 'package:season_planner/core/data/models/planning_period_model.dart';
import 'package:season_planner/core/services/planning_service.dart';
import 'package:season_planner/core/theme.dart';
import 'package:season_planner/core/widgets/ux_components.dart';
import 'package:season_planner/fsAdmin/flight_school_provider.dart';
import 'package:season_planner/fsAdmin/services/flight_school_service.dart';
import 'package:season_planner/user/user_provider.dart';

class ManagePlanningPeriodsView extends StatefulWidget {
  final int initialTab;

  const ManagePlanningPeriodsView({super.key, this.initialTab = 0});

  @override
  State<ManagePlanningPeriodsView> createState() =>
      _ManagePlanningPeriodsViewState();
}

class _ManagePlanningPeriodsViewState extends State<ManagePlanningPeriodsView> {
  final _service = PlanningService();
  List<AvailabilitySubmission> _submissions = [];
  bool _loadingSubs = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadSubmissions();
  }

  Future<void> _loadSubmissions() async {
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null) return;
    setState(() => _loadingSubs = true);
    final subs = await _service.listSchoolSubmissions(fs.id);
    if (!mounted) return;
    setState(() {
      _submissions = subs;
      _loadingSubs = false;
    });
  }

  Future<void> _reloadAll() async {
    await context.read<FlightSchoolProvider>().reloadFlightSchool(
      FlightSchoolService().getFlightSchool,
    );
    await _loadSubmissions();
  }

  Future<void> _openPeriodDialog({PlanningPeriod? existing}) async {
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null) return;

    final isEdit = existing != null;
    final defaultYear = DateTime.now().year + (isEdit ? 0 : 1);
    final labelCtrl = TextEditingController(
      text: isEdit ? existing.seasonLabel : 'Saison $defaultYear',
    );
    PlanningStage stage =
        isEdit ? existing.stage : PlanningStage.availability;
    DateTimeRange range = DateTimeRange(
      start: existing?.startDate ?? DateTime(defaultYear, 1, 1),
      end: existing?.endDate ?? DateTime(defaultYear, 12, 31),
    );

    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder: (ctx, setLocal) {
              final overlapping = fs.planningPeriods.where((p) {
                if (isEdit && p.id == existing.id) return false;
                return p.overlapsRange(range.start, range.end);
              }).toList();

              return AlertDialog(
                title: Text(
                  isEdit ? 'Saison bearbeiten' : 'Neue Saison anlegen',
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
                            labelText: 'Bezeichnung (z. B. Saison 2027)',
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Gültigkeitszeitraum der Saison',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showDateRangePicker(
                              context: ctx,
                              firstDate: DateTime(2020, 1, 1),
                              lastDate: DateTime(2040, 12, 31),
                              initialDateRange: range,
                              helpText: 'Saison-Zeitraum wählen',
                            );
                            if (picked != null) {
                              setLocal(() => range = picked);
                            }
                          },
                          icon: const Icon(Icons.date_range),
                          label: Text(
                            '${_fmt(range.start)} – ${_fmt(range.end)}',
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Für alle Events innerhalb dieses Zeitraums gilt automatisch die Planungsstufe dieser Saison.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (overlapping.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppTheme.warningColor.withValues(
                                alpha: 0.12,
                              ),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: AppTheme.warningColor.withValues(
                                  alpha: 0.4,
                                ),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.warning_amber_rounded,
                                  size: 18,
                                  color: AppTheme.warningColor,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Überschneidung mit: ${overlapping.map((p) => '${p.seasonLabel} (${p.dateRangeLabel})').join(', ')}.',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        DropdownButtonFormField<PlanningStage>(
                          initialValue: stage,
                          decoration: const InputDecoration(
                            labelText: 'Planungsstufe',
                          ),
                          items:
                              PlanningStage.values
                                  .map(
                                    (s) => DropdownMenuItem(
                                      value: s,
                                      child: Text(s.label),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (v) => setLocal(() => stage = v ?? stage),
                        ),
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
                    onPressed: () {
                      if (labelCtrl.text.trim().isEmpty) return;
                      Navigator.pop(ctx, true);
                    },
                    child: Text(isEdit ? 'Speichern' : 'Anlegen'),
                  ),
                ],
              );
            },
          ),
    );

    final label = labelCtrl.text.trim();
    labelCtrl.dispose();
    if (ok != true || label.isEmpty) return;

    final startDate = DateTime(
      range.start.year,
      range.start.month,
      range.start.day,
    );
    final endDate = DateTime(
      range.end.year,
      range.end.month,
      range.end.day,
      23,
      59,
      59,
    );

    setState(() => _busy = true);
    if (isEdit) {
      await _service.updatePeriod(
        period: existing,
        seasonLabel: label,
        stage: stage,
        startDate: startDate,
        endDate: endDate,
      );
    } else {
      await _service.createPeriod(
        flightSchoolId: fs.id,
        seasonLabel: label,
        stage: stage,
        startDate: startDate,
        endDate: endDate,
      );
    }
    await _reloadAll();
    if (mounted) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isEdit
                ? 'Saison „$label“ aktualisiert.'
                : 'Saison „$label“ angelegt.',
          ),
        ),
      );
    }
  }

  Future<void> _deletePeriod(PlanningPeriod period) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Saison löschen?'),
        content: Text(
          'Möchtest du „${period.seasonLabel}“ (${period.dateRangeLabel}) wirklich löschen? '
          'Events in diesem Zeitraum fallen danach auf Standard (Stufe 3 – Produktion) zurück.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.dangerColor),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    await _service.deletePeriod(period);
    await _reloadAll();
    if (mounted) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saison „${period.seasonLabel}“ gelöscht.')),
      );
    }
  }

  Future<void> _changeStage(
    PlanningPeriod period,
    PlanningStage newStage,
  ) async {
    setState(() => _busy = true);
    await _service.updatePeriodStage(period: period, newStage: newStage);
    await _reloadAll();
    if (mounted) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${period.seasonLabel} auf ${newStage.label} umgestellt.',
          ),
        ),
      );
    }
  }

  Future<void> _approveSwap(Event event, TeamMember tm) async {
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null || tm.assignmentId == null || tm.swapRequestedBy == null)
      return;
    setState(() => _busy = true);
    await _service.approveSwap(
      flightSchoolId: fs.id,
      databaseId: fs.databaseId,
      tableId: fs.teamAssignmentsEventsCollectionId,
      assignmentId: tm.assignmentId!,
      newUserId: tm.swapRequestedBy!,
      newUserName: tm.swapRequestedByName ?? 'Teammitglied',
      eventName: event.displayName,
    );
    await _reloadAll();
    if (mounted) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Platztausch bestätigt!')));
    }
  }

  Future<void> _rejectSwap(Event event, TeamMember tm) async {
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null || tm.assignmentId == null) return;
    setState(() => _busy = true);
    await _service.rejectSwap(
      flightSchoolId: fs.id,
      databaseId: fs.databaseId,
      tableId: fs.teamAssignmentsEventsCollectionId,
      assignmentId: tm.assignmentId!,
      eventName: event.displayName,
    );
    await _reloadAll();
    if (mounted) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Tauschanfrage abgelehnt.')));
    }
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  @override
  Widget build(BuildContext context) {
    final fs = context.watch<FlightSchoolProvider>().flightSchool;
    final currentUser = context.watch<UserProvider>().user;
    if (fs == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    String resolveUser(String uid, {String? fallback}) {
      final selfFallback =
          currentUser != null && uid == currentUser.id
              ? (currentUser.name.isNotEmpty
                  ? currentUser.name
                  : currentUser.mail)
              : null;
      return fs.resolveMemberName(uid, fallbackName: fallback ?? selfFallback);
    }

    final periodLabelById = {
      for (final p in fs.planningPeriods) p.id: p.seasonLabel,
    };

    // Alle offenen Tauschanfragen aus Stufe-3-Events sammeln
    final pendingSwaps = <({Event event, TeamMember tm})>[];
    for (final ev in fs.events) {
      for (final tm in ev.team) {
        if (tm.hasOpenSwapRequest) {
          pendingSwaps.add((event: ev, tm: tm));
        }
      }
    }

    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialTab.clamp(0, 2),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Saisonplanung & Stufen'),
          bottom: TabBar(
            tabs: [
              const Tab(text: 'Stufen'),
              const Tab(text: 'Verfügbarkeit'),
              Tab(
                text:
                    pendingSwaps.isEmpty
                        ? 'Tausch'
                        : 'Tausch (${pendingSwaps.length})',
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _busy ? null : () => _openPeriodDialog(),
          icon: const Icon(Icons.add),
          label: const Text('Neue Saison'),
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (_busy) const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: TabBarView(
                  children: [
                    // TAB 1: Planungsstufen je Saison
                    fs.planningPeriods.isEmpty
                        ? EmptyStateView(
                          icon: Icons.layers_outlined,
                          title: 'Noch keine Saisons angelegt',
                          subtitle:
                              'Lege eine Saison mit Zeitraum an. Für alle Events innerhalb dieses Zeitraums gilt automatisch die gewählte Planungsstufe.',
                          actionLabel: 'Neue Saison anlegen',
                          actionIcon: Icons.add,
                          onAction: _busy ? null : () => _openPeriodDialog(),
                        )
                        : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                          itemCount: fs.planningPeriods.length,
                          separatorBuilder:
                              (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final p = fs.planningPeriods[index];
                            final eventsInSeason = fs.events
                                .where((e) => fs.periodForEvent(e)?.id == p.id)
                                .length;
                            final cs = Theme.of(context).colorScheme;

                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                p.seasonLabel,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 16,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Wrap(
                                                spacing: 8,
                                                runSpacing: 4,
                                                crossAxisAlignment:
                                                    WrapCrossAlignment.center,
                                                children: [
                                                  Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        Icons.date_range,
                                                        size: 14,
                                                        color:
                                                            p.hasDateRange
                                                                ? cs.primary
                                                                : AppTheme
                                                                    .warningColor,
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        p.dateRangeLabel,
                                                        style: TextStyle(
                                                          fontSize: 12.5,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color:
                                                              p.hasDateRange
                                                                  ? cs.onSurfaceVariant
                                                                  : AppTheme
                                                                      .warningColor,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  Text(
                                                    '· $eventsInSeason ${eventsInSeason == 1 ? "Event" : "Events"}',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: cs.onSurfaceVariant,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Saison & Zeitraum bearbeiten',
                                          icon: const Icon(Icons.edit_outlined),
                                          onPressed:
                                              _busy
                                                  ? null
                                                  : () => _openPeriodDialog(
                                                    existing: p,
                                                  ),
                                        ),
                                        IconButton(
                                          tooltip: 'Saison löschen',
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            color: AppTheme.dangerColor,
                                          ),
                                          onPressed:
                                              _busy
                                                  ? null
                                                  : () => _deletePeriod(p),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    SegmentedButton<PlanningStage>(
                                      segments: const [
                                        ButtonSegment(
                                          value: PlanningStage.availability,
                                          label: Text('1: Verfügb.'),
                                        ),
                                        ButtonSegment(
                                          value: PlanningStage.application,
                                          label: Text('2: Bewerb.'),
                                        ),
                                        ButtonSegment(
                                          value: PlanningStage.production,
                                          label: Text('3: Prod.'),
                                        ),
                                      ],
                                      selected: {p.stage},
                                      onSelectionChanged:
                                          _busy
                                              ? null
                                              : (set) =>
                                                  _changeStage(p, set.first),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      switch (p.stage) {
                                        PlanningStage.availability =>
                                          'Team sieht geplante Events & Zeiträume und trägt Verfügbarkeit / Abwesenheit ein (keine Rollen- oder Teameinsicht). Bindende Admin-Zuweisungen bleiben aktiv.',
                                        PlanningStage.application =>
                                          'Team sieht offene Stellen und kann sich gezielt bewerben. Team-Besetzung ist nur bei eigenen Einsätzen sichtbar.',
                                        PlanningStage.production =>
                                          'Voller Funktionsumfang inkl. Platztausch. Team-Besetzung ist bei eigenen Einsätzen sichtbar.',
                                      },
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),

                    // TAB 2: Gesammelte Verfügbarkeiten & Blackouts
                    _loadingSubs
                        ? const Center(child: CircularProgressIndicator())
                        : _submissions.isEmpty
                        ? const EmptyStateView(
                          icon: Icons.event_available_outlined,
                          title: 'Noch keine Rückmeldungen',
                          subtitle:
                              'Verfügbarkeiten aus Stufe 1 und Abwesenheiten (Blackouts) deines Teams erscheinen hier automatisch.',
                        )
                        : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: _submissions.length,
                          separatorBuilder:
                              (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final s = _submissions[index];
                            final isAvail =
                                s.kind == AvailabilityKind.available;
                            final userName = resolveUser(s.userId);
                            final periodName =
                                s.planningPeriodId != null
                                    ? periodLabelById[s.planningPeriodId!]
                                    : null;
                            return Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: (isAvail
                                          ? AppTheme.successColor
                                          : AppTheme.dangerColor)
                                      .withValues(alpha: 0.15),
                                  child: Icon(
                                    isAvail
                                        ? Icons.event_available
                                        : Icons.event_busy,
                                    color:
                                        isAvail
                                            ? AppTheme.successColor
                                            : AppTheme.dangerColor,
                                  ),
                                ),
                                title: Text(
                                  '$userName · ${_fmt(s.startDate)} – ${_fmt(s.endDate)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  '${s.kind.label}'
                                  '${periodName != null ? " · $periodName" : ""}'
                                  '${s.notes.isNotEmpty ? "\n${s.notes}" : ""}',
                                ),
                              ),
                            );
                          },
                        ),

                    // TAB 3: Offene Tauschanfragen (Stufe 3)
                    pendingSwaps.isEmpty
                        ? const EmptyStateView(
                          icon: Icons.swap_horiz,
                          title: 'Keine offenen Tauschanfragen',
                          subtitle:
                              'Wenn Teammitglieder in Stufe 3 einen Einsatzplatz tauschen möchten, kannst du den Tausch hier freigeben.',
                        )
                        : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: pendingSwaps.length,
                          separatorBuilder:
                              (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = pendingSwaps[index];
                            final oldName =
                                item.tm.name.isNotEmpty
                                    ? item.tm.name
                                    : resolveUser(
                                      item.tm.userId,
                                      fallback: 'Aktuelles Mitglied',
                                    );
                            final newName =
                                (item.tm.swapRequestedByName ?? '')
                                        .trim()
                                        .isNotEmpty
                                    ? item.tm.swapRequestedByName!
                                    : resolveUser(
                                      item.tm.swapRequestedBy ?? '',
                                      fallback: 'Neues Mitglied',
                                    );
                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${item.event.displayName} (${_fmt(item.event.startTime)})',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Rolle: ${item.tm.roleLabel}\n$oldName  →  $newName',
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        FilledButton.icon(
                                          onPressed:
                                              _busy
                                                  ? null
                                                  : () => _approveSwap(
                                                    item.event,
                                                    item.tm,
                                                  ),
                                          icon: const Icon(
                                            Icons.check,
                                            size: 18,
                                          ),
                                          label: const Text(
                                            'Tausch bestätigen',
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        OutlinedButton.icon(
                                          onPressed:
                                              _busy
                                                  ? null
                                                  : () => _rejectSwap(
                                                    item.event,
                                                    item.tm,
                                                  ),
                                          icon: const Icon(
                                            Icons.close,
                                            size: 18,
                                          ),
                                          label: const Text('Ablehnen'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
