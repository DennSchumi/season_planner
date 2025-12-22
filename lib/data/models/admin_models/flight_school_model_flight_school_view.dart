import 'package:season_planer/data/models/admin_models/user_summary_flight_school_view.dart';
import 'package:season_planer/data/models/event_model.dart';

class FlightSchoolModelFlightSchoolView {
  final String id;
  final String displayName;
  final String databaseId;
  final String teamAssignmentsEventsCollectionId;
  final String eventsCollectionId;
  final String auditLogsCollectionId;
  final String logoLink;
  final List<String> adminUserIds;

  final List<UserSummary> members;
  final List<Event> events;
  final Map<String, dynamic> settings;

  FlightSchoolModelFlightSchoolView({
    required this.id,
    required this.displayName,
    required this.databaseId,
    required this.teamAssignmentsEventsCollectionId,
    required this.eventsCollectionId,
    required this.auditLogsCollectionId,
    required this.logoLink,
    required this.adminUserIds,
    required this.members,
    required this.events,
    required this.settings,
  });

  factory FlightSchoolModelFlightSchoolView.fromJson(Map<String, dynamic> json) {
    return FlightSchoolModelFlightSchoolView(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      databaseId: json['databaseId'] as String,
      teamAssignmentsEventsCollectionId: json['teamAssignmentsEventsCollectionId'] as String,
      eventsCollectionId: json['eventsCollectionId'] as String,
      auditLogsCollectionId: json['auditLogsCollectionId'] as String,
      logoLink: json['logoLink'] as String,
      adminUserIds: List<String>.from(json['adminUserIds'] ?? []),
      members: (json['members'] as List? ?? [])
          .map((m) => UserSummary.fromJson(m as Map<String, dynamic>))
          .toList(),
      events: (json['events'] as List? ?? [])
          .map((e) => Event.fromJson(e as Map<String, dynamic>))
          .toList(),
      settings: (json['settings'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'displayName': displayName,
      'databaseId': databaseId,
      'teamAssignmentsEventsCollectionId': teamAssignmentsEventsCollectionId,
      'eventsCollectionId': eventsCollectionId,
      'auditLogsCollectionId': auditLogsCollectionId,
      'logoLink': logoLink,
      'adminUserIds': adminUserIds,
      'members': members.map((m) => m.toJson()).toList(),
      'events': events.map((e) => e.toJson()).toList(),
      'settings': settings,
    };
  }

  FlightSchoolModelFlightSchoolView copyWith({
    String? id,
    String? displayName,
    String? databaseId,
    String? teamAssignmentsEventsCollectionId,
    String? eventsCollectionId,
    String? auditLogsCollectionId,
    String? logoLink,
    List<String>? adminUserIds,
    List<UserSummary>? members,
    List<Event>? events,
    Map<String, dynamic>? settings,
  }) {
    return FlightSchoolModelFlightSchoolView(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      databaseId: databaseId ?? this.databaseId,
      teamAssignmentsEventsCollectionId:
      teamAssignmentsEventsCollectionId ?? this.teamAssignmentsEventsCollectionId,
      eventsCollectionId: eventsCollectionId ?? this.eventsCollectionId,
      auditLogsCollectionId: auditLogsCollectionId ?? this.auditLogsCollectionId,
      logoLink: logoLink ?? this.logoLink,
      adminUserIds: adminUserIds ?? this.adminUserIds,
      members: members ?? this.members,
      events: events ?? this.events,
      settings: settings ?? this.settings,
    );
  }

  static FlightSchoolModelFlightSchoolView empty() {
    return FlightSchoolModelFlightSchoolView(
      id: '',
      displayName: '',
      databaseId: '',
      teamAssignmentsEventsCollectionId: '',
      eventsCollectionId: '',
      auditLogsCollectionId: '',
      logoLink: '',
      adminUserIds: const [],
      members: const [],
      events: const [],
      settings: const {},
    );
  }

  @override
  String toString() {
    return 'FlightSchoolModelFlightSchoolView(id: $id, displayName: $displayName, databaseId: $databaseId, '
        'teamAssignmentsEventsCollectionId: $teamAssignmentsEventsCollectionId, eventsCollectionId: $eventsCollectionId, '
        'auditLogsCollectionId: $auditLogsCollectionId, logoLink: $logoLink, adminUserIds: $adminUserIds, '
        'members: ${members.length}, events: ${events.length})';
  }
}
