import 'package:flutter/cupertino.dart';

import 'package:season_planer/data/models/admin_models/flight_school_model_flight_school_view.dart';
import 'package:season_planer/data/models/admin_models/user_summary_flight_school_view.dart';
import 'package:season_planer/data/models/event_model.dart';

class FlightSchoolProvider with ChangeNotifier {
  FlightSchoolModelFlightSchoolView? _flightSchool;
  FlightSchoolModelFlightSchoolView? get flightSchool => _flightSchool;

  String? _flightSchoolId;
  bool _isReloading = false;
  bool get isReloading => _isReloading;

  // ------------------------------------------------------------
  // Basis
  // ------------------------------------------------------------

  void setFlightSchool(FlightSchoolModelFlightSchoolView flightSchool) {
    _flightSchool = flightSchool;
    _flightSchoolId = flightSchool.id;
    notifyListeners();
  }

  void clearFlightSchool() {
    _flightSchool = null;
    _flightSchoolId = null;
    _isReloading = false;
    notifyListeners();
  }

  // ------------------------------------------------------------
  // Members – manuell ändern (optimistisches UI)
  // ------------------------------------------------------------

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

  // ------------------------------------------------------------
  // Events – manuell ändern (optimistisches UI)
  // ------------------------------------------------------------

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

  // ------------------------------------------------------------
  // Reload – Service wird von außen übergeben
  // ------------------------------------------------------------

  /// Hartes Reload (await) – z.B. Pull-to-refresh
  Future<void> reloadFlightSchool(
      Future<FlightSchoolModelFlightSchoolView?> Function(String id) loader,
      ) async {
    final id = _flightSchoolId ?? _flightSchool?.id;
    if (id == null || id.isEmpty) return;

    if (_isReloading) return;

    _isReloading = true;
    notifyListeners();

    try {
      final fresh = await loader(id);
      if (fresh != null) {
        _flightSchool = fresh;
        _flightSchoolId = fresh.id;
      }
    } catch (e) {
      debugPrint("reloadFlightSchool error: $e");
    } finally {
      _isReloading = false;
      notifyListeners();
    }
  }

  /// Fire-and-forget Reload
  void reloadFlightSchoolInBackground([
    Future<FlightSchoolModelFlightSchoolView?> Function(String id)? loader,
  ]) {
    if (loader == null || _isReloading) return;

    // ignore: unawaited_futures
    reloadFlightSchool(loader);
  }
}
