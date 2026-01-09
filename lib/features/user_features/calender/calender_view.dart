
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/enums/event_user_status_enum.dart';
import '../../../services/providers/user_provider.dart';
import '../../widgets/calender_widget.dart';
import '../home/widgets/event_detail_view.dart';

class CalenderView extends StatefulWidget{
  const CalenderView({super.key});

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
            Center(
              child: Text(
                'Kalender',
                style: TextStyle(fontSize: 26),
              ),
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