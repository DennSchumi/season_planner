import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/core/data/enums/membership_status_enum.dart';
import 'package:season_planner/core/data/models/planning_period_model.dart';
import 'package:season_planner/core/services/planning_service.dart';
import 'package:season_planner/core/theme.dart';
import 'package:season_planner/core/widgets/ux_components.dart';
import 'package:season_planner/user/data/models/flight_school_model_user_view.dart';
import 'package:season_planner/user/user_provider.dart';

/// Wiederverwendbarer Dialog zum Eintragen einer Verfügbarkeit oder Abwesenheit.
/// Wird sowohl in `MyAvailabilityView` als auch direkt beim Antippen eines Tages
/// im persönlichen Kalender verwendet (mit vorausgewähltem Startdatum).
Future<bool> showAvailabilityEntryDialog({
  required BuildContext context,
  required String userId,
  required List<FlightSchoolUserView> activeSchools,
  AvailabilityKind initialKind = AvailabilityKind.available,
  DateTime? initialStartDate,
  bool allowKindToggle = true,
}) async {
  if (activeSchools.isEmpty) return false;

  String fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  final startInit = dateOnly(initialStartDate ?? DateTime.now());
  AvailabilityKind kind = initialKind;

  // Standardmäßig alle aktiven Flugschulen vorauswählen (per Chips an-/abwählbar)
  final selectedSchoolIds = activeSchools.map((s) => s.id).toSet();

  DateTime startDate = startInit;
  DateTime endDate = startInit;
  final notesCtrl = TextEditingController();

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final cs = Theme.of(ctx).colorScheme;
        final isAvail = kind == AvailabilityKind.available;
        final isSingleDay =
            startDate.year == endDate.year &&
            startDate.month == endDate.month &&
            startDate.day == endDate.day;
        final daySpan = endDate.difference(startDate).inDays + 1;
        final dateSummary = isSingleDay
            ? 'Am ${fmt(startDate)}'
            : 'Von ${fmt(startDate)} bis ${fmt(endDate)}';

        return AlertDialog(
          title: Text(
            isAvail
                ? 'Verfügbarkeit eintragen'
                : 'Abwesenheit / Blackout eintragen',
          ),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (allowKindToggle) ...[
                    SegmentedButton<AvailabilityKind>(
                      segments: const [
                        ButtonSegment(
                          value: AvailabilityKind.available,
                          icon: Icon(Icons.event_available, size: 17),
                          label: Text('Verfügbar'),
                        ),
                        ButtonSegment(
                          value: AvailabilityKind.blackout,
                          icon: Icon(Icons.event_busy, size: 17),
                          label: Text('Abwesend'),
                        ),
                      ],
                      selected: {kind},
                      onSelectionChanged: (s) => setLocal(() => kind = s.first),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (activeSchools.length > 1) ...[
                    Text(
                      'Flugschulen',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: activeSchools.map((s) {
                        final selected = selectedSchoolIds.contains(s.id);
                        final label = s.displayShortName.trim().isNotEmpty
                            ? s.displayShortName.trim()
                            : s.displayName;
                        return FilterChip(
                          label: Text(label),
                          tooltip: s.displayName,
                          selected: selected,
                          onSelected: (v) {
                            setLocal(() {
                              if (v) {
                                selectedSchoolIds.add(s.id);
                              } else {
                                selectedSchoolIds.remove(s.id);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    if (selectedSchoolIds.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Bitte mindestens eine Flugschule auswählen.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppTheme.dangerColor,
                          ),
                        ),
                      ),
                    const SizedBox(height: 14),
                  ],
                  Text(
                    isSingleDay ? 'Datum' : 'Zeitraum ($daySpan Tage)',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Material(
                          color: cs.surfaceContainerHighest.withValues(
                            alpha: 0.55,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: ctx,
                                firstDate: DateTime(2024),
                                lastDate: DateTime(2035),
                                initialDate: startDate,
                                helpText: 'Datum auswählen',
                              );
                              if (picked != null) {
                                setLocal(() {
                                  startDate = dateOnly(picked);
                                  endDate = startDate;
                                });
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.calendar_today_outlined,
                                    size: 16,
                                    color: cs.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      dateSummary,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w700,
                                        color: cs.onSurface,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDateRangePicker(
                            context: ctx,
                            firstDate: DateTime(2024),
                            lastDate: DateTime(2035),
                            initialDateRange: DateTimeRange(
                              start: startDate,
                              end: endDate,
                            ),
                            helpText: 'Zeitraum auswählen',
                          );
                          if (picked != null) {
                            setLocal(() {
                              startDate = dateOnly(picked.start);
                              endDate = dateOnly(picked.end);
                            });
                          }
                        },
                        icon: const Icon(Icons.date_range_outlined, size: 17),
                        label: const Text('Zeitraum wählen'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Notiz (optional)',
                      hintText: isAvail
                          ? 'z. B. bevorzugt ab Nachmittag'
                          : 'z. B. Urlaub',
                    ),
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
              style: FilledButton.styleFrom(
                backgroundColor:
                    isAvail ? AppTheme.successColor : AppTheme.dangerColor,
              ),
              onPressed: selectedSchoolIds.isEmpty
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: const Text('Speichern'),
            ),
          ],
        );
      },
    ),
  );

  final notes = notesCtrl.text.trim();
  notesCtrl.dispose();

  if (ok != true || selectedSchoolIds.isEmpty) return false;

  final chosenSchools =
      activeSchools.where((s) => selectedSchoolIds.contains(s.id)).toList();

  final results = await Future.wait(
    chosenSchools.map((school) {
      final autoPeriod = kind == AvailabilityKind.available
          ? resolvePlanningPeriod(school.planningPeriods, startDate)
          : null;
      return PlanningService().createSubmission(
        userId: userId,
        flightSchoolId: school.id,
        planningPeriodId: autoPeriod?.id,
        kind: kind,
        startDate: startDate,
        endDate: endDate,
        notes: notes,
      );
    }),
  );

  return results.any((r) => r != null);
}

/// Kombinierte Ansicht für:
/// Tab 1: Saison-Verfügbarkeiten (Stufe 1 – positive Verfügbarkeiten)
/// Tab 2: Abwesenheiten / Blackout-Tage (Warnung bei Admin-Zuweisung)
class MyAvailabilityView extends StatefulWidget {
  final int initialTab;

  const MyAvailabilityView({super.key, this.initialTab = 0});

  @override
  State<MyAvailabilityView> createState() => _MyAvailabilityViewState();
}

class _MyAvailabilityViewState extends State<MyAvailabilityView> {
  final _service = PlanningService();
  List<AvailabilitySubmission> _submissions = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = context.read<UserProvider>().user;
    if (user == null) return;
    setState(() => _loading = true);
    final list = await _service.listUserSubmissions(user.id);
    if (!mounted) return;
    setState(() {
      _submissions = list;
      _loading = false;
    });
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  Future<void> _addEntry({
    required AvailabilityKind kind,
    required List<FlightSchoolUserView> activeSchools,
  }) async {
    final user = context.read<UserProvider>().user;
    if (user == null || activeSchools.isEmpty) return;

    setState(() => _busy = true);
    try {
      final saved = await showAvailabilityEntryDialog(
        context: context,
        userId: user.id,
        activeSchools: activeSchools,
        initialKind: kind,
        allowKindToggle: false,
      );
      if (saved && mounted) {
        await _load();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(AvailabilitySubmission item) async {
    final isAvail = item.kind == AvailabilityKind.available;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(
              isAvail ? 'Verfügbarkeit löschen?' : 'Abwesenheit löschen?',
            ),
            content: Text(
              'Möchtest du den Zeitraum ${_fmt(item.startDate)} – ${_fmt(item.endDate)} wirklich löschen?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.dangerColor,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Löschen'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    await _service.deleteSubmission(item.id);
    await _load();
    if (mounted) {
      setState(() => _busy = false);
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('Zeitraum gelöscht.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserProvider>().user;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final activeSchools =
        user.flightSchools
            .where((s) => s.membershipStatus == MembershipStatusEnum.active)
            .toList();
    final schoolById = {for (final s in activeSchools) s.id: s};
    final periodLabelById = <String, String>{};
    for (final s in activeSchools) {
      for (final p in s.planningPeriods) {
        periodLabelById[p.id] = p.seasonLabel;
      }
    }

    final availList =
        _submissions
            .where((s) => s.kind == AvailabilityKind.available)
            .toList();
    final blackoutList =
        _submissions.where((s) => s.kind == AvailabilityKind.blackout).toList();

    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTab,
      child: Builder(
        builder: (tabContext) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Verfügbarkeiten & Abwesenheiten'),
              bottom: const TabBar(
                tabs: [
                  Tab(
                    icon: Icon(Icons.event_available_outlined),
                    text: 'Verfügbarkeiten',
                  ),
                  Tab(
                    icon: Icon(Icons.event_busy_outlined),
                    text: 'Abwesenheiten',
                  ),
                ],
              ),
            ),
            floatingActionButton: FloatingActionButton.extended(
              onPressed:
                  _busy || activeSchools.isEmpty
                      ? null
                      : () {
                        final idx = DefaultTabController.of(tabContext).index;
                        _addEntry(
                          kind:
                              idx == 0
                                  ? AvailabilityKind.available
                                  : AvailabilityKind.blackout,
                          activeSchools: activeSchools,
                        );
                      },
              icon: const Icon(Icons.add),
              label: const Text('Zeitraum hinzufügen'),
            ),
            body: SafeArea(
              child: Column(
                children: [
                  if (_busy) const LinearProgressIndicator(minHeight: 2),
                  Expanded(
                    child:
                        _loading
                            ? const Center(child: CircularProgressIndicator())
                            : TabBarView(
                              children: [
                                _buildList(
                                  items: availList,
                                  emptyTitle: 'Keine Verfügbarkeiten eingetragen',
                                  emptyText:
                                      'Trage hier ein, an welchen Tagen du für Einsätze verfügbar bist.',
                                  schoolById: schoolById,
                                  periodLabelById: periodLabelById,
                                  color: AppTheme.successColor,
                                  icon: Icons.event_available,
                                  onAdd:
                                      _busy || activeSchools.isEmpty
                                          ? null
                                          : () => _addEntry(
                                            kind: AvailabilityKind.available,
                                            activeSchools: activeSchools,
                                          ),
                                ),
                                _buildList(
                                  items: blackoutList,
                                  emptyTitle: 'Keine Abwesenheiten hinterlegt',
                                  emptyText:
                                      'Hinterlege Urlaubs- oder Sperrzeiten. Admins erhalten bei der Team-Zuweisung automatisch eine Warnung.',
                                  schoolById: schoolById,
                                  periodLabelById: periodLabelById,
                                  color: AppTheme.dangerColor,
                                  icon: Icons.event_busy,
                                  onAdd:
                                      _busy || activeSchools.isEmpty
                                          ? null
                                          : () => _addEntry(
                                            kind: AvailabilityKind.blackout,
                                            activeSchools: activeSchools,
                                          ),
                                ),
                              ],
                            ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildList({
    required List<AvailabilitySubmission> items,
    required String emptyTitle,
    required String emptyText,
    required Map<String, FlightSchoolUserView> schoolById,
    required Map<String, String> periodLabelById,
    required Color color,
    required IconData icon,
    VoidCallback? onAdd,
  }) {
    if (items.isEmpty) {
      return EmptyStateView(
        icon: icon,
        title: emptyTitle,
        subtitle: emptyText,
        actionLabel: onAdd != null ? 'Zeitraum hinzufügen' : null,
        actionIcon: Icons.add,
        onAction: onAdd,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = items[index];
        final schoolName =
            schoolById[item.flightSchoolId]?.displayName ?? 'Flugschule';
        final periodLabel =
            item.planningPeriodId != null
                ? periodLabelById[item.planningPeriodId!]
                : null;

        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.15),
              child: Icon(icon, color: color),
            ),
            title: Text(
              item.startDate.year == item.endDate.year &&
                      item.startDate.month == item.endDate.month &&
                      item.startDate.day == item.endDate.day
                  ? 'Am ${_fmt(item.startDate)}'
                  : 'Von ${_fmt(item.startDate)} bis ${_fmt(item.endDate)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  periodLabel != null
                      ? '$schoolName · $periodLabel'
                      : schoolName,
                ),
                if (item.notes.isNotEmpty)
                  Text(
                    item.notes,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
            trailing: IconButton(
              tooltip: 'Eintrag löschen',
              icon: const Icon(
                Icons.delete_outline,
                color: AppTheme.dangerColor,
              ),
              onPressed: _busy ? null : () => _delete(item),
            ),
          ),
        );
      },
    );
  }
}
