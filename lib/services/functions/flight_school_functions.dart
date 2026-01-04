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
}
