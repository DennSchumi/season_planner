import 'package:flutter/material.dart';
import 'package:season_planner/user/data/models/flight_school_model_user_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/data/models/event_model.dart';
import 'data/models/user_model_userView.dart';

class UserProvider with ChangeNotifier {
  UserModelUserView? _user;
  int _selectedTabIndex = 0;

  /// Persistierte Flugschul-Filterauswahl für Start, Kalender & Wichtiges.
  /// `null` bedeutet: noch nicht explizit angepasst -> alle Flugschulen aktiv.
  Set<String>? _selectedFlightSchoolIds;
  String _loadedFilterUserId = '';
  bool _includeArchive = false;

  UserModelUserView? get user => _user;
  int get selectedTabIndex => _selectedTabIndex;
  bool get includeArchive =>
      _includeArchive || (_user?.hasLoadedArchive ?? false);

  void setIncludeArchive(bool value) {
    if (_includeArchive == value) return;
    _includeArchive = value;
    notifyListeners();
  }

  /// Übernimmt ein selektives Teil-Update (z. B. nur Events oder Tandem aus Realtime),
  /// sofern derselbe Nutzer aktiv ist.
  void applyPartialUpdate(UserModelUserView updated) {
    if (_user != null && _user!.id != updated.id) return;
    if (updated.hasLoadedArchive) _includeArchive = true;
    _user = updated;
    notifyListeners();
  }

  /// Aktuell ausgewählte Flugschul-IDs (synchronisiert über Start, Kalender & Wichtiges).
  Set<String> get selectedFlightSchoolIds {
    final u = _user;
    if (u == null) return const {};
    final validIds = u.flightSchools.map((fs) => fs.id).toSet();
    final current = _selectedFlightSchoolIds;
    if (current == null) return validIds;
    return current.intersection(validIds);
  }

  void setSelectedFlightSchoolIds(Set<String> ids) {
    final u = _user;
    final validIds = u?.flightSchools.map((fs) => fs.id).toSet() ?? const <String>{};
    final next = ids.intersection(validIds);
    final prev = selectedFlightSchoolIds;
    if (_selectedFlightSchoolIds != null &&
        prev.length == next.length &&
        prev.containsAll(next)) {
      return;
    }
    _selectedFlightSchoolIds = next;
    if (u != null && u.id.isNotEmpty) {
      _persistSelectedSchools(u.id, next);
    }
    notifyListeners();
  }

  String _filterPrefsKey(String uid) => 'sp_user_selected_schools_$uid';

  Future<void> _loadPersistedSchools(String uid) async {
    if (uid.isEmpty || _loadedFilterUserId == uid) return;
    _loadedFilterUserId = uid;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_filterPrefsKey(uid));
      if (saved != null && _user?.id == uid) {
        _selectedFlightSchoolIds = saved.toSet();
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _persistSelectedSchools(String uid, Set<String> ids) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_filterPrefsKey(uid), ids.toList());
    } catch (_) {}
  }

  void setSelectedTabIndex(int index) {
    if (_selectedTabIndex == index) return;
    _selectedTabIndex = index;
    notifyListeners();
  }

  List<FlightSchoolUserView> get userFlightSchools {
    final u = _user;
    if (u == null) return const [];
    return List<FlightSchoolUserView>.from(u.flightSchools);
  }

  void setUser(UserModelUserView user) {
    final prevIds = _user?.flightSchools.map((fs) => fs.id).toSet() ?? const <String>{};
    final newIds = user.flightSchools.map((fs) => fs.id).toSet();
    final isDifferentUser = _user != null && _user!.id != user.id;

    _user = user;

    if (isDifferentUser) {
      _selectedFlightSchoolIds = null;
      _loadedFilterUserId = '';
      _includeArchive = user.hasLoadedArchive;
    } else {
      if (user.hasLoadedArchive) _includeArchive = true;
      if (_selectedFlightSchoolIds != null) {
        // Neu beigetretene Flugschulen automatisch zur Auswahl hinzufügen
        final added = newIds.difference(prevIds);
        if (added.isNotEmpty) {
          _selectedFlightSchoolIds = {..._selectedFlightSchoolIds!, ...added};
        }
      }
    }

    if (user.id.isNotEmpty && _loadedFilterUserId != user.id) {
      _loadPersistedSchools(user.id);
    }

    notifyListeners();
  }

  void clearUser() {
    _user = null;
    _selectedFlightSchoolIds = null;
    _loadedFilterUserId = '';
    _includeArchive = false;
    notifyListeners();
  }

  void updateEvents(List<Event> events) {
    if (_user == null) return;
    _user = _user!.copyWith(events: events);
    notifyListeners();
  }
}
