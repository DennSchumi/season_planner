class AuditLogEntry {
  final String id;
  final String flightSchoolId;
  final String userId;
  final String action;
  final String details;
  final DateTime timestamp;

  const AuditLogEntry({
    required this.id,
    required this.flightSchoolId,
    required this.userId,
    required this.action,
    required this.details,
    required this.timestamp,
  });

  factory AuditLogEntry.fromMap(String id, Map<String, dynamic> map) {
    return AuditLogEntry(
      id: id,
      flightSchoolId: (map['flight_school_id'] ?? '').toString(),
      userId: (map['user_id'] ?? '').toString(),
      action: (map['action'] ?? '').toString(),
      details: (map['details'] ?? '').toString(),
      timestamp: DateTime.tryParse((map['timestamp'] ?? '').toString()) ??
          DateTime.now(),
    );
  }
}
