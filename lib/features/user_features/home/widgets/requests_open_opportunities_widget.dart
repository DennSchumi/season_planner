import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planer/data/enums/event_status_enum.dart';
import 'package:season_planer/data/enums/membership_status_enum.dart';
import 'package:season_planer/data/models/event_model.dart';
import 'package:season_planer/data/models/user_models/flight_school_model_user_view.dart';
import 'package:season_planer/features/user_features/home/widgets/event_detail_view.dart';
import 'package:season_planer/services/providers/user_provider.dart';

import '../../../../data/enums/event_user_status_enum.dart';
import 'event_card_tile_widget.dart';

class RequestsOpportunitiesWidget extends StatelessWidget {
  final List<Event> events;

  const RequestsOpportunitiesWidget({super.key, required this.events});

  String _getTypeLabel(Event event) {
    switch (event.assignmentStatus) {
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

  Color _getTypeColor(Event event) {
    switch (event.assignmentStatus) {
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

  IconData _getTypeIcon(Event event) {
    switch (event.assignmentStatus) {
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

    final visibleEvents = events.where((event) {
      final fs = fsById[event.flightSchoolId];
      if (fs == null) return false;

      if (fs.membershipStatus != MembershipStatusEnum.active) return false;

      return fs.availableRoles.contains(event.role);
    }).toList();

    if (visibleEvents.isEmpty) {
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
      itemCount: visibleEvents.length,
      itemBuilder: (context, index) {
        final event = visibleEvents[index];
        final fs = fsById[event.flightSchoolId];

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Stack(
            children: [
              EventCardTile(
                event: event,
                flightSchool: fs,
                dateText:
                '${_formatDate(event.startTime)} – ${_formatDate(event.endTime)}',
                status: event.status,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EventDetailView(event: event),
                    ),
                  );
                },
              ),
              if (event.assignmentStatus != EventUserStatusEnum.pending_flight_school)
                Positioned(
                  right: 10,
                  top: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getTypeColor(event).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _getTypeColor(event)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getTypeIcon(event),
                          size: 14,
                          color: _getTypeColor(event),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _getTypeLabel(event),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _getTypeColor(event),
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