import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../../../data/models/user_model.dart';
import '../../../services/database_service.dart';
import '../../../services/flight_school_provider.dart';
import '../../../services/user_provider.dart';

class MainAdminScaffoldView extends StatefulWidget{
   int? selected_index;

  MainAdminScaffoldView(
  {
   super.key,
  this.selected_index
});

  @override
  _MainAdminScaffoldState createState() => _MainAdminScaffoldState();
}
class _MainAdminScaffoldState extends State<MainAdminScaffoldView>{
  int _selectedIndex = 0;


  List<Widget> _widgetList = <Widget>[

  ];

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.selected_index?? 0;
    _loadUser();
  }


  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }
  Future<void> _loadUser() async {
    try {
      final user = await _getUserInformation();
      if (user != null) {
        Provider.of<UserProvider>(context, listen: false).setUser(user);
      }
    } catch (e) {
      print('Fehler: $e');
    }
  }


  Future<UserModel?> _getUserInformation() {
  return DatabaseService().getUserInformation();
}
  @override
  Widget build(BuildContext context) {
    final flight_school_provider = Provider.of<FlightSchoolProvider>(context);
    final user_provider = Provider.of<UserProvider>(context).user;
    if (user_provider == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: Center(child: Text(flight_school_provider.flightSchool!.displayName)),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'HOME'),
          BottomNavigationBarItem(icon: Icon(Icons.access_time_outlined), label: 'EVENT'),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: 'KALENDER'),
          BottomNavigationBarItem(icon: Icon(Icons.account_circle_outlined), label: 'BENUTZER'),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.amber[800],
        onTap: _onItemTapped,
      ),
    );
  }

}