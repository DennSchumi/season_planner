import 'package:season_planner/core/data/enums/application_status_enum.dart';

class PositionApplication {
  final String id;
  final String userId;
  final String teamAssignmentEventId;
  final ApplicationStatusEnum status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const PositionApplication({
    required this.id,
    required this.userId,
    required this.teamAssignmentEventId,
    required this.status,
    this.createdAt,
    this.updatedAt,
  });

  factory PositionApplication.fromMap(Map<String, dynamic> map) {
    return PositionApplication(
      id: (map['id'] ?? '').toString(),
      userId: (map['userId'] ?? '').toString(),
      teamAssignmentEventId: (map['teamAssignmentEventId'] ?? '').toString(),
      status: _parseStatus(map['status']),
      createdAt: _tryParseDate(map['createdAt']),
      updatedAt: _tryParseDate(map['updatedAt']),
    );
  }

  factory PositionApplication.fromJson(Map<String, dynamic> json) {
    return PositionApplication.fromMap(json);
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'teamAssignmentEventId': teamAssignmentEventId,
      'status': status.name,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  Map<String, dynamic> toJson() {
    return toMap();
  }

  PositionApplication copyWith({
    String? id,
    String? userId,
    String? teamAssignmentEventId,
    ApplicationStatusEnum? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PositionApplication(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      teamAssignmentEventId:
      teamAssignmentEventId ?? this.teamAssignmentEventId,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static PositionApplication empty() {
    return const PositionApplication(
      id: '',
      userId: '',
      teamAssignmentEventId: '',
      status: ApplicationStatusEnum.pending,
    );
  }

  static ApplicationStatusEnum _parseStatus(dynamic value) {
    final raw = (value ?? '').toString();

    try {
      return ApplicationStatusEnum.values.byName(raw);
    } catch (_) {
      return ApplicationStatusEnum.pending;
    }
  }

  static DateTime? _tryParseDate(dynamic value) {
    final raw = (value ?? '').toString();
    if (raw.isEmpty) return null;

    try {
      return DateTime.parse(raw);
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() {
    return 'PositionApplication('
        'id: $id, '
        'userId: $userId, '
        'teamAssignmentEventId: $teamAssignmentEventId, '
        'status: $status, '
        'createdAt: $createdAt, '
        'updatedAt: $updatedAt'
        ')';
  }
}