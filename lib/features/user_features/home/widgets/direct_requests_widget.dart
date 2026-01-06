import 'package:flutter/material.dart';
import 'package:season_planer/data/enums/event_status_enum.dart';
import 'package:season_planer/data/models/event_model.dart';
import 'package:season_planer/features/user_features/home/widgets/event_detail_view.dart';

import 'event_card_tile_widget.dart';
class DirectRequestsWidget extends StatelessWidget {
  final List<Event> events;

  const DirectRequestsWidget({super.key, required this.events});

  Color _getStatusColor(Event event) {
    switch (event.status) {
      case EventStatusEnum.scheduled:
        return Colors.green;
      case EventStatusEnum.provisional:
        return Colors.orange;
      case EventStatusEnum.canceled:
        return Colors.red;
      default:
        return Colors.white;
    }
  }

  String _formatDate(DateTime date) => '${date.day}.${date.month}.${date.year}';

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
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
                children: events.map((event) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: EventCardTile(
                      event: event,
                      flightSchool: null, // hier bewusst kein FS-Logo
                      dateText:
                      '${_formatDate(event.startTime)} – ${_formatDate(event.endTime)}',
                      statusColor: _getStatusColor(event),
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
