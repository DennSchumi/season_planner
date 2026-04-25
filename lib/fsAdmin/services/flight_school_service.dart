import 'package:appwrite/appwrite.dart';
import 'package:flutter/cupertino.dart';
import 'package:season_planner/fsAdmin/services/flight_school_functions.dart';

import '../../core/appwrite_config.dart';
import '../../core/data/models/event_model.dart';
import '../data/models/flight_school_model_flight_school_view.dart';

class FlightSchoolService {
  final Client client = Client()
    ..setEndpoint(AppwriteConfig().appwriteEnpoint)
    ..setProject(AppwriteConfig().projectId)
    ..setSelfSigned(status: true);

  late final FlightSchoolFunctions flightSchoolFunctions =
  FlightSchoolFunctions(client);

  static final FlightSchoolService _instance = FlightSchoolService._internal();

  factory FlightSchoolService() {
    return _instance;
  }

  FlightSchoolService._internal();

  Future<bool> updateAdmins({
    required String flightSchoolId,
    required List<String> adminUserIds,
  }) async {
    try {
      final res = await flightSchoolFunctions.updateAdmins(
        flightSchoolId: flightSchoolId,
        adminUserIds: adminUserIds,
      );

      return res["ok"] == true;
    } catch (e) {
      debugPrint("updateAdmins failed: $e");
      return false;
    }
  }

  Future<FlightSchoolModelFlightSchoolView?> getFlightSchool(String id) async {
    try {
      final res = await flightSchoolFunctions.getFlightSchoolAdminView(
        flightSchoolId: id,
      );
      if (res["ok"] != true) return null;

      final fs = Map<String, dynamic>.from(res["flightSchool"]);

      return FlightSchoolModelFlightSchoolView.fromJson(fs);
    } catch (e) {
      debugPrint("getFlightSchool failed: $e");
      return null;
    }
  }

  Future<bool> removeMemberOfFlightSchool(String membershipId) async {
    try {
      final res = await flightSchoolFunctions.removeMember(
        membershipId: membershipId,
      );

      return res["ok"] == true;
    } catch (e) {
      debugPrint("removeMemberOfFlightSchool failed: $e");
      return false;
    }
  }

  Future<bool> updateRolesInMemberOfFlightSchool(
      String membershipId,
      List roles,
      ) async {
    try {
      final res = await flightSchoolFunctions.updateMemberRoles(
        membershipId: membershipId,
        roles: roles,
      );

      return res["ok"] == true;
    } catch (e) {
      debugPrint("updateRolesInMemberOfFlightSchool failed: $e");
      return false;
    }
  }

  Future<void> inviteMember({
    required String flightSchoolId,
    required String email,
  }) async {
    final res = await flightSchoolFunctions.inviteUserToFlightSchool(
      flightSchoolId: flightSchoolId,
      userMail: email,
      roles: const [],
    );

    if (res["ok"] != true) {
      throw Exception("Invite failed: ${res.toString()}");
    }
  }

  Future<bool> createEvent({required Event event}) async {
    try{
      final res = await flightSchoolFunctions.createNewEvent(event: event);
      return res["ok"] == true;
    }catch(e) {
      debugPrint("createNewEvent failed: $e");
      return false;
    }
  }

  Future<bool> updateEvent({required Event event}) async {
    try{
      final res = await flightSchoolFunctions.updateEvent(event: event);
      return res["ok"] == true;
    }catch(e){
      debugPrint("updateEvent failed: $e");
      return false;
    }
  }
}