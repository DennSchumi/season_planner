import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/data/enums/event_user_status_enum.dart';
import '../../user_provider.dart';
import 'package:season_planner/core/widgets/calender_widget.dart';
import '../home/widgets/event_detail_view.dart';

class CalenderView extends StatefulWidget {
  final bool isLoading;
  final bool hasConnection;
  final DateTime? lastUpdated;

  const CalenderView({
    super.key,
    required this.isLoading,
    required this.hasConnection,
    required this.lastUpdated,
  });

  @override
  State<CalenderView> createState() => _CalenderView();
}

class _CalenderView extends State<CalenderView> {
  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserProvider>().user;

    if (user == null) {
      return const Scaffold(
        body: SafeArea(
          child: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    final fsById = {
      for (final fs in user.flightSchools) fs.id: fs,
    };

    final assignments = user.assignments
        .where(
          (a) =>
      a.status == EventUserStatusEnum.accepted_flight_school ||
          a.status == EventUserStatusEnum.accepted_user,
    )
        .toList();

    final events = assignments.map((a) => a.event).toList();

    final assignmentByEventId = {
      for (final a in assignments) a.event.id: a,
    };

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Center(
                      child: Text(
                        'Calendar',
                        style: TextStyle(fontSize: 26),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      if (widget.isLoading)
                        const Icon(Icons.sync, color: Colors.blue)
                      else if (widget.hasConnection)
                        const Icon(Icons.check_circle, color: Colors.green)
                      else
                        const Icon(Icons.error, color: Colors.red),
                      const SizedBox(width: 8),
                      if (widget.lastUpdated != null)
                        Text(
                          widget.hasConnection
                              ? 'Updated: ${widget.lastUpdated!.hour.toString().padLeft(2, '0')}:${widget.lastUpdated!.minute.toString().padLeft(2, '0')}'
                              : 'No connection · Last: ${widget.lastUpdated!.hour.toString().padLeft(2, '0')}:${widget.lastUpdated!.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(
                            fontSize: 12,
                            color: widget.hasConnection
                                ? Colors.grey
                                : Colors.redAccent,
                          ),
                        )
                      else
                        const Text(
                          'No data available',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.redAccent,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: EventsCalendar(
                  events: events,
                  flightSchoolById: (id) => fsById[id],
                  onEventTap: (event) {
                    final assignment = assignmentByEventId[event.id];
                    if (assignment == null) return;

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
              ),
            ],
          ),
        ),
      ),
    );
  }
}