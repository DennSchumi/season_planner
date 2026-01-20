import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planer/data/enums/event_user_status_enum.dart';
import 'package:season_planer/features/user_features/home/widgets/direct_requests_widget.dart';
import 'package:season_planer/features/user_features/home/widgets/flight_school_selector_widget.dart';
import 'package:season_planer/features/user_features/home/widgets/open_opportunities_widget.dart';
import 'package:season_planer/features/user_features/home/widgets/your_events_widget.dart';
import 'package:season_planer/services/database_service.dart';
import 'package:season_planer/services/providers/user_provider.dart';
import '../../../data/models/event_model.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  _HomeViewState createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  Set<String> selectedFlightSchools = {};
  bool _initializedSelection = false;
  Timer? _refreshTimer;
  DateTime? _lastUpdated;
  bool _isLoading = false;
  bool _hasConnection = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _refreshTimer = Timer.periodic(Duration(seconds: 10), (timer) {
      _loadUserData();
    });
  }

  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final user = await DatabaseService().getUserInformation();

      if (user != null) {
        Provider.of<UserProvider>(context, listen: false).setUser(user);
        setState(() {
          _lastUpdated = DateTime.now();
          _hasConnection = true;
        });
      } else {
        setState(() {
          _hasConnection = false;
        });
      }
    } catch (e) {
      setState(() {
        _hasConnection = false;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }


  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
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
          case EventUserStatusEnum.pending_flight_school:
          case EventUserStatusEnum.pending_user:
          case EventUserStatusEnum.denied_flight_school:
          case EventUserStatusEnum.user_requests_change:
          case EventUserStatusEnum.denied_user:
            pendingOrRequestedEvents.add(event);
            break;
        }
      }
    }

    return Scaffold(
      body: SafeArea(
        minimum: EdgeInsets.symmetric(vertical: 10.0, horizontal: 10.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Hello ${user.name ?? "Guest"}',
                    style: TextStyle(fontSize: 26),
                  ),
                  Row(
                    children: [
                      if (_isLoading)
                        Icon(Icons.sync, color: Colors.blue)
                      else if (_hasConnection)
                        Icon(Icons.check_circle, color: Colors.green)
                      else
                        Icon(Icons.error, color: Colors.red),
                      SizedBox(width: 8),
                      if (_hasConnection && _lastUpdated != null)
                        Text(
                          'Updated: ${_lastUpdated!.hour.toString().padLeft(2, '0')}:${_lastUpdated!.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        )
                      else if (!_hasConnection && _lastUpdated != null)
                        Text(
                          'No connection · Last update: ${_lastUpdated!.hour.toString().padLeft(2, '0')}:${_lastUpdated!.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(fontSize: 12, color: Colors.redAccent),
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
              SizedBox(height: 16),
              if (user.flightSchools.length > 1)
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
      ),
    );
  }
}