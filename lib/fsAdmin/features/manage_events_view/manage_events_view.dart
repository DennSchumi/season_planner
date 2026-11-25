import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/core/data/enums/event_status_enum.dart';
import 'package:season_planner/core/data/enums/event_user_status_enum.dart';
import 'package:season_planner/core/data/models/event_model.dart';
import 'package:season_planner/core/data/models/planning_period_model.dart';
import 'package:season_planner/core/services/data_window.dart';
import 'package:season_planner/core/theme.dart';
import 'package:season_planner/core/widgets/user_avatar.dart';
import 'package:season_planner/core/widgets/ux_components.dart';
import 'package:season_planner/fsAdmin/features/manage_planning/manage_planning_periods_view.dart';
import 'package:season_planner/fsAdmin/features/widgets/event_upsert_view.dart';
import 'package:season_planner/fsAdmin/flight_school_provider.dart';
import 'package:season_planner/fsAdmin/services/flight_school_service.dart';
import '../../../user/services/database_service.dart';

class ManageEventsView extends StatefulWidget {
  final bool isLoading;
  final bool hasConnection;
  final DateTime? lastUpdated;

  const ManageEventsView({
    super.key,
    required this.isLoading,
    required this.hasConnection,
    required this.lastUpdated,
  });

  @override
  State<ManageEventsView> createState() => _ManageEventsViewState();
}

class _ManageEventsViewState extends State<ManageEventsView> {
  final _flightSchoolService = FlightSchoolService();
  final TextEditingController _searchCtrl = TextEditingController();

  String _search = "";
  EventStatusEnum? _statusFilter;
  String? _periodFilter;
  DateTimeRange? _dateRange;
  bool _showPastEvents = false;
  bool _filtersExpanded = false;
  bool _loadingArchive = false;

  Future<void> _loadArchive() async {
    if (_loadingArchive) return;
    final fsProvider = context.read<FlightSchoolProvider>();
    final current = fsProvider.flightSchool;
    if (current == null || current.hasLoadedArchive) return;

    setState(() => _loadingArchive = true);
    try {
      fsProvider.setIncludeArchive(true);
      final results = await Future.wait([
        _flightSchoolService.refreshEventsOnly(current, includeArchive: true),
        _flightSchoolService.refreshTandemOnly(current, includeArchive: true),
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
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  int get _activeFilterCount {
    int c = 0;
    if (_showPastEvents) c++;
    if (_periodFilter != null) c++;
    if (_statusFilter != null) c++;
    if (_dateRange != null) c++;
    return c;
  }

  void _resetFilters() {
    setState(() {
      _showPastEvents = false;
      _periodFilter = null;
      _statusFilter = null;
      _dateRange = null;
    });
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final initial = _dateRange ??
        DateTimeRange(
          start: DateTime(now.year, now.month, now.day),
          end: DateTime(now.year, now.month, now.day)
              .add(const Duration(days: 7)),
        );

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(2100, 12, 31),
      initialDateRange: initial,
    );

    if (!mounted) return;
    if (picked != null) {
      setState(() => _dateRange = picked);
      if (DataWindow.isOutsideDefaultWindow(picked.start) ||
          DataWindow.isOutsideDefaultWindow(picked.end)) {
        _loadArchive();
      }
    }
  }

  void _clearDateRange() => setState(() => _dateRange = null);

  bool _matchesSearch(Event e) {
    if (_search.trim().isEmpty) return true;
    final q = _search.toLowerCase();
    return e.displayName.toLowerCase().contains(q) ||
        e.identifier.toLowerCase().contains(q) ||
        e.location.toLowerCase().contains(q);
  }

  bool _matchesStatus(Event e) =>
      _statusFilter == null || e.status == _statusFilter;

  bool _matchesPeriod(Event e, List<PlanningPeriod> periods) {
    if (_periodFilter == null) return true;
    final resolved = resolvePlanningPeriod(
      periods,
      e.startTime,
      fallbackPeriodId: e.planningPeriodId,
    );
    return resolved?.id == _periodFilter;
  }

  bool _matchesDateRange(Event e) {
    if (_dateRange == null) return true;
    final start = DateTime(_dateRange!.start.year, _dateRange!.start.month,
        _dateRange!.start.day, 0, 0, 0);
    final end = DateTime(_dateRange!.end.year, _dateRange!.end.month,
        _dateRange!.end.day, 23, 59, 59);
    return !e.startTime.isBefore(start) && !e.startTime.isAfter(end);
  }

  bool _matchesTimeWindow(Event e) {
    if (_showPastEvents) return true;
    final now = DateTime.now();
    return !e.endTime.isBefore(now);
  }

  List<Event> _applyFilters(List<Event> input, List<PlanningPeriod> periods) {
    final filtered = input
        .where((e) =>
            _matchesTimeWindow(e) &&
            _matchesSearch(e) &&
            _matchesStatus(e) &&
            _matchesPeriod(e, periods) &&
            _matchesDateRange(e))
        .toList();
    filtered.sort((a, b) => a.startTime.compareTo(b.startTime));
    return filtered;
  }

  void _openCreateEvent({Event? duplicateFrom}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EventUpsertView(
          initialEvent: null,
          duplicateFromEvent: duplicateFrom,
          onSave: (event) async {
            await DatabaseService().createEventWithTeam(
              context: context,
              event: event,
            );
            if (!mounted) return;
            context.read<FlightSchoolProvider>().reloadFlightSchoolInBackground(
                  _flightSchoolService.getFlightSchool,
                );
          },
        ),
      ),
    );
  }

  Future<void> _confirmDeleteEvent(Event e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Event löschen?'),
        content: Text('Möchtest du „${e.displayName}“ wirklich löschen?'),
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
    if (ok != true || !mounted) return;

    final deleted = await DatabaseService().deleteEventWithTeam(
      context: context,
      event: e,
    );
    if (!mounted) return;
    if (deleted) {
      context.read<FlightSchoolProvider>().removeEventById(e.id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Event „${e.displayName}“ gelöscht.')),
      );
    }
  }

  void _openEditEvent(Event e) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EventUpsertView(
          initialEvent: e,
          onSave: (updated) async {
            await DatabaseService().updateEventWithTeam(
              context: context,
              event: updated,
            );
            if (!mounted) return;
            context.read<FlightSchoolProvider>().reloadFlightSchoolInBackground(
                  _flightSchoolService.getFlightSchool,
                );
          },
          onDelete: (toDelete) async {
            final ok = await DatabaseService().deleteEventWithTeam(
              context: context,
              event: toDelete,
            );
            if (ok && mounted) {
              context
                  .read<FlightSchoolProvider>()
                  .removeEventById(toDelete.id);
            }
            return ok;
          },
          onDuplicate: (source) {
            _openCreateEvent(duplicateFrom: source);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<FlightSchoolProvider>(context);
    final flightSchool = provider.flightSchool;

    if (flightSchool == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_periodFilter != null &&
        !flightSchool.planningPeriods.any((p) => p.id == _periodFilter)) {
      _periodFilter = null;
    }

    final allEvents = flightSchool.events;
    final events = _applyFilters(allEvents, flightSchool.planningPeriods);

    final openSwapCount = allEvents.fold<int>(
      0,
      (sum, ev) => sum + ev.team.where((t) => t.hasOpenSwapRequest).length,
    );

    // Relevante Planungsperioden für den Sichtbarkeits-/Stufen-Chip ermitteln (3.2)
    final visiblePeriods = _periodFilter != null
        ? flightSchool.planningPeriods
            .where((p) => p.id == _periodFilter)
            .toList()
        : flightSchool.planningPeriods;

    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Events verwalten"),
        automaticallyImplyLeading: false,
        actions: [
          const AdminFlightSchoolSwitcherChip(),
          const AppModeSwitchChip(isAdminMode: true),
          ConnectionStatusAction(
            isLoading: widget.isLoading,
            hasConnection: widget.hasConnection,
            lastUpdated: widget.lastUpdated,
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (openSwapCount > 0)
              SoftCard(
                margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppTheme.darkCard
                    : AppTheme.swapBg,
                border: Border.all(
                  color: AppTheme.swapColor.withValues(alpha: 0.25),
                ),
                child: Row(
                  children: [
                    const TintedIconBadge(
                      icon: Icons.swap_horiz_rounded,
                      iconColor: AppTheme.swapColor,
                      backgroundColor: Colors.white,
                      size: 38,
                      iconSize: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '$openSwapCount offene Tauschanfrage${openSwapCount == 1 ? "" : "n"}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.swapColor,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                const ManagePlanningPeriodsView(initialTab: 2),
                          ),
                        );
                      },
                      child: const Text('Prüfen'),
                    ),
                  ],
                ),
              ),

            // Planungsstufen-Status-Chips mit direktem Link zur Stufen-Verwaltung (3.2)
            if (visiblePeriods.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: visiblePeriods.map((p) {
                        final color = switch (p.stage) {
                          PlanningStage.availability => AppTheme.stage1Color,
                          PlanningStage.application => AppTheme.infoColor,
                          PlanningStage.production => AppTheme.successColor,
                        };
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ActionChip(
                            avatar: Icon(
                              Icons.layers_outlined,
                              size: 16,
                              color: color,
                            ),
                            label: Text(
                              '${p.seasonLabel}${p.hasDateRange ? ' (${p.dateRangeLabel})' : ''} – ${p.stage.shortLabel}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: color,
                              ),
                            ),
                            backgroundColor: color.withValues(alpha: 0.10),
                            side: BorderSide(
                              color: color.withValues(alpha: 0.35),
                            ),
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Planungsstufe verwalten',
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const ManagePlanningPeriodsView(),
                                ),
                              );
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),

            // Kompakte Suchzeile + ausklappbarer Filter-Button (5.3)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          decoration: InputDecoration(
                            hintText: "Suchen (Name / Kennung / Ort)",
                            prefixIcon: const Icon(Icons.search),
                            isDense: true,
                            suffixIcon: _search.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.clear),
                                    tooltip: 'Suche leeren',
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      setState(() => _search = "");
                                    },
                                  ),
                          ),
                          onChanged: (v) => setState(() => _search = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Badge(
                        isLabelVisible: _activeFilterCount > 0,
                        label: Text('$_activeFilterCount'),
                        child: IconButton.filledTonal(
                          tooltip: _filtersExpanded
                              ? 'Filter ausblenden'
                              : 'Filter anzeigen',
                          icon: Icon(
                            _filtersExpanded
                                ? Icons.filter_list_off
                                : Icons.tune,
                          ),
                          onPressed: () => setState(
                            () => _filtersExpanded = !_filtersExpanded,
                          ),
                        ),
                      ),
                    ],
                  ),
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 200),
                    crossFadeState: _filtersExpanded
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    firstChild: const SizedBox.shrink(),
                    secondChild: Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Material(
                        color: cs.surfaceContainerHighest
                            .withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: cs.outlineVariant),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Eventstatus-Filter-Pills (im ausklappbaren Filterbereich)
                              SizedBox(
                                height: 36,
                                child: ListView(
                                  scrollDirection: Axis.horizontal,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: ChoiceChip(
                                        label: const Text('Alle'),
                                        selected: _statusFilter == null,
                                        showCheckmark: false,
                                        onSelected: (_) => setState(
                                          () => _statusFilter = null,
                                        ),
                                      ),
                                    ),
                                    ...EventStatusEnum.values.map(
                                      (st) => Padding(
                                        padding:
                                            const EdgeInsets.only(right: 6),
                                        child: ChoiceChip(
                                          label: Text(st.label),
                                          selected: _statusFilter == st,
                                          showCheckmark: false,
                                          onSelected: (_) => setState(
                                            () => _statusFilter =
                                                _statusFilter == st ? null : st,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: CheckboxListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      title: const Text("Vergangene anzeigen"),
                                      value: _showPastEvents,
                                      onChanged: (v) => setState(
                                        () => _showPastEvents = v ?? false,
                                      ),
                                      controlAffinity:
                                          ListTileControlAffinity.leading,
                                    ),
                                  ),
                                  if (flightSchool.planningPeriods.isNotEmpty)
                                    Expanded(
                                      child: DropdownButtonFormField<String?>(
                                        initialValue: _periodFilter,
                                        decoration: const InputDecoration(
                                          labelText: "Saison",
                                          isDense: true,
                                        ),
                                        items: [
                                          const DropdownMenuItem<String?>(
                                            value: null,
                                            child: Text("Alle Saisons"),
                                          ),
                                          ...flightSchool.planningPeriods.map(
                                            (p) => DropdownMenuItem<String?>(
                                              value: p.id,
                                              child: Text(
                                                '${p.seasonLabel} (St. ${p.stage.value})',
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ),
                                        ],
                                        onChanged: (v) =>
                                            setState(() => _periodFilter = v),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      icon: const Icon(
                                        Icons.date_range,
                                        size: 18,
                                      ),
                                      label: Text(
                                        _dateRange == null
                                            ? "Zeitraum wählen"
                                            : "${_formatDate(_dateRange!.start)} – ${_formatDate(_dateRange!.end)}",
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      onPressed: _pickDateRange,
                                    ),
                                  ),
                                  if (_dateRange != null)
                                    IconButton(
                                      tooltip: "Zeitraum zurücksetzen",
                                      onPressed: _clearDateRange,
                                      icon: const Icon(Icons.close),
                                    ),
                                ],
                              ),
                              if (_activeFilterCount > 0) ...[
                                const SizedBox(height: 6),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: _resetFilters,
                                    icon: const Icon(Icons.refresh, size: 16),
                                    label: const Text('Alle Filter zurücksetzen'),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (_loadingArchive)
              const LinearProgressIndicator(minHeight: 2),
            if (_showPastEvents &&
                !flightSchool.hasLoadedArchive &&
                !_loadingArchive)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: Row(
                  children: [
                    Icon(
                      Icons.history_rounded,
                      size: 15,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Standardmäßig werden die letzten 3 Monate angezeigt.',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                      ),
                      onPressed: _loadArchive,
                      icon: const Icon(Icons.unarchive_outlined, size: 16),
                      label: const Text('Archiv laden'),
                    ),
                  ],
                ),
              ),

            Expanded(
              child: events.isEmpty
                  ? EmptyStateView(
                      icon: Icons.event_outlined,
                      title: allEvents.isEmpty
                          ? 'Noch keine Events angelegt'
                          : 'Keine passenden Events gefunden',
                      subtitle: allEvents.isEmpty
                          ? 'Erstelle dein erstes Event für ${flightSchool.displayName} und besetze die Einsatzrollen.'
                          : 'Passe deine Suchbegriffe oder aktiven Filter an.',
                      actionLabel: allEvents.isEmpty
                          ? 'Erstes Event anlegen'
                          : (_activeFilterCount > 0 || _search.isNotEmpty
                              ? 'Filter zurücksetzen'
                              : null),
                      actionIcon: allEvents.isEmpty ? Icons.add : Icons.refresh,
                      onAction: allEvents.isEmpty
                          ? () => _openCreateEvent()
                          : () {
                              _searchCtrl.clear();
                              setState(() => _search = '');
                              _resetFilters();
                            },
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 148),
                      itemCount: events.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final e = events[index];
                        final hasSwap =
                            e.team.any((t) => t.hasOpenSwapRequest);
                        final isCanceled = e.status == EventStatusEnum.canceled;

                        return CanceledEventDecorator(
                          isCanceled: isCanceled,
                          borderRadius: BorderRadius.circular(20),
                          child: SoftCard(
                            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                            onTap: () => _openEditEvent(e),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: DateBadgeBox(
                                    date: e.startTime,
                                    accentColor:
                                        eventStatusColor(e.status.name),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              e.displayName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 15,
                                                decoration: isCanceled
                                                    ? TextDecoration.lineThrough
                                                    : null,
                                              ),
                                            ),
                                          ),
                                          if (_buildStaffingCounter(e)
                                              case final counter?) ...[
                                            const SizedBox(width: 6),
                                            counter,
                                          ],
                                        ],
                                      ),
                                    const SizedBox(height: 3),
                                    Text(
                                      "${e.identifier.isNotEmpty ? '${e.identifier} · ' : ''}"
                                      "${_formatDateTime(e.startTime)} – ${_formatDateTime(e.endTime)}",
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      "${flightSchool.periodForEvent(e)?.seasonLabel ?? 'Standard'} (Stufe ${flightSchool.effectiveStageFor(e)})"
                                      "${e.location.isNotEmpty ? ' · ${e.location}' : ''}",
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                    if (e.team.isNotEmpty || hasSwap) ...[
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          ...e.team.take(6).map((tm) {
                                            final member = tm.isSlot
                                                ? null
                                                : flightSchool
                                                    .findMemberByAnyId(
                                                        tm.userId);
                                            final avatarUrl =
                                                tm.avatarUrl.isNotEmpty
                                                    ? tm.avatarUrl
                                                    : (member?.avatarUrl ?? '');
                                            final displayName = tm.isSlot
                                                ? 'Offene Stelle'
                                                : (tm.name.isNotEmpty
                                                    ? tm.name
                                                    : (member?.displayName ??
                                                        'Teammitglied'));
                                            return Tooltip(
                                              message:
                                                  '$displayName · ${tm.roleLabel}',
                                              child: UserAvatar(
                                                avatarUrl: avatarUrl,
                                                name: tm.isSlot
                                                    ? ''
                                                    : displayName,
                                                radius: 12,
                                                isOpenSlot: tm.isSlot,
                                              ),
                                            );
                                          }),
                                          if (e.team.length > 6)
                                            Text(
                                              '+${e.team.length - 6}',
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w700,
                                                color: cs.onSurfaceVariant,
                                              ),
                                            ),
                                          if (hasSwap)
                                            const StatusPill(
                                              icon: Icons.swap_horiz_rounded,
                                              label: 'Tausch',
                                              foreground: AppTheme.swapColor,
                                              background: AppTheme.swapBg,
                                              fontSize: 11,
                                            ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              PopupMenuButton<String>(
                                tooltip: 'Event-Aktionen',
                                onSelected: (v) {
                                  if (v == 'edit') _openEditEvent(e);
                                  if (v == 'duplicate') {
                                    _openCreateEvent(duplicateFrom: e);
                                  }
                                  if (v == 'delete') _confirmDeleteEvent(e);
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit_outlined, size: 20),
                                        SizedBox(width: 12),
                                        Text('Bearbeiten'),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'duplicate',
                                    child: Row(
                                      children: [
                                        Icon(Icons.copy_outlined, size: 20),
                                        SizedBox(width: 12),
                                        Text('Als Kopie neu anlegen'),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.delete_outline,
                                          size: 20,
                                          color: AppTheme.dangerColor,
                                        ),
                                        SizedBox(width: 12),
                                        Text(
                                          'Löschen',
                                          style: TextStyle(
                                            color: AppTheme.dangerColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
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
      floatingActionButton: AdaptiveFloatingActionButton(
        tooltip: "Neues Event",
        onPressed: () => _openCreateEvent(),
        icon: Icons.add,
        label: "Neues Event",
      ),
    );
  }

  Widget? _buildStaffingCounter(Event e) {
    if (e.team.isEmpty) return null;
    final openCount = e.team
        .where((t) => t.isSlot || t.statusEnum == EventUserStatusEnum.open)
        .length;
    final staffed = e.team.length - openCount;
    return StatusPill(
      label: '$staffed/${e.team.length} besetzt',
      foreground:
          openCount == 0 ? AppTheme.successColor : AppTheme.warningColor,
      background: openCount == 0 ? AppTheme.successBg : AppTheme.warningBg,
      fontSize: 11,
    );
  }

  String _formatDate(DateTime d) =>
      "${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}";

  String _formatDateTime(DateTime d) =>
      "${_formatDate(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}";
}
