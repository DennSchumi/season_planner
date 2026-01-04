import 'package:appwrite/appwrite.dart';
import 'package:season_planer/services/database_service.dart';
import 'package:season_planer/services/functions/flight_school_functions.dart';

import '../core/appwrite_config.dart';
import '../data/enums/event_role_enum.dart';

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


//remove Member
//add Member
//update Membership roles
  
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