import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/core/data/enums/event_user_status_enum.dart';
import 'package:season_planner/core/data/models/event_assigment_model.dart';
import 'package:season_planner/user/features/home/widgets/application_change_widget.dart';
import 'package:season_planner/user/features/home/widgets/flight_school_selector_widget.dart';
import 'package:season_planner/user/features/home/widgets/requests_open_opportunities_widget.dart';
import 'package:season_planner/user/features/home/widgets/your_events_widget.dart';
import 'package:season_planner/user/user_provider.dart';

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
                  'You are not assigned to any flight school yet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Please contact a Flight School Administrator to gain access.',
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
      selectedFlightSchools = user.flightSchools.map((fs) => fs.id).toSet();
      _initializedSelection = true;
    }

    final acceptedEvents = <EventAssignment>[];
    final requestsAndOpportunities = <EventAssignment>[];
    final changeRequests = <EventAssignment>[];

    final now = DateTime.now();
    final seenAssignmentIds = <String>{};

    for (final assignment in user.assignments) {
      if (assignment.id.isNotEmpty && !seenAssignmentIds.add(assignment.id)) {
        continue;
      }

      final event = assignment.event;

      if (event.startTime.isBefore(now)) continue;
      if (!selectedFlightSchools.contains(event.flightSchoolId)) continue;

      switch (assignment.status) {
        case EventUserStatusEnum.accepted_user:
        case EventUserStatusEnum.accepted_flight_school:
          acceptedEvents.add(assignment);
          break;

        case EventUserStatusEnum.user_requests_change:
          changeRequests.add(assignment);
          break;

        case EventUserStatusEnum.pending_flight_school:
        case EventUserStatusEnum.pending_user:
        case EventUserStatusEnum.denied_flight_school:
        case EventUserStatusEnum.denied_user:
        case EventUserStatusEnum.open:
          requestsAndOpportunities.add(assignment);
          break;

        case EventUserStatusEnum.removed:
          break;
      }
    }

    acceptedEvents.sort(
          (a, b) => a.event.startTime.compareTo(b.event.startTime),
    );
    requestsAndOpportunities.sort(
          (a, b) => a.event.startTime.compareTo(b.event.startTime),
    );
    changeRequests.sort(
          (a, b) => a.event.startTime.compareTo(b.event.startTime),
    );

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
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(_connectionMessage()),
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
              padding: const EdgeInsets.all(10),
              child: FlightSchoolSelector(
                flightSchools: user.flightSchools,
                onSelectionChanged: (selected) {
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
                        _YourEventsTab(
                          acceptedEvents: acceptedEvents,
                          changeRequests: changeRequests,
                          applications: user.applications,
                          allAssignments: user.assignments,
                        ),
                        RequestsOpportunitiesWidget(
                          assignments: requestsAndOpportunities,
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

  String _connectionMessage() {
    final timeText = widget.lastUpdated == null
        ? 'unknown'
        : '${widget.lastUpdated!.hour.toString().padLeft(2, '0')}:'
        '${widget.lastUpdated!.minute.toString().padLeft(2, '0')}';

    if (widget.isLoading) return 'Loading latest data...';
    if (widget.hasConnection) return 'Last updated at $timeText';

    return 'No connection. Last update was at $timeText';
  }
}

class _YourEventsTab extends StatelessWidget {
  final List<EventAssignment> acceptedEvents;
  final List<EventAssignment> changeRequests;
  final List<dynamic> applications;
  final List<EventAssignment> allAssignments;

  const _YourEventsTab({
    required this.acceptedEvents,
    required this.changeRequests,
    required this.applications,
    required this.allAssignments,
  });

  @override
  Widget build(BuildContext context) {
    final hasAccepted = acceptedEvents.isNotEmpty;
    final hasChangesOrApplications =
        changeRequests.isNotEmpty || applications.isNotEmpty;

    if (!hasAccepted && !hasChangesOrApplications) {
      return const Center(
        child: Text(
          'No events found',
          style: TextStyle(color: Colors.black54),
        ),
      );
    }

    if (hasAccepted && !hasChangesOrApplications) {
      return YourEventsWidget(assignments: acceptedEvents);
    }

    if (!hasAccepted && hasChangesOrApplications) {
      return ApplicationsChangeRequestsWidget(
        changeRequests: changeRequests,
        applications: applications.cast(),
        allAssignments: allAssignments,
      );
    }

    return Column(
      children: [
        Expanded(
          child: YourEventsWidget(
            assignments: acceptedEvents,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ApplicationsChangeRequestsWidget(
            changeRequests: changeRequests,
            applications: applications.cast(),
            allAssignments: allAssignments,
          ),
        ),
      ],
    );
  }
}