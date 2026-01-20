import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:season_planer/data/enums/event_user_status_enum.dart';
import 'package:season_planer/features/user_features/home/widgets/flight_school_selector_widget.dart';
import 'package:season_planer/features/user_features/home/widgets/requests_open_opportunities_widget.dart';
import 'package:season_planer/features/user_features/home/widgets/your_events_widget.dart';
import 'package:season_planer/services/database_service.dart';
import 'package:season_planer/services/providers/user_provider.dart';

import '../../../data/models/event_model.dart';

class HomeView extends StatefulWidget {
  final bool isLoading;
  final bool hasConnection;
  final DateTime? lastUpdated;

  const HomeView({
    super.key,
    required this.isLoading,
    required this.hasConnection,
    required this.lastUpdated,
  });

  @override
  _HomeViewState createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  Set<String> selectedFlightSchools = {};
  bool _initializedSelection = false;

  static const List<Tab> tabs = <Tab>[
    Tab(text: 'Your Events'),
    Tab(text: 'Requests & Opportunities'),
  ];

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

    if (!_initializedSelection) {
      selectedFlightSchools = user.flightSchools.map((fs) => fs.id).toSet();
      _initializedSelection = true;
    }

    final List<Event> publicRequests = [];
    final List<Event> acceptedEvents = [];
    final List<Event> pendingOrRequestedEvents = [];
    final List<Event> userChangeRequests = [];
    DateTime dateTimeNow = DateTime.now();

    for (final event in user.events) {
      if (!event.startTime.isBefore(dateTimeNow) && selectedFlightSchools.contains(event.flightSchoolId)) {
        switch (event.assignmentStatus) {
          case EventUserStatusEnum.open:
            publicRequests.add(event);
            break;
          case EventUserStatusEnum.accepted_user:
          case EventUserStatusEnum.accepted_flight_school:
            acceptedEvents.add(event);
            break;
          case EventUserStatusEnum.user_requests_change:
            userChangeRequests.add(event);
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
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            Expanded(
              child:  Text(
                  'Hallo ${user.name ?? "Gast"}',
                  style: TextStyle(fontSize: 22),
                ),

            ),

            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: widget.isLoading
                      ? const Icon(Icons.sync, color: Colors.blue)
                      : widget.hasConnection
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : const Icon(Icons.error, color: Colors.red),
                  tooltip: 'Connection Info',
                  onPressed: () {
                    final message = widget.isLoading
                        ? 'Loading latest data...'
                        : widget.hasConnection
                        ? 'Last updated at ${widget.lastUpdated != null ? '${widget.lastUpdated!.hour.toString().padLeft(2, '0')}:${widget.lastUpdated!.minute.toString().padLeft(2, '0')}' : 'unknown'}'
                        : 'No connection. Last update was at ${widget.lastUpdated != null ? '${widget.lastUpdated!.hour.toString().padLeft(2, '0')}:${widget.lastUpdated!.minute.toString().padLeft(2, '0')}' : 'unknown'}';

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(message),
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  },
                ),
              ],
            ),

            Padding(
              padding: const EdgeInsets.only(right: 12.0),
              child: Stack(
                alignment: Alignment.topRight,
                children: [
                  IconButton(
                    iconSize: 30,
                    icon: const Icon(Icons.notifications_none),
                    tooltip: 'Notifications',
                    onPressed: () {
                      // TODO: Open notifications page/dialog
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('No notifications yet.')),
                      );
                    },
                  ),
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: const Text(
                        '1', //TODO:Variable for count
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (user.flightSchools.length > 1)
            Padding(
              padding: const EdgeInsets.all(10.0),
              child: FlightSchoolSelector(
                flightSchools: user.flightSchools,
                onSelectionChanged: (Set<String> selected) {
                  setState(() {
                    selectedFlightSchools = selected;
                  });
                },
              ),
            ),
          Expanded(
            child: DefaultTabController(
              length: tabs.length,
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.center,
                    child: TabBar(
                      tabs: tabs,
                      isScrollable: false,
                    ),
                  ),

                  Expanded(
                    child: TabBarView(
                      children: [
                        YourEventsWidget(
                          events: [...acceptedEvents, ...userChangeRequests],
                        ),
                        RequestsOpportunitiesWidget(events: [...pendingOrRequestedEvents, ...publicRequests]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}