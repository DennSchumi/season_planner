import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:season_planner/fsAdmin/data/models/flight_school_model_flight_school_view.dart';
import 'package:season_planner/fsAdmin/data/models/user_summary_flight_school_view.dart';
import 'package:season_planner/core/data/models/event_model.dart';

class FlightSchoolProvider with ChangeNotifier {
  static const String _kLastAdminSchoolKey = 'sp_last_admin_flight_school_id';

  FlightSchoolModelFlightSchoolView? _flightSchool;
  FlightSchoolModelFlightSchoolView? get flightSchool => _flightSchool;

  int _selectedTabIndex = 0;
  int get selectedTabIndex => _selectedTabIndex;

  void setSelectedTabIndex(int index) {
    if (_selectedTabIndex == index) return;
    _selectedTabIndex = index;
    notifyListeners();
  }

  String? _flightSchoolId;
  bool _isReloading = false;
  bool _reloadPending = false;
  bool _includeArchive = false;
  bool get isReloading => _isReloading;
  bool get includeArchive =>
      _includeArchive || (_flightSchool?.hasLoadedArchive ?? false);

  void setIncludeArchive(bool value) {
    if (_includeArchive == value) return;
    _includeArchive = value;
    notifyListeners();
  }

  Future<FlightSchoolModelFlightSchoolView?> Function(String id)? _defaultLoader;

  void setFlightSchool(FlightSchoolModelFlightSchoolView flightSchool) {
    if (_flightSchoolId != null && _flightSchoolId != flightSchool.id) {
      _includeArchive = flightSchool.hasLoadedArchive;
    } else if (flightSchool.hasLoadedArchive) {
      _includeArchive = true;
    }
    _flightSchool = flightSchool;
    _flightSchoolId = flightSchool.id;
    _persistLastAdminSchoolId(flightSchool.id);
    notifyListeners();
  }

  /// Übernimmt ein selektives Teil-Update (z. B. nur Events oder Tandem aus Realtime),
  /// sofern zwischenzeitlich nicht zu einer anderen Flugschule gewechselt wurde.
  void applyPartialUpdate(FlightSchoolModelFlightSchoolView updated) {
    if (_flightSchoolId != null && _flightSchoolId != updated.id) return;
    if (updated.hasLoadedArchive) _includeArchive = true;
    _flightSchool = updated;
    _flightSchoolId = updated.id;
    notifyListeners();
  }

  Future<void> _persistLastAdminSchoolId(String id) async {
    if (id.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLastAdminSchoolKey, id);
    } catch (_) {}
  }

  Future<String?> loadLastAdminFlightSchoolId() async {
    if (_flightSchoolId != null && _flightSchoolId!.isNotEmpty) {
      return _flightSchoolId;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_kLastAdminSchoolKey);
      if (saved != null && saved.isNotEmpty) return saved;
    } catch (_) {}
    return null;
  }

  void clearFlightSchool() {
    _flightSchool = null;
    _flightSchoolId = null;
    _isReloading = false;
    _reloadPending = false;
    _includeArchive = false;
    notifyListeners();
  }


  void setDefaultLoader(
      Future<FlightSchoolModelFlightSchoolView?> Function(String id) loader,
      ) {
    _defaultLoader = loader;
  }


  void upsertMember(UserSummary member, {bool reloadInBackground = true}) {
    final fs = _flightSchool;
    if (fs == null) return;

    final members = List<UserSummary>.from(fs.members);
    final idx = members.indexWhere((m) => m.id == member.id);

    if (idx >= 0) {
      members[idx] = member;
    } else {
      members.add(member);
    }

    _flightSchool = fs.copyWith(members: members);
    notifyListeners();

    if (reloadInBackground) {
      reloadFlightSchoolInBackground();
    }
  }

  void removeMemberById(String memberId, {bool reloadInBackground = true}) {
    final fs = _flightSchool;
    if (fs == null) return;

    final members = fs.members.where((m) => m.id != memberId).toList();
    _flightSchool = fs.copyWith(members: members);
    notifyListeners();

    if (reloadInBackground) {
      reloadFlightSchoolInBackground();
    }
  }



  void upsertEvent(Event event, {bool reloadInBackground = true}) {
    final fs = _flightSchool;
    if (fs == null) return;

    final events = List<Event>.from(fs.events);
    final idx = events.indexWhere((e) => e.id == event.id);

    if (idx >= 0) {
      events[idx] = event;
    } else {
      events.add(event);
    }

    events.sort((a, b) => b.startTime.compareTo(a.startTime));

    _flightSchool = fs.copyWith(events: events);
    notifyListeners();

    if (reloadInBackground) {
      reloadFlightSchoolInBackground();
    }
  }

  void removeEventById(String eventId, {bool reloadInBackground = true}) {
    final fs = _flightSchool;
    if (fs == null) return;

    final events = fs.events.where((e) => e.id != eventId).toList();
    _flightSchool = fs.copyWith(events: events);
    notifyListeners();

    if (reloadInBackground) {
      reloadFlightSchoolInBackground();
    }
  }


  Future<void> reloadFlightSchool(
      Future<FlightSchoolModelFlightSchoolView?> Function(String id) loader,
      ) async {
    final id = _flightSchoolId ?? _flightSchool?.id;
    if (id == null || id.isEmpty) return;

    _defaultLoader = loader;

    if (_isReloading) {
      // Nachfolgenden Reload vormerken statt still zu verwerfen
      _reloadPending = true;
      return;
    }

    _isReloading = true;
    notifyListeners();

    try {
      do {
        _reloadPending = false;
        final targetId = _flightSchoolId ?? _flightSchool?.id;
        if (targetId == null || targetId.isEmpty) break;
        final fresh = await loader(targetId);
        // Nur übernehmen, wenn inzwischen nicht zu einer anderen Flugschule gewechselt wurde
        if (fresh != null &&
            (_flightSchoolId == null || _flightSchoolId == fresh.id)) {
          _flightSchool = fresh;
          _flightSchoolId = fresh.id;
        }
      } while (_reloadPending);
    } catch (e) {
      debugPrint("reloadFlightSchool error: $e");
    } finally {
      _isReloading = false;
      notifyListeners();
    }
  }

  void reloadFlightSchoolInBackground([
    Future<FlightSchoolModelFlightSchoolView?> Function(String id)? loader,
  ]) {
    final effectiveLoader = loader ?? _defaultLoader;
    if (effectiveLoader == null) return;

    if (_isReloading) {
      _reloadPending = true;
      return;
    }

    // ignore: unawaited_futures
    reloadFlightSchool(effectiveLoader);
  }
}
