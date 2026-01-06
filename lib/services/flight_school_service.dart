import 'package:appwrite/appwrite.dart';
import 'package:flutter/cupertino.dart';
import 'package:season_planer/services/database_service.dart';
import 'package:season_planer/services/functions/flight_school_functions.dart';

import '../core/appwrite_config.dart';
import '../data/enums/event_role_enum.dart';
import '../data/enums/event_status_enum.dart';
import '../data/enums/event_user_status_enum.dart';
import '../data/models/admin_models/flight_school_model_flight_school_view.dart';
import '../data/models/admin_models/user_summary_flight_school_view.dart';
import '../data/models/event_model.dart';

class FlightSchoolService {
  final Client client = Client()
      .setEndpoint(AppwriteConfig().appwriteEnpoint)
      .setProject(AppwriteConfig().projectId)
      .setSelfSigned(status: true);

  late final flighSchoolFunctions = FlightSchoolFunctions(client);

  static final FlightSchoolService _instance = FlightSchoolService._internal();

  factory FlightSchoolService(){
    return _instance;
  }

  FlightSchoolService._internal();

  late final Databases _database;

  void init() {
    _database = Databases(client);
  }

  //TODO: Move remaining methods for FS

  //update Image
  //update Informations

  Future<bool> updateAdmins({required String flightSchoolId, required List<String> adminUserIds}) async {
    try {
      await _database.updateDocument(
        databaseId: AppwriteConfig().mainDatabaseId,
        collectionId: AppwriteConfig().flightSchoolsCollectionId,
        documentId: flightSchoolId,
        data: {
          'admin_users': adminUserIds,
        },
      );

      return true;
    } catch (e) {
      debugPrint("updateAdmins failed: $e");
      return false;
    }
  }


  Future<FlightSchoolModelFlightSchoolView?> getFlightSchool(String id) async {
    try {
      final fsDoc = await _fetchFlightSchoolDoc(id);
      final fs = fsDoc.data;

      final databaseId = (fs["database_id"] ?? "") as String;
      final teamAssignmentsId = (fs["team_assigments_events_id"] ?? "") as String;
      final eventsCollectionId = (fs["events_id"] ?? "") as String;

      final members = await _fetchMembers(id);
      final events = await _fetchEvents(
        flightSchoolId: id,
        databaseId: databaseId,
        eventsCollectionId: eventsCollectionId,
        teamAssignmentsId: teamAssignmentsId,
      );

      final settings =
          (fs["settings"] as Map<String, dynamic>?) ?? <String, dynamic>{};

      return FlightSchoolModelFlightSchoolView(
        id: fsDoc.$id,
        displayName: (fs["display_name"] ?? "") as String,
        displayShortName: (fs["display_short_name"]) as String,
        databaseId: databaseId,
        teamAssignmentsEventsCollectionId: teamAssignmentsId,
        eventsCollectionId: eventsCollectionId,
        auditLogsCollectionId: (fs["audit_logs_id"] ?? "") as String,
        logoLink: (fs["logo_link"] ?? "!") as String,
        logoId: (fs["logo_id"] ?? ""),
        adminUserIds: List<String>.from(fs["admin_users"] ?? const []),
        members: members,
        events: events,
        settings: settings,
      );
    } catch (e) {
      print("getFlightSchool (FS view) error: $e");
      return null;
    }
  }

  Future<dynamic> _fetchFlightSchoolDoc(String id) async {
    return _database.getDocument(
      databaseId: AppwriteConfig().mainDatabaseId,
      collectionId: AppwriteConfig().flightSchoolsCollectionId,
      documentId: id,
    );
  }

  Future<List<UserSummary>> _fetchMembers(String flightSchoolId) async {
    List<UserSummary> members = [];

    try {
      final fsFn = FlightSchoolFunctions(client);
      final result = await fsFn.getMembersWithAuth(
        flightSchoolId: flightSchoolId,
      );

      if (result is List) {
        members = result.map((m) {
          final mm = (m is Map) ? m : <String, dynamic>{};
          return UserSummary(
            id: (mm["userId"] ?? "").toString(),
            name: (mm["name"] ?? "").toString(),
            mail: (mm["email"] ?? "").toString(),
            phone: (mm["phone"] ?? "").toString(),
            membershipId: (mm["membership"]["id"]).toString(),
            roles: UserSummary.parseRoles(
              mm["membership"]?["roles"],
            ),
          );
        }).toList();
      } else {
        members = [];
      }
    } catch (e) {
      members = [];
      debugPrint("getMembersWithAuth failed: $e");
    }

    return members;
  }

  Future<List<Event>> _fetchEvents({
    required String flightSchoolId,
    required String databaseId,
    required String eventsCollectionId,
    required String teamAssignmentsId,
  }) async {
    List<Event> events = [];

    try {
      if (databaseId.isNotEmpty && eventsCollectionId.isNotEmpty) {
        final eventsResult = await _database.listDocuments(
          databaseId: databaseId,
          collectionId: eventsCollectionId,
          queries: [
            Query.orderDesc("start_time"),
            Query.limit(200),
          ],
        );

        final List<Event> eventList = [];

        for (final eventDoc in eventsResult.documents) {
          final eventData = eventDoc.data;

          final teamDocs = await _database.listDocuments(
            databaseId: databaseId,
            collectionId: teamAssignmentsId,
            queries: [
              Query.equal("events", eventDoc.$id),
            ],
          );

          final teamMembers = teamDocs.documents
              .map((d) => TeamMember.fromMap(d.data))
              .toList();

          final firstAssignment =
          teamDocs.documents.isNotEmpty ? teamDocs.documents.first.data : null;

          eventList.add(
            Event(
              id: eventDoc.$id,
              flightSchoolId: flightSchoolId,
              identifier: (eventData["identifier"] ?? "test").toString(),
              status: EventStatusEnum.values.byName(eventData["status"]),
              startTime: DateTime.parse(eventData["start_time"]),
              endTime: DateTime.parse(eventData["end_time"]),
              displayName: (eventData["display_name"] ?? "test").toString(),
              team: teamMembers,
              notes: eventData["notes"],
              location: eventData["location"],
              role: firstAssignment != null
                  ? EventRoleEnum.values.byName(firstAssignment["role"])
                  : EventRoleEnum.values.first,
              assignmentStatus: firstAssignment != null
                  ? EventUserStatusEnum.values.byName(firstAssignment["status"])
                  : EventUserStatusEnum.values.first,
            ),
          );
        }

        events = eventList;
      }
    } catch (e) {
      print("events loading error: $e");
      events = [];
    }

    return events;
  }



  ///Event Handling
  ///

  /// Member Handling
Future<bool> removeMemberOfFlightSchool(String membershipId) async {
    try{
      _database.deleteDocument(
          databaseId: AppwriteConfig().mainDatabaseId,
          collectionId: AppwriteConfig().membershipsId,
          documentId: membershipId,
      );
      return false;
    }catch(e){
      print(e);
      return false;
    }
}

Future<bool> updateRolesInMemberOfFlightSchool(String membershipId,List roles) async {
    try{
      _database.updateDocument(
          databaseId: AppwriteConfig().mainDatabaseId,
          collectionId: AppwriteConfig().membershipsId,
          documentId: membershipId,
          data: {
               "roles": roles
          }
      );
      return true;
    }catch(e){
      print(e);
      return false;
    }
  }

  Future<void> inviteMember({
    required String flightSchoolId,
    required String email,
  }) async {
    final roleNames = [""];

    final res = await flighSchoolFunctions.inviteUserToFlightSchool(
      flightSchoolId: flightSchoolId,
      userMail: email,
      roles: roleNames,
    );

    if (res["ok"] != true) {
      throw Exception("Invite failed: ${res.toString()}");
    }
  }



}