class FlightSchool {
  final String id;
  final String displayName;
  final String databaseId;
  final String teamAssignmentsEventsCollectionId;
  final String eventsCollectionId;
  final String auditLogsCollectionId;
  final String logoLink;
  final List<String> adminUserIds;

  FlightSchool({
    required this.id,
    required this.displayName,
    required this.databaseId,
    required this.teamAssignmentsEventsCollectionId,
    required this.eventsCollectionId,
    required this.auditLogsCollectionId,
    required this.logoLink,
    required this.adminUserIds,
  });

  factory FlightSchool.fromJson(Map<String, dynamic> json) {
    return FlightSchool(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      databaseId: json['databaseId'] as String,
      teamAssignmentsEventsCollectionId: json['teamAssignmentsEventsCollectionId'] as String,
      eventsCollectionId: json['eventsCollectionId'] as String,
      auditLogsCollectionId: json['auditLogsCollectionId'] as String,
      logoLink: json['logoLink'] as String,
      adminUserIds: List<String>.from(json['adminUserIds'] ?? []),
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
    };
  }

  FlightSchool copyWith({
    String? id,
    String? displayName,
    String? databaseId,
    String? teamAssignmentsEventsCollectionId,
    String? eventsCollectionId,
    String? auditLogsCollectionId,
    String? logoLink,
    List<String>? adminUserIds,
  }) {
    return FlightSchool(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      databaseId: databaseId ?? this.databaseId,
      teamAssignmentsEventsCollectionId: teamAssignmentsEventsCollectionId ?? this.teamAssignmentsEventsCollectionId,
      eventsCollectionId: eventsCollectionId ?? this.eventsCollectionId,
      auditLogsCollectionId: auditLogsCollectionId ?? this.auditLogsCollectionId,
      logoLink: logoLink ?? this.logoLink,
      adminUserIds: adminUserIds ?? this.adminUserIds,
    );
  }

  @override
  String toString() {
    return 'FlightSchool(id: $id, displayName: $displayName, databaseId: $databaseId, '
        'teamAssignmentsEventsCollectionId: $teamAssignmentsEventsCollectionId, eventsCollectionId: $eventsCollectionId, '
        'auditLogsCollectionId: $auditLogsCollectionId, logoLink: $logoLink, adminUserIds: $adminUserIds)';
  }
}
