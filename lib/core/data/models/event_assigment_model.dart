import 'package:season_planner/core/data/enums/event_role_enum.dart';
import 'package:season_planner/core/data/enums/event_user_status_enum.dart';
import 'package:season_planner/core/data/models/event_model.dart';

import '../enums/event_status_enum.dart';

class EventAssignment {
  final String id;
  final String userId;
  final Event event;
  final EventRoleEnum role;
  final EventUserStatusEnum status;

  const EventAssignment({
    required this.id,
    required this.userId,
    required this.event,
    required this.role,
    required this.status,
  });

  factory EventAssignment.fromJson(Map<String, dynamic> json) {
    return EventAssignment(
      id: (json['id'] ?? '').toString(),
      userId: (json['userId'] ?? '').toString(),
      event: Event.fromJson(Map<String, dynamic>.from(json['event'])),
      role: EventRoleEnum.values.byName((json['role'] ?? '').toString()),
      status: EventUserStatusEnum.values.byName((json['status'] ?? '').toString()),
    );
  }

  factory EventAssignment.fromMap(Map<String, dynamic> map) {
    return EventAssignment.fromJson(map);
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'event': event.toJson(),
      'role': role.name,
      'status': status.name,
    };
  }

  Map<String, dynamic> toMap() {
    return toJson();
  }

  EventAssignment copyWith({
    String? id,
    String? userId,
    Event? event,
    EventRoleEnum? role,
    EventUserStatusEnum? status,
  }) {
    return EventAssignment(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      event: event ?? this.event,
      role: role ?? this.role,
      status: status ?? this.status,
    );
  }

  static EventAssignment empty() {
    return EventAssignment(
      id: '',
      userId: '',
      event: Event(
        id: '',
        flightSchoolId: '',
        identifier: '',
        status: EventStatusEnum.provisional,
        startTime: DateTime.fromMillisecondsSinceEpoch(0),
        endTime: DateTime.fromMillisecondsSinceEpoch(0),
        displayName: '',
        location: '',
        team: const [],
        notes: '',
      ),
      role: EventRoleEnum.values.first,
      status: EventUserStatusEnum.values.first,
    );
  }

  @override
  String toString() {
    return 'EventAssignment('
        'id: $id, '
        'userId: $userId, '
        'event: $event, '
        'role: $role, '
        'status: $status'
        ')';
  }
}