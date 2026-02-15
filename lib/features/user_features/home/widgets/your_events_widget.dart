import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/data/enums/event_status_enum.dart';
import 'package:season_planner/data/models/event_model.dart';
import 'package:season_planner/data/models/user_models/flight_school_model_user_view.dart';
import 'package:season_planner/features/user_features/home/widgets/event_detail_view.dart';

import '../../../../services/providers/user_provider.dart';
import 'event_card_tile_widget.dart';

class YourEventsWidget extends StatelessWidget {
  final List<Event> events;

  const YourEventsWidget({super.key, required this.events});



  String _formatDate(DateTime date) => '${date.day}.${date.month}.${date.year}';

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final user = userProvider.user;

    if (user == null) {
      return const SizedBox(
        height: 180,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final flightSchools = user.flightSchools;

    final Map<String, FlightSchoolUserView> fsById = {
      for (final fs in flightSchools) fs.id: fs,
    };

    if (events.isEmpty) {
      return const SizedBox(
        height: 50,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: events.map((event) {
                  final fs = fsById[event.flightSchoolId];

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: EventCardTile(
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