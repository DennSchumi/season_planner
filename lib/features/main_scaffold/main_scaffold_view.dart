import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:season_planer/core/AppState.dart';
import 'package:season_planer/data/models/user_model.dart';
import 'package:season_planer/features/account/account_view.dart';
import 'package:season_planer/features/calender/calender_view.dart';
import 'package:season_planer/features/home/home_view.dart';
import 'package:season_planer/services/database_service.dart';

class MainScaffoldView extends StatefulWidget{

  @override
  _MainScaffoldState createState() => _MainScaffoldState();

}
class _MainScaffoldState extends State<MainScaffoldView>{
  int _selectedIndex = 0;
  List<Widget> _widgetList = <Widget>[
    HomeView(),
    CalenderView(),
    AccountView()
  ];

  @override
  void initState() {
    super.initState();
  }


  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

/*UserModel getUserInformation(){
    return DatabaseService()
}*/
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(child: _widgetList.elementAt(_selectedIndex)),
      bottomNavigationBar: BottomNavigationBar(
          items: [
            BottomNavigationBarItem(icon: Icon(Icons.home),label: 'HOME'),
            BottomNavigationBarItem(icon: Icon(Icons.calendar_month),label:'KALENDER'),
            BottomNavigationBarItem(icon: Icon(Icons.account_circle_outlined),label:'BENUTZER')
          ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.amber[800],
        onTap: _onItemTapped,
      ),
    );
  }

}