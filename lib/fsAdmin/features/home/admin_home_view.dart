import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/core/data/enums/event_role_enum.dart';
import 'package:season_planner/core/data/enums/event_status_enum.dart';
import 'package:season_planner/core/data/enums/event_user_status_enum.dart';
import 'package:season_planner/core/data/models/event_model.dart';
import 'package:season_planner/core/data/models/qualification_model.dart';
import 'package:season_planner/core/data/models/role_document_model.dart';
import 'package:season_planner/core/data/models/tandem_model.dart';
import 'package:season_planner/core/data/models/team_role_model.dart';
import 'package:season_planner/core/data/models/timesheet_model.dart';
import 'package:season_planner/core/services/notification_service.dart';
import 'package:season_planner/core/services/planning_service.dart';
import 'package:season_planner/core/services/qualification_service.dart';
import 'package:season_planner/core/services/role_document_service.dart';
import 'package:season_planner/core/services/security_privacy_service.dart';
import 'package:season_planner/core/services/tandem_service.dart';
import 'package:season_planner/core/services/timesheet_service.dart';
import 'package:season_planner/core/theme.dart';
import 'package:season_planner/core/widgets/user_avatar.dart';
import 'package:season_planner/core/widgets/ux_components.dart';
import 'package:season_planner/fsAdmin/data/models/flight_school_model_flight_school_view.dart';
import 'package:season_planner/fsAdmin/data/models/user_summary_flight_school_view.dart';
import 'package:season_planner/fsAdmin/features/manage_planning/manage_planning_periods_view.dart';
import 'package:season_planner/fsAdmin/features/manage_qualifications/manage_qualifications_view.dart';
import 'package:season_planner/fsAdmin/features/manage_qualifications/review_qualifications_view.dart';
import 'package:season_planner/fsAdmin/features/manage_tandem/manage_tandem_view.dart';
import 'package:season_planner/fsAdmin/features/manage_timesheets/manage_timesheets_view.dart';
import 'package:season_planner/fsAdmin/features/widgets/admin_event_preview_sheet.dart';
import 'package:season_planner/fsAdmin/features/widgets/event_upsert_view.dart';
import 'package:season_planner/fsAdmin/flight_school_provider.dart';
import 'package:season_planner/fsAdmin/services/flight_school_service.dart';
import 'package:season_planner/user/services/database_service.dart';
import 'package:season_planner/user/user_provider.dart';

enum _AdminTodoCategory {
  all,
  joinRequests,
  applications,
  tandemRequests,
  documents,
  swaps,
  changeRequests,
  deniedAssignments,
  qualificationRequests,
  unfilledEvents,
  unsignedChecklists,
  missingTimesheets,
}

class AdminHomeView extends StatefulWidget {
  final bool isLoading;
  final bool hasConnection;
  final DateTime? lastUpdated;
  final ValueChanged<int>? onSelectTab;
  final ValueChanged<int>? onExtraTodoCountChanged;

  const AdminHomeView({
    super.key,
    required this.isLoading,
    required this.hasConnection,
    required this.lastUpdated,
    this.onSelectTab,
    this.onExtraTodoCountChanged,
  });

  @override
  State<AdminHomeView> createState() => _AdminHomeViewState();
}

class _AdminHomeViewState extends State<AdminHomeView> {
  final _fsService = FlightSchoolService();
  final _qualService = QualificationService();
  final _planService = PlanningService();
  final _docService = RoleDocumentService();
  final _timesheetService = TimesheetService();

  bool _loadingAsync = true;
  bool _busy = false;
  _AdminTodoCategory _activeCategory = _AdminTodoCategory.all;

  List<QualificationApproval> _pendingApprovals = [];
  List<ChecklistCompletion> _schoolCompletions = [];
  List<EventTimesheet> _schoolTimesheets = [];
  String? _loadedSchoolId;
  int _lastEventCount = -1;
  String? _autoCompleteCheckKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAsyncTodos();
    });
  }

  @override
  void didUpdateWidget(covariant AdminHomeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lastUpdated != widget.lastUpdated) {
      _loadAsyncTodos();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs != null &&
        (fs.id != _loadedSchoolId || fs.events.length != _lastEventCount)) {
      _loadedSchoolId = fs.id;
      _lastEventCount = fs.events.length;
      _loadAsyncTodos();
    }
  }

  Future<void> _loadAsyncTodos() async {
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null || fs.id.isEmpty) return;

    try {
      final results = await Future.wait([
        _qualService.listSchoolApprovals(
          fs.id,
          status: ApprovalStatusEnum.submitted,
        ),
        _docService.listCompletionsForSchool(fs.id),
        if (fs.timesheetEnabled)
          _timesheetService.listTimesheetsForSchool(fs.id)
        else
          Future<List<EventTimesheet>>.value(const []),
      ]);
      if (!mounted) return;
      final approvals = results[0] as List<QualificationApproval>;
      final completions = results[1] as List<ChecklistCompletion>;
      final timesheets = results[2] as List<EventTimesheet>;

      setState(() {
        _pendingApprovals = approvals;
        _schoolCompletions = completions;
        _schoolTimesheets = timesheets;
        _loadingAsync = false;
      });
      _notifyExtraCount(fs, approvals, completions, timesheets);
      NotificationService().evaluateAdminSnapshot(
        fs: fs,
        pendingDocsCount: approvals.length,
        context: context,
      );

      // Prüfe im Hintergrund, ob beendete Events nun automatisch auf „Abgeschlossen“ wechseln können
      final now = DateTime.now();
      final hasEndedOpenEvents = fs.events.any(
        (ev) =>
            ev.status != EventStatusEnum.done &&
            ev.status != EventStatusEnum.canceled &&
            ev.endTime.isBefore(now),
      );
      final checkKey = '${fs.id}_${fs.events.length}_${completions.length}_${timesheets.length}';
      if (hasEndedOpenEvents && _autoCompleteCheckKey != checkKey) {
        _autoCompleteCheckKey = checkKey;
        SecurityPrivacyService()
            .checkEventCompletion(flightSchoolId: fs.id)
            .then((completedIds) {
          if (completedIds.isNotEmpty && mounted) {
            context.read<FlightSchoolProvider>().reloadFlightSchool(
                  _fsService.getFlightSchool,
                );
          }
        });
      }
    } catch (e) {
      debugPrint('AdminHomeView _loadAsyncTodos error: $e');
      if (mounted) setState(() => _loadingAsync = false);
    }
  }

  void _notifyExtraCount(
    FlightSchoolModelFlightSchoolView fs,
    List<QualificationApproval> approvals,
    List<ChecklistCompletion> completions,
    List<EventTimesheet> timesheets,
  ) {
    final unsigned = _collectUnsignedChecklists(fs, completions).length;
    final missingSheets = _collectMissingTimesheets(fs, timesheets).length;
    widget.onExtraTodoCountChanged?.call(
      approvals.length + unsigned + missingSheets,
    );
  }

  Future<void> _refreshAll() async {
    await context.read<FlightSchoolProvider>().reloadFlightSchool(
          _fsService.getFlightSchool,
        );
    if (!mounted) return;
    await _loadAsyncTodos();
  }

  // ==================== DATEN-AGGREGATION ====================

  TeamRole? _findTeamRole(
    FlightSchoolModelFlightSchoolView fs,
    String roleName,
  ) {
    final lower = roleName.trim().toLowerCase();
    final labelLower = EventRoleEnum.displayLabel(roleName).toLowerCase();
    for (final r in fs.teamRoles) {
      final rn = r.name.trim().toLowerCase();
      if (rn == lower || rn == labelLower) return r;
    }
    return null;
  }

  List<({Event event, TeamMember tm})> _collectApplications(
    FlightSchoolModelFlightSchoolView fs,
  ) {
    final now = DateTime.now();
    final list = <({Event event, TeamMember tm})>[];
    for (final ev in fs.events) {
      if (ev.status == EventStatusEnum.canceled || ev.endTime.isBefore(now)) {
        continue;
      }
      for (final tm in ev.team) {
        if (!tm.isSlot &&
            tm.statusEnum == EventUserStatusEnum.pending_flight_school) {
          list.add((event: ev, tm: tm));
        }
      }
    }
    list.sort((a, b) => a.event.startTime.compareTo(b.event.startTime));
    return list;
  }

  List<({Event event, TeamMember tm})> _collectChangeRequests(
    FlightSchoolModelFlightSchoolView fs,
  ) {
    final now = DateTime.now();
    final list = <({Event event, TeamMember tm})>[];
    for (final ev in fs.events) {
      if (ev.status == EventStatusEnum.canceled || ev.endTime.isBefore(now)) {
        continue;
      }
      for (final tm in ev.team) {
        if (!tm.isSlot &&
            tm.statusEnum == EventUserStatusEnum.user_requests_change) {
          list.add((event: ev, tm: tm));
        }
      }
    }
    list.sort((a, b) => a.event.startTime.compareTo(b.event.startTime));
    return list;
  }

  List<({Event event, TeamMember tm})> _collectDeniedAssignments(
    FlightSchoolModelFlightSchoolView fs,
  ) {
    final now = DateTime.now();
    final list = <({Event event, TeamMember tm})>[];
    for (final ev in fs.events) {
      if (ev.status == EventStatusEnum.canceled || ev.endTime.isBefore(now)) {
        continue;
      }
      for (final tm in ev.team) {
        if (!tm.isSlot && tm.statusEnum == EventUserStatusEnum.denied_user) {
          list.add((event: ev, tm: tm));
        }
      }
    }
    list.sort((a, b) => a.event.startTime.compareTo(b.event.startTime));
    return list;
  }

  List<({Event event, TeamMember tm})> _collectOpenSwaps(
    FlightSchoolModelFlightSchoolView fs,
  ) {
    final now = DateTime.now();
    final list = <({Event event, TeamMember tm})>[];
    for (final ev in fs.events) {
      if (ev.status == EventStatusEnum.canceled || ev.endTime.isBefore(now)) {
        continue;
      }
      for (final tm in ev.team) {
        if (tm.hasOpenSwapRequest) {
          list.add((event: ev, tm: tm));
        }
      }
    }
    list.sort((a, b) => a.event.startTime.compareTo(b.event.startTime));
    return list;
  }

  List<({UserSummary member, Qualification qual})> _collectQualRequests(
    FlightSchoolModelFlightSchoolView fs,
  ) {
    final qualById = {for (final q in fs.qualifications) q.id: q};
    final list = <({UserSummary member, Qualification qual})>[];
    for (final m in fs.members) {
      for (final reqId in m.requestedQualificationIds) {
        final q = qualById[reqId];
        if (q != null) {
          list.add((member: m, qual: q));
        }
      }
    }
    return list;
  }

  List<({Event event, List<TeamMember> openSlots})> _collectUnfilledSoonEvents(
    FlightSchoolModelFlightSchoolView fs,
  ) {
    final now = DateTime.now();
    final horizon = now.add(const Duration(days: 14));
    final list = <({Event event, List<TeamMember> openSlots})>[];
    for (final ev in fs.events) {
      if (ev.status == EventStatusEnum.canceled ||
          ev.endTime.isBefore(now) ||
          ev.startTime.isAfter(horizon)) {
        continue;
      }
      final openSlots = ev.team
          .where((tm) => tm.isSlot || tm.statusEnum == EventUserStatusEnum.open)
          .toList();
      if (openSlots.isNotEmpty) {
        list.add((event: ev, openSlots: openSlots));
      }
    }
    list.sort((a, b) => a.event.startTime.compareTo(b.event.startTime));
    return list;
  }

  /// Fehlende Checklisten-Unterschriften: erst 2 Tage nach Event-Ende beim Admin melden.
  List<({Event event, TeamMember tm})> _collectUnsignedChecklists(
    FlightSchoolModelFlightSchoolView fs,
    List<ChecklistCompletion> completions,
  ) {
    final now = DateTime.now();
    final graceCutoff = now.subtract(const Duration(days: 2));
    final cutoff = now.subtract(const Duration(days: 30));

    final signedAssignmentIds = <String>{};
    final signedEventUserPairs = <String>{};
    for (final c in completions) {
      if (!c.isSigned) continue;
      if (c.assignmentId.isNotEmpty) signedAssignmentIds.add(c.assignmentId);
      if (c.eventId.isNotEmpty && c.userId.isNotEmpty) {
        signedEventUserPairs.add('${c.eventId}|${c.userId}');
      }
    }

    final list = <({Event event, TeamMember tm})>[];
    for (final ev in fs.events) {
      if (ev.status == EventStatusEnum.canceled) continue;
      if (!ev.endTime.isBefore(graceCutoff) || ev.endTime.isBefore(cutoff)) {
        continue;
      }

      for (final tm in ev.team) {
        if (tm.isSlot) continue;
        final st = tm.statusEnum;
        final isBinding = st == EventUserStatusEnum.accepted_flight_school ||
            st == EventUserStatusEnum.accepted_user ||
            st == EventUserStatusEnum.user_requests_change;
        if (!isBinding) continue;

        final role = _findTeamRole(fs, tm.role);
        final checklistId = role?.checklistId?.trim() ?? '';
        if (checklistId.isEmpty) continue;

        final assignmentSigned = tm.assignmentId != null &&
            signedAssignmentIds.contains(tm.assignmentId);
        final pairSigned = signedEventUserPairs.contains('${ev.id}|${tm.userId}');
        if (assignmentSigned || pairSigned) continue;

        list.add((event: ev, tm: tm));
      }
    }

    list.sort((a, b) => b.event.endTime.compareTo(a.event.endTime));
    return list;
  }

  /// Fehlende Stundenzettel (Lehrpersonal): erst 2 Tage nach Event-Ende beim Admin melden.
  List<({Event event, TeamMember tm})> _collectMissingTimesheets(
    FlightSchoolModelFlightSchoolView fs,
    List<EventTimesheet> timesheets,
  ) {
    if (!fs.timesheetEnabled) return const [];
    final now = DateTime.now();
    final graceCutoff = now.subtract(const Duration(days: 2));
    final cutoff = now.subtract(const Duration(days: 30));

    final submittedAssignmentIds = <String>{};
    final submittedEventUserPairs = <String>{};
    for (final s in timesheets) {
      if (!s.isSubmitted) continue;
      if (s.assignmentId.isNotEmpty) submittedAssignmentIds.add(s.assignmentId);
      if (s.eventId.isNotEmpty && s.userId.isNotEmpty) {
        submittedEventUserPairs.add('${s.eventId}|${s.userId}');
      }
    }

    final list = <({Event event, TeamMember tm})>[];
    for (final ev in fs.events) {
      if (ev.status == EventStatusEnum.canceled) continue;
      if (!ev.endTime.isBefore(graceCutoff) || ev.endTime.isBefore(cutoff)) {
        continue;
      }

      for (final tm in ev.team) {
        if (tm.isSlot) continue;
        final st = tm.statusEnum;
        final isBinding = st == EventUserStatusEnum.accepted_flight_school ||
            st == EventUserStatusEnum.accepted_user ||
            st == EventUserStatusEnum.user_requests_change;
        if (!isBinding) continue;

        final member = fs.findMemberByAnyId(tm.userId);
        if (member == null || !fs.memberRequiresTimesheet(member)) continue;

        final assignmentSubmitted = tm.assignmentId != null &&
            submittedAssignmentIds.contains(tm.assignmentId);
        final pairSubmitted =
            submittedEventUserPairs.contains('${ev.id}|${tm.userId}') ||
                submittedEventUserPairs.contains('${ev.id}|${member.id}');
        if (assignmentSubmitted || pairSubmitted) continue;

        list.add((event: ev, tm: tm));
      }
    }

    list.sort((a, b) => b.event.endTime.compareTo(a.event.endTime));
    return list;
  }

  // ==================== INLINE-AKTIONEN ====================

  Future<void> _openEventPreview(
    Event e,
    FlightSchoolModelFlightSchoolView fs,
  ) async {
    await showAdminEventPreviewSheet(
      context,
      event: e,
      flightSchool: fs,
      onOpenEdit: () => _openEditEvent(e),
    );
  }

  Future<void> _openEditEvent(Event e) async {
    await Navigator.push(
      context,
      PageRouteBuilder<void>(
        pageBuilder: (_, __, ___) => EventUpsertView(
          initialEvent: e,
          onSave: (updated) async {
            await DatabaseService().updateEventWithTeam(
              context: context,
              event: updated,
            );
            if (!mounted) return;
            await context.read<FlightSchoolProvider>().reloadFlightSchool(
                  _fsService.getFlightSchool,
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
        ),
        transitionsBuilder: (_, anim, __, child) {
          final curved = CurvedAnimation(
            parent: anim,
            curve: Curves.easeOutCubic,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.14),
              end: Offset.zero,
            ).animate(curved),
            child: FadeTransition(opacity: curved, child: child),
          );
        },
        transitionDuration: const Duration(milliseconds: 240),
      ),
    );
    if (mounted) await _loadAsyncTodos();
  }

  Future<void> _handleJoinRequest(UserSummary req, {required bool approve}) async {
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null || _busy) return;
    setState(() => _busy = true);
    try {
      final ok = approve
          ? await _fsService.approveJoinRequest(
              flightSchoolId: fs.id,
              membershipId: req.membershipId,
              memberName: req.displayName,
            )
          : await _fsService.rejectJoinRequest(
              flightSchoolId: fs.id,
              membershipId: req.membershipId,
              memberName: req.displayName,
            );
      if (!mounted) return;
      await _refreshAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? (approve
                    ? '„${req.displayName}“ ins Team aufgenommen.'
                    : 'Beitrittsanfrage von „${req.displayName}“ abgelehnt.')
                : 'Aktion fehlgeschlagen.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleApplication(
    Event event,
    TeamMember tm, {
    required bool approve,
  }) async {
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null || _busy) return;
    if (tm.assignmentId == null || tm.assignmentId!.isEmpty) {
      await _openEditEvent(event);
      return;
    }

    if (approve) {
      final member = fs.findMemberByAnyId(tm.userId);
      final memberName =
          tm.name.isNotEmpty ? tm.name : fs.resolveMemberName(tm.userId);
      final localConflicts = TandemService.findMemberEventConflicts(
        userId: member?.id ?? tm.userId,
        userRowId: member?.userRowId,
        startTime: event.startTime,
        endTime: event.endTime,
        events: fs.events,
        tandemDuties: fs.tandemDuties,
        ignoreEventId: event.id,
      );
      final crossMap = await SecurityPrivacyService().checkCrossSchoolConflicts(
        flightSchoolId: fs.id,
        userIds: [
          member?.id ?? tm.userId,
          if (member != null && member.userRowId.isNotEmpty) member.userRowId,
        ],
        startTime: event.startTime,
        endTime: event.endTime,
        ignoreEventId: event.id,
        otherSchoolsOnly: true,
      );
      if (!mounted) return;
      final conflicts = <String>{
        ...localConflicts,
        ...crossMap.values.expand((e) => e),
      }.toList();
      if (conflicts.isNotEmpty) {
        final confirmed = await showAdminDoubleBookingConfirmDialog(
          context,
          title: 'Doppelbesetzung bestätigen',
          message:
              '$memberName ist während „${event.displayName}“ bereits anderweitig verplant. Möchtest du die Bewerbung trotzdem annehmen?',
          conflicts: conflicts,
          confirmLabel: 'Trotzdem annehmen',
        );
        if (!confirmed || !mounted) return;
      }
    }

    setState(() => _busy = true);
    try {
      final memberName =
          tm.name.isNotEmpty ? tm.name : fs.resolveMemberName(tm.userId);
      final ok = await _fsService.decideEventApplication(
        flightSchoolId: fs.id,
        databaseId: fs.databaseId,
        tableId: fs.teamAssignmentsEventsCollectionId,
        assignmentId: tm.assignmentId!,
        approve: approve,
        eventName: event.displayName,
        memberName: memberName,
        roleName: tm.roleLabel,
      );
      if (!mounted) return;
      await _refreshAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? (approve
                    ? 'Bewerbung von $memberName angenommen.'
                    : 'Bewerbung von $memberName abgelehnt.')
                : 'Aktion fehlgeschlagen.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleSwap(
    Event event,
    TeamMember tm, {
    required bool approve,
  }) async {
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null || _busy) return;
    if (tm.assignmentId == null || (approve && tm.swapRequestedBy == null)) {
      await _openEditEvent(event);
      return;
    }

    if (approve && tm.swapRequestedBy != null) {
      final targetUid = tm.swapRequestedBy!;
      final member = fs.findMemberByAnyId(targetUid);
      final targetName = (tm.swapRequestedByName ?? '').trim().isNotEmpty
          ? tm.swapRequestedByName!
          : fs.resolveMemberName(targetUid);
      final localConflicts = TandemService.findMemberEventConflicts(
        userId: member?.id ?? targetUid,
        userRowId: member?.userRowId,
        startTime: event.startTime,
        endTime: event.endTime,
        events: fs.events,
        tandemDuties: fs.tandemDuties,
        ignoreEventId: event.id,
      );
      final crossMap = await SecurityPrivacyService().checkCrossSchoolConflicts(
        flightSchoolId: fs.id,
        userIds: [
          member?.id ?? targetUid,
          if (member != null && member.userRowId.isNotEmpty) member.userRowId,
        ],
        startTime: event.startTime,
        endTime: event.endTime,
        ignoreEventId: event.id,
        otherSchoolsOnly: true,
      );
      if (!mounted) return;
      final conflicts = <String>{
        ...localConflicts,
        ...crossMap.values.expand((e) => e),
      }.toList();
      if (conflicts.isNotEmpty) {
        final confirmed = await showAdminDoubleBookingConfirmDialog(
          context,
          title: 'Doppelbesetzung bestätigen',
          message:
              '$targetName ist während „${event.displayName}“ bereits anderweitig verplant. Möchtest du den Platztausch trotzdem bestätigen?',
          conflicts: conflicts,
          confirmLabel: 'Trotzdem tauschen',
        );
        if (!confirmed || !mounted) return;
      }
    }

    setState(() => _busy = true);
    try {
      final ok = approve
          ? await _planService.approveSwap(
              flightSchoolId: fs.id,
              databaseId: fs.databaseId,
              tableId: fs.teamAssignmentsEventsCollectionId,
              assignmentId: tm.assignmentId!,
              newUserId: tm.swapRequestedBy!,
              newUserName: (tm.swapRequestedByName ?? '').trim().isNotEmpty
                  ? tm.swapRequestedByName!
                  : fs.resolveMemberName(tm.swapRequestedBy!),
              eventName: event.displayName,
            )
          : await _planService.rejectSwap(
              flightSchoolId: fs.id,
              databaseId: fs.databaseId,
              tableId: fs.teamAssignmentsEventsCollectionId,
              assignmentId: tm.assignmentId!,
              eventName: event.displayName,
            );
      if (!mounted) return;
      await _refreshAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? (approve ? 'Platztausch bestätigt.' : 'Tauschanfrage abgelehnt.')
                : 'Aktion fehlgeschlagen.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleQualRequest(
    UserSummary member,
    Qualification qual, {
    required bool approve,
  }) async {
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null || _busy) return;
    setState(() => _busy = true);
    try {
      final ok = approve
          ? await _qualService.approveQualificationRequest(
              membershipId: member.membershipId,
              flightSchoolId: fs.id,
              memberName: member.displayName,
              currentQualificationIds: member.qualificationIds,
              currentRequestedIds: member.requestedQualificationIds,
              qualificationId: qual.id,
              qualificationName: qual.name,
            )
          : await _qualService.rejectQualificationRequest(
              membershipId: member.membershipId,
              flightSchoolId: fs.id,
              memberName: member.displayName,
              currentRequestedIds: member.requestedQualificationIds,
              qualificationId: qual.id,
              qualificationName: qual.name,
            );
      if (!mounted) return;
      await _refreshAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? (approve
                    ? 'Qualifikation „${qual.name}“ für ${member.displayName} freigegeben.'
                    : 'Anfrage für „${qual.name}“ abgelehnt.')
                : 'Aktion fehlgeschlagen.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<TandemDuty> _collectTandemRequests(
    FlightSchoolModelFlightSchoolView fs,
  ) {
    if (!fs.tandemEnabled) return const [];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final list = fs.tandemDuties
        .where(
          (d) =>
              (d.status == TandemDutyStatus.requestedByPilot ||
                  d.status == TandemDutyStatus.cancellationRequested) &&
              !d.endDay.isBefore(today),
        )
        .toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    return list;
  }

  Future<void> _handleTandemRequest(
    TandemDuty duty, {
    required bool approve,
  }) async {
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null || _busy) return;
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

    setState(() => _busy = true);
    try {
      final ok = await TandemService().updateDutyStatus(
        flightSchoolId: fs.id,
        dutyId: duty.id,
        newStatus: nextStatus,
        summary: '$pilotName (${duty.dateRangeLabel})',
      );
      if (!mounted) return;
      await _refreshAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? (isCancelReq
                    ? (approve
                        ? 'Tandem-Absage von $pilotName bestätigt.'
                        : 'Absage-Anfrage von $pilotName abgelehnt – Einsatz bleibt aktiv.')
                    : (approve
                        ? 'Tandem-Anfrage von $pilotName freigegeben.'
                        : 'Tandem-Anfrage von $pilotName abgelehnt.'))
                : 'Aktion fehlgeschlagen.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openDocumentReview() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ReviewQualificationsView()),
    );
    if (mounted) await _refreshAll();
  }

  // ==================== FORMATIERUNG ====================

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  String _fmtDateTime(DateTime d) =>
      '${_fmtDate(d)} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  String _daysUntilLabel(DateTime start) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(start.year, start.month, start.day);
    final diff = target.difference(today).inDays;
    if (diff <= 0) return 'Heute / laufend';
    if (diff == 1) return 'Morgen';
    return 'in $diff Tagen';
  }

  String _avatarFor(
    FlightSchoolModelFlightSchoolView fs,
    String userId, {
    String fallback = '',
  }) {
    if (fallback.isNotEmpty) return fallback;
    return fs.findMemberByAnyId(userId)?.avatarUrl ?? '';
  }

  // ==================== BUILD ====================

  @override
  Widget build(BuildContext context) {
    final fs = context.watch<FlightSchoolProvider>().flightSchool;
    final currentUser = context.watch<UserProvider>().user;
    if (fs == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (fs.id.isNotEmpty && fs.id != _loadedSchoolId) {
      _loadedSchoolId = fs.id;
      _lastEventCount = fs.events.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadAsyncTodos();
      });
    }

    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();

    final joinRequests = fs.pendingRequests;
    final applications = _collectApplications(fs);
    final tandemRequests = _collectTandemRequests(fs);
    final changeRequests = _collectChangeRequests(fs);
    final deniedAssignments = _collectDeniedAssignments(fs);
    final openSwaps = _collectOpenSwaps(fs);
    final qualRequests = _collectQualRequests(fs);
    final unfilledSoon = _collectUnfilledSoonEvents(fs);
    final unsignedChecklists =
        _loadingAsync ? const <({Event event, TeamMember tm})>[] : _collectUnsignedChecklists(fs, _schoolCompletions);
    final missingTimesheets =
        _loadingAsync ? const <({Event event, TeamMember tm})>[] : _collectMissingTimesheets(fs, _schoolTimesheets);
    final pendingDocs = _loadingAsync ? const <QualificationApproval>[] : _pendingApprovals;

    final totalTodos = joinRequests.length +
        applications.length +
        tandemRequests.length +
        pendingDocs.length +
        openSwaps.length +
        changeRequests.length +
        deniedAssignments.length +
        qualRequests.length +
        unfilledSoon.length +
        unsignedChecklists.length +
        missingTimesheets.length;

    // Falls gewählter Kategorie-Filter leer geworden ist, zurück auf "Alle"
    bool hasCategory(_AdminTodoCategory cat) => switch (cat) {
          _AdminTodoCategory.all => true,
          _AdminTodoCategory.joinRequests => joinRequests.isNotEmpty,
          _AdminTodoCategory.applications => applications.isNotEmpty,
          _AdminTodoCategory.tandemRequests => tandemRequests.isNotEmpty,
          _AdminTodoCategory.documents => pendingDocs.isNotEmpty,
          _AdminTodoCategory.swaps => openSwaps.isNotEmpty,
          _AdminTodoCategory.changeRequests => changeRequests.isNotEmpty,
          _AdminTodoCategory.deniedAssignments => deniedAssignments.isNotEmpty,
          _AdminTodoCategory.qualificationRequests => qualRequests.isNotEmpty,
          _AdminTodoCategory.unfilledEvents => unfilledSoon.isNotEmpty,
          _AdminTodoCategory.unsignedChecklists =>
            unsignedChecklists.isNotEmpty,
          _AdminTodoCategory.missingTimesheets => missingTimesheets.isNotEmpty,
        };

    final effectiveFilter =
        hasCategory(_activeCategory) ? _activeCategory : _AdminTodoCategory.all;

    bool showSection(_AdminTodoCategory cat) =>
        hasCategory(cat) &&
        (effectiveFilter == _AdminTodoCategory.all || effectiveFilter == cat);

    final upcomingEvents = fs.events
        .where(
          (e) =>
              e.status != EventStatusEnum.canceled && !e.endTime.isBefore(now),
        )
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    final runningEvents = upcomingEvents
        .where((e) => !e.startTime.isAfter(now))
        .toList()
      ..sort((a, b) => a.endTime.compareTo(b.endTime));

    final futureEvents = upcomingEvents
        .where((e) => e.startTime.isAfter(now))
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    final List<Event> nextEvents;
    if (futureEvents.isEmpty) {
      nextEvents = const [];
    } else {
      final firstStart = futureEvents.first.startTime;
      nextEvents = futureEvents
          .where(
            (e) =>
                e.startTime.year == firstStart.year &&
                e.startTime.month == firstStart.month &&
                e.startTime.day == firstStart.day,
          )
          .toList();
    }

    final filterEntries = <({
      _AdminTodoCategory cat,
      String label,
      int count,
      Color color,
    })>[
      if (joinRequests.isNotEmpty)
        (
          cat: _AdminTodoCategory.joinRequests,
          label: 'Beitritt',
          count: joinRequests.length,
          color: AppTheme.successColor,
        ),
      if (applications.isNotEmpty)
        (
          cat: _AdminTodoCategory.applications,
          label: 'Bewerbungen',
          count: applications.length,
          color: AppTheme.infoColor,
        ),
      if (tandemRequests.isNotEmpty)
        (
          cat: _AdminTodoCategory.tandemRequests,
          label: 'Tandem',
          count: tandemRequests.length,
          color: AppTheme.primaryColor,
        ),
      if (pendingDocs.isNotEmpty)
        (
          cat: _AdminTodoCategory.documents,
          label: 'Dokumente',
          count: pendingDocs.length,
          color: AppTheme.warningColor,
        ),
      if (changeRequests.isNotEmpty)
        (
          cat: _AdminTodoCategory.changeRequests,
          label: 'Änderungen',
          count: changeRequests.length,
          color: AppTheme.warningColor,
        ),
      if (deniedAssignments.isNotEmpty)
        (
          cat: _AdminTodoCategory.deniedAssignments,
          label: 'Abgelehnt',
          count: deniedAssignments.length,
          color: AppTheme.dangerColor,
        ),
      if (openSwaps.isNotEmpty)
        (
          cat: _AdminTodoCategory.swaps,
          label: 'Tausch',
          count: openSwaps.length,
          color: AppTheme.swapColor,
        ),
      if (qualRequests.isNotEmpty)
        (
          cat: _AdminTodoCategory.qualificationRequests,
          label: 'Qualifikationen',
          count: qualRequests.length,
          color: AppTheme.stage1Color,
        ),
      if (unfilledSoon.isNotEmpty)
        (
          cat: _AdminTodoCategory.unfilledEvents,
          label: 'Unbesetzt',
          count: unfilledSoon.length,
          color: AppTheme.dangerColor,
        ),
      if (unsignedChecklists.isNotEmpty)
        (
          cat: _AdminTodoCategory.unsignedChecklists,
          label: 'Checklisten',
          count: unsignedChecklists.length,
          color: AppTheme.dangerColor,
        ),
      if (missingTimesheets.isNotEmpty)
        (
          cat: _AdminTodoCategory.missingTimesheets,
          label: 'Stundenzettel',
          count: missingTimesheets.length,
          color: AppTheme.dangerColor,
        ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          fs.displayShortName.isNotEmpty
              ? '${fs.displayShortName} · Übersicht'
              : 'Admin-Übersicht',
        ),
        automaticallyImplyLeading: false,
        actions: [
          const AdminFlightSchoolSwitcherChip(),
          const AppModeSwitchChip(isAdminMode: true),
          const AppBarActionDivider(),
          ConnectionStatusAction(
            isLoading: widget.isLoading || _loadingAsync,
            hasConnection: widget.hasConnection,
            lastUpdated: widget.lastUpdated,
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refreshAll,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 108),
                  children: [
                    // 1) Status-Header-Karte + 2 kompakte KPI-Karten + Quick-Actions
                    _buildHeaderCard(
                      cs: cs,
                      fs: fs,
                      totalTodos: totalTodos,
                      upcomingCount: upcomingEvents.length,
                      openRequestCount: applications.length +
                          tandemRequests.length +
                          openSwaps.length +
                          changeRequests.length,
                      unfilledJobs90Days: upcomingEvents
                          .where(
                            (e) => !e.startTime.isAfter(
                              now.add(const Duration(days: 90)),
                            ),
                          )
                          .fold<int>(
                            0,
                            (sum, ev) =>
                                sum +
                                ev.team
                                    .where(
                                      (t) =>
                                          t.isSlot ||
                                          t.statusEnum ==
                                              EventUserStatusEnum.open,
                                    )
                                    .length,
                          ),
                    ),

                    // 2) Kategorie-Filter-Pills (nur wenn mind. 2 Kategorien aktiv)
                    if (filterEntries.length > 1) ...[
                      const SizedBox(height: 10),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: FilterChip(
                                label: Text('Alle ($totalTodos)'),
                                selected:
                                    effectiveFilter == _AdminTodoCategory.all,
                                onSelected: (_) => setState(
                                  () =>
                                      _activeCategory = _AdminTodoCategory.all,
                                ),
                              ),
                            ),
                            ...filterEntries.map(
                              (entry) => Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: FilterChip(
                                  label: Text('${entry.label} (${entry.count})'),
                                  selected: effectiveFilter == entry.cat,
                                  selectedColor:
                                      entry.color.withValues(alpha: 0.18),
                                  checkmarkColor: entry.color,
                                  onSelected: (_) => setState(
                                    () => _activeCategory =
                                        effectiveFilter == entry.cat
                                            ? _AdminTodoCategory.all
                                            : entry.cat,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 12),

                    // 3) Alles-erledigt-Zustand
                    if (totalTodos == 0 && !_loadingAsync)
                      _buildAllDoneCard(cs)
                    else ...[
                      // 3a) Team-Beitrittsanfragen
                      if (showSection(_AdminTodoCategory.joinRequests)) ...[
                        _SectionTitle(
                          icon: Icons.group_add_outlined,
                          color: AppTheme.successColor,
                          title: 'Team-Beitrittsanfragen',
                          count: joinRequests.length,
                          actionLabel: 'Personal',
                          onAction: widget.onSelectTab != null
                              ? () => widget.onSelectTab!(2)
                              : null,
                        ),
                        ...joinRequests.map(
                          (req) => _ActionCard(
                            leading: UserAvatar(
                              avatarUrl: req.avatarUrl,
                              name: req.displayName,
                              radius: 20,
                            ),
                            title: req.displayName,
                            subtitle: req.mail.isNotEmpty
                                ? req.mail
                                : 'Möchte dem Team beitreten',
                            actions: [
                              FilledButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () => _handleJoinRequest(
                                          req,
                                          approve: true,
                                        ),
                                icon: const Icon(Icons.check, size: 17),
                                label: const Text('Annehmen'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () => _handleJoinRequest(
                                          req,
                                          approve: false,
                                        ),
                                icon: const Icon(Icons.close, size: 17),
                                label: const Text('Ablehnen'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // 3b) Bewerbungen auf Posten
                      if (showSection(_AdminTodoCategory.applications)) ...[
                        _SectionTitle(
                          icon: Icons.how_to_reg_outlined,
                          color: AppTheme.infoColor,
                          title: 'Bewerbungen auf Posten',
                          count: applications.length,
                        ),
                        ...applications.map((item) {
                          final memberName = item.tm.name.isNotEmpty
                              ? item.tm.name
                              : fs.resolveMemberName(item.tm.userId);
                          return _ActionCard(
                            onTap: () => _openEditEvent(item.event),
                            leading: UserAvatar(
                              avatarUrl: _avatarFor(
                                fs,
                                item.tm.userId,
                                fallback: item.tm.avatarUrl,
                              ),
                              name: memberName,
                              radius: 20,
                            ),
                            title: '$memberName · ${item.tm.roleLabel}',
                            subtitle:
                                '${item.event.displayName} · ${_fmtDateTime(item.event.startTime)}',
                            actions: [
                              FilledButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () => _handleApplication(
                                          item.event,
                                          item.tm,
                                          approve: true,
                                        ),
                                icon: const Icon(Icons.check, size: 17),
                                label: const Text('Annehmen'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () => _handleApplication(
                                          item.event,
                                          item.tm,
                                          approve: false,
                                        ),
                                icon: const Icon(Icons.close, size: 17),
                                label: const Text('Ablehnen'),
                              ),
                            ],
                          );
                        }),
                        const SizedBox(height: 12),
                      ],

                      // 3b2) Tandem-Anfragen von Piloten
                      if (showSection(_AdminTodoCategory.tandemRequests)) ...[
                        _SectionTitle(
                          icon: Icons.paragliding_rounded,
                          color: AppTheme.primaryColor,
                          title: 'Tandem-Anfragen',
                          count: tandemRequests.length,
                          actionLabel: 'Tandemplanung',
                          onAction: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ManageTandemView(),
                              ),
                            );
                            if (mounted) await _refreshAll();
                          },
                        ),
                        ...tandemRequests.map((duty) {
                          final pilotName = fs.resolveMemberName(duty.userId);
                          final isCancelReq = duty.status ==
                              TandemDutyStatus.cancellationRequested;
                          return _ActionCard(
                            leading: UserAvatar(
                              avatarUrl: _avatarFor(fs, duty.userId),
                              name: pilotName,
                              radius: 20,
                            ),
                            title: isCancelReq
                                ? '$pilotName · Tandem-Absage angefragt'
                                : '$pilotName · Tandempilot',
                            subtitle:
                                '${duty.dateRangeLabel} · ${duty.timeWindowLabel}'
                                '${duty.notes.isNotEmpty ? ' · ${duty.notes}' : ''}',
                            actions: [
                              FilledButton.icon(
                                style: isCancelReq
                                    ? FilledButton.styleFrom(
                                        backgroundColor: AppTheme.dangerColor,
                                        foregroundColor: Colors.white,
                                      )
                                    : null,
                                onPressed: _busy
                                    ? null
                                    : () => _handleTandemRequest(
                                          duty,
                                          approve: true,
                                        ),
                                icon: const Icon(Icons.check, size: 17),
                                label: Text(
                                  isCancelReq
                                      ? 'Absage bestätigen'
                                      : 'Freigeben',
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () => _handleTandemRequest(
                                          duty,
                                          approve: false,
                                        ),
                                icon: const Icon(Icons.close, size: 17),
                                label: Text(
                                  isCancelReq ? 'Bleibt aktiv' : 'Ablehnen',
                                ),
                              ),
                            ],
                          );
                        }),
                        const SizedBox(height: 12),
                      ],

                      // 3c) Freizugebende Dokumente
                      if (showSection(_AdminTodoCategory.documents)) ...[
                        _SectionTitle(
                          icon: Icons.verified_user_outlined,
                          color: AppTheme.warningColor,
                          title: 'Freizugebende Dokumente',
                          count: pendingDocs.length,
                          actionLabel: 'Alle prüfen',
                          onAction: _openDocumentReview,
                        ),
                        ...pendingDocs.map((approval) {
                          final fallback = currentUser != null &&
                                  approval.userId == currentUser.id
                              ? (currentUser.name.isNotEmpty
                                  ? currentUser.name
                                  : currentUser.mail)
                              : null;
                          final memberName = fs.resolveMemberName(
                            approval.userId,
                            fallbackName: fallback,
                          );
                          return _ActionCard(
                            onTap: _openDocumentReview,
                            leading: UserAvatar(
                              avatarUrl: _avatarFor(fs, approval.userId),
                              name: memberName,
                              radius: 20,
                            ),
                            title: approval.documentType,
                            subtitle: 'Eingereicht von $memberName',
                            trailing: FilledButton.tonal(
                              onPressed: _openDocumentReview,
                              child: const Text('Prüfen'),
                            ),
                          );
                        }),
                        const SizedBox(height: 12),
                      ],

                      // 3d) Änderungsanfragen von Mitarbeitern
                      if (showSection(_AdminTodoCategory.changeRequests)) ...[
                        _SectionTitle(
                          icon: Icons.change_circle_outlined,
                          color: AppTheme.warningColor,
                          title: 'Änderungsanfragen',
                          count: changeRequests.length,
                        ),
                        ...changeRequests.map((item) {
                          final memberName = item.tm.name.isNotEmpty
                              ? item.tm.name
                              : fs.resolveMemberName(item.tm.userId);
                          return _ActionCard(
                            onTap: () => _openEditEvent(item.event),
                            leading: UserAvatar(
                              avatarUrl: _avatarFor(
                                fs,
                                item.tm.userId,
                                fallback: item.tm.avatarUrl,
                              ),
                              name: memberName,
                              radius: 20,
                            ),
                            title: '$memberName bittet um Ersatz',
                            subtitle:
                                '${item.event.displayName} (${item.tm.roleLabel}) · ${_fmtDate(item.event.startTime)}',
                            trailing: FilledButton.tonal(
                              onPressed: () => _openEditEvent(item.event),
                              child: const Text('Öffnen'),
                            ),
                          );
                        }),
                        const SizedBox(height: 12),
                      ],

                      // 3e) Abgelehnte Einteilungen (Mitglied hat Anfrage abgelehnt)
                      if (showSection(_AdminTodoCategory.deniedAssignments)) ...[
                        _SectionTitle(
                          icon: Icons.person_off_outlined,
                          color: AppTheme.dangerColor,
                          title: 'Abgelehnte Einteilungen',
                          count: deniedAssignments.length,
                        ),
                        ...deniedAssignments.map((item) {
                          final memberName = item.tm.name.isNotEmpty
                              ? item.tm.name
                              : fs.resolveMemberName(item.tm.userId);
                          return _ActionCard(
                            onTap: () => _openEditEvent(item.event),
                            leading: UserAvatar(
                              avatarUrl: _avatarFor(
                                fs,
                                item.tm.userId,
                                fallback: item.tm.avatarUrl,
                              ),
                              name: memberName,
                              radius: 20,
                            ),
                            title: '$memberName hat abgelehnt',
                            subtitle:
                                '${item.event.displayName} (${item.tm.roleLabel}) · ${_fmtDate(item.event.startTime)}',
                            trailing: FilledButton.tonal(
                              onPressed: () => _openEditEvent(item.event),
                              child: const Text('Neu besetzen'),
                            ),
                          );
                        }),
                        const SizedBox(height: 12),
                      ],

                      // 3f) Offene Tauschanfragen
                      if (showSection(_AdminTodoCategory.swaps)) ...[
                        _SectionTitle(
                          icon: Icons.swap_horiz,
                          color: AppTheme.swapColor,
                          title: 'Offene Tauschanfragen',
                          count: openSwaps.length,
                          actionLabel: 'Tausch-Tab',
                          onAction: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ManagePlanningPeriodsView(
                                  initialTab: 2,
                                ),
                              ),
                            );
                            if (mounted) await _refreshAll();
                          },
                        ),
                        ...openSwaps.map((item) {
                          final oldName = item.tm.name.isNotEmpty
                              ? item.tm.name
                              : fs.resolveMemberName(item.tm.userId);
                          final newName =
                              (item.tm.swapRequestedByName ?? '').trim().isNotEmpty
                                  ? item.tm.swapRequestedByName!
                                  : fs.resolveMemberName(
                                      item.tm.swapRequestedBy ?? '',
                                    );
                          return _ActionCard(
                            onTap: () => _openEditEvent(item.event),
                            leading: CircleAvatar(
                              radius: 20,
                              backgroundColor:
                                  AppTheme.swapColor.withValues(alpha: 0.14),
                              child: const Icon(
                                Icons.swap_horiz,
                                color: AppTheme.swapColor,
                              ),
                            ),
                            title: '$oldName → $newName',
                            subtitle:
                                '${item.event.displayName} (${item.tm.roleLabel}) · ${_fmtDate(item.event.startTime)}',
                            actions: [
                              FilledButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () => _handleSwap(
                                          item.event,
                                          item.tm,
                                          approve: true,
                                        ),
                                icon: const Icon(Icons.check, size: 17),
                                label: const Text('Bestätigen'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () => _handleSwap(
                                          item.event,
                                          item.tm,
                                          approve: false,
                                        ),
                                icon: const Icon(Icons.close, size: 17),
                                label: const Text('Ablehnen'),
                              ),
                            ],
                          );
                        }),
                        const SizedBox(height: 12),
                      ],

                      // 3g) Qualifikations-Anfragen
                      if (showSection(
                        _AdminTodoCategory.qualificationRequests,
                      )) ...[
                        _SectionTitle(
                          icon: Icons.workspace_premium_outlined,
                          color: AppTheme.stage1Color,
                          title: 'Qualifikations-Anfragen',
                          count: qualRequests.length,
                          actionLabel: 'Verwalten',
                          onAction: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ManageQualificationsView(
                                  initialTab: 1,
                                ),
                              ),
                            );
                            if (mounted) await _refreshAll();
                          },
                        ),
                        ...qualRequests.map(
                          (item) => _ActionCard(
                            leading: UserAvatar(
                              avatarUrl: item.member.avatarUrl,
                              name: item.member.displayName,
                              radius: 20,
                            ),
                            title: item.qual.name,
                            subtitle:
                                'Angefragt von ${item.member.displayName}',
                            actions: [
                              FilledButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () => _handleQualRequest(
                                          item.member,
                                          item.qual,
                                          approve: true,
                                        ),
                                icon: const Icon(Icons.check, size: 17),
                                label: const Text('Freigeben'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () => _handleQualRequest(
                                          item.member,
                                          item.qual,
                                          approve: false,
                                        ),
                                icon: const Icon(Icons.close, size: 17),
                                label: const Text('Ablehnen'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // 3h) Unbesetzte Stellen (nächste 14 Tage)
                      if (showSection(_AdminTodoCategory.unfilledEvents)) ...[
                        _SectionTitle(
                          icon: Icons.event_busy_outlined,
                          color: AppTheme.dangerColor,
                          title: 'Unbesetzte Stellen (14 Tage)',
                          count: unfilledSoon.length,
                        ),
                        ...unfilledSoon.map((item) {
                          final roleSummary = item.openSlots
                              .map((s) => s.roleLabel)
                              .join(', ');
                          return _ActionCard(
                            onTap: () => _openEditEvent(item.event),
                            leading: CircleAvatar(
                              radius: 20,
                              backgroundColor:
                                  AppTheme.dangerColor.withValues(alpha: 0.14),
                              child: Text(
                                '${item.openSlots.length}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.dangerColor,
                                ),
                              ),
                            ),
                            title:
                                '${item.event.displayName} (${_daysUntilLabel(item.event.startTime)})',
                            subtitle:
                                '${_fmtDate(item.event.startTime)} · Offen: $roleSummary',
                            trailing: const Icon(Icons.chevron_right),
                          );
                        }),
                        const SizedBox(height: 12),
                      ],

                      // 3i) Fehlende Checklisten-Unterschriften (letzte 30 Tage)
                      if (showSection(
                        _AdminTodoCategory.unsignedChecklists,
                      )) ...[
                        _SectionTitle(
                          icon: Icons.draw_outlined,
                          color: AppTheme.dangerColor,
                          title: 'Fehlende Checklisten-Unterschriften',
                          count: unsignedChecklists.length,
                        ),
                        ...unsignedChecklists.map((item) {
                          final memberName = item.tm.name.isNotEmpty
                              ? item.tm.name
                              : fs.resolveMemberName(item.tm.userId);
                          return _ActionCard(
                            onTap: () => _openEditEvent(item.event),
                            leading: UserAvatar(
                              avatarUrl: _avatarFor(
                                fs,
                                item.tm.userId,
                                fallback: item.tm.avatarUrl,
                              ),
                              name: memberName,
                              radius: 20,
                            ),
                            title: '${item.event.displayName} · ${item.tm.roleLabel}',
                            subtitle:
                                '$memberName · beendet am ${_fmtDate(item.event.endTime)}',
                            trailing: const Icon(Icons.chevron_right),
                          );
                        }),
                        const SizedBox(height: 12),
                      ],

                      // 3j) Fehlende Stundenzettel (> 2 Tage nach Event-Ende)
                      if (showSection(
                        _AdminTodoCategory.missingTimesheets,
                      )) ...[
                        _SectionTitle(
                          icon: Icons.access_time_filled_rounded,
                          color: AppTheme.dangerColor,
                          title: 'Fehlende Stundenzettel',
                          count: missingTimesheets.length,
                          actionLabel: 'Übersicht',
                          onAction: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ManageTimesheetsView(),
                              ),
                            );
                            if (mounted) await _refreshAll();
                          },
                        ),
                        ...missingTimesheets.map((item) {
                          final memberName = item.tm.name.isNotEmpty
                              ? item.tm.name
                              : fs.resolveMemberName(item.tm.userId);
                          return _ActionCard(
                            onTap: () => _openEditEvent(item.event),
                            leading: UserAvatar(
                              avatarUrl: _avatarFor(
                                fs,
                                item.tm.userId,
                                fallback: item.tm.avatarUrl,
                              ),
                              name: memberName,
                              radius: 20,
                            ),
                            title:
                                '${item.event.displayName} · ${item.tm.roleLabel}',
                            subtitle:
                                '$memberName · beendet am ${_fmtDate(item.event.endTime)}',
                            trailing: const Icon(Icons.chevron_right),
                          );
                        }),
                        const SizedBox(height: 12),
                      ],
                    ],

                    // 4) Laufende Events + darunter nächstes Event (bei gleichem Starttag alle)
                    if (runningEvents.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _SectionTitle(
                        icon: Icons.play_circle_outline_rounded,
                        color: AppTheme.successColor,
                        title: runningEvents.length == 1
                            ? 'Laufendes Event'
                            : 'Laufende Events',
                        count: runningEvents.length,
                        actionLabel:
                            nextEvents.isEmpty ? 'Alle Events' : null,
                        onAction: nextEvents.isEmpty &&
                                widget.onSelectTab != null
                            ? () => widget.onSelectTab!(1)
                            : null,
                      ),
                      ...runningEvents.map(
                        (ev) => _buildOverviewEventCard(
                          ev: ev,
                          fs: fs,
                          cs: cs,
                          isRunning: true,
                        ),
                      ),
                    ],
                    if (nextEvents.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _SectionTitle(
                        icon: Icons.upcoming_outlined,
                        color: cs.primary,
                        title: nextEvents.length == 1
                            ? 'Nächstes Event'
                            : 'Nächste Events',
                        count: nextEvents.length,
                        actionLabel: 'Alle Events',
                        onAction: widget.onSelectTab != null
                            ? () => widget.onSelectTab!(1)
                            : null,
                      ),
                      ...nextEvents.map(
                        (ev) => _buildOverviewEventCard(
                          ev: ev,
                          fs: fs,
                          cs: cs,
                          isRunning: false,
                        ),
                      ),
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

  Widget _buildHeaderCard({
    required ColorScheme cs,
    required FlightSchoolModelFlightSchoolView fs,
    required int totalTodos,
    required int upcomingCount,
    required int openRequestCount,
    required int unfilledJobs90Days,
  }) {
    final allClear = totalTodos == 0 && !_loadingAsync;
    final statusColor = allClear ? AppTheme.successColor : AppTheme.warningColor;
    final statusBg = allClear ? AppTheme.successBg : AppTheme.warningBg;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Kompakte Schul-Identitätskarte
        SoftCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              ClipOval(
                child: fs.logoLink.isEmpty
                    ? Image.asset(
                        'lib/assets/images/fsBaseImage.webp',
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                      )
                    : Image.network(
                        fs.logoLink,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Image.asset(
                          'lib/assets/images/fsBaseImage.webp',
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fs.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16.5,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${fs.members.length} Teammitglieder · $upcomingCount anstehende Events',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusPill(
                icon: allClear
                    ? Icons.check_circle_outline_rounded
                    : Icons.assignment_late_outlined,
                label: _loadingAsync && totalTodos == 0
                    ? 'Prüfe…'
                    : (allClear ? 'Alles erledigt' : '$totalTodos offen'),
                foreground: statusColor,
                background: statusBg,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // 2 kompakte Kennzahlen-Kacheln
        Row(
          children: [
            Expanded(
              child: KpiMetricCard(
                icon: Icons.inbox_rounded,
                iconColor: AppTheme.primaryColor,
                iconBg: AppTheme.primaryTint,
                value: '$openRequestCount',
                label: 'Anfragen & Tausch',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: KpiMetricCard(
                icon: unfilledJobs90Days > 0
                    ? Icons.person_search_rounded
                    : Icons.verified_rounded,
                iconColor: unfilledJobs90Days > 0
                    ? AppTheme.warningColor
                    : AppTheme.successColor,
                iconBg: unfilledJobs90Days > 0
                    ? AppTheme.warningBg
                    : AppTheme.successBg,
                value: '$unfilledJobs90Days',
                label: 'Unbesetzt (90 Tage)',
                onTap: widget.onSelectTab != null
                    ? () => widget.onSelectTab!(1)
                    : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOverviewEventCard({
    required Event ev,
    required FlightSchoolModelFlightSchoolView fs,
    required ColorScheme cs,
    required bool isRunning,
  }) {
    final openCount = ev.team
        .where(
          (t) => t.isSlot || t.statusEnum == EventUserStatusEnum.open,
        )
        .length;
    final staffed = ev.team.length - openCount;
    final isCanceled = ev.status == EventStatusEnum.canceled;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: CanceledEventDecorator(
        isCanceled: isCanceled,
        borderRadius: BorderRadius.circular(18),
        child: SoftCard(
          padding: const EdgeInsets.all(14),
          onTap: () => _openEventPreview(ev, fs),
          child: Row(
            children: [
              DateBadgeBox(
                date: ev.startTime,
                accentColor: isRunning
                    ? AppTheme.successColor
                    : eventStatusColor(ev.status.name),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ev.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        decoration:
                            isCanceled ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${_fmtDateTime(ev.startTime)}'
                      '${ev.location.isNotEmpty ? ' · ${ev.location}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (ev.team.isNotEmpty) ...[
                const SizedBox(width: 8),
                StatusPill(
                  label: '$staffed/${ev.team.length} besetzt',
                  foreground: openCount == 0
                      ? AppTheme.successColor
                      : AppTheme.warningColor,
                  background: openCount == 0
                      ? AppTheme.successBg
                      : AppTheme.warningBg,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAllDoneCard(ColorScheme cs) {
    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
      child: Column(
        children: [
          const TintedIconBadge(
            icon: Icons.task_alt_rounded,
            iconColor: AppTheme.successColor,
            backgroundColor: AppTheme.successBg,
            size: 56,
            iconSize: 28,
            radius: 18,
          ),
          const SizedBox(height: 12),
          const Text(
            'Keine offenen Admin-Aufgaben',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            'Alle Beitrittsanfragen, Bewerbungen, Nachweise, Tauschanfragen und Checklisten sind auf dem aktuellen Stand.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: cs.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final int count;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _SectionTitle({
    required this.icon,
    required this.color,
    required this.title,
    required this.count,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 2, 8),
      child: Row(
        children: [
          TintedIconBadge(
            icon: icon,
            iconColor: color,
            backgroundColor: color.withValues(alpha: 0.12),
            size: 28,
            iconSize: 16,
            radius: 8,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14.5,
                letterSpacing: -0.1,
              ),
            ),
          ),
          StatusPill(
            label: '$count',
            foreground: color,
            background: color.withValues(alpha: 0.12),
            fontSize: 11.5,
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(width: 4),
            TextButton(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final Widget leading;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final List<Widget> actions;
  final VoidCallback? onTap;

  const _ActionCard({
    required this.leading,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.actions = const [],
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SoftCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
            ],
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: actions,
            ),
          ],
        ],
      ),
    );
  }
}
