import 'dart:convert';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/enums.dart';
import 'package:season_planner/core/appwrite_config.dart';
import 'package:season_planner/core/data/enums/event_role_enum.dart';
import 'package:season_planner/core/data/enums/event_status_enum.dart';
import 'package:season_planner/core/data/enums/event_user_status_enum.dart';
import 'package:season_planner/core/data/enums/membership_status_enum.dart';
import 'package:season_planner/core/data/models/event_application_model.dart';
import 'package:season_planner/core/data/models/event_model.dart';
import 'package:season_planner/user/data/models/flight_school_model_user_view.dart';
import 'package:season_planner/user/data/models/user_model_userView.dart';

import '../../core/data/models/event_assigment_model.dart';

class UserService {
  final Client client = Client()
    ..setEndpoint(AppwriteConfig().appwriteEnpoint)
    ..setProject(AppwriteConfig().projectId)
    ..setSelfSigned(status: true);

  static final UserService _instance = UserService._internal();

  factory UserService() => _instance;

  late final Functions functions;

  UserService._internal() {
    functions = Functions(client);
  }

  Future<bool> createApplication(String teamAssignmentEventId) async {
    try {
      final exec = await functions.createExecution(
        functionId: AppwriteConfig().userFunctionsID,
        method: ExecutionMethod.pOST,
        path: '/user/applications',
        headers: {
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'teamAssignmentEventId': teamAssignmentEventId,
        }),
      );


      if ((exec.responseBody).isEmpty) return false;

      final Map<String, dynamic> body = jsonDecode(exec.responseBody);
      return body['ok'] == true;
    } catch (e, st) {
      print('createApplication error: $e');
      print(st);
      return false;
    }
  }

  Future<UserModelUserView?> loadUserInformation() async {
    try {
      final exec = await functions.createExecution(
        functionId: AppwriteConfig().userFunctionsID,
        method: ExecutionMethod.gET,
        path: '/user/profile',
        headers: {
          'content-type': 'application/json',
        },
      );


      final rawBody = exec.responseBody;
      if (rawBody.isEmpty) return null;

      final Map<String, dynamic> body = jsonDecode(rawBody);

      if (body['ok'] != true) {
        print('loadUserInformation backend error: ${body['error']}');
        return null;
      }

      final userJson = Map<String, dynamic>.from(body['user'] ?? {});
      final flightSchoolsJson = (body['flightSchools'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final flightSchools = flightSchoolsJson.map(_mapFlightSchoolUserView).toList();
      final assignments =
      _flattenAssignmentsFromFlightSchools(flightSchoolsJson);
      final applications =
      _flattenApplicationsFromFlightSchools(flightSchoolsJson);

      return UserModelUserView(
        id: (userJson['id'] ?? '').toString(),
        name: (userJson['name'] ?? '').toString(),
        mail: (userJson['email'] ?? '').toString(),
        phone: (userJson['phone'] ?? '').toString(),
        flightSchools: flightSchools,
        assignments: assignments,
        applications: applications,
      );
    } catch (e, st) {
      print('loadUserInformation error: $e');
      return null;
    }
  }

  FlightSchoolUserView _mapFlightSchoolUserView(Map<String, dynamic> fs) {
    return FlightSchoolUserView(
      id: (fs['id'] ?? '').toString(),
      displayName: (fs['displayName'] ?? '').toString(),
      displayShortName: (fs['displayShortName'] ?? '').toString(),
      membershipStatus: _parseMembershipStatus(fs['membershipStatus']),
      availableRoles: (fs['availableRoles'] as List? ?? const [])
          .map((r) => _parseEventRole(r.toString()))
          .whereType<EventRoleEnum>()
          .toList(),
      databaseId: (fs['databaseId'] ?? '').toString(),
      teamAssignmentsEventsCollectionId:
      (fs['teamAssignmentsEventsCollectionId'] ?? '').toString(),
      eventsCollectionId: (fs['eventsCollectionId'] ?? '').toString(),
      auditLogsCollectionId: (fs['auditLogsCollectionId'] ?? '').toString(),
      adminUserIds: List<String>.from(fs['adminUserIds'] ?? const []),
      logoLink: (fs['logoLink'] ?? '').toString(),
    );
  }

  List<EventAssignment> _flattenAssignmentsFromFlightSchools(
      List<Map<String, dynamic>> flightSchoolsJson,
      ) {
    final List<EventAssignment> allAssignments = [];

    for (final fs in flightSchoolsJson) {
      final flightSchoolId = (fs['id'] ?? '').toString();

      final eventsById = <String, Map<String, dynamic>>{};
      for (final event in (fs['events'] as List? ?? const [])) {
        final map = Map<String, dynamic>.from(event as Map);
        final eventId = (map['id'] ?? '').toString();
        if (eventId.isNotEmpty) {
          eventsById[eventId] = map;
        }
      }

      void addItems(List<dynamic> items) {
        for (final item in items) {
          final itemMap = Map<String, dynamic>.from(item as Map);
          final eventId = (itemMap['eventId'] ?? '').toString();
          final eventJson = eventsById[eventId];
          if (eventJson == null) continue;

          allAssignments.add(
            _mapAssignment(
              eventJson: eventJson,
              itemJson: itemMap,
              flightSchoolId: flightSchoolId,
            ),
          );
        }
      }

      addItems(fs['assignments'] as List? ?? const []);
      addItems(fs['assignmentRequests'] as List? ?? const []);
      addItems(fs['openOpportunities'] as List? ?? const []);
    }

    return allAssignments;
  }

  List<PositionApplication> _flattenApplicationsFromFlightSchools(
      List<Map<String, dynamic>> flightSchoolsJson,
      ) {
    final List<PositionApplication> allApplications = [];

    for (final fs in flightSchoolsJson) {
      final applications = fs['applications'] as List? ?? const [];

      for (final application in applications) {
        final map = Map<String, dynamic>.from(application as Map);
        allApplications.add(PositionApplication.fromMap(map));
      }
    }

    return allApplications;
  }

  EventAssignment _mapAssignment({
    required Map<String, dynamic> eventJson,
    required Map<String, dynamic> itemJson,
    required String flightSchoolId,
  }) {
    final team = (eventJson['team'] as List? ?? const [])
        .map(
          (member) => TeamMember.fromMap(
        Map<String, dynamic>.from(member as Map),
      ),
    )
        .toList();

    final event = Event(
      id: (eventJson['id'] ?? '').toString(),
      flightSchoolId: flightSchoolId,
      identifier: (eventJson['identifier'] ?? '').toString(),
      status: _parseEventStatus(eventJson['status']),
      startTime: DateTime.parse(eventJson['startTime'] as String),
      endTime: DateTime.parse(eventJson['endTime'] as String),
      displayName: (eventJson['displayName'] ?? '').toString(),
      location: (eventJson['location'] ?? '').toString(),
      notes: (eventJson['notes'] ?? '').toString(),
      team: team,
    );

    return EventAssignment(
      id: (itemJson['id'] ?? '').toString(),
      userId: (itemJson['userId'] ?? '').toString(),
      event: event,
      role: _parseEventRole(itemJson['role']) ?? EventRoleEnum.values.first,
      status: _parseEventUserStatus(itemJson['status']),
    );
  }

  MembershipStatusEnum _parseMembershipStatus(dynamic value) {
    final raw = (value ?? '').toString();
    return MembershipStatusEnum.values.byName(raw);
  }

  EventStatusEnum _parseEventStatus(dynamic value) {
    final raw = (value ?? '').toString();
    return EventStatusEnum.values.byName(raw);
  }

  EventUserStatusEnum _parseEventUserStatus(dynamic value) {
    final raw = (value ?? '').toString();
    return EventUserStatusEnum.values.byName(raw);
  }

  EventRoleEnum? _parseEventRole(dynamic value) {
    final raw = (value ?? '').toString();
    if (raw.isEmpty) return null;

    try {
      return EventRoleEnum.values.byName(raw);
    } catch (_) {
      return null;
    }
  }

  Future<bool> changeAssignmentStatus({required String teamAssignmentEventId, required EventUserStatusEnum newStatus}) async {return false;}

  Future<dynamic> withdrawApplication(String id) async {}
}