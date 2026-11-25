import 'package:season_planner/core/data/enums/event_role_enum.dart';
import 'package:season_planner/core/data/enums/membership_status_enum.dart';
import 'package:season_planner/core/data/enums/subscription_status_enum.dart';
import 'package:season_planner/core/data/enums/team_tier_enum.dart';
import 'package:season_planner/core/data/models/event_model.dart';
import 'package:season_planner/core/data/models/planning_period_model.dart';
import 'package:season_planner/core/data/models/team_role_model.dart';
import 'package:season_planner/core/data/models/timesheet_model.dart';

class FlightSchoolUserView {
  final String id;
  final String membershipId;
  final String displayName;
  final String displayShortName;

  final MembershipStatusEnum membershipStatus;
  final SubscriptionStatusEnum subscriptionStatus;

  /// Interne Einstufung (Stammteam vs. Erweitertes Team) – für das Mitglied unsichtbar.
  final TeamTierEnum teamTier;

  /// Freigeschaltete Einsatzrollen des Nutzers in dieser Flugschule (`team_roles`).
  final List<String> availableRoles;

  /// Vom Admin zugeteilte Qualifikations-IDs des Nutzers in dieser Flugschule.
  final List<String> assignedQualificationIds;

  /// Vom Nutzer angefragte Qualifikations-IDs (warten auf Admin-Freigabe).
  final List<String> requestedQualificationIds;

  final String databaseId;
  final String teamAssignmentsEventsCollectionId;
  final String eventsCollectionId;
  final String auditLogsCollectionId;
  final String logoLink;
  final List<String> adminUserIds;
  final List<TeamRole> teamRoles;
  final List<Qualification> qualifications;
  final List<PlanningPeriod> planningPeriods;
  final bool tandemEnabled;
  final bool timesheetEnabled;
  final List<String> timesheetQualificationIds;

  FlightSchoolUserView({
    required this.id,
    this.membershipId = '',
    required this.displayName,
    required this.displayShortName,
    required this.membershipStatus,
    this.subscriptionStatus = SubscriptionStatusEnum.active,
    this.teamTier = TeamTierEnum.core,
    required this.availableRoles,
    this.assignedQualificationIds = const [],
    this.requestedQualificationIds = const [],
    required this.databaseId,
    required this.teamAssignmentsEventsCollectionId,
    required this.eventsCollectionId,
    required this.auditLogsCollectionId,
    required this.logoLink,
    required this.adminUserIds,
    this.teamRoles = const [],
    this.qualifications = const [],
    this.planningPeriods = const [],
    this.tandemEnabled = true,
    this.timesheetEnabled = true,
    this.timesheetQualificationIds = const [],
  });

  /// True, wenn der Nutzer aufgrund seiner Qualifikation(en) in dieser Flugschule
  /// für Events einen Stundenzettel ausfüllen muss.
  bool get userRequiresTimesheet => memberQualifiesForTimesheet(
        timesheetEnabled: timesheetEnabled,
        schoolQualifications: qualifications,
        configuredQualIds: timesheetQualificationIds,
        memberQualificationIds: assignedQualificationIds,
      );

  bool get isExtendedTeam => teamTier == TeamTierEnum.extended;

  /// True, wenn der Nutzer die Teamrolle „Tandempilot“ zugeordnet bekommen hat.
  /// Nur Mitglieder mit dieser Teamrolle sehen die komplette Tandemplanung im Kalender.
  bool get isTandemPilot => availableRoles.any(
        (r) => EventRoleEnum.displayLabel(r).toLowerCase().contains('tandem'),
      );

  /// True, wenn dem Mitglied ausschließlich die Teamrolle „Tandempilot“ zugeordnet ist
  /// (und keine weiteren Event-Teamrollen). Solche Mitglieder sehen nicht alle Schul-Events.
  bool get isTandemOnly =>
      availableRoles.isNotEmpty &&
      availableRoles.every(
        (r) => EventRoleEnum.displayLabel(r).toLowerCase().contains('tandem'),
      );

  bool hasRole(String roleName) {
    final target = EventRoleEnum.displayLabel(roleName).toLowerCase();
    return availableRoles.any((r) =>
        r.toLowerCase() == roleName.toLowerCase() ||
        EventRoleEnum.displayLabel(r).toLowerCase() == target);
  }

  bool hasQualification(String qualificationId) =>
      assignedQualificationIds.contains(qualificationId);

  bool hasRequestedQualification(String qualificationId) =>
      requestedQualificationIds.contains(qualificationId);

  TeamRole? findTeamRole(String roleName) {
    final target = EventRoleEnum.displayLabel(roleName).toLowerCase();
    for (final r in teamRoles) {
      if (r.name.toLowerCase() == roleName.toLowerCase() ||
          r.name.toLowerCase() == target) {
        return r;
      }
    }
    return null;
  }

  Qualification? findQualificationById(String id) {
    for (final q in qualifications) {
      if (q.id == id) return q;
    }
    return null;
  }

  /// Prüft, ob der Nutzer die Pflicht-Qualifikationen einer Teamrolle erfüllt (UND / ODER).
  ({
    bool satisfied,
    List<Qualification> missing,
    bool requireAll,
    List<Qualification> relevantQualifications,
  }) checkRoleQualificationStatus(String roleName) {
    final role = findTeamRole(roleName);
    if (role == null || role.requiredQualificationIds.isEmpty) {
      return (
        satisfied: true,
        missing: const [],
        requireAll: true,
        relevantQualifications: const [],
      );
    }

    final requiredQuals = role.requiredQualificationIds
        .map(findQualificationById)
        .whereType<Qualification>()
        .toList();
    if (requiredQuals.isEmpty) {
      return (
        satisfied: true,
        missing: const [],
        requireAll: role.requireAllQualifications,
        relevantQualifications: const [],
      );
    }

    final owned = requiredQuals
        .where((q) => assignedQualificationIds.contains(q.id))
        .toList();
    final missing = requiredQuals
        .where((q) => !assignedQualificationIds.contains(q.id))
        .toList();

    if (role.requireAllQualifications) {
      return (
        satisfied: missing.isEmpty,
        missing: missing,
        requireAll: true,
        relevantQualifications: requiredQuals,
      );
    } else {
      final satisfied = owned.isNotEmpty;
      return (
        satisfied: satisfied,
        missing: satisfied ? const [] : requiredQuals,
        requireAll: false,
        relevantQualifications: satisfied ? owned : requiredQuals,
      );
    }
  }

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
  int effectiveStageFor(Event event) {
    final period = periodForEvent(event);
    return period?.stage.value ?? 3;
  }

  static List<String> _parseAvailableRoles(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((v) => v?.toString().trim() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
  }

  factory FlightSchoolUserView.fromJson(Map<String, dynamic> json) {
    final displayName = json['displayName'] as String? ?? '';
    return FlightSchoolUserView(
      id: json['id'] as String,
      displayName: displayName,
      displayShortName:
          (json['displayShortName'] as String?)?.trim().isNotEmpty == true
              ? json['displayShortName'] as String
              : displayName,
      membershipStatus: MembershipStatusEnumX.parse(json['membershipStatus']),
      subscriptionStatus: SubscriptionStatusEnumX.parse(json['subscriptionStatus']),
      teamTier: TeamTierEnum.parse(json['teamTier'] ?? json['team_tier']),
      availableRoles: _parseAvailableRoles(json['availableRoles']),
      databaseId: (json['databaseId'] ?? '').toString(),
      teamAssignmentsEventsCollectionId:
          (json['teamAssignmentsEventsCollectionId'] ?? '').toString(),
      eventsCollectionId: (json['eventsCollectionId'] ?? '').toString(),
      auditLogsCollectionId: (json['auditLogsCollectionId'] ?? '').toString(),
      logoLink: (json['logoLink'] ?? '').toString(),
      adminUserIds: List<String>.from(json['adminUserIds'] ?? []),
      tandemEnabled: json['tandemEnabled'] != false,
      timesheetEnabled: json['timesheetEnabled'] != false,
      timesheetQualificationIds:
          List<String>.from(json['timesheetQualificationIds'] ?? const []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'displayName': displayName,
      'displayShortName': displayShortName,
      'membershipStatus': membershipStatus.name,
      'subscriptionStatus': subscriptionStatus.name,
      'teamTier': teamTier.wireValue,
      'availableRoles': availableRoles,
      'databaseId': databaseId,
      'teamAssignmentsEventsCollectionId': teamAssignmentsEventsCollectionId,
      'eventsCollectionId': eventsCollectionId,
      'auditLogsCollectionId': auditLogsCollectionId,
      'logoLink': logoLink,
      'adminUserIds': adminUserIds,
      'tandemEnabled': tandemEnabled,
      'timesheetEnabled': timesheetEnabled,
      'timesheetQualificationIds': timesheetQualificationIds,
    };
  }

  FlightSchoolUserView copyWith({
    String? id,
    String? membershipId,
    String? displayName,
    String? displayShortName,
    MembershipStatusEnum? membershipStatus,
    SubscriptionStatusEnum? subscriptionStatus,
    TeamTierEnum? teamTier,
    List<String>? availableRoles,
    List<String>? assignedQualificationIds,
    List<String>? requestedQualificationIds,
    String? databaseId,
    String? teamAssignmentsEventsCollectionId,
    String? eventsCollectionId,
    String? auditLogsCollectionId,
    String? logoLink,
    List<String>? adminUserIds,
    List<TeamRole>? teamRoles,
    List<Qualification>? qualifications,
    List<PlanningPeriod>? planningPeriods,
    bool? tandemEnabled,
    bool? timesheetEnabled,
    List<String>? timesheetQualificationIds,
  }) {
    return FlightSchoolUserView(
      id: id ?? this.id,
      membershipId: membershipId ?? this.membershipId,
      displayName: displayName ?? this.displayName,
      displayShortName: displayShortName ?? this.displayShortName,
      membershipStatus: membershipStatus ?? this.membershipStatus,
      subscriptionStatus: subscriptionStatus ?? this.subscriptionStatus,
      teamTier: teamTier ?? this.teamTier,
      availableRoles: availableRoles ?? this.availableRoles,
      assignedQualificationIds:
          assignedQualificationIds ?? this.assignedQualificationIds,
      requestedQualificationIds:
          requestedQualificationIds ?? this.requestedQualificationIds,
      databaseId: databaseId ?? this.databaseId,
      teamAssignmentsEventsCollectionId: teamAssignmentsEventsCollectionId ??
          this.teamAssignmentsEventsCollectionId,
      eventsCollectionId: eventsCollectionId ?? this.eventsCollectionId,
      auditLogsCollectionId:
          auditLogsCollectionId ?? this.auditLogsCollectionId,
      logoLink: logoLink ?? this.logoLink,
      adminUserIds: adminUserIds ?? this.adminUserIds,
      teamRoles: teamRoles ?? this.teamRoles,
      qualifications: qualifications ?? this.qualifications,
      planningPeriods: planningPeriods ?? this.planningPeriods,
      tandemEnabled: tandemEnabled ?? this.tandemEnabled,
      timesheetEnabled: timesheetEnabled ?? this.timesheetEnabled,
      timesheetQualificationIds:
          timesheetQualificationIds ?? this.timesheetQualificationIds,
    );
  }
}
