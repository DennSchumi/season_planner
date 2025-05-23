import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:season_planer/services/database_service.dart';

class HomeView extends StatefulWidget{
  @override
  _HomeViewState createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView>{

  @override
  void initState() {
    super.initState();
    DatabaseService().getUserInformation();
  }

  @override
  Widget build(BuildContext context){
    return Scaffold(
      body: Center(
        child: Text("Home"),
      ),
    );
  }
}