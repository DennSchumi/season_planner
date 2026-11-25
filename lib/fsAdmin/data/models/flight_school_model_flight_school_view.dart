import 'package:season_planner/core/data/enums/event_role_enum.dart';
import 'package:season_planner/core/data/enums/subscription_status_enum.dart';
import 'package:season_planner/core/data/models/audit_export_model.dart';
import 'package:season_planner/core/data/models/event_model.dart';
import 'package:season_planner/core/data/models/planning_period_model.dart';
import 'package:season_planner/core/data/models/tandem_model.dart';
import 'package:season_planner/core/data/models/team_role_model.dart';
import 'package:season_planner/core/data/models/timesheet_model.dart';
import 'user_summary_flight_school_view.dart';

class FlightSchoolModelFlightSchoolView {
  final String id;
  final String displayName;
  final String displayShortName;
  final String databaseId;
  final String teamAssignmentsEventsCollectionId;
  final String eventsCollectionId;
  final String auditLogsCollectionId;
  final String logoLink;
  final String logoId;
  final List<String> adminUserIds;
  final SubscriptionStatusEnum subscriptionStatus;
  final String icsToken;

  final List<UserSummary> members;
  final List<UserSummary> pendingRequests;
  final List<Event> events;
  final List<TeamRole> teamRoles;
  final List<Qualification> qualifications;
  final List<PlanningPeriod> planningPeriods;
  final bool tandemEnabled;
  final List<TandemDuty> tandemDuties;
  final List<TandemDemand> tandemDemands;
  final bool timesheetEnabled;
  final List<String> timesheetQualificationIds;
  final bool auditExportsEnabled;
  final FlightSchoolAuditProfile auditProfile;
  final Map<String, dynamic> settings;
  final bool hasLoadedArchive;

  FlightSchoolModelFlightSchoolView({
    required this.id,
    required this.displayName,
    required this.databaseId,
    required this.displayShortName,
    required this.teamAssignmentsEventsCollectionId,
    required this.eventsCollectionId,
    required this.auditLogsCollectionId,
    required this.logoLink,
    required this.logoId,
    required this.adminUserIds,
    this.subscriptionStatus = SubscriptionStatusEnum.active,
    this.icsToken = '',
    required this.members,
    this.pendingRequests = const [],
    required this.events,
    this.teamRoles = const [],
    this.qualifications = const [],
    this.planningPeriods = const [],
    this.tandemEnabled = true,
    this.tandemDuties = const [],
    this.tandemDemands = const [],
    this.timesheetEnabled = true,
    this.timesheetQualificationIds = const [],
    this.auditExportsEnabled = true,
    this.auditProfile = const FlightSchoolAuditProfile(),
    required this.settings,
    this.hasLoadedArchive = false,
  });

  bool get isSubscriptionActive => subscriptionStatus.isActive;

  Set<String> get effectiveTimesheetQualificationIds =>
      resolveEffectiveTimesheetQualificationIds(
        allQualifications: qualifications,
        configuredIds: timesheetQualificationIds,
      );

  bool memberRequiresTimesheet(UserSummary member) =>
      memberQualifiesForTimesheet(
        timesheetEnabled: timesheetEnabled,
        schoolQualifications: qualifications,
        configuredQualIds: timesheetQualificationIds,
        memberQualificationIds: member.qualificationIds,
      );

  bool memberHasTandemRole(UserSummary member) => member.roles.any(
        (r) => EventRoleEnum.displayLabel(r).toLowerCase().contains('tandem'),
      );

  bool memberHasTandemQualification(UserSummary member) {
    for (final qId in member.qualificationIds) {
      final q = findQualificationById(qId);
      if (q != null && q.name.toLowerCase().contains('tandem')) return true;
      if (qId.toLowerCase().contains('tandem')) return true;
    }
    return false;
  }

  List<UserSummary> get tandemPilots => members
      .where((m) => memberHasTandemRole(m) || memberHasTandemQualification(m))
      .toList();

  List<String> get availableRoleNames => teamRoles.isNotEmpty
      ? teamRoles.map((r) => r.name).toList()
      : List<String>.from(kDefaultTeamRoleNames);

  Qualification? findQualificationById(String qualId) {
    for (final q in qualifications) {
      if (q.id == qualId) return q;
    }
    return null;
  }

  String qualificationName(String qualId) {
    return findQualificationById(qualId)?.name ?? qualId;
  }

  int get openQualificationRequestCount => members.fold<int>(
        0,
        (sum, m) => sum + m.requestedQualificationIds.length,
      );

  /// Ermittelt die maßgebliche Saison für ein Datum (primär über den Saison-Zeitraum).
  PlanningPeriod? periodForDate(DateTime date, {String? fallbackPeriodId}) =>
      resolvePlanningPeriod(
        planningPeriods,
        date,
        fallbackPeriodId: fallbackPeriodId,
      );

  /// Ermittelt die maßgebliche Saison für ein Event anhand seines Startdatums.
  PlanningPeriod? periodForEvent(Event event) => periodForDate(
        event.startTime,
        fallbackPeriodId: event.planningPeriodId,
      );

  /// Ermittelt die wirksame Planungsstufe (1, 2 oder 3) für ein Event live
  /// anhand der Saison-Zeiträume dieser Flugschule (Standard: Stufe 3).
  int effectiveStageFor(Event event) => periodForEvent(event)?.stage.value ?? 3;

  /// Sucht ein Mitglied anhand seiner Auth-ID oder `core_db.users`-Row-ID.
  UserSummary? findMemberByAnyId(String userId) {
    final trimmed = userId.trim();
    if (trimmed.isEmpty) return null;
    for (final m in [...members, ...pendingRequests]) {
      if (m.matchesId(trimmed)) return m;
    }
    return null;
  }

  /// Löst eine Benutzer-ID (Auth-ID oder Row-ID) lesbar in den Namen auf.
  String resolveMemberName(
    String userId, {
    String? fallbackName,
    String emptyLabel = 'System',
  }) {
    final trimmed = userId.trim();
    if (trimmed.isEmpty) return emptyLabel;
    final m = findMemberByAnyId(trimmed);
    if (m != null) return m.displayName;
    if (fallbackName != null && fallbackName.trim().isNotEmpty) {
      return fallbackName.trim();
    }
    return 'Unbekanntes Mitglied';
  }

  FlightSchoolModelFlightSchoolView copyWith({
    String? id,
    String? displayName,
    String? displayShortName,
    String? databaseId,
    String? teamAssignmentsEventsCollectionId,
    String? eventsCollectionId,
    String? auditLogsCollectionId,
    String? logoLink,
    String? logoId,
    List<String>? adminUserIds,
    SubscriptionStatusEnum? subscriptionStatus,
    String? icsToken,
    List<UserSummary>? members,
    List<UserSummary>? pendingRequests,
    List<Event>? events,
    List<TeamRole>? teamRoles,
    List<Qualification>? qualifications,
    List<PlanningPeriod>? planningPeriods,
    bool? tandemEnabled,
    List<TandemDuty>? tandemDuties,
    List<TandemDemand>? tandemDemands,
    bool? timesheetEnabled,
    List<String>? timesheetQualificationIds,
    bool? auditExportsEnabled,
    FlightSchoolAuditProfile? auditProfile,
    Map<String, dynamic>? settings,
    bool? hasLoadedArchive,
  }) {
    return FlightSchoolModelFlightSchoolView(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      displayShortName: displayShortName ?? this.displayShortName,
      databaseId: databaseId ?? this.databaseId,
      teamAssignmentsEventsCollectionId:
          teamAssignmentsEventsCollectionId ??
              this.teamAssignmentsEventsCollectionId,
      eventsCollectionId: eventsCollectionId ?? this.eventsCollectionId,
      auditLogsCollectionId:
          auditLogsCollectionId ?? this.auditLogsCollectionId,
      logoLink: logoLink ?? this.logoLink,
      logoId: logoId ?? this.logoId,
      adminUserIds: adminUserIds ?? this.adminUserIds,
      subscriptionStatus: subscriptionStatus ?? this.subscriptionStatus,
      icsToken: icsToken ?? this.icsToken,
      members: members ?? this.members,
      pendingRequests: pendingRequests ?? this.pendingRequests,
      events: events ?? this.events,
      teamRoles: teamRoles ?? this.teamRoles,
      qualifications: qualifications ?? this.qualifications,
      planningPeriods: planningPeriods ?? this.planningPeriods,
      tandemEnabled: tandemEnabled ?? this.tandemEnabled,
      tandemDuties: tandemDuties ?? this.tandemDuties,
      tandemDemands: tandemDemands ?? this.tandemDemands,
      timesheetEnabled: timesheetEnabled ?? this.timesheetEnabled,
      timesheetQualificationIds:
          timesheetQualificationIds ?? this.timesheetQualificationIds,
      auditExportsEnabled: auditExportsEnabled ?? this.auditExportsEnabled,
      auditProfile: auditProfile ?? this.auditProfile,
      settings: settings ?? this.settings,
      hasLoadedArchive: hasLoadedArchive ?? this.hasLoadedArchive,
    );
  }

  static FlightSchoolModelFlightSchoolView empty() {
    return FlightSchoolModelFlightSchoolView(
      id: '',
      displayName: '',
      displayShortName: '',
      databaseId: '',
      teamAssignmentsEventsCollectionId: '',
      eventsCollectionId: '',
      auditLogsCollectionId: '',
      logoLink: '',
      logoId: '',
      adminUserIds: const [],
      subscriptionStatus: SubscriptionStatusEnum.pending,
      icsToken: '',
      members: const [],
      pendingRequests: const [],
      events: const [],
      teamRoles: const [],
      qualifications: const [],
      planningPeriods: const [],
      settings: const {},
    );
  }
}
