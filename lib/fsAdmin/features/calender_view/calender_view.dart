import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/core/data/models/event_model.dart';
import 'package:season_planner/core/data/models/planning_period_model.dart';
import 'package:season_planner/core/data/models/tandem_model.dart';
import 'package:season_planner/core/services/data_window.dart';
import 'package:season_planner/core/services/planning_service.dart';
import 'package:season_planner/core/services/security_privacy_service.dart';
import 'package:season_planner/core/services/tandem_service.dart';
import 'package:season_planner/core/widgets/calender_widget.dart';
import 'package:season_planner/core/widgets/ics_subscription_dialog.dart';
import 'package:season_planner/core/widgets/tandem_dialogs.dart';
import 'package:season_planner/core/widgets/ux_components.dart';
import 'package:season_planner/fsAdmin/features/manage_tandem/manage_tandem_view.dart';
import 'package:season_planner/fsAdmin/features/widgets/event_upsert_view.dart';
import 'package:season_planner/fsAdmin/flight_school_provider.dart';
import 'package:season_planner/fsAdmin/services/flight_school_service.dart';
import 'package:season_planner/user/services/database_service.dart';

class CalenderViewFlightSchool extends StatefulWidget {
  final bool isLoading;
  final bool hasConnection;
  final DateTime? lastUpdated;

  const CalenderViewFlightSchool({
    super.key,
    this.isLoading = false,
    this.hasConnection = true,
    this.lastUpdated,
  });

  @override
  _CalenderViewFlightSchool createState() => _CalenderViewFlightSchool();
}

class _CalenderViewFlightSchool extends State<CalenderViewFlightSchool> {
  final _planningService = PlanningService();
  DateTime? _selectedDay;
  List<AvailabilitySubmission> _schoolSubmissions = [];
  String? _loadedSchoolId;
  bool _loadingArchive = false;

  Future<void> _ensureArchiveForMonth(DateTime monthFirstDay) async {
    if (_loadingArchive) return;
    if (!DataWindow.isMonthOutsideDefaultWindow(monthFirstDay)) return;
    final fsProvider = context.read<FlightSchoolProvider>();
    final current = fsProvider.flightSchool;
    if (current == null || fsProvider.includeArchive) return;

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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSubmissions());
  }

  @override
  void didUpdateWidget(covariant CalenderViewFlightSchool oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lastUpdated != widget.lastUpdated) {
      _loadSubmissions();
    }
  }

  Future<void> _loadSubmissions() async {
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null || fs.id.isEmpty) return;
    _loadedSchoolId = fs.id;
    final list = await _planningService.listSchoolSubmissions(fs.id);
    if (!mounted) return;
    setState(() => _schoolSubmissions = list);
  }

  void _openCreateEvent({DateTime? initialDate, Event? duplicateFrom}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EventUpsertView(
          initialEvent: null,
          initialDate: initialDate,
          duplicateFromEvent: duplicateFrom,
          onSave: (event) async {
            await DatabaseService().createEventWithTeam(
              context: context,
              event: event,
            );
            if (!mounted) return;
            context.read<FlightSchoolProvider>().reloadFlightSchoolInBackground(
                  FlightSchoolService().getFlightSchool,
                );
          },
        ),
      ),
    );
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
                  FlightSchoolService().getFlightSchool,
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

  Future<void> _openTandemDemandSettings(DateTime _) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ManageTandemView()),
    );
    if (!mounted) return;
    context.read<FlightSchoolProvider>().reloadFlightSchoolInBackground(
          FlightSchoolService().getFlightSchool,
        );
  }

  Future<void> _assignTandemForDay(DateTime date) async {
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null || !fs.tandemEnabled) return;
    final saved = await showAdminAssignTandemDialog(
      context: context,
      fs: fs,
      initialDate: date,
      teamAvailabilities: _schoolSubmissions,
    );
    if (saved && mounted) {
      context.read<FlightSchoolProvider>().reloadFlightSchoolInBackground(
            FlightSchoolService().getFlightSchool,
          );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tandem-Einteilung gespeichert.')),
      );
    }
  }

  Future<void> _decideTandemDuty(TandemDuty duty, bool approve) async {
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null) return;
    final pilotName = fs.resolveMemberName(duty.userId);
    final isCancelReq = duty.status == TandemDutyStatus.cancellationRequested;
    if (!isCancelReq && approve) {
      final member = fs.findMemberByAnyId(duty.userId);
      final localConflict = TandemService.findScheduleConflict(
        userId: member?.id ?? duty.userId,
        userRowId: member?.userRowId,
        startDate: duty.startDate,
        endDate: duty.endDate,
        isFullDay: duty.isFullDay,
        events: fs.events,
        tandemDuties: fs.tandemDuties,
        ignoreDutyId: duty.id,
      );
      final crossMap = await SecurityPrivacyService().checkCrossSchoolConflicts(
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
              '$pilotName ist im Zeitraum ${duty.dateRangeLabel} bereits anderweitig verplant. Möchtest du die Tandem-Anfrage trotzdem freigeben?',
          conflicts: conflicts,
          confirmLabel: 'Trotzdem freigeben',
        );
        if (!confirmed || !mounted) return;
      }
    }
    final nextStatus = isCancelReq
        ? (approve ? TandemDutyStatus.declined : TandemDutyStatus.confirmed)
        : (approve ? TandemDutyStatus.confirmed : TandemDutyStatus.declined);
    final ok = await TandemService().updateDutyStatus(
      flightSchoolId: fs.id,
      dutyId: duty.id,
      newStatus: nextStatus,
      summary: '$pilotName (${duty.dateRangeLabel})',
    );
    if (!mounted) return;
    if (ok) {
      context.read<FlightSchoolProvider>().reloadFlightSchoolInBackground(
            FlightSchoolService().getFlightSchool,
          );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isCancelReq
                ? (approve
                    ? 'Tandem-Absage von $pilotName bestätigt.'
                    : 'Absage-Anfrage von $pilotName abgelehnt – Einsatz bleibt aktiv.')
                : (approve
                    ? 'Tandem-Anfrage von $pilotName freigegeben.'
                    : 'Tandem-Anfrage von $pilotName abgelehnt.'),
          ),
        ),
      );
    }
  }

  Future<void> _deleteTandemDuty(TandemDuty duty) async {
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null) return;
    final pilotName = fs.resolveMemberName(duty.userId);
    final ok = await TandemService().deleteDuty(
      flightSchoolId: fs.id,
      dutyId: duty.id,
      summary: '$pilotName (${duty.dateRangeLabel})',
    );
    if (!mounted) return;
    if (ok) {
      context.read<FlightSchoolProvider>().reloadFlightSchoolInBackground(
            FlightSchoolService().getFlightSchool,
          );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tandem-Einteilung entfernt.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final fs = context.watch<FlightSchoolProvider>().flightSchool;
    if (fs == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (fs.id.isNotEmpty && _loadedSchoolId != fs.id) {
      _loadedSchoolId = fs.id;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadSubmissions());
    }

    final stage1Periods = fs.planningPeriods
        .where((p) => p.stage == PlanningStage.availability && p.hasDateRange)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Kalender"),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Flugschul-Kalender-Abo (ICS)',
            onPressed: () {
              showIcsSubscriptionDialog(
                context: context,
                title: 'Flugschul-Kalender-Abo',
                subtitle:
                    'Automatisch aktueller Kalender-Feed aller Events von ${fs.displayName}.',
                calendarName:
                    'Season Planner – ${fs.displayShortName.isNotEmpty ? fs.displayShortName : fs.displayName}',
                loadUrl: () =>
                    FlightSchoolService().getOrCreateSchoolIcsFeedUrl(fs.id),
                onRegenerateUrl: () => FlightSchoolService()
                    .getOrCreateSchoolIcsFeedUrl(fs.id, forceRegenerate: true),
              );
            },
            icon: const Icon(Icons.rss_feed_outlined, size: 21),
          ),
          const AppBarActionDivider(),
          const AdminFlightSchoolSwitcherChip(),
          const AppModeSwitchChip(isAdminMode: true),
          ConnectionStatusAction(
            isLoading: widget.isLoading,
            hasConnection: widget.hasConnection,
            lastUpdated: widget.lastUpdated,
          ),
        ],
      ),
      floatingActionButton: AdaptiveFloatingActionButton(
        tooltip: 'Neues Event anlegen',
        onPressed: () => _openCreateEvent(initialDate: _selectedDay),
        icon: Icons.add,
        label: 'Neues Event',
      ),
      body: SafeArea(
        child: EventsCalendar(
          events: fs.events,
          flightSchoolById: (_) => fs,
          showFlightSchool: false,
          stage1Periods: stage1Periods,
          availabilityEntries: _schoolSubmissions,
          isAdminAvailabilityView: true,
          resolveUserName: (uid) => fs.resolveMemberName(uid),
          onEventTap: _openEditEvent,
          onCreateEventForDay: (date) => _openCreateEvent(initialDate: date),
          onSelectedDayChanged: (day) => _selectedDay = day,
          onVisibleMonthChanged: _ensureArchiveForMonth,
          showTandemSection: fs.tandemEnabled,
          tandemDuties: fs.tandemDuties,
          tandemDemands: fs.tandemDemands,
          isAdminTandemView: true,
          onAdminAssignTandem: fs.tandemEnabled ? _assignTandemForDay : null,
          onManageTandemDemand:
              fs.tandemEnabled ? _openTandemDemandSettings : null,
          onDecideTandemDuty: fs.tandemEnabled ? _decideTandemDuty : null,
          onDeleteTandemDuty: fs.tandemEnabled ? _deleteTandemDuty : null,
        ),
      ),
    );
  }
}
