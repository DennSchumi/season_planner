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
}