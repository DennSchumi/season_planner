import 'package:flutter/material.dart';
import 'package:season_planer/data/enums/event_status_enum.dart';
import 'package:season_planer/data/models/event_model.dart';
import 'package:season_planer/features/user_features/home/widgets/event_detail_view.dart';

class YourEventsWidget extends StatelessWidget {
  final List<Event> events;

  const YourEventsWidget({super.key, required this.events});

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

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return  SizedBox(
        height: 50,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text('Your upcoming Events'),
            ],),
            Center(
              child:Text('No events found'),

            )
          ],
        ),
      );
    }
    return SizedBox(
      height: 180,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Your upcoming Events'),
          const SizedBox(height: 10),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...events.map(
                        (event) => Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Card(
                        elevation: 2,
                        child: ListTile(
                          title: Text(event.displayName),
                          subtitle: Text(
                            '${_formatDate(event.startTime)} – ${_formatDate(event.endTime)}',
                          ),
                          leading: const Icon(Icons.event_available),
                          trailing: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: _getStatusColor(event),
                              shape: BoxShape.circle,
                            ),
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    EventDetailView(event: event),
                              ),
                            );
                          },
                        ),
                      ),
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

  String _formatDate(DateTime date) {
    return '${date.day}.${date.month}.${date.year}';
  }
}
