import 'package:flutter/material.dart';

import '../data/models/event_model.dart';
import '../data/models/user_model.dart';

class UserProvider with ChangeNotifier {
  UserModel? _user;

  UserModel? get user => _user;

  void setUser(UserModel user) {
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
