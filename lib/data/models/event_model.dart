import 'package:season_planer/data/enums/event_role_enum.dart';
import 'package:season_planer/data/enums/event_status_enum.dart';
import 'package:season_planer/data/enums/event_user_status_enum.dart';

class Event {
  final String id;
  final String flightSchoolId;
  final String identifier;
  final EventStatusEnum status;
  final DateTime startTime;
  final DateTime endTime;
  final String displayName;
  final List<String> team;
  final List<String> notes;
  final EventRoleEnum role;
  final EventUserStatusEnum assignmentStatus;

  Event({
    required this.id,
    required this.flightSchoolId,
    required this.identifier,
    required this.status,
    required this.startTime,
    required this.endTime,
    required this.displayName,
    required this.team,
    required this.notes,
    required this.role,
    required this.assignmentStatus,
  });

  factory Event.fromJson(Map<String, dynamic> json) {
    return Event(
      id: json['id'] as String,
      flightSchoolId: json['flightSchoolId'] as String,
      identifier: json['identifier'] as String,
      status: EventStatusEnum.values.byName(json['status']),
      startTime: DateTime.parse(json['startTime']),
      endTime: DateTime.parse(json['endTime']),
      displayName: json['displayName'] as String,
      team: List<String>.from(json['team'] ?? []),
      notes: List<String>.from(json['notes'] ?? []),
      role: EventRoleEnum.values.byName(json['role']),
      assignmentStatus: EventUserStatusEnum.values.byName(json['assignmentStatus']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'flightSchoolId': flightSchoolId,
      'identifier': identifier,
      'status': status.name,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime.toIso8601String(),
      'displayName': displayName,
      'team': team,
      'notes': notes,
      'role': role.name,
      'assignmentStatus': assignmentStatus.name,
    };
  }

  Event copyWith({
    String? id,
    String? flightSchoolId,
    String? identifier,
    EventStatusEnum? status,
    DateTime? startTime,
    DateTime? endTime,
    String? displayName,
    List<String>? team,
    List<String>? notes,
    EventRoleEnum? role,
    EventUserStatusEnum? assignmentStatus,
  }) {
    return Event(
      id: id ?? this.id,
      flightSchoolId: flightSchoolId ?? this.flightSchoolId,
      identifier: identifier ?? this.identifier,
      status: status ?? this.status,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      displayName: displayName ?? this.displayName,
      team: team ?? this.team,
      notes: notes ?? this.notes,
      role: role ?? this.role,
      assignmentStatus: assignmentStatus ?? this.assignmentStatus,
    );
  }

  @override
  String toString() {
    return 'Event(id: $id, flightSchoolId: $flightSchoolId, identifier: $identifier, status: $status, '
        'startTime: $startTime, endTime: $endTime, displayName: $displayName, team: $team, '
        'notes: $notes, role: $role, assignmentStatus: $assignmentStatus)';
  }
}
