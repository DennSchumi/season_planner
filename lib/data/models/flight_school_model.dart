class FlightSchool {
  final String id;
  final String displayName;
  final String databaseId;
  final String teamAssignmentsEventsCollectionId;
  final String eventsCollectionId;
  final String auditLogsCollectionId;
  final String logoLink;

  // Constructor
  FlightSchool({
    required this.id,
    required this.displayName,
    required this.databaseId,
    required this.teamAssignmentsEventsCollectionId,
    required this.eventsCollectionId,
    required this.auditLogsCollectionId,
    required this.logoLink,
  });

  // Factory method to create an instance from a JSON object
  factory FlightSchool.fromJson(Map<String, dynamic> json) {
    return FlightSchool(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      databaseId: json['databaseId'] as String,
      teamAssignmentsEventsCollectionId: json['teamAssignmentsEventsCollectionId'] as String,
      eventsCollectionId: json['eventsCollectionId'] as String,
      auditLogsCollectionId: json['auditLogsCollectionId'] as String,
      logoLink: json['logoLink'] as String,
    );
  }

  // Convert object to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'displayName': displayName,
      'databaseId': databaseId,
      'teamAssignmentsEventsCollectionId': teamAssignmentsEventsCollectionId,
      'eventsCollectionId': eventsCollectionId,
      'auditLogsCollectionId': auditLogsCollectionId,
      'logoLink': logoLink,
    };
  }

  // Copy method to update specific fields
  FlightSchool copyWith({
    String? id,
    String? displayName,
    String? databaseId,
    String? teamAssignmentsEventsCollectionId,
    String? eventsCollectionId,
    String? auditLogsCollectionId,
    String? logoLink,
  }) {
    return FlightSchool(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      databaseId: databaseId ?? this.databaseId,
      teamAssignmentsEventsCollectionId: teamAssignmentsEventsCollectionId ?? this.teamAssignmentsEventsCollectionId,
      eventsCollectionId: eventsCollectionId ?? this.eventsCollectionId,
      auditLogsCollectionId: auditLogsCollectionId ?? this.auditLogsCollectionId,
      logoLink: logoLink ?? this.logoLink,
    );
  }

  // Debugging & Readable Output
  @override
  String toString() {
    return 'FlightSchool(id: $id, displayName: $displayName, databaseId: $databaseId, '
        'teamAssignmentsEventsCollectionId: $teamAssignmentsEventsCollectionId, eventsCollectionId: $eventsCollectionId, '
        'auditLogsCollectionId: $auditLogsCollectionId, logoLink: $logoLink)';
  }
}
