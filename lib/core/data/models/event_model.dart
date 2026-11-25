import 'package:season_planner/core/data/enums/event_role_enum.dart';
import 'package:season_planner/core/data/enums/event_status_enum.dart';
import 'package:season_planner/core/data/enums/event_user_status_enum.dart';

class Event {
  final String id;
  final String? eventDocId;
  final String flightSchoolId;

  final String identifier;
  final EventStatusEnum status;
  final DateTime startTime;
  final DateTime endTime;

  final String displayName;
  final String location;

  final List<TeamMember> team;

  final String notes;

  /// Dynamischer Rollenname aus `core_db.team_roles` (oder Legacy-Enum-Key).
  final String role;
  final EventUserStatusEnum assignmentStatus;

  /// Planungsstufe & Serie (Appwrite 2.x Erweiterungen)
  final String? planningPeriodId;
  final int planningStage; // 1 = Verfügbarkeit, 2 = Bewerbung, 3 = Produktion
  final String? seriesId;

  /// Tausch-Workflow in Stufe 3 (Produktion)
  final bool swapOffered;
  final String? swapRequestedBy;
  final String? swapRequestedByName;

  /// Gibt an, ob dieser Event-Eintrag ein Tausch-Angebot eines anderen Mitglieds ist
  final bool isSwapOfferFromOther;
  final String? assignedUserId;

  /// Vorherige Start-/Endzeit nach einer Terminverschiebung (für Nutzer-Benachrichtigungen)
  final DateTime? previousStartTime;
  final DateTime? previousEndTime;

  Event({
    required this.id,
    this.eventDocId,
    required this.flightSchoolId,
    required this.identifier,
    required this.status,
    required this.startTime,
    required this.endTime,
    required this.displayName,
    required this.location,
    required this.team,
    required this.notes,
    required this.role,
    required this.assignmentStatus,
    this.planningPeriodId,
    this.planningStage = 3,
    this.seriesId,
    this.swapOffered = false,
    this.swapRequestedBy,
    this.swapRequestedByName,
    this.isSwapOfferFromOther = false,
    this.assignedUserId,
    this.previousStartTime,
    this.previousEndTime,
  });

  String get roleLabel => EventRoleEnum.displayLabel(role);

  bool get hasOpenSwapRequest =>
      swapOffered && (swapRequestedBy != null && swapRequestedBy!.isNotEmpty);

  bool get wasRescheduled =>
      previousStartTime != null &&
      previousEndTime != null &&
      (previousStartTime != startTime || previousEndTime != endTime);

  /// True, wenn der aktuelle Nutzer für dieses Event verbindlich eingeteilt ist
  /// (Admin-Zuweisung oder bestätigte Anfrage) – unabhängig von der Planungsstufe.
  bool get isOwnBindingAssignment =>
      !isSwapOfferFromOther &&
      (assignmentStatus == EventUserStatusEnum.accepted_flight_school ||
          assignmentStatus == EventUserStatusEnum.accepted_user ||
          assignmentStatus == EventUserStatusEnum.user_requests_change);

  factory Event.fromJson(Map<String, dynamic> json) {
    return Event(
      id: (json['id'] ?? '').toString(),
      eventDocId: json['eventDocId']?.toString(),
      flightSchoolId: (json['flightSchoolId'] ?? '').toString(),
      identifier: (json['identifier'] ?? '').toString(),
      status: EventStatusEnum.parse(json['status']),
      startTime: DateTime.parse(json['startTime']),
      endTime: DateTime.parse(json['endTime']),
      displayName: (json['displayName'] ?? '').toString(),
      location: (json['location'] ?? '').toString(),
      team: (json['team'] as List? ?? const [])
          .map((e) => TeamMember.fromMap(e as Map<String, dynamic>))
          .toList(),
      notes: (json['notes'] ?? '').toString(),
      role: (json['role'] ?? '').toString(),
      assignmentStatus: EventUserStatusLabelX.parse(json['assignmentStatus']),
      planningPeriodId: json['planningPeriodId']?.toString(),
      planningStage: (json['planningStage'] is int)
          ? json['planningStage'] as int
          : int.tryParse('${json['planningStage']}') ?? 3,
      seriesId: json['seriesId']?.toString(),
      swapOffered: json['swapOffered'] == true,
      swapRequestedBy: json['swapRequestedBy']?.toString(),
      swapRequestedByName: json['swapRequestedByName']?.toString(),
      isSwapOfferFromOther: json['isSwapOfferFromOther'] == true,
      assignedUserId: json['assignedUserId']?.toString(),
      previousStartTime: json['previousStartTime'] != null
          ? DateTime.tryParse(json['previousStartTime'].toString())
          : null,
      previousEndTime: json['previousEndTime'] != null
          ? DateTime.tryParse(json['previousEndTime'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'eventDocId': eventDocId,
      'flightSchoolId': flightSchoolId,
      'identifier': identifier,
      'status': status.name,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime.toIso8601String(),
      'displayName': displayName,
      'location': location,
      'team': team.map((t) => t.toMap()).toList(),
      'notes': notes,
      'role': role,
      'assignmentStatus': assignmentStatus.name,
      'planningPeriodId': planningPeriodId,
      'planningStage': planningStage,
      'seriesId': seriesId,
      'swapOffered': swapOffered,
      'swapRequestedBy': swapRequestedBy,
      'swapRequestedByName': swapRequestedByName,
      'isSwapOfferFromOther': isSwapOfferFromOther,
      'assignedUserId': assignedUserId,
      if (previousStartTime != null)
        'previousStartTime': previousStartTime!.toIso8601String(),
      if (previousEndTime != null)
        'previousEndTime': previousEndTime!.toIso8601String(),
    };
  }

  Event copyWith({
    String? id,
    String? eventDocId,
    String? flightSchoolId,
    String? identifier,
    EventStatusEnum? status,
    DateTime? startTime,
    DateTime? endTime,
    String? displayName,
    String? location,
    List<TeamMember>? team,
    String? notes,
    String? role,
    EventUserStatusEnum? assignmentStatus,
    String? planningPeriodId,
    int? planningStage,
    String? seriesId,
    bool? swapOffered,
    String? swapRequestedBy,
    String? swapRequestedByName,
    bool? isSwapOfferFromOther,
    String? assignedUserId,
    DateTime? previousStartTime,
    DateTime? previousEndTime,
  }) {
    return Event(
      id: id ?? this.id,
      eventDocId: eventDocId ?? this.eventDocId,
      flightSchoolId: flightSchoolId ?? this.flightSchoolId,
      identifier: identifier ?? this.identifier,
      status: status ?? this.status,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      displayName: displayName ?? this.displayName,
      location: location ?? this.location,
      team: team ?? this.team,
      notes: notes ?? this.notes,
      role: role ?? this.role,
      assignmentStatus: assignmentStatus ?? this.assignmentStatus,
      planningPeriodId: planningPeriodId ?? this.planningPeriodId,
      planningStage: planningStage ?? this.planningStage,
      seriesId: seriesId ?? this.seriesId,
      swapOffered: swapOffered ?? this.swapOffered,
      swapRequestedBy: swapRequestedBy ?? this.swapRequestedBy,
      swapRequestedByName: swapRequestedByName ?? this.swapRequestedByName,
      isSwapOfferFromOther: isSwapOfferFromOther ?? this.isSwapOfferFromOther,
      assignedUserId: assignedUserId ?? this.assignedUserId,
      previousStartTime: previousStartTime ?? this.previousStartTime,
      previousEndTime: previousEndTime ?? this.previousEndTime,
    );
  }
}

class TeamMember {
  final String? assignmentId;
  final String userId;
  final String name;
  final String avatarUrl;
  final String role;
  final String status;
  final bool swapOffered;
  final String? swapRequestedBy;
  final String? swapRequestedByName;

  const TeamMember({
    this.assignmentId,
    required this.userId,
    required this.name,
    this.avatarUrl = '',
    required this.role,
    required this.status,
    this.swapOffered = false,
    this.swapRequestedBy,
    this.swapRequestedByName,
  });

  String get roleLabel => EventRoleEnum.displayLabel(role);

  bool get hasOpenSwapRequest =>
      swapOffered && (swapRequestedBy != null && swapRequestedBy!.isNotEmpty);

  factory TeamMember.fromMap(Map<String, dynamic> map) {
    return TeamMember(
      assignmentId: (map['\$id'] ?? map['assignmentId'])?.toString(),
      userId: (map['user_id'] ?? map['userId'] ?? '').toString(),
      name: (map['name'] ?? map['display_name'] ?? '').toString(),
      avatarUrl: (map['avatar_url'] ?? map['avatarUrl'] ?? '').toString(),
      role: (map['role'] ?? '').toString(),
      status: (map['status'] ?? '').toString(),
      swapOffered: map['swap_offered'] == true || map['swapOffered'] == true,
      swapRequestedBy: (map['swap_requested_by'] ?? map['swapRequestedBy'])?.toString(),
      swapRequestedByName:
          (map['swap_requested_by_name'] ?? map['swapRequestedByName'])?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (assignmentId != null) 'assignmentId': assignmentId,
      'user_id': userId,
      'name': name,
      if (avatarUrl.isNotEmpty) 'avatar_url': avatarUrl,
      'role': role,
      'status': status,
      'swap_offered': swapOffered,
      if (swapRequestedBy != null) 'swap_requested_by': swapRequestedBy,
      if (swapRequestedByName != null)
        'swap_requested_by_name': swapRequestedByName,
    };
  }

  TeamMember copyWith({
    String? assignmentId,
    String? userId,
    String? name,
    String? avatarUrl,
    String? role,
    String? status,
    bool? swapOffered,
    String? swapRequestedBy,
    String? swapRequestedByName,
    bool clearSwap = false,
  }) {
    return TeamMember(
      assignmentId: assignmentId ?? this.assignmentId,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      role: role ?? this.role,
      status: status ?? this.status,
      swapOffered: clearSwap ? false : (swapOffered ?? this.swapOffered),
      swapRequestedBy: clearSwap ? null : (swapRequestedBy ?? this.swapRequestedBy),
      swapRequestedByName:
          clearSwap ? null : (swapRequestedByName ?? this.swapRequestedByName),
    );
  }

  bool get isSlot => userId.isEmpty || userId.startsWith('slot_');

  EventUserStatusEnum? get statusEnum {
    try {
      return EventUserStatusEnum.values.byName(status);
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TeamMember &&
        other.assignmentId == assignmentId &&
        other.userId == userId &&
        other.name == name &&
        other.role == role &&
        other.status == status &&
        other.swapOffered == swapOffered &&
        other.swapRequestedBy == swapRequestedBy;
  }

  @override
  int get hashCode => Object.hash(
        assignmentId,
        userId,
        name,
        role,
        status,
        swapOffered,
        swapRequestedBy,
      );
}
