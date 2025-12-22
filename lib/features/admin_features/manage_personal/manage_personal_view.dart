import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:season_planer/data/models/user_models/flight_school_model_user_view.dart';
import 'package:season_planer/services/flight_school_provider.dart';

class ManagePersonalView extends StatefulWidget{

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