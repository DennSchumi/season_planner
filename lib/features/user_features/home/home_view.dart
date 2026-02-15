import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/data/enums/event_user_status_enum.dart';
import 'package:season_planner/features/user_features/home/widgets/flight_school_selector_widget.dart';
import 'package:season_planner/features/user_features/home/widgets/requests_open_opportunities_widget.dart';
import 'package:season_planner/features/user_features/home/widgets/your_events_widget.dart';
import 'package:season_planner/services/database_service.dart';
import 'package:season_planner/services/providers/user_provider.dart';

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
  State<HomeView> createState() => _HomeViewState();
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
    final user = context.watch<UserProvider>().user;

    if (user == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (user.flightSchools.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(
            'Hello ${user.name ?? "Guest"}',
            style: const TextStyle(fontSize: 22),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.flight_outlined,
                  size: 70,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 20),
                const Text(
                  "You are not assigned to any flight school yet.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  "Please contact an Flight School Administrator to gain Access",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!_initializedSelection) {
      selectedFlightSchools =
          user.flightSchools.map((fs) => fs.id).toSet();
      _initializedSelection = true;
    }

    final List<Event> publicRequests = [];
    final List<Event> acceptedEvents = [];
    final List<Event> pendingOrRequestedEvents = [];
    final List<Event> userChangeRequests = [];

    final now = DateTime.now();

    for (final event in user.events) {
      if (!event.startTime.isBefore(now) &&
          selectedFlightSchools.contains(event.flightSchoolId)) {
        switch (event.assignmentStatus) {
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

          case EventUserStatusEnum.open:
            publicRequests.add(event);
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
              child: Text(
                'Hello ${user.name ?? "Guest"}',
                style: const TextStyle(fontSize: 22),
              ),
            ),
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
                  const TabBar(
                    tabs: tabs,
                    isScrollable: false,
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        YourEventsWidget(
                          events: [
                            ...acceptedEvents,
                            ...userChangeRequests
                          ],
                        ),
                        RequestsOpportunitiesWidget(
                          events: [
                            ...pendingOrRequestedEvents,
                            ...publicRequests
                          ],
                        ),
                      ],
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
}
