import 'package:appwrite/appwrite.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:season_planer/data/enums/event_role_enum.dart';
import 'package:season_planer/data/enums/event_user_status_enum.dart';
import 'package:season_planer/data/models/event_model.dart';
import 'package:season_planer/data/models/user_models/flight_school_model_user_view.dart';
import 'package:season_planer/data/models/user_models/user_model_userView.dart';
import 'package:season_planer/services/auth_service.dart';

import '../core/appwrite_config.dart';
import '../data/enums/event_status_enum.dart';
import '../data/models/admin_models/flight_school_model_flight_school_view.dart';
import '../data/models/admin_models/user_summary_flight_school_view.dart';
import 'providers/flight_school_provider.dart';
import 'functions/flight_school_functions.dart';

class DatabaseService {
  final Client client = Client()
      .setEndpoint(AppwriteConfig().appwriteEnpoint)
      .setProject(AppwriteConfig().projectId)
      .setSelfSigned(status: true);

  static final DatabaseService _instance = DatabaseService._internal();

  factory DatabaseService() {
    return _instance;
  }
  DatabaseService._internal();

  late final Databases _database;
  late final Storage _storage;

  void init() {
    _database = Databases(client);
    _storage = Storage(client);
  }

  Future<bool> changeEventAssignmentStatus({
    required UserModelUserView user,
    required Event event,
    required EventUserStatusEnum newStatus,
  }) async {
    try {
      final flightSchool = user.flightSchools.firstWhere(
            (fs) => fs.id == event.flightSchoolId,
        orElse: () => throw Exception("Flight school not found."),
      );

      final assignments = await _database.listDocuments(
        databaseId: flightSchool.databaseId,
        collectionId: flightSchool.teamAssignmentsEventsCollectionId,
        queries: [
          Query.equal('\$id', event.id),
        ],
      );

      if (assignments.documents.isEmpty) {
        throw Exception('No matching assignment found.');
      }

      final assignmentId = assignments.documents.first.$id;

      await _database.updateDocument(
        databaseId: flightSchool.databaseId,
        collectionId: flightSchool.teamAssignmentsEventsCollectionId,
        documentId: assignmentId,
        data: {
          'status': newStatus.name,
          'user_id':user.id
        },
      );

      return true;
    } catch (e) {
      print('Error while updating status: $e');
      return false;
    }
  }

  Future<List<Event>> loadUserEvents(UserModelUserView user) async {
    final List<Event> allEvents = [];

    for (final flightSchool in user.flightSchools) {
      final teamAssignments = await _database.listDocuments(
        databaseId: flightSchool.databaseId,
        collectionId: flightSchool.teamAssignmentsEventsCollectionId,
        queries: [
          Query.or([
            Query.equal("user_id", user.id),
            Query.equal("user_id", "69"),
          ])
        ],
      );

      for (final assignment in teamAssignments.documents) {
        final data = assignment.data;

        final eventData = data["events"];

        final teamDocs = await _database.listDocuments(
          databaseId: flightSchool.databaseId,
          collectionId: flightSchool.teamAssignmentsEventsCollectionId,
          queries: [
            Query.equal("events", [eventData["\$id"]]),
          ],
        );

        final List<TeamMember> teamMembers = teamDocs.documents
            .map((doc) => TeamMember.fromMap(doc.data))
            .toList();

        final event = Event(
          id: data["\$id"],
          flightSchoolId: flightSchool.id ?? "test",
          identifier: eventData["identifier"] ?? "test",
          status: EventStatusEnum.values.byName(eventData["status"]),
          startTime: DateTime.parse(eventData["start_time"]),
          endTime: DateTime.parse(eventData["end_time"]),
          displayName: eventData["display_name"] ?? "test",
          location: eventData["location"],
          team: teamMembers,
          notes: eventData["notes"] ?? "",
          role: EventRoleEnum.values.byName(data["role"]),
          assignmentStatus: EventUserStatusEnum.values.byName(data["status"]),
        );

        allEvents.add(event);
      }
    }
    return allEvents;
  }

  Future<FlightSchoolModelFlightSchoolView?> getFlightSchool(String id) async {
    try {
      final fsDoc = await _database.getDocument(
        databaseId: AppwriteConfig().mainDatabaseId,
        collectionId: AppwriteConfig().flightSchoolsCollectionId,
        documentId: id,
      );

      final fs = fsDoc.data;

      final String databaseId = (fs["database_id"] ?? "") as String;
      final String teamAssignmentsId =
      (fs["team_assigments_events_id"] ?? "") as String;
      final String eventsCollectionId = (fs["events_id"] ?? "") as String;

      List<UserSummary> members = [];

      try {
        final fsFn = FlightSchoolFunctions(client);

        final result = await fsFn.getMembersWithAuth(
          flightSchoolId: id,
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
              roles:UserSummary.parseRoles(
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

            final firstAssignment = teamDocs.documents.isNotEmpty ? teamDocs.documents.first.data : null;

            eventList.add(
              Event(
                id: eventDoc.$id,
                flightSchoolId: id,
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


      final settings = (fs["settings"] as Map<String, dynamic>?) ?? <String, dynamic>{};

      return FlightSchoolModelFlightSchoolView(
        id: fsDoc.$id,
        displayName: (fs["display_name"] ?? "") as String,
        databaseId: databaseId,
        teamAssignmentsEventsCollectionId: teamAssignmentsId,
        eventsCollectionId: eventsCollectionId,
        auditLogsCollectionId: (fs["audit_logs_id"] ?? "") as String,
        logoLink: (fs["logo_link"] ?? "!") as String,
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



  Future<UserModelUserView?> getUserInformation() async {
    try {
      final user = await AuthService().getCurrentUser();
      if (user == null) return null;

      final userID = user.$id;

      final userDocument = await _database.listDocuments(
        databaseId: AppwriteConfig().mainDatabaseId,
        collectionId: AppwriteConfig().usersCollectionID,
        queries: [Query.equal("\$id", userID)],
      );

      if (userDocument.documents.isEmpty) return null;

      final userDocumentData = userDocument.documents.first.data;
      final membershipsList = userDocumentData["memberships"] as List;

      final List<FlightSchoolUserView> flightSchools = membershipsList
          .where((m) => m["flightSchools"] != null)
          .map((membership) {
        final fs = membership["flightSchools"];
          return FlightSchoolUserView(
          id: fs["\$id"],
          displayName: fs["display_name"],
          databaseId: fs["database_id"],
          teamAssignmentsEventsCollectionId: fs["team_assigments_events_id"],
          eventsCollectionId: fs["events_id"],
          auditLogsCollectionId: fs["audit_logs_id"],
          adminUserIds: List<String>.from(fs["admin_users"] ?? []),
          logoLink: "!",
        );
      })
          .toList();

      final List<Event> allEvents = [];

      for (final flightSchool in flightSchools) {
        final teamAssignments = await _database.listDocuments(
          databaseId: flightSchool.databaseId,
          collectionId: flightSchool.teamAssignmentsEventsCollectionId,
          queries: [
            Query.or([
              Query.equal("user_id", userID),
              Query.equal("user_id", "69"),
            ])
          ],
        );

        for (final assignment in teamAssignments.documents) {
          final data = assignment.data;
          final eventData = data["events"];

          final teamDocs = await _database.listDocuments(
            databaseId: flightSchool.databaseId,
            collectionId: flightSchool.teamAssignmentsEventsCollectionId,
            queries: [
              Query.equal("events", [eventData["\$id"]]),
            ],
          );

          final teamMembers = teamDocs.documents
              .map((doc) => TeamMember.fromMap(doc.data))
              .toList();

          allEvents.add(Event(
            id: data["\$id"],
            flightSchoolId: flightSchool.id ?? "test",
            identifier: eventData["identifier"] ?? "test",
            status: EventStatusEnum.values.byName(eventData["status"]),
            startTime: DateTime.parse(eventData["start_time"]),
            endTime: DateTime.parse(eventData["end_time"]),
            displayName: eventData["display_name"] ?? "test",
            team: teamMembers,
            location: eventData["location"],
            notes: eventData["notes"],
            role: EventRoleEnum.values.byName(data["role"]),
            assignmentStatus: EventUserStatusEnum.values.byName(data["status"]),
          ));
        }
      }
      return UserModelUserView(
        id: userID,
        name: user.name,
        mail: user.email,
        phone: user.phone,
        flightSchools: flightSchools,
        events: allEvents,
      );
    } catch (e) {
      print(e);
      return null;
    }
  }

  Future<Event> createEventWithTeam({
    required BuildContext context,
    required Event event,
  }) async {
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null) throw Exception("FlightSchool not set in provider");

    final eventDoc = await _database.createDocument(
      databaseId: fs.databaseId,
      collectionId: fs.eventsCollectionId,
      documentId: ID.unique(),
      data: {
        "identifier": event.identifier,
        "display_name": event.displayName,
        "status": event.status.name,
        "start_time": event.startTime.toIso8601String(),
        "end_time": event.endTime.toIso8601String(),
        "notes": event.notes,
        "location": event.location
      },
    );

    final created = event.copyWith(
      id: eventDoc.$id,
      flightSchoolId: fs.id,
    );

    print(created.team);

    for (final tm in created.team) {
      await _database.createDocument(
        databaseId: fs.databaseId,
        collectionId: fs.teamAssignmentsEventsCollectionId,
        documentId: ID.unique(),
        data: {
          "user_id": tm.isSlot ? "" : tm.userId,
          "role": tm.role,
          "status": tm.status,
          "events": created.id,
        },
      );
    }

    return created;
  }

  Future<Event> updateEventWithTeam({
    required BuildContext context,
    required Event event,
  }) async {
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null) throw Exception("FlightSchool not set in provider");

    if (event.id.trim().isEmpty) {
      throw Exception("Event.id is empty – cannot update.");
    }

    await _database.updateDocument(
      databaseId: fs.databaseId,
      collectionId: fs.eventsCollectionId,
      documentId: event.id,
      data: {
        "identifier": event.identifier,
        "display_name": event.displayName,
        "status": event.status.name,
        "start_time": event.startTime.toIso8601String(),
        "end_time": event.endTime.toIso8601String(),
        "notes": event.notes,
        "location": event.location,
      },
    );

    final existing = await _database.listDocuments(
      databaseId: fs.databaseId,
      collectionId: fs.teamAssignmentsEventsCollectionId,
      queries: [
        Query.equal("events", [event.id]),
        Query.limit(500),
      ],
    );

    final Map<String, dynamic> existingByKey = {};
    for (final doc in existing.documents) {
      final data = doc.data;
      final userId = (data["user_id"] ?? "").toString();
      final key = userId.isEmpty ? "slot:${doc.$id}" : "user:$userId";

      existingByKey[key] = {
        "docId": doc.$id,
        "user_id": userId,
        "role": (data["role"] ?? "").toString(),
        "status": (data["status"] ?? "").toString(),
      };
    }

    final Map<String, TeamMember> newByKey = {};
    int slotIndex = 0;
    for (final tm in event.team) {
      if (tm.isSlot) {
        newByKey["slot:new:$slotIndex"] = tm;
        slotIndex++;
      } else {
        newByKey["user:${tm.userId}"] = tm;
      }
    }


    for (final entry in existingByKey.entries) {
      final key = entry.key;
      final docId = (entry.value["docId"] as String);

      final isExistingSlot = key.startsWith("slot:");
      final isExistingUser = key.startsWith("user:");

      if (isExistingUser) {
        if (!newByKey.containsKey(key)) {
          await _database.deleteDocument(
            databaseId: fs.databaseId,
            collectionId: fs.teamAssignmentsEventsCollectionId,
            documentId: docId,
          );
        }
      } else if (isExistingSlot) {
        await _database.deleteDocument(
          databaseId: fs.databaseId,
          collectionId: fs.teamAssignmentsEventsCollectionId,
          documentId: docId,
        );
      }
    }

    for (final entry in newByKey.entries) {
      final key = entry.key;
      final tm = entry.value;

      if (key.startsWith("slot:new:")) {
        await _database.createDocument(
          databaseId: fs.databaseId,
          collectionId: fs.teamAssignmentsEventsCollectionId,
          documentId: ID.unique(),
          data: {
            "user_id": "",
            "role": tm.role,
            "status": tm.status,
            "events": event.id,
          },
        );
        continue;
      }

      final existingEntry = existingByKey[key];
      if (existingEntry == null) {
        await _database.createDocument(
          databaseId: fs.databaseId,
          collectionId: fs.teamAssignmentsEventsCollectionId,
          documentId: ID.unique(),
          data: {
            "user_id": tm.userId,
            "role": tm.role,
            "status": tm.status,
            "events": event.id,
          },
        );
      } else {
        final docId = existingEntry["docId"] as String;
        final oldRole = existingEntry["role"] as String;
        final oldStatus = existingEntry["status"] as String;

        if (oldRole != tm.role || oldStatus != tm.status) {
          await _database.updateDocument(
            databaseId: fs.databaseId,
            collectionId: fs.teamAssignmentsEventsCollectionId,
            documentId: docId,
            data: {
              "role": tm.role,
              "status": tm.status,
            },
          );
        }
      }
    }

    return event;
  }



  List<String> asStringList(dynamic value) {
    if (value == null) return <String>[];
    if (value is List) return value.map((e) => e.toString()).toList();
    if (value is String) return value.isEmpty ? <String>[] : <String>[value];
    return <String>[value.toString()];
  }



}