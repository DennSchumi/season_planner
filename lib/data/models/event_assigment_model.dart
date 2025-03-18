import 'package:season_planer/data/enums/event_role_enum.dart';
import 'package:season_planer/data/models/event_model.dart';

class EventAssignment {
  final String userId;
  final Event event;
  final EventRoleEnum role;

  // Constructor
  EventAssignment({
    required this.userId,
    required this.event,
    required this.role,
  });

  // Factory method to create an instance from a JSON object
  factory EventAssignment.fromJson(Map<String, dynamic> json) {
    return EventAssignment(
      userId: json['userId'] as String,
      event: Event.fromJson(json['event']),
      role: EventRoleEnum.values.byName(json['role']), // Enum parsing
    );
  }

  // Convert object to JSON
  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'event': event.toJson(),
      'role': role.name, // Enum to string
    };
  }

  // Copy method to update specific fields
  EventAssignment copyWith({
    String? userId,
    Event? event,
    EventRoleEnum? role,
  }) {
    return EventAssignment(
      userId: userId ?? this.userId,
      event: event ?? this.event,
      role: role ?? this.role,
    );
  }

  // Debugging & Readable Output
  @override
  String toString() {
    return 'EventAssignment(userId: $userId, event: $event, role: $role)';
  }
}
