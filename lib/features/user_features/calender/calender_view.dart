
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/enums/event_user_status_enum.dart';
import '../../../services/providers/user_provider.dart';
import '../../widgets/calender_widget.dart';
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
  _CalenderView createState() => _CalenderView();
}


class _CalenderView extends State<CalenderView>{

  @override
  Widget build(BuildContext context){
    final user = context.watch<UserProvider>().user!;
    final fsById = { for (final fs in user.flightSchools) fs.id: fs };
    final events = user.events
        .where((e) => e.assignmentStatus == EventUserStatusEnum.accepted_flight_school || e.assignmentStatus == EventUserStatusEnum.accepted_user)
        .toList();

    return Scaffold(
      body:SafeArea(child:  Center(
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Center(child:   Text(
                  'Calendar',
                  style: TextStyle(fontSize: 26),
                ),)),

                Row(
                  children: [
                    if (widget.isLoading)
                      Icon(Icons.sync, color: Colors.blue)
                    else if (widget.hasConnection)
                      Icon(Icons.check_circle, color: Colors.green)
                    else
                      Icon(Icons.error, color: Colors.red),
                    SizedBox(width: 8),
                    if (widget.lastUpdated != null)
                      Text(
                        widget.hasConnection
                            ? 'Updated: ${widget.lastUpdated!.hour.toString().padLeft(2, '0')}:${widget.lastUpdated!.minute.toString().padLeft(2, '0')}'
                            : 'No connection · Last: ${widget.lastUpdated!.hour.toString().padLeft(2, '0')}:${widget.lastUpdated!.minute.toString().padLeft(2, '0')}',
                        style: TextStyle(fontSize: 12, color: widget.hasConnection ? Colors.grey : Colors.redAccent),
                      )
                    else
                      Text(
                        'No data available',
                        style: TextStyle(fontSize: 12, color: Colors.redAccent),
                      ),
                  ],
                ),
              ],
            ),

            SizedBox(height: 16,),
            EventsCalendar(
              events:events,
              flightSchoolById: (id) => fsById[id],
              onEventTap: (e) {
                Navigator.push(context, MaterialPageRoute(builder: (_) => EventDetailView(event: e)));
              },
            )
          ],
        ),
      ),
    ));
  }
}