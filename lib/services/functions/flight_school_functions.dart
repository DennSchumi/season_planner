import 'dart:convert';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/enums.dart';
import 'package:season_planer/core/appwrite_config.dart';

class FlightSchoolFunctions {
  final Functions functions;
  FlightSchoolFunctions(Client client) : functions = Functions(client);

  Future<List<dynamic>> getMembersWithAuth({
    required String flightSchoolId,
  }) async {
    print(flightSchoolId);
    final path = "/members?flightSchoolId=${Uri.encodeQueryComponent(flightSchoolId)}";

    final res = await functions.createExecution(
      functionId: AppwriteConfig().flightSchoolFunctionsId,
      path: path,
      method: ExecutionMethod.gET,
      headers: const {
        "content-type": "application/json",
      },
    );


    final body = res.responseBody;
    if (body == null || body.isEmpty) return const [];



    final decoded = jsonDecode(body);

    if (decoded is Map<String, dynamic>) {
      final members = decoded["members"];
      if (members is List) return members;
      return [];
    }
    return [];
  }


  Future<Map<String, dynamic>> inviteUserToFlightSchool({
    required String flightSchoolId,
    required String userMail,
    List<String>? roles,
  }) async {
    final payload = <String, dynamic>{
      "flightSchoolId": flightSchoolId,
      "userMail": userMail,
      if (roles != null) "roles": roles,
    };

    final exec = await functions.createExecution(
      functionId: AppwriteConfig().flightSchoolFunctionsId,
      method: ExecutionMethod.pOST,
      path: "/members/invite",
      headers: {"content-type": "application/json"},
      body: jsonEncode(payload),
    );

    final body = (exec.responseBody ?? "").trim();
    if (body.isEmpty) return {"ok": false};

    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;

    return {"ok": false};
  }
}
