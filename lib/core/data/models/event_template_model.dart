import 'package:season_planner/core/data/enums/event_status_enum.dart';

class EventTemplate {
  final String id;
  final String flightSchoolId;
  final String templateName;
  final String displayName;
  final String identifier;
  final String location;
  final String notes;
  final EventStatusEnum status;
  final int durationMinutes;
  final int defaultStartHour;
  final int defaultStartMinute;
  final List<String> roles;

  const EventTemplate({
    required this.id,
    required this.flightSchoolId,
    required this.templateName,
    required this.displayName,
    this.identifier = '',
    this.location = '',
    this.notes = '',
    this.status = EventStatusEnum.scheduled,
    required this.durationMinutes,
    this.defaultStartHour = 9,
    this.defaultStartMinute = 0,
    this.roles = const [],
  });

  Duration get duration => Duration(minutes: durationMinutes);

  String get durationLabel {
    final days = durationMinutes ~/ (60 * 24);
    final hours = (durationMinutes % (60 * 24)) ~/ 60;
    final mins = durationMinutes % 60;
    if (days >= 1) {
      if (hours == 0) return '$days ${days == 1 ? "Tag" : "Tage"}';
      return '$days ${days == 1 ? "Tag" : "Tage"} $hours Std.';
    }
    if (hours >= 1 && mins > 0) return '$hours Std. $mins Min.';
    if (hours >= 1) return '$hours Std.';
    return '$mins Min.';
  }

  factory EventTemplate.fromMap(String id, Map<String, dynamic> map) {
    final durRaw = map['duration_minutes'];
    final hourRaw = map['default_start_hour'];
    final minRaw = map['default_start_minute'];
    return EventTemplate(
      id: id,
      flightSchoolId: (map['flight_school_id'] ?? '').toString(),
      templateName: (map['template_name'] ?? 'Vorlage').toString(),
      displayName: (map['display_name'] ?? '').toString(),
      identifier: (map['identifier'] ?? '').toString(),
      location: (map['location'] ?? '').toString(),
      notes: (map['notes'] ?? '').toString(),
      status: EventStatusEnum.parse(map['status']),
      durationMinutes: (durRaw is int ? durRaw : int.tryParse('$durRaw')) ?? 120,
      defaultStartHour:
          (hourRaw is int ? hourRaw : int.tryParse('$hourRaw')) ?? 9,
      defaultStartMinute:
          (minRaw is int ? minRaw : int.tryParse('$minRaw')) ?? 0,
      roles: (map['roles'] as List? ?? const [])
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList(),
    );
  }

  Map<String, dynamic> toMap() => {
        'flight_school_id': flightSchoolId,
        'template_name': templateName,
        'display_name': displayName,
        'identifier': identifier,
        'location': location,
        'notes': notes,
        'status': status.name,
        'duration_minutes': durationMinutes,
        'default_start_hour': defaultStartHour,
        'default_start_minute': defaultStartMinute,
        'roles': roles,
      };
}
