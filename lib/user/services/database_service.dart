import 'dart:math';
import 'dart:typed_data';
import 'package:appwrite/appwrite.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/core/data/enums/event_status_enum.dart';
import 'package:season_planner/core/data/enums/event_user_status_enum.dart';
import 'package:season_planner/core/data/enums/membership_status_enum.dart';
import 'package:season_planner/core/data/enums/subscription_status_enum.dart';
import 'package:season_planner/core/data/enums/team_tier_enum.dart';
import 'package:season_planner/core/data/models/event_model.dart';
import 'package:season_planner/core/data/models/planning_period_model.dart';
import 'package:season_planner/core/data/models/tandem_model.dart';
import 'package:season_planner/core/data/models/team_role_model.dart';
import 'package:season_planner/core/services/appwrite_pagination.dart';
import 'package:season_planner/core/services/audit_log_service.dart';
import 'package:season_planner/core/services/auth_service.dart';
import 'package:season_planner/core/services/data_window.dart';
import 'package:season_planner/core/services/file_optimization_service.dart';
import 'package:season_planner/core/services/planning_service.dart';
import 'package:season_planner/core/services/qualification_service.dart';
import 'package:season_planner/core/services/security_privacy_service.dart';
import 'package:season_planner/core/services/tandem_service.dart';
import 'package:season_planner/user/data/models/flight_school_model_user_view.dart';
import 'package:season_planner/user/data/models/user_model_userView.dart';
import '../../core/appwrite_config.dart';
import '../../fsAdmin/flight_school_provider.dart';

class PublicFlightSchoolSummary {
  final String id;
  final String displayName;
  final String displayShortName;
  final String logoLink;

  const PublicFlightSchoolSummary({
    required this.id,
    required this.displayName,
    required this.displayShortName,
    required this.logoLink,
  });
}

enum RecurrenceFrequency {
  none('Keine Wiederholung'),
  weekly('Wöchentlich'),
  biweekly('Alle 2 Wochen'),
  monthly('Monatlich');

  final String label;
  const RecurrenceFrequency(this.label);
}

class DatabaseService {
  Client get client => AuthService().client;

  static final DatabaseService _instance = DatabaseService._internal();

  factory DatabaseService() {
    return _instance;
  }
  DatabaseService._internal();

  late final TablesDB _tablesDB;
  late final Storage _storage;
  bool _initialized = false;

  void init() {
    if (_initialized) return;
    _tablesDB = TablesDB(client);
    _storage = Storage(client);
    _initialized = true;
  }

  TablesDB get tablesDB {
    if (!_initialized) init();
    return _tablesDB;
  }

  Storage get storage {
    if (!_initialized) init();
    return _storage;
  }

  // ==================== MITGLIEDSCHAFTEN & ONBOARDING ====================

  Future<List<PublicFlightSchoolSummary>> listAllFlightSchools() async {
    try {
      final cfg = AppwriteConfig();
      final res = await tablesDB.listRows(
        databaseId: cfg.mainDatabaseId,
        tableId: cfg.flightSchoolsCollectionId,
        queries: [Query.limit(200)],
      );
      final list = res.rows.map((r) {
        return PublicFlightSchoolSummary(
          id: r.$id,
          displayName: (r.data['display_name'] ?? 'Unbenannte Flugschule').toString(),
          displayShortName: (r.data['display_short_name'] ?? '').toString(),
          logoLink: (r.data['logo_link'] ?? '').toString(),
        );
      }).toList();
      list.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
      return list;
    } catch (e) {
      debugPrint('listAllFlightSchools error: $e');
      return [];
    }
  }

  /// Legt für jede gewählte Flugschule serverseitig eine Beitrittsanfrage (`status: requested`) an.
  Future<int> requestJoinFlightSchools(List<String> flightSchoolIds) async {
    final user = await AuthService().getCurrentUser();
    if (user == null) throw Exception('Kein angemeldeter Benutzer.');
    await AuthService().ensureUserProfileRow(user: user);
    return SecurityPrivacyService().requestJoinFlightSchools(flightSchoolIds);
  }

  /// Erstellt eine neue Flugschule (`subscription_status: pending`),
  /// macht den aktuellen Nutzer zum ersten Admin, legt die 4 Standardrollen
  /// sowie eine initiale Planungsperiode an.
  Future<String> createFlightSchool({
    required String displayName,
    required String displayShortName,
  }) async {
    final user = await AuthService().getCurrentUser();
    if (user == null) throw Exception('Kein angemeldeter Benutzer.');
    final userRow = await AuthService().ensureUserProfileRow(user: user);
    final userRowId = userRow?.$id ?? user.$id;

    final cfg = AppwriteConfig();
    final schoolRow = await tablesDB.createRow(
      databaseId: cfg.mainDatabaseId,
      tableId: cfg.flightSchoolsCollectionId,
      rowId: ID.unique(),
      data: {
        'display_name': displayName.trim(),
        'display_short_name': displayShortName.trim().isEmpty
            ? displayName.trim()
            : displayShortName.trim(),
        'database_id': cfg.seasonPlannerDatabaseId,
        'events_id': cfg.eventsTableId,
        'team_assigments_events_id': cfg.teamAssignmentsEventsTableId,
        'audit_logs_id': cfg.auditLogsTableId,
        'admin_users': [user.$id],
        'inventoryEnabled': true,
        'seasonPlannerEnabled': true,
        'subscription_status': SubscriptionStatusEnum.pending.name,
      },
      permissions: [
        Permission.read(Role.users()),
        Permission.update(Role.user(user.$id)),
        Permission.delete(Role.user(user.$id)),
      ],
    );

    final schoolId = schoolRow.$id;

    // Appwrite-Team für diese Flugschule anlegen & Gründer als Admin+Member aufnehmen
    await SecurityPrivacyService().syncSchoolTeam(schoolId);

    // 4 Standard-Qualifikationen & 5 Standard-Einsatzrollen automatisch anlegen
    await QualificationService().ensureDefaultQualifications(schoolId);
    final roles = await QualificationService().ensureDefaultRoles(schoolId);

    // Erste Mitgliedschaft als aktiv anlegen
    await tablesDB.createRow(
      databaseId: cfg.mainDatabaseId,
      tableId: cfg.membershipsId,
      rowId: ID.unique(),
      data: {
        'users': userRowId,
        'flightSchools': schoolId,
        'status': MembershipStatusEnum.active.name,
        'roles': roles.map((r) => r.name).toList(),
        'qualifications': <String>[],
        'requested_qualifications': <String>[],
      },
      permissions: SecurityPrivacyService.ownerAndSchoolAdminPerms(
        userId: user.$id,
        flightSchoolId: schoolId,
        allowOwnerDelete: true,
      ),
    );
    await SecurityPrivacyService().syncSchoolTeam(schoolId);

    // Initiale Planungsperiode für das aktuelle Jahr
    final year = DateTime.now().year;
    await PlanningService().createPeriod(
      flightSchoolId: schoolId,
      seasonLabel: 'Saison $year',
      stage: PlanningStage.production,
      startDate: DateTime(year, 1, 1),
      endDate: DateTime(year, 12, 31),
    );

    await AuditLogService().log(
      flightSchoolId: schoolId,
      userId: user.$id,
      action: 'Flugschule angelegt',
      details: '„${displayName.trim()}“ erstellt (Status: Abo wird aktiviert)',
    );

    return schoolId;
  }

  Future<bool> acceptMembership({
    required String flightSchoolId,
  }) async {
    try {
      final user = await AuthService().getCurrentUser();
      if (user == null) return false;

      final userRow = await AuthService().ensureUserProfileRow(user: user);
      final userRowId = userRow?.$id ?? user.$id;
      final cfg = AppwriteConfig();

      final memberships = await tablesDB.listRows(
        databaseId: cfg.mainDatabaseId,
        tableId: cfg.membershipsId,
        queries: [
          Query.equal("users", userRowId),
          Query.equal("flightSchools", [flightSchoolId]),
          Query.limit(1),
        ],
      );

      if (memberships.rows.isEmpty) {
        throw Exception("Mitgliedschaft nicht gefunden.");
      }

      await tablesDB.updateRow(
        databaseId: cfg.mainDatabaseId,
        tableId: cfg.membershipsId,
        rowId: memberships.rows.first.$id,
        data: {
          "status": MembershipStatusEnum.active.name,
        },
      );
      await SecurityPrivacyService().syncSchoolTeam(flightSchoolId);

      return true;
    } catch (e) {
      debugPrint("acceptMembership error: $e");
      return false;
    }
  }

  /// Löscht die Membership (User verlässt Flugschule oder zieht Anfrage zurück).
  Future<bool> leaveMembership({
    required String flightSchoolId,
  }) async {
    try {
      final user = await AuthService().getCurrentUser();
      if (user == null) return false;

      final userRow = await AuthService().ensureUserProfileRow(user: user);
      final userRowId = userRow?.$id ?? user.$id;
      final cfg = AppwriteConfig();

      final memberships = await tablesDB.listRows(
        databaseId: cfg.mainDatabaseId,
        tableId: cfg.membershipsId,
        queries: [
          Query.equal("users", userRowId),
          Query.equal("flightSchools", [flightSchoolId]),
          Query.limit(1),
        ],
      );

      if (memberships.rows.isEmpty) {
        throw Exception("Mitgliedschaft nicht gefunden.");
      }

      await tablesDB.deleteRow(
        databaseId: cfg.mainDatabaseId,
        tableId: cfg.membershipsId,
        rowId: memberships.rows.first.$id,
      );
      // Dokument-Freigaben, Datei-Leserechte & Appwrite-Team-Zugang für diese Schule sofort entziehen
      await SecurityPrivacyService().revokeSchoolAccess(
        flightSchoolId: flightSchoolId,
      );

      return true;
    } catch (e) {
      debugPrint("leaveMembership error: $e");
      return false;
    }
  }

  /// Lädt ein Profilbild in den Storage-Bucket `user_avatars` hoch und
  /// speichert URL & File-ID in `core_db.users`.
  Future<({String url, String fileId})?> uploadUserAvatar({
    required Uint8List bytes,
    required String filename,
    String? oldAvatarFileId,
  }) async {
    try {
      final current = await AuthService().getCurrentUser();
      if (current == null) return null;
      final userRow = await AuthService().ensureUserProfileRow(user: current);
      if (userRow == null) return null;

      final optimized = await FileOptimizationService().optimizeAvatarOrLogo(
        bytes: bytes,
        fileName: filename,
      );

      final cfg = AppwriteConfig();
      final uploaded = await storage.createFile(
        bucketId: cfg.userAvatarsBucketId,
        fileId: ID.unique(),
        file: InputFile.fromBytes(
          bytes: optimized.bytes,
          filename: optimized.fileName,
        ),
        permissions: [
          Permission.read(Role.users()),
          Permission.update(Role.user(current.$id)),
          Permission.delete(Role.user(current.$id)),
        ],
      );

      if (oldAvatarFileId != null && oldAvatarFileId.trim().isNotEmpty) {
        try {
          await storage.deleteFile(
            bucketId: cfg.userAvatarsBucketId,
            fileId: oldAvatarFileId.trim(),
          );
        } catch (_) {}
      }

      final url = cfg.fileViewUrl(cfg.userAvatarsBucketId, uploaded.$id);
      await tablesDB.updateRow(
        databaseId: cfg.mainDatabaseId,
        tableId: cfg.usersCollectionID,
        rowId: userRow.$id,
        data: {
          'avatar_url': url,
          'avatar_file_id': uploaded.$id,
        },
      );

      return (url: url, fileId: uploaded.$id);
    } catch (e) {
      debugPrint('uploadUserAvatar error: $e');
      return null;
    }
  }

  /// Entfernt das aktuelle Profilbild aus Storage (falls vorhanden) und `core_db.users`.
  Future<bool> removeUserAvatar({String? oldAvatarFileId}) async {
    try {
      final current = await AuthService().getCurrentUser();
      if (current == null) return false;
      final userRow = await AuthService().ensureUserProfileRow(user: current);
      if (userRow == null) return false;

      final cfg = AppwriteConfig();
      if (oldAvatarFileId != null && oldAvatarFileId.trim().isNotEmpty) {
        try {
          await storage.deleteFile(
            bucketId: cfg.userAvatarsBucketId,
            fileId: oldAvatarFileId.trim(),
          );
        } catch (_) {}
      }

      await tablesDB.updateRow(
        databaseId: cfg.mainDatabaseId,
        tableId: cfg.usersCollectionID,
        rowId: userRow.$id,
        data: {
          'avatar_url': '',
          'avatar_file_id': '',
        },
      );
      return true;
    } catch (e) {
      debugPrint('removeUserAvatar error: $e');
      return false;
    }
  }

  Future<bool> updateAccount({
    required String firstName,
    required String lastName,
    required String email,
    String phone = "",
    String? password,
    String? emergencyContactName,
    String? emergencyContactRelation,
    String? emergencyContactPhone,
    String? birthDate,
    String? address,
    String? licenseNumber,
    String? licenseRatings,
    String? employmentType,
    String? activeSince,
  }) async {
    try {
      final account = AuthService().account;
      final fullName = "${firstName.trim()} ${lastName.trim()}".trim();
      if (fullName.isNotEmpty) {
        await account.updateName(name: fullName);
      }

      final current = await account.get();
      final currentEmail = current.email;

      if (email.trim().isNotEmpty && email.trim() != currentEmail) {
        if (password == null || password.isEmpty) {
          throw Exception("Für eine E-Mail-Änderung wird dein Passwort benötigt.");
        }
        await account.updateEmail(
          email: email.trim(),
          password: password,
        );
      }

      final trimmedPhone = phone.trim();
      final prefs = Map<String, dynamic>.from(current.prefs.data);
      final oldPrefsPhone = (prefs['phone'] ?? '').toString().trim();
      if (trimmedPhone != oldPrefsPhone) {
        if (trimmedPhone.isNotEmpty) {
          prefs['phone'] = trimmedPhone;
        } else if (prefs.containsKey('phone')) {
          // Appwrite lehnt ein komplett leeres JSON-Objekt `{}` bei PATCH /account/prefs mit 400 ab.
          if (prefs.length <= 1) {
            prefs['phone'] = '';
          } else {
            prefs.remove('phone');
          }
        }
        if (prefs.isNotEmpty) {
          try {
            await account.updatePrefs(prefs: prefs);
          } catch (e) {
            debugPrint('updateAccount prefs warning: $e');
          }
        }
      }

      // Auch in core_db.users synchronisieren
      final cfg = AppwriteConfig();
      try {
        final userRow = await AuthService().ensureUserProfileRow(
          user: current,
          phoneOverride: trimmedPhone,
        );
        if (userRow != null) {
          await tablesDB.updateRow(
            databaseId: cfg.mainDatabaseId,
            tableId: cfg.usersCollectionID,
            rowId: userRow.$id,
            data: {
              'name': fullName,
              'email': email.trim(),
              'phone': trimmedPhone,
              if (emergencyContactName != null)
                'emergency_contact_name': emergencyContactName.trim(),
              if (emergencyContactRelation != null)
                'emergency_contact_relation': emergencyContactRelation.trim(),
              if (emergencyContactPhone != null)
                'emergency_contact_phone': emergencyContactPhone.trim(),
              if (birthDate != null) 'birth_date': birthDate.trim(),
              if (address != null) 'address': address.trim(),
              if (licenseNumber != null) 'license_number': licenseNumber.trim(),
              if (licenseRatings != null)
                'license_ratings': licenseRatings.trim(),
              if (employmentType != null)
                'employment_type': employmentType.trim(),
              if (activeSince != null) 'active_since': activeSince.trim(),
            },
          );
        }
      } catch (e) {
        debugPrint('updateAccount core_db.users sync warning: $e');
      }

      return true;
    } catch (e) {
      debugPrint("updateAccount error: $e");
      return false;
    }
  }

  // ==================== EVENT-WORKFLOW (NUTZER) ====================

  Future<bool> changeEventAssignmentStatus({
    required UserModelUserView user,
    required Event event,
    required EventUserStatusEnum newStatus,
  }) async {
    try {
      final flightSchool = user.flightSchools.firstWhere(
        (fs) => fs.id == event.flightSchoolId,
        orElse: () => throw Exception("Flugschule nicht gefunden."),
      );

      await tablesDB.updateRow(
        databaseId: flightSchool.databaseId,
        tableId: flightSchool.teamAssignmentsEventsCollectionId,
        rowId: event.id,
        data: {
          'status': newStatus.name,
          'user_id': user.id,
          'name': user.name,
        },
      );

      await AuditLogService().log(
        flightSchoolId: flightSchool.id,
        userId: user.id,
        action: 'Zuweisungsstatus geändert',
        details:
            'Event „${event.displayName}“ (${event.roleLabel}): ${newStatus.label()}',
      );

      return true;
    } catch (e) {
      debugPrint('Error while updating status: $e');
      return false;
    }
  }

  Future<List<Event>> loadUserEvents(
    UserModelUserView user, {
    bool includeArchive = false,
  }) async {
    final userID = user.id;
    final activeSchools = user.flightSchools
        .where((fs) => fs.membershipStatus == MembershipStatusEnum.active)
        .toList();
    if (activeSchools.isEmpty) return const [];

    final windowStartIso = DataWindow.defaultStart().toIso8601String();
    final windowEndIso = DataWindow.defaultEnd().toIso8601String();

    bool isBindingStatus(EventUserStatusEnum s) =>
        s == EventUserStatusEnum.accepted_flight_school ||
        s == EventUserStatusEnum.accepted_user ||
        s == EventUserStatusEnum.user_requests_change;

    final perSchoolLists = await Future.wait(
      activeSchools.map((flightSchool) async {
        final schoolEvents = <Event>[];
        try {
          // 1) Events dieser Flugschule im Zeitfenster über zusammengesetzten Index
          //    (flight_school_id, start_time / end_time) laden
          final eventQueries = <String>[
            Query.equal('flight_school_id', flightSchool.id),
            if (!includeArchive) ...[
              Query.greaterThanEqual('end_time', windowStartIso),
              Query.lessThanEqual('start_time', windowEndIso),
            ],
            Query.orderAsc('start_time'),
          ];
          final schoolEventRows = await listAllRows(
            tablesDB,
            databaseId: flightSchool.databaseId,
            tableId: flightSchool.eventsCollectionId,
            queries: eventQueries,
          );
          if (schoolEventRows.isEmpty) return schoolEvents;

          final eventDataById = <String, Map<String, dynamic>>{
            for (final ev in schoolEventRows) ev.$id: ev.data,
          };

          // 2) Team-Zuweisungen streng auf die geladenen Event-IDs dieser Flugschule
          //    gebündelt in 100er-Chunks laden (kein schulübergreifender Vollscan!)
          final allAssignmentsByEventId =
              <String, List<({String id, Map<String, dynamic> data})>>{};
          final eventIds = eventDataById.keys.toList();
          final chunkResults = await Future.wait(
            chunkList(eventIds, size: 100).map((chunk) {
              return listAllRows(
                tablesDB,
                databaseId: flightSchool.databaseId,
                tableId: flightSchool.teamAssignmentsEventsCollectionId,
                queries: [
                  Query.equal('events', chunk),
                  Query.select(['*', 'events.\$id']),
                ],
              );
            }),
          );

          for (final rows in chunkResults) {
            for (final row in rows) {
              final rawEv = row.data['events'];
              final evId = rawEv is Map
                  ? (rawEv['\$id'] ?? '').toString()
                  : (rawEv ?? '').toString();
              if (evId.isEmpty || !eventDataById.containsKey(evId)) continue;
              final mapWithId = Map<String, dynamic>.from(row.data);
              mapWithId['\$id'] = row.$id;
              allAssignmentsByEventId
                  .putIfAbsent(evId, () => [])
                  .add((id: row.$id, data: mapWithId));
            }
          }

          // 3) Erkennen, bei welchen Events der Nutzer verbindlich eingeplant ist
          final userScheduledEventIds = <String>{};
          for (final entry in allAssignmentsByEventId.entries) {
            for (final item in entry.value) {
              final assignedUserId = (item.data['user_id'] ?? '').toString();
              final rawStatus = EventUserStatusLabelX.parse(item.data['status']);
              if (assignedUserId == userID && isBindingStatus(rawStatus)) {
                userScheduledEventIds.add(entry.key);
              }
            }
          }

          // 4) Team-Liste & Avatare nur für verbindlich eingeplante Stufe-2/3-Events aufbauen
          final teamCache = <String, List<TeamMember>>{};
          final avatarByUserId = <String, String>{};
          final rawByEvent = <String, List<TeamMember>>{};
          final allMemberUserIds = <String>{};

          for (final evId in userScheduledEventIds) {
            final evData = eventDataById[evId];
            if (evData == null) continue;
            final startParsed = DateTime.tryParse(
              (evData['start_time'] ?? '').toString(),
            );
            if (startParsed == null) continue;
            final storedPeriodId =
                (evData['planning_period_id'] ?? '').toString();
            final period = resolvePlanningPeriod(
              flightSchool.planningPeriods,
              startParsed,
              fallbackPeriodId: storedPeriodId,
            );
            if ((period?.stage.value ?? 3) < 2) continue;

            final rawList = allAssignmentsByEventId[evId] ?? const [];
            for (final item in rawList) {
              final tm = TeamMember.fromMap(item.data);
              rawByEvent.putIfAbsent(evId, () => []).add(tm);
              if (!tm.isSlot && tm.userId.trim().isNotEmpty) {
                allMemberUserIds.add(tm.userId.trim());
              }
            }
          }

          if (allMemberUserIds.isNotEmpty) {
            try {
              final publicProfiles = await SecurityPrivacyService()
                  .getTeamPublicProfiles([flightSchool.id]);
              for (final entry in publicProfiles.entries) {
                if (entry.value.avatarUrl.isNotEmpty) {
                  avatarByUserId[entry.key] = entry.value.avatarUrl;
                }
              }
            } catch (e) {
              debugPrint('ensureAvatarsLoaded error: $e');
            }
          }

          for (final entry in rawByEvent.entries) {
            teamCache[entry.key] = entry.value
                .map((m) => m.isSlot
                    ? m
                    : m.copyWith(avatarUrl: avatarByUserId[m.userId] ?? ''))
                .toList();
          }

          // 5) Relevante Zuweisungen (eigene, offene Slots, Tausch-Angebote) auswerten
          final isTandemOnly = flightSchool.isTandemOnly;
          final isExtendedTeam = flightSchool.isExtendedTeam;

          final seenStage1EventIds = <String>{};
          for (final evRow in schoolEventRows) {
            final eventDocId = evRow.$id;
            final eventData = evRow.data;
            final assignments = allAssignmentsByEventId[eventDocId] ?? const [];

            DateTime startTime;
            DateTime endTime;
            try {
              startTime = DateTime.parse(eventData['start_time']);
              endTime = DateTime.parse(eventData['end_time']);
            } catch (rowErr) {
              debugPrint('Skipping malformed event $eventDocId: $rowErr');
              continue;
            }

            final storedPeriodId =
                (eventData['planning_period_id'] ?? '').toString();
            final period = resolvePlanningPeriod(
              flightSchool.planningPeriods,
              startTime,
              fallbackPeriodId: storedPeriodId,
            );
            final stage = period?.stage.value ?? 3;

            for (final item in assignments) {
              try {
                final data = item.data;
                final assignedUserId = (data['user_id'] ?? '').toString();
                final swapOffered = data['swap_offered'] == true;

                // Nur eigene Zuweisungen, offene Slots oder zum Tausch angebotene Plätze
                if (assignedUserId.isNotEmpty &&
                    assignedUserId != userID &&
                    !swapOffered) {
                  continue;
                }

                final rawStatus = EventUserStatusLabelX.parse(data['status']);
                final swapRequestedBy =
                    (data['swap_requested_by'] ?? '').toString();
                final swapRequestedByName =
                    (data['swap_requested_by_name'] ?? '').toString();

                final isSwapOfferFromOther = swapOffered &&
                    assignedUserId.isNotEmpty &&
                    assignedUserId != userID;
                final isOwnBinding =
                    assignedUserId == userID && isBindingStatus(rawStatus);
                final isOwnDirectRequest = assignedUserId == userID &&
                    rawStatus == EventUserStatusEnum.pending_user;
                final isUserScheduledInEvent =
                    isOwnBinding || userScheduledEventIds.contains(eventDocId);

                // Reine Tandempiloten sehen keine fremden Schul-Events –
                // nur eigene verbindliche Zuweisungen oder direkte Admin-Anfragen.
                if (isTandemOnly && !isOwnBinding && !isOwnDirectRequest) {
                  continue;
                }

                // Stufe 1 (Verfügbarkeit) ODER Erweitertes Team (dauerhaft ohne Details)
                final prevStartRaw =
                    (eventData['previous_start_time'] ?? '').toString().trim();
                final prevEndRaw =
                    (eventData['previous_end_time'] ?? '').toString().trim();
                final previousStartTime = prevStartRaw.isEmpty
                    ? null
                    : DateTime.tryParse(prevStartRaw);
                final previousEndTime =
                    prevEndRaw.isEmpty ? null : DateTime.tryParse(prevEndRaw);

                if (stage == 1 || (isExtendedTeam && !isOwnBinding && !isOwnDirectRequest)) {
                  if (isOwnBinding || isOwnDirectRequest) {
                    seenStage1EventIds.add(eventDocId);
                    schoolEvents.add(Event(
                      id: item.id,
                      eventDocId: eventDocId,
                      flightSchoolId: flightSchool.id,
                      identifier: (eventData['identifier'] ?? '').toString(),
                      status: EventStatusEnum.parse(eventData['status']),
                      startTime: startTime,
                      endTime: endTime,
                      displayName:
                          (eventData['display_name'] ?? 'Event').toString(),
                      team: const [],
                      location: (eventData['location'] ?? '').toString(),
                      notes: (eventData['notes'] ?? '').toString(),
                      role: (data['role'] ?? '').toString(),
                      assignmentStatus: rawStatus,
                      planningPeriodId: period?.id ??
                          (storedPeriodId.isEmpty ? null : storedPeriodId),
                      planningStage: 1,
                      seriesId: eventData['series_id']?.toString(),
                      swapOffered: false,
                      isSwapOfferFromOther: false,
                      assignedUserId: assignedUserId,
                      previousStartTime: previousStartTime,
                      previousEndTime: previousEndTime,
                    ));
                    continue;
                  }

                  if (isUserScheduledInEvent || isSwapOfferFromOther) continue;
                  if (seenStage1EventIds.contains(eventDocId)) continue;
                  seenStage1EventIds.add(eventDocId);

                  schoolEvents.add(Event(
                    id: isExtendedTeam && stage != 1
                        ? 'ext_$eventDocId'
                        : 'stage1_$eventDocId',
                    eventDocId: eventDocId,
                    flightSchoolId: flightSchool.id,
                    identifier: '',
                    status: EventStatusEnum.parse(eventData['status']),
                    startTime: startTime,
                    endTime: endTime,
                    displayName:
                        (eventData['display_name'] ?? 'Event').toString(),
                    team: const [],
                    location: (eventData['location'] ?? '').toString(),
                    notes: '',
                    role: '',
                    assignmentStatus: EventUserStatusEnum.open,
                    planningPeriodId: period?.id ??
                        (storedPeriodId.isEmpty ? null : storedPeriodId),
                    planningStage: stage == 1 ? 1 : stage,
                    seriesId: eventData['series_id']?.toString(),
                    swapOffered: false,
                    isSwapOfferFromOther: false,
                  ));
                  continue;
                }

                // Stufe 2 (Bewerbung): Noch keine Platztausch-Angebote anderer anzeigen
                if (stage == 2 && isSwapOfferFromOther) {
                  continue;
                }

                final List<TeamMember> teamMembers =
                    (stage >= 2 && isUserScheduledInEvent)
                        ? (teamCache[eventDocId] ?? const [])
                        : const [];

                schoolEvents.add(Event(
                  id: item.id,
                  eventDocId: eventDocId,
                  flightSchoolId: flightSchool.id,
                  identifier: (eventData['identifier'] ?? '').toString(),
                  status: EventStatusEnum.parse(eventData['status']),
                  startTime: startTime,
                  endTime: endTime,
                  displayName:
                      (eventData['display_name'] ?? 'Event').toString(),
                  team: teamMembers,
                  location: (eventData['location'] ?? '').toString(),
                  notes: (eventData['notes'] ?? '').toString(),
                  role: (data['role'] ?? '').toString(),
                  assignmentStatus: rawStatus,
                  planningPeriodId: period?.id ??
                      (storedPeriodId.isEmpty ? null : storedPeriodId),
                  planningStage: stage,
                  seriesId: eventData['series_id']?.toString(),
                  swapOffered: stage == 3 ? swapOffered : false,
                  swapRequestedBy: stage != 3 || swapRequestedBy.isEmpty
                      ? null
                      : swapRequestedBy,
                  swapRequestedByName: stage != 3 || swapRequestedByName.isEmpty
                      ? null
                      : swapRequestedByName,
                  isSwapOfferFromOther:
                      stage == 3 ? isSwapOfferFromOther : false,
                  assignedUserId:
                      assignedUserId.isEmpty ? null : assignedUserId,
                  previousStartTime: previousStartTime,
                  previousEndTime: previousEndTime,
                ));
              } catch (rowErr) {
                debugPrint('Skipping malformed assignment ${item.id}: $rowErr');
              }
            }

            // 6) Stufe-1-Events bzw. Vorschau-Events für das erweiterte Team ohne
            //    eigene/offene Team-Slots direkt ergänzen (nicht für reine Tandempiloten)
            if (!isTandemOnly &&
                (stage == 1 || isExtendedTeam) &&
                !seenStage1EventIds.contains(eventDocId) &&
                !userScheduledEventIds.contains(eventDocId)) {
              seenStage1EventIds.add(eventDocId);
              schoolEvents.add(Event(
                id: isExtendedTeam && stage != 1
                    ? 'ext_$eventDocId'
                    : 'stage1_$eventDocId',
                eventDocId: eventDocId,
                flightSchoolId: flightSchool.id,
                identifier: '',
                status: EventStatusEnum.parse(eventData['status']),
                startTime: startTime,
                endTime: endTime,
                displayName: (eventData['display_name'] ?? 'Event').toString(),
                location: (eventData['location'] ?? '').toString(),
                team: const [],
                notes: '',
                role: '',
                assignmentStatus: EventUserStatusEnum.open,
                planningPeriodId: period?.id,
                planningStage: stage == 1 ? 1 : stage,
                seriesId: eventData['series_id']?.toString(),
              ));
            }
          }
        } catch (e) {
          debugPrint('loadUserEvents error for school ${flightSchool.id}: $e');
        }
        return schoolEvents;
      }),
    );

    return perSchoolLists.expand((l) => l).toList();
  }

  Future<Map<String, String>> _resolveTandemPilotNames({
    required List<TandemDuty> duties,
    required String currentUserId,
  }) async {
    final pilotNames = <String, String>{};
    final schoolIds = duties
        .where((d) => d.userId.isNotEmpty && d.userId != currentUserId)
        .map((d) => d.flightSchoolId)
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    if (schoolIds.isEmpty) return pilotNames;

    try {
      final profiles = await SecurityPrivacyService().getTeamPublicProfiles(
        schoolIds,
      );
      for (final entry in profiles.entries) {
        if (entry.value.name.isNotEmpty) {
          pilotNames[entry.key] = entry.value.name;
        }
      }
    } catch (e) {
      debugPrint('resolveTandemPilotNames error: $e');
    }
    return pilotNames;
  }

  /// Selektives Realtime-Update: lädt nur die Events des Nutzers neu (1–2 Queries statt Vollladung).
  Future<UserModelUserView> refreshUserEventsOnly(
    UserModelUserView current, {
    bool? includeArchive,
  }) async {
    final effArchive = includeArchive ?? current.hasLoadedArchive;
    final events = await loadUserEvents(current, includeArchive: effArchive);
    return current.copyWith(
      events: events,
      hasLoadedArchive: effArchive,
    );
  }

  /// Selektives Realtime-Update: lädt nur Tandem-Dienste & -Bedarfe des Nutzers neu.
  Future<UserModelUserView> refreshUserTandemOnly(
    UserModelUserView current, {
    bool? includeArchive,
  }) async {
    final effArchive = includeArchive ?? current.hasLoadedArchive;
    final tandemSchools = current.flightSchools
        .where(
          (fs) =>
              fs.membershipStatus == MembershipStatusEnum.active &&
              fs.tandemEnabled &&
              fs.isTandemPilot,
        )
        .toList();
    if (tandemSchools.isEmpty) {
      return current.copyWith(
        tandemDuties: const [],
        tandemDemands: const [],
        hasLoadedArchive: effArchive,
      );
    }

    final results = await Future.wait([
      Future.wait(
        tandemSchools.map(
          (fs) => TandemService().listDutiesForSchool(
            fs.id,
            includeArchive: effArchive,
          ),
        ),
      ),
      Future.wait(
        tandemSchools.map((fs) => TandemService().listDemandsForSchool(fs.id)),
      ),
    ]);
    final allDuties = (results[0] as List<List<TandemDuty>>)
        .expand((l) => l)
        .toList();
    final allDemands = (results[1] as List<List<TandemDemand>>)
        .expand((l) => l)
        .toList();
    final pilotNames = await _resolveTandemPilotNames(
      duties: allDuties,
      currentUserId: current.id,
    );

    return current.copyWith(
      tandemDuties: allDuties,
      tandemDemands: allDemands,
      tandemPilotNamesById: {
        ...current.tandemPilotNamesById,
        ...pilotNames,
      },
      hasLoadedArchive: effArchive,
    );
  }

  Future<UserModelUserView?> getUserInformation({
    bool includeArchive = false,
  }) async {
    try {
      final user = await AuthService().getCurrentUser();
      if (user == null) return null;

      await AuthService().ensureUserProfileRow(user: user);

      final userID = user.$id;
      final cfg = AppwriteConfig();

      final userDocument = await tablesDB.listRows(
        databaseId: cfg.mainDatabaseId,
        tableId: cfg.usersCollectionID,
        queries: [
          Query.or([
            Query.equal("\$id", userID),
            Query.equal("auth_id", userID),
          ]),
          Query.select(['*', 'memberships.*', 'memberships.flightSchools.*']),
        ],
      );

      final List<FlightSchoolUserView> flightSchools = [];
      String avatarUrl = '';
      String avatarFileId = '';
      String emergencyContactName = '';
      String emergencyContactRelation = '';
      String emergencyContactPhone = '';
      String dbPhone = '';
      String birthDate = '';
      String address = '';
      String licenseNumber = '';
      String licenseRatings = '';
      String employmentType = '';
      String activeSince = '';

      if (userDocument.rows.isNotEmpty) {
        final userDocumentData = userDocument.rows.first.data;
        avatarUrl = (userDocumentData['avatar_url'] ?? '').toString();
        avatarFileId = (userDocumentData['avatar_file_id'] ?? '').toString();
        emergencyContactName =
            (userDocumentData['emergency_contact_name'] ?? '').toString();
        emergencyContactRelation =
            (userDocumentData['emergency_contact_relation'] ?? '').toString();
        emergencyContactPhone =
            (userDocumentData['emergency_contact_phone'] ?? '').toString();
        dbPhone = (userDocumentData['phone'] ?? '').toString();
        birthDate = (userDocumentData['birth_date'] ?? '').toString();
        address = (userDocumentData['address'] ?? '').toString();
        licenseNumber = (userDocumentData['license_number'] ?? '').toString();
        licenseRatings = (userDocumentData['license_ratings'] ?? '').toString();
        employmentType = (userDocumentData['employment_type'] ?? '').toString();
        activeSince = (userDocumentData['active_since'] ?? '').toString();
        final membershipsList =
            (userDocumentData["memberships"] as List?) ?? [];

        final validMemberships = membershipsList
            .whereType<Map>()
            .where((m) => m["flightSchools"] is Map)
            .toList();

        final loadedSchools = await Future.wait(
          validMemberships.map((membership) async {
            final fs = membership["flightSchools"] as Map;
            final fsId = (fs["\$id"] ?? "").toString();
            if (fsId.isEmpty) return null;

            final meta = await Future.wait([
              QualificationService().listTeamRoles(fsId),
              QualificationService().listQualifications(fsId),
              PlanningService().listPeriods(fsId),
            ]);
            final roles = meta[0] as List<TeamRole>;
            final qualifications = meta[1] as List<Qualification>;
            final periods = meta[2] as List<PlanningPeriod>;

            return FlightSchoolUserView(
              id: fsId,
              membershipId: (membership["\$id"] ?? "").toString(),
              displayName: (fs["display_name"] ?? "").toString(),
              displayShortName: (fs["display_short_name"] ?? "").toString(),
              membershipStatus:
                  MembershipStatusEnumX.parse(membership["status"]),
              subscriptionStatus:
                  SubscriptionStatusEnumX.parse(fs["subscription_status"]),
              teamTier: TeamTierEnum.parse(membership["team_tier"]),
              availableRoles: (membership["roles"] as List? ?? [])
                  .map((r) => r.toString())
                  .where((r) => r.isNotEmpty)
                  .toList(),
              assignedQualificationIds:
                  (membership["qualifications"] as List? ?? [])
                      .map((q) => q.toString())
                      .where((q) => q.isNotEmpty)
                      .toList(),
              requestedQualificationIds:
                  (membership["requested_qualifications"] as List? ?? [])
                      .map((q) => q.toString())
                      .where((q) => q.isNotEmpty)
                      .toList(),
              databaseId:
                  (fs["database_id"] ?? cfg.seasonPlannerDatabaseId).toString(),
              teamAssignmentsEventsCollectionId:
                  (fs["team_assigments_events_id"] ??
                          cfg.teamAssignmentsEventsTableId)
                      .toString(),
              eventsCollectionId:
                  (fs["events_id"] ?? cfg.eventsTableId).toString(),
              auditLogsCollectionId:
                  (fs["audit_logs_id"] ?? cfg.auditLogsTableId).toString(),
              adminUserIds: List<String>.from(fs["admin_users"] ?? const []),
              logoLink: (fs["logo_link"] ?? "").toString(),
              teamRoles: roles,
              qualifications: qualifications,
              planningPeriods: periods,
              tandemEnabled: fs["tandem_enabled"] != false,
              timesheetEnabled: fs["timesheet_enabled"] != false,
              timesheetQualificationIds:
                  (fs["timesheet_qualification_ids"] as List? ?? const [])
                      .map((e) => e.toString().trim())
                      .where((e) => e.isNotEmpty)
                      .toList(),
            );
          }),
        );

        flightSchools.addAll(loadedSchools.whereType<FlightSchoolUserView>());
      }

      // Auch Flugschulen laden, bei denen der Nutzer in `admin_users` steht,
      // aber (z. B. nach Austritt aus dem Team) keine reguläre `memberships`-Zeile hat.
      final List<FlightSchoolUserView> adminOnlyFlightSchools = [];
      try {
        final userRowId = userDocument.rows.isNotEmpty
            ? userDocument.rows.first.$id
            : userID;
        final knownSchoolIds = flightSchools.map((fs) => fs.id).toSet();
        final allSchoolsRes = await tablesDB.listRows(
          databaseId: cfg.mainDatabaseId,
          tableId: cfg.flightSchoolsCollectionId,
          queries: [Query.limit(200)],
        );
        for (final row in allSchoolsRes.rows) {
          final fsId = row.$id;
          if (knownSchoolIds.contains(fsId)) continue;
          final adminIds = List<String>.from(row.data['admin_users'] ?? const []);
          if (!adminIds.contains(userID) && !adminIds.contains(userRowId)) {
            continue;
          }
          adminOnlyFlightSchools.add(
            FlightSchoolUserView(
              id: fsId,
              membershipId: '',
              displayName: (row.data['display_name'] ?? '').toString(),
              displayShortName:
                  (row.data['display_short_name'] ?? '').toString(),
              membershipStatus: MembershipStatusEnum.inactive,
              subscriptionStatus: SubscriptionStatusEnumX.parse(
                row.data['subscription_status'],
              ),
              teamTier: TeamTierEnum.core,
              availableRoles: const [],
              assignedQualificationIds: const [],
              requestedQualificationIds: const [],
              databaseId:
                  (row.data['database_id'] ?? cfg.seasonPlannerDatabaseId)
                      .toString(),
              teamAssignmentsEventsCollectionId:
                  (row.data['team_assigments_events_id'] ??
                          cfg.teamAssignmentsEventsTableId)
                      .toString(),
              eventsCollectionId:
                  (row.data['events_id'] ?? cfg.eventsTableId).toString(),
              auditLogsCollectionId:
                  (row.data['audit_logs_id'] ?? cfg.auditLogsTableId)
                      .toString(),
              adminUserIds: adminIds,
              logoLink: (row.data['logo_link'] ?? '').toString(),
              tandemEnabled: row.data['tandem_enabled'] != false,
              timesheetEnabled: row.data['timesheet_enabled'] != false,
              timesheetQualificationIds:
                  (row.data['timesheet_qualification_ids'] as List? ?? const [])
                      .map((e) => e.toString().trim())
                      .where((e) => e.isNotEmpty)
                      .toList(),
            ),
          );
        }
      } catch (e) {
        debugPrint('getUserInformation admin-only schools warning: $e');
      }

      final phone = dbPhone.isNotEmpty
          ? dbPhone
          : (user.phone.isNotEmpty
              ? user.phone
              : (user.prefs.data['phone'] ?? '').toString());

      final preliminaryUser = UserModelUserView(
        id: userID,
        name: user.name,
        mail: user.email,
        phone: phone,
        avatarUrl: avatarUrl,
        avatarFileId: avatarFileId,
        emergencyContactName: emergencyContactName,
        emergencyContactRelation: emergencyContactRelation,
        emergencyContactPhone: emergencyContactPhone,
        birthDate: birthDate,
        address: address,
        licenseNumber: licenseNumber,
        licenseRatings: licenseRatings,
        employmentType: employmentType,
        activeSince: activeSince,
        flightSchools: flightSchools,
        adminOnlyFlightSchools: adminOnlyFlightSchools,
        events: const [],
      );

      final tandemSchools = flightSchools
          .where(
            (fs) =>
                fs.membershipStatus == MembershipStatusEnum.active &&
                fs.tandemEnabled &&
                fs.isTandemPilot,
          )
          .toList();

      final loadedAll = await Future.wait([
        loadUserEvents(preliminaryUser, includeArchive: includeArchive),
        Future.wait(
          tandemSchools.map(
            (fs) => TandemService().listDutiesForSchool(
              fs.id,
              includeArchive: includeArchive,
            ),
          ),
        ),
        Future.wait(
          tandemSchools.map((fs) => TandemService().listDemandsForSchool(fs.id)),
        ),
      ]);

      final allEvents = loadedAll[0] as List<Event>;
      final dutiesNested = loadedAll[1] as List<List<TandemDuty>>;
      final demandsNested = loadedAll[2] as List<List<TandemDemand>>;
      final allTandemDuties = dutiesNested.expand((l) => l).toList();
      final allTandemDemands = demandsNested.expand((l) => l).toList();

      // Namen der Mit-Piloten gebündelt auflösen (nur für Tage mit eigener Bestätigung angezeigt)
      final pilotNames = await _resolveTandemPilotNames(
        duties: allTandemDuties,
        currentUserId: userID,
      );

      return preliminaryUser.copyWith(
        events: allEvents,
        tandemDuties: allTandemDuties,
        tandemDemands: allTandemDemands,
        tandemPilotNamesById: pilotNames,
        hasLoadedArchive: includeArchive,
      );
    } catch (e) {
      debugPrint('getUserInformation error: $e');
      return null;
    }
  }

  // ==================== EVENT-CRUD & SERIENEVENTS (ADMIN) ====================

  Future<Event> createEventWithTeam({
    required BuildContext context,
    required Event event,
  }) async {
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null) throw Exception("Keine Flugschule im Provider gesetzt.");
    if (!fs.isSubscriptionActive) {
      throw Exception(
        "Events können erst nach Aktivierung des Flugschul-Abos angelegt werden.",
      );
    }

    final eventDoc = await tablesDB.createRow(
      databaseId: fs.databaseId,
      tableId: fs.eventsCollectionId,
      rowId: ID.unique(),
      data: {
        "flight_school_id": fs.id,
        "identifier": event.identifier,
        "display_name": event.displayName,
        "status": event.status.name,
        "start_time": event.startTime.toIso8601String(),
        "end_time": event.endTime.toIso8601String(),
        "notes": event.notes,
        "location": event.location,
        if (event.planningPeriodId != null && event.planningPeriodId!.isNotEmpty)
          "planning_period_id": event.planningPeriodId,
        if (event.seriesId != null && event.seriesId!.isNotEmpty)
          "series_id": event.seriesId,
      },
      permissions: SecurityPrivacyService.schoolReadAdminWritePerms(fs.id),
    );

    final created = event.copyWith(
      id: eventDoc.$id,
      eventDocId: eventDoc.$id,
      flightSchoolId: fs.id,
    );

    final assignPerms = SecurityPrivacyService.schoolMemberUpdatePerms(fs.id);
    for (final tm in created.team) {
      await tablesDB.createRow(
        databaseId: fs.databaseId,
        tableId: fs.teamAssignmentsEventsCollectionId,
        rowId: ID.unique(),
        data: {
          "user_id": tm.isSlot ? "" : tm.userId,
          "name": tm.isSlot ? "" : tm.name,
          "role": tm.role,
          "status": tm.status,
          "events": created.id,
          "swap_offered": false,
        },
        permissions: assignPerms,
      );
    }

    await AuditLogService().log(
      flightSchoolId: fs.id,
      action: 'Event erstellt',
      details: '„${created.displayName}“ (${created.team.length} Team-Plätze)',
    );

    return created;
  }

  /// Erstellt ein Serienevent (mehrere aufeinanderfolgende Events mit gemeinsamer `series_id`).
  Future<List<Event>> createEventSeries({
    required BuildContext context,
    required Event baseEvent,
    required RecurrenceFrequency frequency,
    required int count,
  }) async {
    if (frequency == RecurrenceFrequency.none || count <= 1) {
      return [await createEventWithTeam(context: context, event: baseEvent)];
    }

    final seriesId = 'series_${DateTime.now().millisecondsSinceEpoch}';
    final created = <Event>[];
    final duration = baseEvent.endTime.difference(baseEvent.startTime);
    final fs = context.read<FlightSchoolProvider>().flightSchool;

    for (int i = 0; i < count; i++) {
      DateTime start;
      switch (frequency) {
        case RecurrenceFrequency.weekly:
          start = baseEvent.startTime.add(Duration(days: 7 * i));
          break;
        case RecurrenceFrequency.biweekly:
          start = baseEvent.startTime.add(Duration(days: 14 * i));
          break;
        case RecurrenceFrequency.monthly:
          start = DateTime(
            baseEvent.startTime.year,
            baseEvent.startTime.month + i,
            baseEvent.startTime.day,
            baseEvent.startTime.hour,
            baseEvent.startTime.minute,
          );
          break;
        case RecurrenceFrequency.none:
          start = baseEvent.startTime;
          break;
      }

      final matchedPeriod = fs?.periodForDate(start);
      final suffix = count > 1 ? ' (${i + 1}/$count)' : '';
      final ev = baseEvent.copyWith(
        displayName: '${baseEvent.displayName}$suffix',
        identifier: baseEvent.identifier.isEmpty
            ? ''
            : '${baseEvent.identifier}-${i + 1}',
        startTime: start,
        endTime: start.add(duration),
        planningPeriodId: matchedPeriod?.id,
        seriesId: seriesId,
      );

      try {
        final saved = await createEventWithTeam(context: context, event: ev);
        created.add(saved);
      } catch (e) {
        if (created.isNotEmpty) {
          throw Exception(
            'Serien-Erstellung abgebrochen: ${created.length} von $count Events wurden bereits angelegt. Fehler: $e',
          );
        }
        rethrow;
      }
    }

    return created;
  }

  Future<Event> updateEventWithTeam({
    required BuildContext context,
    required Event event,
  }) async {
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null) throw Exception("Keine Flugschule im Provider gesetzt.");
    if (!fs.isSubscriptionActive) {
      throw Exception(
        "Events können erst nach Aktivierung des Flugschul-Abos bearbeitet werden.",
      );
    }

    if (event.id.trim().isEmpty) {
      throw Exception("Event-ID fehlt.");
    }

    final updateData = <String, dynamic>{
      "identifier": event.identifier,
      "display_name": event.displayName,
      "status": event.status.name,
      "start_time": event.startTime.toIso8601String(),
      "end_time": event.endTime.toIso8601String(),
      "notes": event.notes,
      "location": event.location,
      "planning_period_id": event.planningPeriodId ?? '',
    };
    if (event.previousStartTime != null && event.previousEndTime != null) {
      updateData["previous_start_time"] =
          event.previousStartTime!.toIso8601String();
      updateData["previous_end_time"] =
          event.previousEndTime!.toIso8601String();
    }

    await tablesDB.updateRow(
      databaseId: fs.databaseId,
      tableId: fs.eventsCollectionId,
      rowId: event.id,
      data: updateData,
    );

    final existing = await tablesDB.listRows(
      databaseId: fs.databaseId,
      tableId: fs.teamAssignmentsEventsCollectionId,
      queries: [
        Query.equal("events", [event.id]),
        Query.limit(500),
      ],
    );

    final Map<String, dynamic> existingByKey = {};
    for (final doc in existing.rows) {
      final data = doc.data;
      final userId = (data["user_id"] ?? "").toString();
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

      if (key.startsWith("user:")) {
        if (!newByKey.containsKey(key)) {
          await tablesDB.deleteRow(
            databaseId: fs.databaseId,
            tableId: fs.teamAssignmentsEventsCollectionId,
            rowId: docId,
          );
        }
      } else if (key.startsWith("slot:")) {
        await tablesDB.deleteRow(
          databaseId: fs.databaseId,
          tableId: fs.teamAssignmentsEventsCollectionId,
          rowId: docId,
        );
      }
    }

    final assignPerms = SecurityPrivacyService.schoolMemberUpdatePerms(fs.id);
    for (final entry in newByKey.entries) {
      final key = entry.key;
      final tm = entry.value;

      if (key.startsWith("slot:new:")) {
        await tablesDB.createRow(
          databaseId: fs.databaseId,
          tableId: fs.teamAssignmentsEventsCollectionId,
          rowId: ID.unique(),
          data: {
            "user_id": "",
            "name": "",
            "role": tm.role,
            "status": tm.status,
            "events": event.id,
            "swap_offered": false,
          },
          permissions: assignPerms,
        );
        continue;
      }

      final existingEntry = existingByKey[key];
      if (existingEntry == null) {
        await tablesDB.createRow(
          databaseId: fs.databaseId,
          tableId: fs.teamAssignmentsEventsCollectionId,
          rowId: ID.unique(),
          data: {
            "user_id": tm.userId,
            "name": tm.name,
            "role": tm.role,
            "status": tm.status,
            "events": event.id,
            "swap_offered": false,
          },
          permissions: assignPerms,
        );
      } else {
        final docId = existingEntry["docId"] as String;
        final oldRole = existingEntry["role"] as String;
        final oldStatus = existingEntry["status"] as String;

        if (oldRole != tm.role || oldStatus != tm.status) {
          await tablesDB.updateRow(
            databaseId: fs.databaseId,
            tableId: fs.teamAssignmentsEventsCollectionId,
            rowId: docId,
            data: {
              "role": tm.role,
              "status": tm.status,
              "name": tm.name,
            },
          );
        }
      }
    }

    await AuditLogService().log(
      flightSchoolId: fs.id,
      action: 'Event aktualisiert',
      details: '„${event.displayName}“ bearbeitet',
    );

    return event;
  }

  /// Löscht ein Event inkl. aller zugehörigen Team-Zuweisungen.
  Future<bool> deleteEventWithTeam({
    required BuildContext context,
    required Event event,
  }) async {
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null) throw Exception("Keine Flugschule im Provider gesetzt.");
    if (!fs.isSubscriptionActive) {
      throw Exception(
        "Events können erst nach Aktivierung des Flugschul-Abos gelöscht werden.",
      );
    }

    try {
      final existing = await tablesDB.listRows(
        databaseId: fs.databaseId,
        tableId: fs.teamAssignmentsEventsCollectionId,
        queries: [
          Query.equal("events", [event.id]),
          Query.limit(500),
        ],
      );
      for (final row in existing.rows) {
        await tablesDB.deleteRow(
          databaseId: fs.databaseId,
          tableId: fs.teamAssignmentsEventsCollectionId,
          rowId: row.$id,
        );
      }

      await tablesDB.deleteRow(
        databaseId: fs.databaseId,
        tableId: fs.eventsCollectionId,
        rowId: event.id,
      );

      await AuditLogService().log(
        flightSchoolId: fs.id,
        action: 'Event gelöscht',
        details: '„${event.displayName}“ vollständig entfernt',
      );

      return true;
    } catch (e) {
      debugPrint('deleteEventWithTeam error: $e');
      return false;
    }
  }

  // ==================== ICS-KALENDER-ABO TOKEN ====================

  String _generateRandomToken() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rand = Random.secure();
    return List.generate(32, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  Future<String> getOrCreateUserIcsFeedUrl({bool forceRegenerate = false}) async {
    final user = await AuthService().getCurrentUser();
    if (user == null) throw Exception('Nicht angemeldet.');
    final row = await AuthService().ensureUserProfileRow(user: user);
    if (row == null) {
      throw Exception(
        'Benutzerprofil konnte in der Datenbank nicht gefunden oder angelegt werden.',
      );
    }

    final cfg = AppwriteConfig();
    String token = (row.data['ics_token'] ?? '').toString();
    if (forceRegenerate || token.isEmpty) {
      token = _generateRandomToken();
      await tablesDB.updateRow(
        databaseId: cfg.mainDatabaseId,
        tableId: cfg.usersCollectionID,
        rowId: row.$id,
        data: {'ics_token': token},
      );
    }

    return '${cfg.icsFeedBaseUrl}/?type=user&id=${Uri.encodeQueryComponent(row.$id)}&token=$token';
  }
}
