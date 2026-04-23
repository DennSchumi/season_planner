import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/core/data/models/event_assigment_model.dart';
import 'package:season_planner/user/features/home/widgets/event_detail_view.dart';

import '../../../../user/data/models/flight_school_model_user_view.dart';
import '../../../user_provider.dart';
import 'event_card_tile_widget.dart';

class DirectRequestsWidget extends StatelessWidget {
  final List<EventAssignment> assignments;

  const DirectRequestsWidget({
    super.key,
    required this.assignments,
  });

  String _formatDate(DateTime date) => '${date.day}.${date.month}.${date.year}';

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

    if (assignments.isEmpty) {
      return const SizedBox(
        height: 70,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Direct Requests'),
            SizedBox(height: 10),
            Center(child: Text('No events found')),
          ],
        ),
      );
    }

    return SizedBox(
      height: 180,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Direct Requests'),
          const SizedBox(height: 10),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: assignments.map((assignment) {
                  final event = assignment.event;
                  final fs = fsById[event.flightSchoolId];

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: EventCardTile(
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
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}