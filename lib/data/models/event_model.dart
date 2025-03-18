import 'package:season_planer/data/enums/event_status_enum.dart';

class Event {
  final String identifier;
  final EventStatusEnum status;
  final DateTime startTime;
  final DateTime endTime;
  final String displayName;
  final List<String> team;
  final List<String> notes;

  // Constructor
  Event({
    required this.identifier,
    required this.status,
    required this.startTime,
    required this.endTime,
    required this.displayName,
    required this.team,
    required this.notes,
  });

  // Factory method to create an instance from a JSON object
  factory Event.fromJson(Map<String, dynamic> json) {
    return Event(
      identifier: json['identifier'] as String,
      status: EventStatusEnum.values.byName(json['status']), // Enum parsing
      startTime: DateTime.parse(json['startTime']),
      endTime: DateTime.parse(json['endTime']),
      displayName: json['displayName'] as String,
      team: List<String>.from(json['team'] ?? []),
      notes: List<String>.from(json['notes'] ?? []),
    );
  }

  // Convert object to JSON
  Map<String, dynamic> toJson() {
    return {
      'identifier': identifier,
      'status': status.name, // Enum to string
      'startTime': startTime.toIso8601String(),
      'endTime': endTime.toIso8601String(),
      'displayName': displayName,
      'team': team,
      'notes': notes,
    };
  }

  // Copy method to update specific fields
  Event copyWith({
    String? identifier,
    EventStatusEnum? status,
    DateTime? startTime,
    DateTime? endTime,
    String? displayName,
    List<String>? team,
    List<String>? notes,
  }) {
    return Event(
      identifier: identifier ?? this.identifier,
      status: status ?? this.status,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      displayName: displayName ?? this.displayName,
      team: team ?? this.team,
      notes: notes ?? this.notes,
    );
  }

  // Debugging & Readable Output
  @override
  String toString() {
    return 'Event(identifier: $identifier, status: $status, startTime: $startTime, endTime: $endTime, '
        'displayName: $displayName, team: $team, notes: $notes)';
  }
}
