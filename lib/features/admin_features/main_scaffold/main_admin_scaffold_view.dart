import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/features/admin_features/calender_view/calender_view.dart';
import 'package:season_planner/features/admin_features/manage_events_view/manage_events_view.dart';
import 'package:season_planner/features/admin_features/manage_flight_school_view/manage_flight_school_view.dart';
import 'package:season_planner/features/admin_features/manage_personal/manage_personal_view.dart';

import '../../../data/models/user_models/user_model_userView.dart';
import '../../../services/database_service.dart';
import '../../../services/providers/flight_school_provider.dart';
import '../../../services/providers/user_provider.dart';

class MainAdminScaffoldView extends StatefulWidget {
  final int? selected_index;

  const MainAdminScaffoldView({
    super.key,
    this.selected_index,
  });

  @override
  _MainAdminScaffoldState createState() => _MainAdminScaffoldState();
}

class _MainAdminScaffoldState extends State<MainAdminScaffoldView> {
  int _selectedIndex = 0;
  Timer? _refreshTimer;
  bool isLoading = false;
  bool hasConnection = true;
  DateTime? lastUpdated;


  List<Widget> get _widgetList => [
    ManageEventsView(
      isLoading: isLoading,
      hasConnection: hasConnection,
      lastUpdated: lastUpdated,
    ),
    ManagePersonalView(
      isLoading: isLoading,
      hasConnection: hasConnection,
      lastUpdated: lastUpdated,),
    CalenderViewFlightSchool(  isLoading: isLoading,
      hasConnection: hasConnection,
      lastUpdated: lastUpdated,),
    ManageFlightSchoolView(),
  ];


  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.selected_index ?? 0;
    _loadUser();
    _startAutoRefresh();
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Future<void> _loadUser() async {
    setState(() {
      isLoading = true;
    });

    try {
      final user = await _getUserInformation();
      if (user != null) {
        Provider.of<UserProvider>(context, listen: false).setUser(user);
        setState(() {
          hasConnection = true;
          lastUpdated = DateTime.now();
        });
      }
    } catch (e) {
      debugPrint('Fehler beim Laden des Users: $e');
      setState(() {
        hasConnection = false;
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }



  Future<UserModelUserView?> _getUserInformation() {
    return DatabaseService().getUserInformation();
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) => _loadUser());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context).user;

    if (userProvider == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: _widgetList[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.event), label: 'EVENTS'),
          BottomNavigationBarItem(icon: Icon(Icons.supervised_user_circle), label: 'PERSONAL'),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: 'KALENDER'),
          BottomNavigationBarItem(icon: Icon(Icons.account_circle_outlined), label: 'SCHOOL'),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.amber[800],
        onTap: _onItemTapped,
      ),
    );
  }
}
