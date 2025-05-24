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
          ]
      );

      for (final assignment in teamAssignments.documents) {
        final data = assignment.data;
        final eventData = data["event"];
        final event = Event(
          id: data["\$id"],
          flightSchoolId: flightSchool.id ?? "test",
          identifier: eventData["identifier"] ?? "test",
          status: EventStatusEnum.values.byName(eventData["status"]),
          startTime: DateTime.parse(eventData["start_time"]),
          endTime: DateTime.parse(eventData["end_time"]),
          displayName: eventData["display_name"] ?? "test",
          team: List<String>.from(eventData["team"] ?? []),
          notes: List<String>.from(eventData["notes"] ?? []),
          role: EventRoleEnum.values.byName(data["role"]),
          assignmentStatus: EventUserStatusEnum.values.byName(data["status"]),
        );
        allEvents.add(event);
      }
    }
    return allEvents != null ? allEvents:user.events;
  }

   Future<UserModel?> getUserInformation() async {
    try{
      final user = await AuthService().getCurrentUser();
      if(user != null){
        String userID = user.$id;

        //get All FlightSchools relevant to user
        models.DocumentList userDocument = await _database.listDocuments(
          databaseId: AppwriteConfig().mainDatabaseId,
          collectionId: AppwriteConfig().usersCollectionID,
          queries:[
            Query.equal("id", userID)
          ]
        );

        final userDocumentData = userDocument.documents.first.data;
        final flightshoolList = userDocumentData["flightSchools"];


        final List<FlightSchool> flightSchools = flightshoolList.map<FlightSchool>( (flightSchool) {
        //TODO: getFile Link for logo or other solution
          return FlightSchool(
              id: flightSchool["\$id"],
              displayName: flightSchool["display_name"],
              databaseId: flightSchool["database_id"],
              teamAssignmentsEventsCollectionId: flightSchool["team_assigments_events_id"],
              eventsCollectionId: flightSchool["events_id"],
              auditLogsCollectionId: flightSchool["audit_logs_id"],
              adminUserIds:List<String>.from(flightSchool['admin_users'] ?? []),
              logoLink: "!");
        }).toList();


     //get All events Relevant to User
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
              ]
          );

          for (final assignment in teamAssignments.documents) {
            final data = assignment.data;
            final eventData = data["event"];
            final event = Event(
              id: data["\$id"],
              flightSchoolId: flightSchool.id ?? "test",
              identifier: eventData["identifier"] ?? "test",
              status: EventStatusEnum.values.byName(eventData["status"]),
              startTime: DateTime.parse(eventData["start_time"]),
              endTime: DateTime.parse(eventData["end_time"]),
              displayName: eventData["display_name"] ?? "test",
              team: List<String>.from(eventData["team"] ?? []),
              notes: List<String>.from(eventData["notes"] ?? []),
              role: EventRoleEnum.values.byName(data["role"]),
              assignmentStatus: EventUserStatusEnum.values.byName(data["status"]),
            );
            allEvents.add(event);
          }
        }

        return UserModel(
            id: userID,
            name: user.name,
            mail: user.email,
            phone: user.phone,
            flightSchools: flightSchools,
            events: allEvents);

      }
    }catch(e){
      print(e);
    }
  }


}