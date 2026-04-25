import 'package:season_planner/core/data/enums/event_role_enum.dart';
import 'package:season_planner/core/data/enums/event_status_enum.dart';
import 'package:season_planner/core/data/enums/event_user_status_enum.dart';

import 'package:season_planner/core/data/enums/event_status_enum.dart';

class Event {
  final String id;
  final String flightSchoolId;

  final String identifier;
  final EventStatusEnum status;
  final DateTime startTime;
  final DateTime endTime;

  final String displayName;
  final String location;

  final List<TeamMember> team;

  final String notes;

  const Event({
    required this.id,
    required this.flightSchoolId,
    required this.identifier,
    required this.status,
    required this.startTime,
    required this.endTime,
    required this.displayName,
    required this.location,
    required this.team,
    required this.notes,
  });

  factory Event.fromJson(Map<String, dynamic> json) {
    return Event(
      id: (json['id'] ?? '').toString(),
      flightSchoolId: (json['flightSchoolId'] ?? '').toString(),
      identifier: (json['identifier'] ?? '').toString(),
      status: EventStatusEnum.values.byName(json['status']),
      startTime: DateTime.parse(json['startTime']),
      endTime: DateTime.parse(json['endTime']),
      displayName: (json['displayName'] ?? '').toString(),
      location: (json['location'] ?? '').toString(),
      team: (json['team'] as List? ?? const [])
          .map((e) => TeamMember.fromMap(e as Map<String, dynamic>))
          .toList(),
      notes: (json['notes'] ?? '').toString(),
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
      'location': location,
      'team': team.map((t) => t.toMap()).toList(),
      'notes': notes,
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
    String? location,
    List<TeamMember>? team,
    String? notes,
  }) {
    return Event(
      id: id ?? this.id,
      flightSchoolId: flightSchoolId ?? this.flightSchoolId,
      identifier: identifier ?? this.identifier,
      status: status ?? this.status,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      displayName: displayName ?? this.displayName,
      location: location ?? this.location,
      team: team ?? this.team,
      notes: notes ?? this.notes,
    );
  }

  @override
  String toString() {
    return 'Event('
        'id: $id, '
        'flightSchoolId: $flightSchoolId, '
        'identifier: $identifier, '
        'status: $status, '
        'startTime: $startTime, '
        'endTime: $endTime, '
        'displayName: $displayName, '
        'location: $location, '
        'team: ${team.length}, '
        'notes: $notes'
        ')';
  }
}

class TeamMember {
  final String id;
  final String userId;
  final String name;
  final String role;
  final String status;

  const TeamMember({
    required this.id,
    required this.userId,
    required this.name,
    required this.role,
    required this.status,
  });

  factory TeamMember.fromMap(Map<String, dynamic> map) {
    return TeamMember(
      id: (map['id'] ?? map['\$id'] ?? '').toString(),
      userId: (map['user_id'] ?? map['userId'] ?? '').toString(),
      name: (map['name'] ?? map['display_name'] ?? '').toString(),
      role: (map['role'] ?? '').toString(),
      status: (map['status'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'name': name,
      'role': role,
      'status': status,
    };
  }

  TeamMember copyWith({
    String? id,
    String? userId,
    String? name,
    String? role,
    String? status,
  }) {
    return TeamMember(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      role: role ?? this.role,
      status: status ?? this.status,
    );
  }

  bool get isSlot => userId.startsWith('slot_');

  EventRoleEnum? get roleEnum {
    try {
      return EventRoleEnum.values.byName(role);
    } catch (_) {
      return null;
    }
  }

  EventUserStatusEnum? get statusEnum {
    try {
      return EventUserStatusEnum.values.byName(status);
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() {
    return 'TeamMember(id: $id, userId: $userId, name: $name, role: $role, status: $status)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TeamMember &&
        other.id == id &&
        other.userId == userId &&
        other.name == name &&
        other.role == role &&
        other.status == status;
  }

  @override
  int get hashCode => Object.hash(id, userId, name, role, status);
}
