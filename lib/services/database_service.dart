import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:season_planer/data/models/event_model.dart';
import 'package:season_planer/data/models/flight_school_model.dart';
import 'package:season_planer/data/models/user_model.dart';
import 'package:season_planer/services/auth_service.dart';

import '../core/appwrite_config.dart';
import '../data/enums/event_status_enum.dart';
import '../data/enums/role_enum.dart';

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
              logoLink: "!");
        }).toList();

     //get All events Relevant to User
        final List<Event> allEvents = [];

        for (final flightSchool in flightSchools) {
          final teamAssignments = await _database.listDocuments(
            databaseId: flightSchool.databaseId,
            collectionId: flightSchool.teamAssignmentsEventsCollectionId,
            queries: [Query.equal("user_id", userID)],
          );

          for (final assignment in teamAssignments.documents) {
            final data = assignment.data;
            final eventData = data["event"];

            final event = Event(
              flightSchoolId: flightSchool.id ?? "test",
              identifier: eventData["identifier"] ?? "test",
              status: EventStatusEnum.values.byName(eventData["status"]),
              startTime: DateTime.parse(eventData["start_time"]),
              endTime: DateTime.parse(eventData["end_time"]),
              displayName: eventData["display_name"] ?? "test",
              team: List<String>.from(eventData["team"] ?? []),
              notes: List<String>.from(eventData["notes"] ?? []),
              role: RoleEnum.values.byName(data["role"]),
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