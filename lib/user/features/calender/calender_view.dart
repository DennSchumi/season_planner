import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/core/data/enums/event_status_enum.dart';
import 'package:season_planner/core/data/enums/event_user_status_enum.dart';
import 'package:season_planner/core/data/enums/membership_status_enum.dart';
import 'package:season_planner/core/data/models/event_model.dart';
import 'package:season_planner/core/data/models/planning_period_model.dart';
import 'package:season_planner/core/data/models/tandem_model.dart';
import 'package:season_planner/core/services/data_window.dart';
import 'package:season_planner/core/services/notification_service.dart';
import 'package:season_planner/core/services/planning_service.dart';
import 'package:season_planner/core/services/security_privacy_service.dart';
import 'package:season_planner/core/services/tandem_service.dart';
import 'package:season_planner/core/theme.dart';
import 'package:season_planner/core/widgets/calender_widget.dart';
import 'package:season_planner/core/widgets/ics_subscription_dialog.dart';
import 'package:season_planner/core/widgets/tandem_dialogs.dart';
import 'package:season_planner/core/widgets/ux_components.dart';
import 'package:season_planner/user/features/availability/my_availability_view.dart';
import 'package:season_planner/user/features/home/widgets/flight_school_selector_widget.dart';
import 'package:season_planner/user/features/home/widgets/your_events_widget.dart';
import 'package:season_planner/user/services/database_service.dart';
import '../../user_provider.dart';
import '../home/widgets/event_preview_sheet.dart';

class CalenderView extends StatefulWidget {
  final bool isLoading;
  final bool hasConnection;
  final DateTime? lastUpdated;

  const CalenderView({
    super.key,
    required this.isLoading,
    required this.hasConnection,
    required this.lastUpdated,
  });

  @override
  _CalenderView createState() => _CalenderView();
}

class _CalenderView extends State<CalenderView> {
  final _planningService = PlanningService();
  List<AvailabilitySubmission> _submissions = [];
  String? _loadedUserId;
  bool _loadingArchive = false;

  Future<void> _ensureArchiveForMonth(DateTime monthFirstDay) async {
    if (_loadingArchive) return;
    if (!DataWindow.isMonthOutsideDefaultWindow(monthFirstDay)) return;
    final userProvider = context.read<UserProvider>();
    final current = userProvider.user;
    if (current == null || userProvider.includeArchive) return;

    setState(() => _loadingArchive = true);
    try {
      userProvider.setIncludeArchive(true);
      final db = DatabaseService();
      final results = await Future.wait([
        db.refreshUserEventsOnly(current, includeArchive: true),
        db.refreshUserTandemOnly(current, includeArchive: true),
      ]);
      if (!mounted) return;
      final updated = current.copyWith(
        events: results[0].events,
        tandemDuties: results[1].tandemDuties,
        tandemDemands: results[1].tandemDemands,
        tandemPilotNamesById: results[1].tandemPilotNamesById,
        hasLoadedArchive: true,
      );
      userProvider.applyPartialUpdate(updated);
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
  void didUpdateWidget(covariant CalenderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lastUpdated != widget.lastUpdated) {
      _loadSubmissions();
    }
  }

  Future<void> _loadSubmissions() async {
    final user = context.read<UserProvider>().user;
    if (user == null || user.id.isEmpty) return;
    _loadedUserId = user.id;
    final list = await _planningService.listUserSubmissions(user.id);
    if (!mounted) return;
    setState(() => _submissions = list);
  }

  Future<void> _createAvailabilityForDay(
    DateTime date,
    AvailabilityKind kind,
  ) async {
    final user = context.read<UserProvider>().user;
    if (user == null) return;
    final activeSchools = user.flightSchools
        .where((s) => s.membershipStatus == MembershipStatusEnum.active)
        .toList();
    if (activeSchools.isEmpty) return;

    final saved = await showAvailabilityEntryDialog(
      context: context,
      userId: user.id,
      activeSchools: activeSchools,
      initialKind: kind,
      initialStartDate: date,
      allowKindToggle: true,
    );
    if (saved && mounted) {
      await _loadSubmissions();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              kind == AvailabilityKind.available
                  ? 'Verfügbarkeit gespeichert.'
                  : 'Abwesenheit gespeichert.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _deleteAvailability(AvailabilitySubmission item) async {
    final isAvail = item.kind == AvailabilityKind.available;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          isAvail ? 'Verfügbarkeit löschen?' : 'Abwesenheit löschen?',
        ),
        content: const Text(
          'Möchtest du diesen eingetragenen Zeitraum wirklich löschen?',
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
    await _planningService.deleteSubmission(item.id);
    if (mounted) {
      await _loadSubmissions();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Zeitraum gelöscht.')),
        );
      }
    }
  }

  Future<void> _reloadUserData() async {
    final updated = await DatabaseService().getUserInformation();
    if (updated != null && mounted) {
      context.read<UserProvider>().setUser(updated);
    }
  }

  Future<void> _requestTandemForDay(DateTime date) async {
    final user = context.read<UserProvider>().user;
    if (user == null) return;
    final eligibleSchools = user.flightSchools
        .where(
          (s) =>
              s.membershipStatus == MembershipStatusEnum.active &&
              s.tandemEnabled &&
              s.isTandemPilot,
        )
        .toList();
    if (eligibleSchools.isEmpty) return;

    final saved = await showPilotRequestTandemDialog(
      context: context,
      user: user,
      eligibleSchools: eligibleSchools,
      initialDate: date,
    );
    if (saved && mounted) {
      await _reloadUserData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tandem-Anfrage wurde an die Flugschule gesendet.'),
          ),
        );
      }
    }
  }

  Future<void> _decideTandemDuty(TandemDuty duty, bool approve) async {
    final user = context.read<UserProvider>().user;
    if (user == null) return;
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
        if (!mounted) return;
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
    if (!mounted) return;
    if (ok) {
      if (approve) {
        NotificationService().markKeyAsSeen('u_tandem_confirmed:${duty.id}');
      }
      await _reloadUserData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              approve ? 'Tandem-Einsatz zugesagt.' : 'Tandem-Anfrage abgelehnt.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _deleteTandemDuty(TandemDuty duty) async {
    final ok = await TandemService().deleteDuty(
      flightSchoolId: duty.flightSchoolId,
      dutyId: duty.id,
      summary: 'Anfrage zurückgezogen (${duty.dateRangeLabel})',
    );
    if (!mounted) return;
    if (ok) {
      await _reloadUserData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tandem-Anfrage zurückgezogen.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final user = userProvider.user;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (user.id.isNotEmpty && _loadedUserId != user.id) {
      _loadedUserId = user.id;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadSubmissions());
    }

    final selectedSchoolIds = userProvider.selectedFlightSchoolIds;
    final fsById = {for (final fs in user.flightSchools) fs.id: fs};
    final activeSchools = user.flightSchools
        .where((s) => s.membershipStatus == MembershipStatusEnum.active)
        .toList();
    final filteredActiveSchools = activeSchools
        .where((s) => selectedSchoolIds.contains(s.id))
        .toList();

    final stage1Periods = <PlanningPeriod>[
      for (final fs in filteredActiveSchools)
        if (!fs.isTandemOnly)
          ...fs.planningPeriods.where(
            (p) => p.stage == PlanningStage.availability && p.hasDateRange,
          ),
    ];

    String eventKey(Event e) =>
        (e.eventDocId != null && e.eventDocId!.isNotEmpty)
            ? e.eventDocId!
            : e.id;

    final now = DateTime.now();
    final scheduledEvents = user.events
        .where(
          (e) =>
              e.isOwnBindingAssignment && e.status != EventStatusEnum.canceled,
        )
        .toList();
    final scheduledKeys = scheduledEvents.map(eventKey).toSet();

    bool isBlockedBySchedule(Event candidate) {
      if (scheduledKeys.contains(eventKey(candidate))) return true;
      for (final s in scheduledEvents) {
        if (candidate.startTime.isBefore(s.endTime) &&
            candidate.endTime.isAfter(s.startTime)) {
          return true;
        }
      }
      return false;
    }

    int calendarPriority(Event e, int stage) {
      if (e.isOwnBindingAssignment) return 0;
      if (!e.isSwapOfferFromOther &&
          e.assignmentStatus == EventUserStatusEnum.pending_user) {
        return 1;
      }
      if (!e.isSwapOfferFromOther &&
          e.assignmentStatus == EventUserStatusEnum.pending_flight_school) {
        return 2;
      }
      if (e.isSwapOfferFromOther) return 3;
      if (e.assignmentStatus == EventUserStatusEnum.open && stage >= 2) {
        return 4;
      }
      return 5;
    }

    // Pro Event maximal 1 Kalender-Balken; parallele offene Stellen desselben
    // Events werden als `siblingOpportunities` an EventDetailView durchgereicht.
    final groupedByEvent = <String, List<Event>>{};
    for (final e in user.events) {
      if (!selectedSchoolIds.contains(e.flightSchoolId)) continue;
      final fs = fsById[e.flightSchoolId];
      final stage = fs?.effectiveStageFor(e) ?? e.planningStage;

      bool include = false;
      if (e.isOwnBindingAssignment) {
        include = true;
      } else if (!e.isSwapOfferFromOther &&
          (e.assignmentStatus == EventUserStatusEnum.pending_flight_school ||
              e.assignmentStatus == EventUserStatusEnum.pending_user)) {
        include = true;
      } else if (fs != null && fs.isTandemOnly) {
        // Reine Tandempiloten sehen keine fremden Schul-Events im Kalender
        include = false;
      } else if (fs != null && fs.isExtendedTeam) {
        // Erweitertes Team sieht nicht zugewiesene Events grau & ohne Details
        include = !e.isSwapOfferFromOther;
      } else if (stage == 1 && !e.isSwapOfferFromOther) {
        include = true;
      } else if (stage >= 2 &&
          !e.endTime.isBefore(now) &&
          e.status != EventStatusEnum.canceled &&
          fs != null &&
          fs.membershipStatus == MembershipStatusEnum.active &&
          !isBlockedBySchedule(e)) {
        final isOpenSlot =
            !e.isSwapOfferFromOther &&
            e.assignmentStatus == EventUserStatusEnum.open &&
            fs.hasRole(e.role);
        final isSwapSlot =
            e.isSwapOfferFromOther && stage == 3 && fs.hasRole(e.role);
        if (isOpenSlot || isSwapSlot) {
          include = true;
        }
      }

      if (!include) continue;
      groupedByEvent.putIfAbsent(eventKey(e), () => []).add(e);
    }

    final events = <Event>[];
    final siblingsByEventKey = <String, List<Event>>{};
    for (final entry in groupedByEvent.entries) {
      final list = entry.value;
      list.sort((a, b) {
        final stageA =
            fsById[a.flightSchoolId]?.effectiveStageFor(a) ?? a.planningStage;
        final stageB =
            fsById[b.flightSchoolId]?.effectiveStageFor(b) ?? b.planningStage;
        return calendarPriority(a, stageA).compareTo(
          calendarPriority(b, stageB),
        );
      });
      final primary = list.first;
      events.add(primary);
      // Nur für offene/anfragbare Events Geschwister-Stellen mitgeben
      if (!primary.isOwnBindingAssignment) {
        siblingsByEventKey[entry.key] = list;
      }
    }

    final tandemSchools = filteredActiveSchools
        .where((s) => s.tandemEnabled && s.isTandemPilot)
        .toList();
    final tandemSchoolIds = tandemSchools.map((s) => s.id).toSet();
    final visibleTandemDuties = user.tandemDuties
        .where((d) => tandemSchoolIds.contains(d.flightSchoolId))
        .toList();
    final visibleTandemDemands = user.tandemDemands
        .where((d) => tandemSchoolIds.contains(d.flightSchoolId))
        .toList();
    final visibleSubmissions = _submissions
        .where((s) => selectedSchoolIds.contains(s.flightSchoolId))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kalender'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Persönliches Kalender-Abo (ICS)',
            onPressed: () {
              showIcsSubscriptionDialog(
                context: context,
                title: 'Persönliches Kalender-Abo',
                subtitle:
                    'Automatisch aktueller Kalender-Feed für deine bestätigten Events.',
                calendarName: 'Season Planner – Meine Events',
                loadUrl: () => DatabaseService().getOrCreateUserIcsFeedUrl(),
                onRegenerateUrl: () => DatabaseService()
                    .getOrCreateUserIcsFeedUrl(forceRegenerate: true),
              );
            },
            icon: const Icon(Icons.rss_feed_outlined, size: 21),
          ),
          const AppBarActionDivider(),
          const AppModeSwitchChip(isAdminMode: false),
          ConnectionStatusAction(
            isLoading: widget.isLoading,
            hasConnection: widget.hasConnection,
            lastUpdated: widget.lastUpdated,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (user.flightSchools.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 2),
                child: FlightSchoolSelector(
                  flightSchools: user.flightSchools,
                  selectedIds: selectedSchoolIds,
                  onSelectionChanged: (selected) {
                    context
                        .read<UserProvider>()
                        .setSelectedFlightSchoolIds(selected);
                  },
                ),
              ),
            Expanded(
              child: EventsCalendar(
                events: events,
                flightSchoolById: (id) => fsById[id],
                redactStage1: true,
                stage1Periods: stage1Periods,
                availabilityEntries: visibleSubmissions,
                resolveUserName: user.resolveTandemPilotName,
                onVisibleMonthChanged: _ensureArchiveForMonth,
                onCreateAvailabilityForDay: activeSchools.isEmpty
                    ? null
                    : _createAvailabilityForDay,
                onDeleteAvailability: _deleteAvailability,
                showTandemSection: tandemSchools.isNotEmpty,
                tandemDuties: visibleTandemDuties,
                tandemDemands: visibleTandemDemands,
                isAdminTandemView: false,
                currentUserId: user.id,
                onPilotRequestTandem:
                    tandemSchools.isNotEmpty ? _requestTandemForDay : null,
                onDecideTandemDuty:
                    tandemSchools.isNotEmpty ? _decideTandemDuty : null,
                onDeleteTandemDuty:
                    tandemSchools.isNotEmpty ? _deleteTandemDuty : null,
                onOwnTandemDutyTap: tandemSchools.isEmpty
                    ? null
                    : (duty) {
                        final bundle = TandemDutyBundle(
                          flightSchoolId: duty.flightSchoolId,
                          userId: duty.userId,
                          startDate: duty.startDate,
                          endDate: duty.endDate,
                          isFullDay: duty.isFullDay,
                          duties: [duty],
                        );
                        showUserTandemPreviewSheet(
                          context,
                          bundle: bundle,
                          flightSchool: fsById[duty.flightSchoolId],
                        );
                      },
                onEventTap: (e) {
                  final siblings =
                      siblingsByEventKey[eventKey(e)] ?? const <Event>[];
                  showEventPreviewSheet(
                    context,
                    event: e,
                    siblingOpportunities: siblings,
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
