import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planer/data/enums/event_user_status_enum.dart';
import 'package:season_planer/features/user_features/home/widgets/direct_requests_widget.dart';
import 'package:season_planer/features/user_features/home/widgets/flight_school_selector_widget.dart';
import 'package:season_planer/features/user_features/home/widgets/open_opportunities_widget.dart';
import 'package:season_planer/features/user_features/home/widgets/your_events_widget.dart';
import 'package:season_planer/services/database_service.dart';
import 'package:season_planer/services/user_provider.dart';

import '../../../data/models/event_model.dart';

class HomeView extends StatefulWidget {
  @override
  _HomeViewState createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  Set<String> selectedFlightSchools = {};

  @override
  void initState() {
    super.initState();
    DatabaseService().getUserInformation();
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<UserProvider>(context).user;

    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if(user.flightSchools.length == 1) selectedFlightSchools.add(user.flightSchools[0].id);

    final List<Event> publicRequests = [];
    final List<Event> acceptedEvents = [];
    final List<Event> pendingOrRequestedEvents = [];
    DateTime date_time_now = DateTime.now();

    for (final event in user.events) {
      if (!event.startTime.isBefore(date_time_now) && selectedFlightSchools.contains(event.flightSchoolId)) {
        switch (event.assignmentStatus) {
          case EventUserStatusEnum.open:
            publicRequests.add(event);
            break;
          case EventUserStatusEnum.accepted_user:
          case EventUserStatusEnum.aceppted_flight_school:
            acceptedEvents.add(event);
            break;
          case EventUserStatusEnum.pending_flight_school:
          case EventUserStatusEnum.pending_user:
          case EventUserStatusEnum.denied_flight_school:
          case EventUserStatusEnum.denied_user:
            pendingOrRequestedEvents.add(event);
            break;
        }
      }
    }

    return Scaffold(
      body: SafeArea(
        minimum: EdgeInsets.symmetric(vertical: 10.0, horizontal: 10.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Text(
                'Hallo ${user.name ?? "Gast"}',
                style: TextStyle(fontSize: 15),
              ),
            ),
            SizedBox(height: 10,),
            if(user.flightSchools.length>1)
            FlightSchoolSelector(
              flightSchools: user.flightSchools,
              onSelectionChanged: (Set<String> selected) {
                setState(() {
                  selectedFlightSchools = selected;
                });
              },
            ),

            Divider(),
            YourEventsWidget(events: acceptedEvents),
            Divider(),
            DirectRequestsWidget(events: pendingOrRequestedEvents),
            Divider(),
            OpenOpportunitiesWidget(events: publicRequests),
          ],
        ),
      ),
    );
  }
}
