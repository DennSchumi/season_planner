class FlightSchoolUserView {
  final String id;
  final String displayName;
  final String displayShortName;
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
    required this.databaseId,
    required this.teamAssignmentsEventsCollectionId,
    required this.eventsCollectionId,
    required this.auditLogsCollectionId,
    required this.logoLink,
    required this.adminUserIds,
  });

  factory FlightSchoolUserView.fromJson(Map<String, dynamic> json) {
    final displayName = json['displayName'] as String? ?? '';

    return FlightSchoolUserView(
      id: json['id'] as String,
      displayName: displayName,
      displayShortName:
      (json['displayShortName'] as String?)?.trim().isNotEmpty == true
          ? json['displayShortName'] as String
          : displayName,
      databaseId: json['databaseId'] as String,
      teamAssignmentsEventsCollectionId:
      json['teamAssignmentsEventsCollectionId'] as String,
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
      'displayShortName': displayShortName,
      'databaseId': databaseId,
      'teamAssignmentsEventsCollectionId':
      teamAssignmentsEventsCollectionId,
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
      displayShortName:
      displayShortName ?? this.displayShortName,
      databaseId: databaseId ?? this.databaseId,
      teamAssignmentsEventsCollectionId:
      teamAssignmentsEventsCollectionId ??
          this.teamAssignmentsEventsCollectionId,
      eventsCollectionId:
      eventsCollectionId ?? this.eventsCollectionId,
      auditLogsCollectionId:
      auditLogsCollectionId ?? this.auditLogsCollectionId,
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
        'databaseId: $databaseId, '
        'teamAssignmentsEventsCollectionId: $teamAssignmentsEventsCollectionId, '
        'eventsCollectionId: $eventsCollectionId, '
        'auditLogsCollectionId: $auditLogsCollectionId, '
        'logoLink: $logoLink, '
        'adminUserIds: $adminUserIds'
        ')';
  }
}
