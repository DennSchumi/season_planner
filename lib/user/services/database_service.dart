import 'package:appwrite/appwrite.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/core/data/enums/event_role_enum.dart';
import 'package:season_planner/core/data/enums/event_user_status_enum.dart';
import 'package:season_planner/core/data/enums/membership_status_enum.dart';
import 'package:season_planner/core/data/models/event_model.dart';
import 'package:season_planner/user/data/models/flight_school_model_user_view.dart';
import 'package:season_planner/user/data/models/user_model_userView.dart';
import 'package:season_planner/core/services/auth_service.dart';
import '../../core/appwrite_config.dart';
import '../../core/data/enums/event_status_enum.dart';
import '../../fsAdmin/flight_school_provider.dart';




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



  Future<bool> acceptMembership({
    required String flightSchoolId,
  }) async {
    try {
      final user = await AuthService().getCurrentUser();
      if (user == null) return false;

      final userId = user.$id;

      final memberships = await _database.listDocuments(
        databaseId: AppwriteConfig().mainDatabaseId,
        collectionId: AppwriteConfig().membershipsId,
        queries: [
          Query.equal("users", userId),
          Query.equal("flightSchools", [flightSchoolId]),
          Query.limit(1),
        ],
      );

      if (memberships.documents.isEmpty) {
        throw Exception("Membership not found for flightSchoolId=$flightSchoolId");
      }

      final membershipDoc = memberships.documents.first;

      await _database.updateDocument(
        databaseId: AppwriteConfig().mainDatabaseId,
        collectionId: AppwriteConfig().membershipsId,
        documentId: membershipDoc.$id,
        data: {
          "status": MembershipStatusEnum.active.name,
        },
      );

      return true;
    } catch (e) {
      print("acceptMembership error: $e");
      return false;
    }
  }

  /// Löscht die Membership (User verlässt Flugschule).
  Future<bool> leaveMembership({
    required String flightSchoolId,
  }) async {
    try {
      final user = await AuthService().getCurrentUser();
      if (user == null) return false;

      final userId = user.$id;

      final memberships = await _database.listDocuments(
        databaseId: AppwriteConfig().mainDatabaseId,
        collectionId: AppwriteConfig().membershipsId,
        queries: [
          Query.equal("users", userId),
          Query.equal("flightSchools", [flightSchoolId]),
          Query.limit(1),
        ],
      );

      if (memberships.documents.isEmpty) {
        throw Exception("Membership not found for flightSchoolId=$flightSchoolId");
      }

      final membershipDocId = memberships.documents.first.$id;

      await _database.deleteDocument(
        databaseId: AppwriteConfig().mainDatabaseId,
        collectionId: AppwriteConfig().membershipsId,
        documentId: membershipDocId,
      );

      return true;
    } catch (e) {
      print("leaveMembership error: $e");
      return false;
    }
  }

  Future<bool> updateAccount({
    required String firstName,
    required String lastName,
    required String email,
    String phone = "",
    String? password,
  }) async {
    try {
      final account = Account(client);

      final fullName = "${firstName.trim()} ${lastName.trim()}".trim();
      if (fullName.isNotEmpty) {
        await account.updateName(name: fullName);
      }

      final current = await account.get();
      final currentEmail = current.email;

      if (email.trim().isNotEmpty && email.trim() != currentEmail) {
        if (password == null || password.isEmpty) {
          throw Exception(
            "Email change requires password (Appwrite). Provide password.",
          );
        }
        await account.updateEmail(
          email: email.trim(),
          password: password,
        );
      }


      if (phone.trim().isNotEmpty) {

        final prefs = Map<String, dynamic>.from(current.prefs.data);
        await account.updatePrefs(prefs: prefs);

        await account.updatePrefs(prefs: prefs);
      } else {
        final prefs = Map<String, dynamic>.from(current.prefs.data);
        prefs.remove("phone");
        await account.updatePrefs(prefs: prefs);
      }

      return true;
    } catch (e) {
      print("updateAccount error: $e");
      return false;
    }
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
        databaseId: AppwriteConfig().mainDatabaseId,
        collectionId: AppwriteConfig().teamAssignmentsCollectionId,
        queries: [
          Query.equal('events', event.id),
          Query.equal('user', user.id),
        ],
      );

      String assignmentId;
      if (assignments.documents.isNotEmpty) {
        assignmentId = assignments.documents.first.$id;
      } else {
        // Find an open slot if no direct assignment
        final openSlots = await _database.listDocuments(
          databaseId: AppwriteConfig().mainDatabaseId,
          collectionId: AppwriteConfig().teamAssignmentsCollectionId,
          queries: [
            Query.equal('events', event.id),
            Query.isNull('user'),
          ],
        );
        if (openSlots.documents.isEmpty) {
          throw Exception('No matching assignment found.');
        }
        assignmentId = openSlots.documents.first.$id;
      }

      await _database.updateDocument(
        databaseId: AppwriteConfig().mainDatabaseId,
        collectionId: AppwriteConfig().teamAssignmentsCollectionId,
        documentId: assignmentId,
        data: {
          'status': newStatus.name,
          'user': user.id
        },
      );

      return true;
    } catch (e) {
      print('Error while updating status: $e');
      return false;
    }
  }

  Future<List<Event>> loadUserEvents(UserModelUserView user) async {
    final updatedUser = await getUserInformation();
    if (updatedUser != null) {
      return updatedUser.events;
    }
    return [];
  }




  Future<UserModelUserView?> getUserInformation() async {
    try {
      final user = await AuthService().getCurrentUser();
      if (user == null) return null;

      final userID = user.$id;

      final userDocument = await _database.listDocuments(
        databaseId: AppwriteConfig().mainDatabaseId,
        collectionId: AppwriteConfig().usersCollectionID,
        queries: [Query.equal("auth_id", userID)],
      );

      if (userDocument.documents.isEmpty) {
        // Auto-create document for local dev if missing
        try {
          await _database.createDocument(
            databaseId: AppwriteConfig().mainDatabaseId,
            collectionId: AppwriteConfig().usersCollectionID,
            documentId: ID.unique(),
            data: {
              "auth_id": userID
            },
            permissions: [Permission.read(Role.user(userID)), Permission.write(Role.user(userID))]
          );
        } catch (e) {
          print("Could not auto-create user document: $e");
        }
        return UserModelUserView(
            id: userID,
            name: user.name,
            mail: user.email,
            phone: user.phone,
            flightSchools: [],
            events: []
        );
      }

      final userDocumentData = userDocument.documents.first.data;
      final membershipsList = (userDocumentData["memberships"] as List?) ?? [];

      final List<FlightSchoolUserView> flightSchools = [];
      for (final membershipItem in membershipsList) {
        Map<String, dynamic>? membership;
        if (membershipItem is String) {
          try {
             final mDoc = await _database.getDocument(
                databaseId: AppwriteConfig().mainDatabaseId,
                collectionId: AppwriteConfig().membershipsId,
                documentId: membershipItem,
             );
             membership = mDoc.data;
          } catch(e) {
             print("Fehler beim Laden der Membership: $e");
             continue;
          }
        } else if (membershipItem is Map) {
           membership = Map<String, dynamic>.from(membershipItem);
        } else {
           continue;
        }

        final fsField = membership["flightSchools"];
        if (fsField != null) {
          String fsId = "";
          if (fsField is String) {
            fsId = fsField;
          } else if (fsField is Map) {
            fsId = fsField["\$id"] ?? "";
          }

          if (fsId.isNotEmpty) {
            try {
              final fsDoc = await _database.getDocument(
                databaseId: AppwriteConfig().mainDatabaseId,
                collectionId: AppwriteConfig().flightSchoolsCollectionId,
                documentId: fsId,
              );
              final fsData = fsDoc.data;
              flightSchools.add(FlightSchoolUserView(
                id: fsDoc.$id,
                displayName: fsData["display_name"] ?? "",
                displayShortName: fsData["display_short_name"] ?? "",
                membershipStatus: MembershipStatusEnum.values.firstWhere(
                  (e) => e.name == membership?["status"],
                  orElse: () => MembershipStatusEnum.inactive
                ),
                availableRoles: (membership?["roles"] as List? ?? [])
                    .map((r) => EventRoleEnum.values.byName(r.toString()))
                    .toList(),
                databaseId: fsData["database_id"] ?? "",
                teamAssignmentsEventsCollectionId: fsData["team_assigments_events_id"] ?? "",
                eventsCollectionId: fsData["events_id"] ?? "",
                auditLogsCollectionId: fsData["audit_logs_id"] ?? "",
                adminUserIds: List<String>.from(fsData["admin_users"] ?? []),
                logoLink: fsData["logo_link"] ?? "",
              ));
            } catch (e) {
              print("Fehler beim Laden der Flugschule $fsId: $e");
            }
          }
        }
      }
      final List<Event> allEvents = [];

      for (final flightSchool in flightSchools) {
        try {
          // Fetch all events for this flight school
          final eventsResult = await _database.listDocuments(
            databaseId: AppwriteConfig().mainDatabaseId,
            collectionId: AppwriteConfig().eventsCollectionId,
            queries: [
              Query.equal("flight_school", flightSchool.id),
              Query.orderDesc("start_time"),
            ],
          );

          for (final eventDoc in eventsResult.documents) {
            final eventData = eventDoc.data;

            // Fetch all team assignments for this event
            final teamDocs = await _database.listDocuments(
              databaseId: AppwriteConfig().mainDatabaseId,
              collectionId: AppwriteConfig().teamAssignmentsCollectionId,
              queries: [
                Query.equal("events", eventDoc.$id),
              ],
            );

            bool isUserInvolvedOrOpen = false;
            Map<String, dynamic>? userAssignment;

            final teamMembers = teamDocs.documents.map((doc) {
              final data = doc.data;
              final userField = data["user"];
              String assignedUserId = "";
              if (userField is String) {
                assignedUserId = userField;
              } else if (userField is Map) {
                assignedUserId = userField["\$id"] ?? "";
              }

              if (assignedUserId == userID) {
                isUserInvolvedOrOpen = true;
                userAssignment = data;
              } else if (assignedUserId.isEmpty) {
                isUserInvolvedOrOpen = true;
              }

              return TeamMember(
                  userId: assignedUserId.isEmpty ? "slot_${doc.$id}" : assignedUserId,
                  name: userField is Map ? (userField["name"] ?? "") : "",
                  role: data["role"] ?? "",
                  status: data["status"] ?? ""
              );
            }).toList();

            if (!isUserInvolvedOrOpen) continue;

            allEvents.add(Event(
              id: eventDoc.$id,
              flightSchoolId: flightSchool.id,
              identifier: (eventData["identifier"] ?? "").toString(),
              status: EventStatusEnum.values.firstWhere(
                (e) => e.name == eventData["status"],
                orElse: () => EventStatusEnum.provisional
              ),
              startTime: DateTime.parse(eventData["start_time"]),
              endTime: DateTime.parse(eventData["end_time"]),
              displayName: (eventData["display_name"] ?? "").toString(),
              team: teamMembers,
              location: (eventData["location"] ?? "").toString(),
              notes: (eventData["notes"] ?? "").toString(),
              role: userAssignment != null ? EventRoleEnum.values.firstWhere(
                (e) => e.name == userAssignment!["role"],
                orElse: () => EventRoleEnum.trainee
              ) : EventRoleEnum.trainee,
              assignmentStatus: userAssignment != null ? EventUserStatusEnum.values.firstWhere(
                (e) => e.name == userAssignment!["status"],
                orElse: () => EventUserStatusEnum.open
              ) : EventUserStatusEnum.open,
            ));
          }
        } catch (e) {
          print("Fehler beim Laden der Events für Flugschule ${flightSchool.id}: $e");
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
      databaseId: AppwriteConfig().mainDatabaseId,
      collectionId: AppwriteConfig().eventsCollectionId,
      documentId: ID.unique(),
      data: {
        "flight_school": fs.id,
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
      final data = <String, dynamic>{
        "role": tm.role,
        "status": tm.status,
        "events": created.id,
      };
      if (!tm.isSlot && tm.userId.isNotEmpty) {
        data["user"] = tm.userId;
      }

      await _database.createDocument(
        databaseId: AppwriteConfig().mainDatabaseId,
        collectionId: AppwriteConfig().teamAssignmentsCollectionId,
        documentId: ID.unique(),
        data: data,
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
      databaseId: AppwriteConfig().mainDatabaseId,
      collectionId: AppwriteConfig().eventsCollectionId,
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
      databaseId: AppwriteConfig().mainDatabaseId,
      collectionId: AppwriteConfig().teamAssignmentsCollectionId,
      queries: [
        Query.equal("events", event.id),
        Query.limit(500),
      ],
    );

    final Map<String, dynamic> existingByKey = {};
    for (final doc in existing.documents) {
      final data = doc.data;
      final userField = data["user"];
      String userId = "";
      if (userField is String) {
        userId = userField;
      } else if (userField is Map) {
        userId = userField["\$id"] ?? "";
      }

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
            databaseId: AppwriteConfig().mainDatabaseId,
            collectionId: AppwriteConfig().teamAssignmentsCollectionId,
            documentId: docId,
          );
        }
      } else if (isExistingSlot) {
        await _database.deleteDocument(
          databaseId: AppwriteConfig().mainDatabaseId,
          collectionId: AppwriteConfig().teamAssignmentsCollectionId,
          documentId: docId,
        );
      }
    }

    for (final entry in newByKey.entries) {
      final key = entry.key;
      final tm = entry.value;

      if (key.startsWith("slot:new:")) {
        await _database.createDocument(
          databaseId: AppwriteConfig().mainDatabaseId,
          collectionId: AppwriteConfig().teamAssignmentsCollectionId,
          documentId: ID.unique(),
          data: {
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
          databaseId: AppwriteConfig().mainDatabaseId,
          collectionId: AppwriteConfig().teamAssignmentsCollectionId,
          documentId: ID.unique(),
          data: {
            "user": tm.userId,
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
            databaseId: AppwriteConfig().mainDatabaseId,
            collectionId: AppwriteConfig().teamAssignmentsCollectionId,
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