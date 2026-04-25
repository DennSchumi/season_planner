import 'dart:convert';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/enums.dart';
import '../../core/appwrite_config.dart';
import '../../core/data/models/event_model.dart';

class FlightSchoolFunctions {
  final Functions functions;

  FlightSchoolFunctions(Client client) : functions = Functions(client);

  Future<Map<String, dynamic>> getFlightSchoolAdminView({
    required String flightSchoolId,
  }) async {
    final exec = await functions.createExecution(
      functionId: AppwriteConfig().flightSchoolFunctionsId,
      method: ExecutionMethod.gET,
      path: '/admin/flight-school?flightSchoolId=$flightSchoolId',
      headers: {'content-type': 'application/json'},
    );

    return jsonDecode(exec.responseBody);
  }

  Future<List<dynamic>> getMembersWithAuth({
    required String flightSchoolId,
  }) async {
    final exec = await functions.createExecution(
      functionId: AppwriteConfig().flightSchoolFunctionsId,
      method: ExecutionMethod.gET,
      path: '/admin/members?flightSchoolId=$flightSchoolId',
      headers: {'content-type': 'application/json'},
    );

    final body = jsonDecode(exec.responseBody);
    return body["members"] as List? ?? [];
  }

  Future<Map<String, dynamic>> inviteUserToFlightSchool({
    required String flightSchoolId,
    required String userMail,
    required List<String> roles,
  }) async {
    final exec = await functions.createExecution(
      functionId: AppwriteConfig().flightSchoolFunctionsId,
      method: ExecutionMethod.pOST,
      path: '/admin/members/invite',
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        "flightSchoolId": flightSchoolId,
        "userMail": userMail,
        "roles": roles,
      }),
    );

    return jsonDecode(exec.responseBody);
  }

  Future<Map<String, dynamic>> updateAdmins({
    required String flightSchoolId,
    required List<String> adminUserIds,
  }) async {
    final exec = await functions.createExecution(
      functionId: AppwriteConfig().flightSchoolFunctionsId,
      method: ExecutionMethod.pOST,
      path: '/admin/admins',
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        "flightSchoolId": flightSchoolId,
        "adminUserIds": adminUserIds,
      }),
    );

    return jsonDecode(exec.responseBody);
  }

  Future<Map<String, dynamic>> removeMember({
    required String membershipId,
  }) async {
    final exec = await functions.createExecution(
      functionId: AppwriteConfig().flightSchoolFunctionsId,
      method: ExecutionMethod.dELETE,
      path: '/admin/members',
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        "membershipId": membershipId,
      }),
    );

    return jsonDecode(exec.responseBody);
  }

  Future<Map<String, dynamic>> updateMemberRoles({
    required String membershipId,
    required List roles,
  }) async {
    final exec = await functions.createExecution(
      functionId: AppwriteConfig().flightSchoolFunctionsId,
      method: ExecutionMethod.pOST,
      path: '/admin/members/roles',
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        "membershipId": membershipId,
        "roles": roles,
      }),
    );

    return jsonDecode(exec.responseBody);
  }

  Future<dynamic> createNewEvent({ required Event event}) async {
    final exec = await functions.createExecution(
        functionId: AppwriteConfig().flightSchoolFunctionsId,
      method: ExecutionMethod.pOST,
      path: '/admin/events',
      headers:  {'content-type': 'application/json'},
      body: jsonEncode({
        "event": event.toJson()
      })
    );

    return jsonDecode(exec.responseBody);
  }

  Future<dynamic> updateEvent({required Event event}) async {
    final exec = await functions.createExecution(
        functionId: AppwriteConfig().flightSchoolFunctionsId,
      method: ExecutionMethod.pATCH,
      path:  '/admin/events',
        headers:  {'content-type': 'application/json'},
        body: jsonEncode({
          "event": event.toJson()
        })
    );

    return jsonDecode(exec.responseBody);
  }
}