import 'package:flutter/cupertino.dart';
import 'package:season_planer/data/models/flight_school_model.dart';

class FlightSchoolProvider with ChangeNotifier{
  FlightSchool? _flightSchool;

  FlightSchool? get flightSchool => _flightSchool;

  void setFlightSchool(FlightSchool flightSchool){
    _flightSchool = flightSchool;
    notifyListeners();
  }

  void clearFlightSchool(){
    _flightSchool = null;
    notifyListeners();
  }

}