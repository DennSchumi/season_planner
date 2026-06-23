import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/core/data/enums/application_status_enum.dart';
import 'package:season_planner/core/data/enums/event_user_status_enum.dart';
import 'package:season_planner/core/data/enums/membership_status_enum.dart';
import 'package:season_planner/core/data/models/event_application_model.dart';
import 'package:season_planner/core/data/models/event_assigment_model.dart';
import 'package:season_planner/user/data/models/flight_school_model_user_view.dart';
import 'package:season_planner/user/features/home/widgets/event_card_tile_widget.dart';
import 'package:season_planner/user/features/home/widgets/event_detail_view.dart';
import 'package:season_planner/user/user_provider.dart';

class ApplicationsChangeRequestsWidget extends StatelessWidget {
  final List<EventAssignment> changeRequests;
  final List<PositionApplication> applications;
  final List<EventAssignment> allAssignments;

  const ApplicationsChangeRequestsWidget({
    super.key,
    required this.changeRequests,
    required this.applications,
    required this.allAssignments,
  });

  String _formatDate(DateTime date) => '${date.day}.${date.month}.${date.year}';

  Color _badgeColorForChangeRequest() => Colors.purple;

  IconData _badgeIconForChangeRequest() => Icons.swap_horiz;

  String _badgeLabelForChangeRequest() => 'Change Request';

  Color _badgeColorForApplication(PositionApplication app) {
    switch (app.status) {
      case ApplicationStatusEnum.pending:
        return Colors.orange;
      case ApplicationStatusEnum.accepted:
        return Colors.green;
      case ApplicationStatusEnum.rejected:
        return Colors.red;
      case ApplicationStatusEnum.withdrawn:
        return Colors.grey;
    }
  }

  IconData _badgeIconForApplication(PositionApplication app) {
    switch (app.status) {
      case ApplicationStatusEnum.pending:
        return Icons.hourglass_top;
      case ApplicationStatusEnum.accepted:
        return Icons.check_circle_outline;
      case ApplicationStatusEnum.rejected:
        return Icons.block;
      case ApplicationStatusEnum.withdrawn:
        return Icons.undo;
    }
  }

  String _badgeLabelForApplication(PositionApplication app) {
    switch (app.status) {
      case ApplicationStatusEnum.pending:
        return 'Application Pending';
      case ApplicationStatusEnum.accepted:
        return 'Application Accepted';
      case ApplicationStatusEnum.rejected:
        return 'Application Rejected';
      case ApplicationStatusEnum.withdrawn:
        return 'Application Withdrawn';
    }
  }

  EventAssignment? _assignmentForApplication(PositionApplication app) {
    if (app.teamAssignmentEventId.isEmpty) return null;

    for (final assignment in allAssignments) {
      if (assignment.id == app.teamAssignmentEventId) {
        return assignment;
      }
    }

    return null;
  }

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

    final visibleChangeRequests = changeRequests.where((assignment) {
      final fs = fsById[assignment.event.flightSchoolId];
      if (fs == null) return false;
      return fs.membershipStatus == MembershipStatusEnum.active;
    }).toList();

    final applicationItems = applications
        .map((app) {
      final assignment = _assignmentForApplication(app);
      if (assignment == null) return null;

      final fs = fsById[assignment.event.flightSchoolId];
      if (fs == null) return null;
      if (fs.membershipStatus != MembershipStatusEnum.active) return null;

      return _ApplicationAssignmentItem(
        application: app,
        assignment: assignment,
      );
    })
        .whereType<_ApplicationAssignmentItem>()
        .toList();

    visibleChangeRequests.sort(
          (a, b) => a.event.startTime.compareTo(b.event.startTime),
    );

    applicationItems.sort(
          (a, b) => a.assignment.event.startTime.compareTo(
        b.assignment.event.startTime,
      ),
    );

    if (visibleChangeRequests.isEmpty && applicationItems.isEmpty) {
      return const Center(
        child: Text(
          'No applications or change requests found',
          style: TextStyle(color: Colors.black54),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        ...visibleChangeRequests.map((assignment) {
          final event = assignment.event;
          final fs = fsById[event.flightSchoolId];

          return _EventCardWithBadge(
            assignment: assignment,
            flightSchool: fs,
            dateText:
            '${_formatDate(event.startTime)} – ${_formatDate(event.endTime)}',
            badgeLabel: _badgeLabelForChangeRequest(),
            badgeColor: _badgeColorForChangeRequest(),
            badgeIcon: _badgeIconForChangeRequest(),
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
          );
        }),
        ...applicationItems.map((item) {
          final assignment = item.assignment;
          final application = item.application;
          final event = assignment.event;
          final fs = fsById[event.flightSchoolId];

          return _EventCardWithBadge(
            assignment: assignment,
            flightSchool: fs,
            dateText:
            '${_formatDate(event.startTime)} – ${_formatDate(event.endTime)}',
            badgeLabel: _badgeLabelForApplication(application),
            badgeColor: _badgeColorForApplication(application),
            badgeIcon: _badgeIconForApplication(application),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EventDetailView(
                    assignment: assignment,
                    application: application,
                  ),
                ),
              );
            },
          );
        }),
      ],
    );
  }
}

class _ApplicationAssignmentItem {
  final PositionApplication application;
  final EventAssignment assignment;

  const _ApplicationAssignmentItem({
    required this.application,
    required this.assignment,
  });
}

class _EventCardWithBadge extends StatelessWidget {
  final EventAssignment assignment;
  final FlightSchoolUserView? flightSchool;
  final String dateText;
  final String badgeLabel;
  final Color badgeColor;
  final IconData badgeIcon;
  final VoidCallback onTap;

  const _EventCardWithBadge({
    required this.assignment,
    required this.flightSchool,
    required this.dateText,
    required this.badgeLabel,
    required this.badgeColor,
    required this.badgeIcon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Stack(
        children: [
          EventCardTile(
            assignment: assignment,
            flightSchool: flightSchool,
            dateText: dateText,
            status: assignment.event.status,
            onTap: onTap,
          ),
          Positioned(
            right: 10,
            top: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: badgeColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: badgeColor),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    badgeIcon,
                    size: 14,
                    color: badgeColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    badgeLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: badgeColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}