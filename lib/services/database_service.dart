import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:provider/provider.dart';
import 'package:season_planer/data/enums/event_role_enum.dart';
import 'package:season_planer/data/enums/event_user_status_enum.dart';
import 'package:season_planer/data/models/event_model.dart';
import 'package:season_planer/data/models/user_models/flight_school_model_user_view.dart';
import 'package:season_planer/data/models/user_models/user_model_userView.dart';
import 'package:season_planer/services/auth_service.dart';
import 'package:season_planer/services/user_provider.dart';

import '../core/appwrite_config.dart';
import '../data/enums/event_status_enum.dart';
import '../data/models/admin_models/flight_school_model_flight_school_view.dart';
import '../data/models/admin_models/user_summary_flight_school_view.dart';

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
          team: teamMembers,
          notes: List<String>.from(eventData["notes"] ?? []),
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
        final usersResult = await _database.listDocuments(
          databaseId: AppwriteConfig().mainDatabaseId,
          collectionId: AppwriteConfig().usersCollectionID,
          queries: [],
        );

        members = usersResult.documents
            .where((u) {
          final data = u.data;
          final memberships = data["memberships"];
          if (memberships is! List) return false;

          return memberships.any((m) {
            if (m is! Map) return false;

            final direct = m["flightSchoolId"];
            if (direct != null && direct.toString() == id) return true;

            final rel = m["flightSchools"];
            if (rel is Map) {
              final relId = rel["\$id"] ?? rel["id"];
              if (relId != null && relId.toString() == id) return true;
            }

            return false;
          });
        })
            .map((u) {
          final data = u.data;
          return UserSummary(
            id: (data["id"] ?? u.$id).toString(),
            name: (data["name"] ?? "").toString(),
            mail: (data["mail"] ?? data["email"] ?? "").toString(),
            phone: (data["phone"] ?? "").toString(),
          );
        })
            .toList();
      } catch (_) {
        members = [];
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

          for (final doc in eventsResult.documents) {
            final data = doc.data;

            eventList.add(
              Event(
                id: doc.$id,
                flightSchoolId: id,
                identifier: data["identifier"] ?? "test",
                status: EventStatusEnum.values.byName(data["status"]),
                startTime: DateTime.parse(data["start_time"]),
                endTime: DateTime.parse(data["end_time"]),
                displayName: data["display_name"] ?? "test",
                team: teamMembers,
                notes: asStringList(data["notes"]),
                role: EventRoleEnum.values.byName(data["role"]),
                assignmentStatus: EventUserStatusEnum.values.byName(data["status"]),
              ),
            );
          }

          events = eventList;

        }
      } catch (_) {
        events = [];
      }

      print(events);

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
        queries: [Query.equal("id", userID)],
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
            notes: asStringList(eventData["notes"]),
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


  List<String> asStringList(dynamic value) {
    if (value == null) return <String>[];
    if (value is List) return value.map((e) => e.toString()).toList();
    if (value is String) return value.isEmpty ? <String>[] : <String>[value];
    return <String>[value.toString()];
  }


}