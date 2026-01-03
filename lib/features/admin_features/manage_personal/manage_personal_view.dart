import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planer/services/flight_school_provider.dart';

class ManagePersonalView extends StatefulWidget{
  const ManagePersonalView({super.key});


  @override
  _ManagePersonalView createState() => _ManagePersonalView();
}

class _ManagePersonalView extends State<ManagePersonalView>{
  @override
  Widget build(BuildContext context) {
    final flightSchool = Provider.of<FlightSchoolProvider>(context).flightSchool;
    return Scaffold(
        body: Text(flightSchool.toString()),
    );
  }

}