import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/features/user_features/current_event/current_event_view.dart';
import '../../../data/models/user_models/user_model_userView.dart';
import '../../../services/database_service.dart';
import '../../../services/providers/user_provider.dart';
import '../account/account_view.dart';
import '../calender/calender_view.dart';
import '../home/home_view.dart';

class MainUserScaffoldView extends StatefulWidget {
  final int? selected_index;

  MainUserScaffoldView({super.key, this.selected_index});

  @override
  _MainUserScaffoldState createState() => _MainUserScaffoldState();
}

class _MainUserScaffoldState extends State<MainUserScaffoldView> {
  int _selectedIndex = 0;
  Timer? _refreshTimer;
  DateTime? _lastUpdated;
  bool _isLoading = false;
  bool _hasConnection = true;

  List<Widget> get widgetList => <Widget>[
    HomeView(
      isLoading: _isLoading,
      hasConnection: _hasConnection,
      lastUpdated: _lastUpdated,
    ),
    CurrentEventView(
      isLoading: _isLoading,
      hasConnection: _hasConnection,
      lastUpdated: _lastUpdated,
    ),
    CalenderView(
      isLoading: _isLoading,
      hasConnection: _hasConnection,
      lastUpdated: _lastUpdated,
    ),
    AccountView(),
  ];


  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.selected_index ?? 0;
    _loadUser();

    _refreshTimer = Timer.periodic(Duration(seconds: 60), (timer) {
      _loadUser();
    });
  }

  Future<void> _loadUser() async {
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
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body:  widgetList[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'HOME'),
          BottomNavigationBarItem(icon: Icon(Icons.access_time_outlined), label: 'EVENT'),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: 'KALENDER'),
          BottomNavigationBarItem(icon: Icon(Icons.account_circle_outlined), label: 'USER'),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.amber[800],
        onTap: _onItemTapped,
      ),
    );
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

}
