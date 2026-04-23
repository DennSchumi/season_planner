import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/core/data/enums/event_user_status_enum.dart';
import 'package:season_planner/core/data/enums/membership_status_enum.dart';
import 'package:season_planner/user/data/models/flight_school_model_user_view.dart';
import 'package:season_planner/user/features/home/widgets/event_detail_view.dart';
import 'package:season_planner/user/user_provider.dart';
import 'package:season_planner/core/data/models/event_assigment_model.dart';
import 'event_card_tile_widget.dart';

class RequestsOpportunitiesWidget extends StatelessWidget {
  final List<EventAssignment> assignments;

  const RequestsOpportunitiesWidget({
    super.key,
    required this.assignments,
  });

  String _getTypeLabel(EventAssignment assignment) {
    switch (assignment.status) {
      case EventUserStatusEnum.open:
        return 'Open Opportunity';
      case EventUserStatusEnum.pending_user:
      case EventUserStatusEnum.pending_flight_school:
        return 'Direct Request';
      case EventUserStatusEnum.denied_user:
      case EventUserStatusEnum.denied_flight_school:
        return 'Denied';
      default:
        return 'Request';
    }
  }

  Color _getTypeColor(EventAssignment assignment) {
    switch (assignment.status) {
      case EventUserStatusEnum.open:
        return Colors.blue;
      case EventUserStatusEnum.pending_user:
      case EventUserStatusEnum.pending_flight_school:
        return Colors.orange;
      case EventUserStatusEnum.denied_user:
      case EventUserStatusEnum.denied_flight_school:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getTypeIcon(EventAssignment assignment) {
    switch (assignment.status) {
      case EventUserStatusEnum.open:
        return Icons.public;
      case EventUserStatusEnum.pending_user:
      case EventUserStatusEnum.pending_flight_school:
        return Icons.notifications_active;
      case EventUserStatusEnum.denied_user:
      case EventUserStatusEnum.denied_flight_school:
        return Icons.block;
      default:
        return Icons.help_outline;
    }
  }

  String _formatDate(DateTime date) =>
      '${date.day}.${date.month}.${date.year}';

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserProvider>().user;

    if (user == null) {
      return const SizedBox(
        height: 180,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final Map<String, FlightSchoolUserView> fsById = {
      for (final fs in user.flightSchools) fs.id: fs,
    };

    final visibleAssignments = assignments.where((assignment) {
      final event = assignment.event;
      final fs = fsById[event.flightSchoolId];
      if (fs == null) return false;

      if (fs.membershipStatus != MembershipStatusEnum.active) return false;

      return fs.availableRoles.contains(assignment.role);
    }).toList();

    if (visibleAssignments.isEmpty) {
      return const SizedBox(
        height: 70,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Text('No events found')),
          ],
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      itemCount: visibleAssignments.length,
      itemBuilder: (context, index) {
        final assignment = visibleAssignments[index];
        final event = assignment.event;
        final fs = fsById[event.flightSchoolId];

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Stack(
            children: [
              EventCardTile(
                assignment: assignment,
                flightSchool: fs,
                dateText:
                '${_formatDate(event.startTime)} – ${_formatDate(event.endTime)}',
                status: event.status,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EventDetailView(
                        assignment: assignment,
                      ),
                    ),
                  );
                },
              ),
              if (assignment.status != EventUserStatusEnum.pending_flight_school)
                Positioned(
                  right: 10,
                  top: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _getTypeColor(assignment).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _getTypeColor(assignment)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getTypeIcon(assignment),
                          size: 14,
                          color: _getTypeColor(assignment),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _getTypeLabel(assignment),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _getTypeColor(assignment),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}