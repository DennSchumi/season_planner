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
  final List<TeamMember> team;
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
      team: List<TeamMember>.from(json['team'] ?? []),
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
    List<TeamMember>? team,
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
class TeamMember {
  final String userId;
  final String name;
  final String role;
  final String status;

  const TeamMember({
    required this.userId,
    required this.name,
    required this.role,
    required this.status,
  });


  factory TeamMember.fromMap(Map<String, dynamic> map) {
    return TeamMember(
      userId: (map['user_id'] ?? map['userId'] ?? '') as String,
      name: (map['name'] ?? map['display_name'] ?? '') as String,
      role: (map['role'] ?? '') as String,
      status: (map['status'] ?? '') as String,
    );
  }


  Map<String, dynamic> toMap() {
    return {
      'user_id': userId,
      'name': name,
      'role': role,
      'status': status,
    };
  }

  TeamMember copyWith({
    String? userId,
    String? name,
    String? role,
    String? status,
  }) {
    return TeamMember(
      userId: userId ?? this.userId,
      name: name ?? this.name,
      role: role ?? this.role,
      status: status ?? this.status,
    );
  }

  @override
  String toString() {
    return 'TeamMember(userId: $userId, name: $name, role: $role, status: $status)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TeamMember &&
        other.userId == userId &&
        other.name == name &&
        other.role == role &&
        other.status == status;
  }

  @override
  int get hashCode => Object.hash(userId, name, role, status);
}
