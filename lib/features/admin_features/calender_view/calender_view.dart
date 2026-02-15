
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/services/providers/flight_school_provider.dart';

import '../../../services/providers/user_provider.dart';
import '../../widgets/calender_widget.dart';

class CalenderViewFlightSchool extends StatefulWidget{
  final bool isLoading;
  final bool hasConnection;
  final DateTime? lastUpdated;

  const CalenderViewFlightSchool({super.key, this.isLoading = false,
    this.hasConnection = true,
    this.lastUpdated,});


  @override
  _CalenderViewFlightSchool createState() => _CalenderViewFlightSchool();
}

class _CalenderViewFlightSchool extends State<CalenderViewFlightSchool>{


  @override
  Widget build(BuildContext context){
    final fs = context.watch<FlightSchoolProvider>().flightSchool!;
    final fsById = { fs.id };

    return Scaffold(
      appBar: AppBar(
        title: const Text("Calender"),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: widget.isLoading
                ? const Icon(Icons.sync, color: Colors.blue)
                : widget.hasConnection
                ? const Icon(Icons.check_circle, color: Colors.green)
                : const Icon(Icons.error, color: Colors.red),
            onPressed: () {
              if (widget.lastUpdated == null) return;

              final time = '${widget.lastUpdated!.hour.toString().padLeft(2, '0')}:${widget.lastUpdated!.minute.toString().padLeft(2, '0')}';

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    widget.hasConnection
                        ? 'Last update: $time'
                        : 'Offline · Last update: $time',
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body:SafeArea(child:  Center(
        child: Column(
          children: [

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