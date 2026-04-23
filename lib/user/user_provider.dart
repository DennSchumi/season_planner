import 'package:flutter/material.dart';
import 'package:season_planner/core/data/models/event_assigment_model.dart';
import 'package:season_planner/user/data/models/flight_school_model_user_view.dart';

import '../core/data/models/event_model.dart';
import 'data/models/user_model_userView.dart';

class UserProvider with ChangeNotifier {
  UserModelUserView? _user;

  UserModelUserView? get user => _user;

  List<FlightSchoolUserView> get userFlightSchools {
    return List<FlightSchoolUserView>.from(_user!.flightSchools);
  }

  void setUser(UserModelUserView user) {
    _user = user;
    notifyListeners();
  }

  void clearUser() {
    _user = null;
    notifyListeners();
  }

  void updateEvents(List<EventAssignment> eventAssignments) {
    if (_user == null) return;
    _user = _user!.copyWith(assignments: eventAssignments);
    notifyListeners();
  }

}
