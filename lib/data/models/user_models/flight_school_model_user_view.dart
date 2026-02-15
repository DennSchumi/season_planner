import 'package:season_planner/data/enums/event_role_enum.dart';
import '../../enums/membership_status_enum.dart';

class FlightSchoolUserView {
  final String id;
  final String displayName;
  final String displayShortName;

  final MembershipStatusEnum membershipStatus;
  final List<EventRoleEnum> availableRoles;

  final String databaseId;
  final String teamAssignmentsEventsCollectionId;
  final String eventsCollectionId;
  final String auditLogsCollectionId;
  final String logoLink;
  final List<String> adminUserIds;

  FlightSchoolUserView({
    required this.id,
    required this.displayName,
    required this.displayShortName,
    required this.membershipStatus,
    required this.availableRoles,
    required this.databaseId,
    required this.teamAssignmentsEventsCollectionId,
    required this.eventsCollectionId,
    required this.auditLogsCollectionId,
    required this.logoLink,
    required this.adminUserIds,
  });

  static List<EventRoleEnum> _parseAvailableRoles(dynamic raw) {
    if (raw is! List) return const [];

    final roles = <EventRoleEnum>[];
    for (final v in raw) {
      final name = v?.toString();
      if (name == null) continue;

      try {
        roles.add(EventRoleEnum.values.byName(name));
      } catch (_) {
      }
    }
    return roles;
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
      membershipStatus: MembershipStatusEnum.values.byName(
        (json['membershipStatus'] ?? MembershipStatusEnum.active.name).toString(),
      ),
      availableRoles: _parseAvailableRoles(json['availableRoles']),
      databaseId: (json['databaseId'] ?? '').toString(),
      teamAssignmentsEventsCollectionId:
      (json['teamAssignmentsEventsCollectionId'] ?? '').toString(),
      eventsCollectionId: (json['eventsCollectionId'] ?? '').toString(),
      auditLogsCollectionId: (json['auditLogsCollectionId'] ?? '').toString(),
      logoLink: (json['logoLink'] ?? '').toString(),
      adminUserIds: List<String>.from(json['adminUserIds'] ?? []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'displayName': displayName,
      'displayShortName': displayShortName,
      'membershipStatus': membershipStatus.name,
      'availableRoles': availableRoles.map((r) => r.name).toList(),
      'databaseId': databaseId,
      'teamAssignmentsEventsCollectionId': teamAssignmentsEventsCollectionId,
      'eventsCollectionId': eventsCollectionId,
      'auditLogsCollectionId': auditLogsCollectionId,
      'logoLink': logoLink,
      'adminUserIds': adminUserIds,
    };
  }

  FlightSchoolUserView copyWith({
    String? id,
    String? displayName,
    String? displayShortName,
    MembershipStatusEnum? membershipStatus,
    List<EventRoleEnum>? availableRoles,
    String? databaseId,
    String? teamAssignmentsEventsCollectionId,
    String? eventsCollectionId,
    String? auditLogsCollectionId,
    String? logoLink,
    List<String>? adminUserIds,
  }) {
    return FlightSchoolUserView(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      displayShortName: displayShortName ?? this.displayShortName,
      membershipStatus: membershipStatus ?? this.membershipStatus,
      availableRoles: availableRoles ?? this.availableRoles,
      databaseId: databaseId ?? this.databaseId,
      teamAssignmentsEventsCollectionId: teamAssignmentsEventsCollectionId ??
          this.teamAssignmentsEventsCollectionId,
      eventsCollectionId: eventsCollectionId ?? this.eventsCollectionId,
      auditLogsCollectionId: auditLogsCollectionId ?? this.auditLogsCollectionId,
      logoLink: logoLink ?? this.logoLink,
      adminUserIds: adminUserIds ?? this.adminUserIds,
    );
  }

  @override
  String toString() {
    return 'FlightSchoolUserView('
        'id: $id, '
        'displayName: $displayName, '
        'displayShortName: $displayShortName, '
        'membershipStatus: ${membershipStatus.name}, '
        'availableRoles: ${availableRoles.map((e) => e.name).toList()}, '
        'databaseId: $databaseId, '
        'teamAssignmentsEventsCollectionId: $teamAssignmentsEventsCollectionId, '
        'eventsCollectionId: $eventsCollectionId, '
        'auditLogsCollectionId: $auditLogsCollectionId, '
        'logoLink: $logoLink, '
        'adminUserIds: $adminUserIds'
        ')';
  }
}
