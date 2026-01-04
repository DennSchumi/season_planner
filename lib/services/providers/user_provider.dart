import 'package:flutter/material.dart';

import '../../data/models/event_model.dart';
import '../../data/models/user_models/user_model_userView.dart';

class UserProvider with ChangeNotifier {
  UserModelUserView? _user;

  UserModelUserView? get user => _user;

  void setUser(UserModelUserView user) {
    _user = user;
    notifyListeners();
  }

  void clearUser() {
    _user = null;
    notifyListeners();
  }

  void updateEvents(List<Event> events) {
    if (_user == null) return;
    _user = _user!.copyWith(events: events);
    notifyListeners();
  }

}
