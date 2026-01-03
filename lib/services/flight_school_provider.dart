import 'package:flutter/cupertino.dart';
import 'package:season_planer/data/models/admin_models/flight_school_model_flight_school_view.dart';

class FlightSchoolProvider with ChangeNotifier{
  FlightSchoolModelFlightSchoolView? _flightSchool;

  FlightSchoolModelFlightSchoolView? get flightSchool => _flightSchool;

  void setFlightSchool(FlightSchoolModelFlightSchoolView flightSchool){
    _flightSchool = flightSchool;
    notifyListeners();
  }

  void clearFlightSchool(){
    _flightSchool = null;
    notifyListeners();
  }

}