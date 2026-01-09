
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planer/services/providers/flight_school_provider.dart';

import '../../../services/providers/user_provider.dart';
import '../../widgets/calender_widget.dart';

class CalenderViewFlightSchool extends StatefulWidget{
  const CalenderViewFlightSchool({super.key});

  @override
  _CalenderViewFlightSchool createState() => _CalenderViewFlightSchool();
}

class _CalenderViewFlightSchool extends State<CalenderViewFlightSchool>{


  @override
  Widget build(BuildContext context){
    final fs = context.watch<FlightSchoolProvider>().flightSchool!;
    final fsById = { fs.id };

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
            Expanded(
                child: EventsCalendar(
              events: fs!.events ?? const [],
              flightSchoolById: (_) => fs,
              showFlightSchool: false,
              //onEventTap: (e) => Navigator.push(),
            ) )

          ],
        ),
      ),
    ));
  }
}