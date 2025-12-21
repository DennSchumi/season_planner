import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:provider/provider.dart';
import 'package:season_planer/data/enums/event_role_enum.dart';
import 'package:season_planer/data/enums/event_user_status_enum.dart';
import 'package:season_planer/data/models/event_model.dart';
import 'package:season_planer/data/models/flight_school_model.dart';
import 'package:season_planer/data/models/user_model.dart';
import 'package:season_planer/services/auth_service.dart';
import 'package:season_planer/services/user_provider.dart';

import '../core/appwrite_config.dart';
import '../data/enums/event_status_enum.dart';

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
    required UserModel user,
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

  Future<List<Event>> loadUserEvents(UserModel user) async {
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


  Future<UserModel?> getUserInformation() async {
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

      final List<FlightSchool> flightSchools = membershipsList
          .where((m) => m["flightSchools"] != null)
          .map((membership) {
        final fs = membership["flightSchools"];
          return FlightSchool(
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
      return UserModel(
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