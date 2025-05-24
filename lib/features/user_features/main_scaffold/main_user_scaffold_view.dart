import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:season_planer/features/user_features/current_event/current_event_view.dart';


import '../../../data/models/user_model.dart';
import '../../../services/database_service.dart';
import '../../../services/user_provider.dart';
import '../account/account_view.dart';
import '../calender/calender_view.dart';
import '../home/home_view.dart';

class MainUserScaffoldView extends StatefulWidget{
   int? selected_index;

  MainUserScaffoldView(
  {
 super.key,
this.selected_index
});

  @override
  _MainUserScaffoldState createState() => _MainUserScaffoldState();
}
class _MainUserScaffoldState extends State<MainUserScaffoldView>{
  int _selectedIndex = 0;

  List<Widget> _widgetList = <Widget>[
    HomeView(),
    CurrentEventView(),
    CalenderView(),
    AccountView()
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
    final user = Provider.of<UserProvider>(context).user;


    if (user == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: Center(child: _widgetList.elementAt(_selectedIndex)),
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