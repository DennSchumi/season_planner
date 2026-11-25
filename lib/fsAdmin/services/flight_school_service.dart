import 'dart:math';
import 'dart:typed_data';
import 'package:appwrite/appwrite.dart';
import 'package:flutter/cupertino.dart';
import 'package:season_planner/core/data/enums/event_status_enum.dart';
import 'package:season_planner/core/data/enums/event_user_status_enum.dart';
import 'package:season_planner/core/data/enums/membership_status_enum.dart';
import 'package:season_planner/core/data/enums/subscription_status_enum.dart';
import 'package:season_planner/core/data/enums/team_tier_enum.dart';
import 'package:season_planner/core/data/models/audit_export_model.dart';
import 'package:season_planner/core/data/models/event_model.dart';
import 'package:season_planner/core/data/models/planning_period_model.dart';
import 'package:season_planner/core/data/models/tandem_model.dart';
import 'package:season_planner/core/data/models/team_role_model.dart';
import 'package:season_planner/core/services/appwrite_pagination.dart';
import 'package:season_planner/core/services/audit_log_service.dart';
import 'package:season_planner/core/services/auth_service.dart';
import 'package:season_planner/core/services/data_window.dart';
import 'package:season_planner/core/services/planning_service.dart';
import 'package:season_planner/core/services/qualification_service.dart';
import 'package:season_planner/core/services/security_privacy_service.dart';
import 'package:season_planner/core/services/tandem_service.dart';
import 'package:season_planner/fsAdmin/services/flight_school_functions.dart';

import '../../core/appwrite_config.dart';
import '../data/models/flight_school_model_flight_school_view.dart';
import '../data/models/user_summary_flight_school_view.dart';

class LogoUploadResult {
  final String logoId;
  final String logoLink;
  const LogoUploadResult({required this.logoId, required this.logoLink});
}

class FlightSchoolService {
  Client get client => AuthService().client;

  late final flighSchoolFunctions = FlightSchoolFunctions(client);

  static final FlightSchoolService _instance = FlightSchoolService._internal();

  factory FlightSchoolService() {
    return _instance;
  }

  FlightSchoolService._internal();

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

  // ==================== STAMMDATEN & LOGO ====================

  Future<LogoUploadResult?> uploadFlightSchoolLogo({
    required String flightSchoolId,
    required Uint8List bytes,
    required String filename,
    String? oldLogoFileId,
  }) async {
    try {
      final cfg = AppwriteConfig();
      final uploaded = await storage.createFile(
        bucketId: cfg.flightSchoolLogosId,
        fileId: ID.unique(),
        file: InputFile.fromBytes(bytes: bytes, filename: filename),
        permissions: [
          Permission.read(Role.any()),
          Permission.update(Role.team(flightSchoolId, 'admin')),
          Permission.delete(Role.team(flightSchoolId, 'admin')),
        ],
      );

      if (oldLogoFileId != null && oldLogoFileId.trim().isNotEmpty) {
        try {
          await storage.deleteFile(
            bucketId: cfg.flightSchoolLogosId,
            fileId: oldLogoFileId,
          );
        } catch (_) {}
      }

      final url = cfg.fileViewUrl(cfg.flightSchoolLogosId, uploaded.$id);
      return LogoUploadResult(logoId: uploaded.$id, logoLink: url);
    } catch (e) {
      debugPrint('uploadFlightSchoolLogo failed: $e');
      return null;
    }
  }

  Future<bool> updateFlightSchoolShortName({
    required String flightSchoolId,
    required String shortName,
  }) async {
    try {
      final cfg = AppwriteConfig();
      await tablesDB.updateRow(
        databaseId: cfg.mainDatabaseId,
        tableId: cfg.flightSchoolsCollectionId,
        rowId: flightSchoolId,
        data: {'display_short_name': shortName.trim()},
      );
      await AuditLogService().log(
        flightSchoolId: flightSchoolId,
        action: 'Kurzname geändert',
        details: 'Neuer Kurzname: „${shortName.trim()}“',
      );
      return true;
    } catch (e) {
      debugPrint('updateFlightSchoolShortName failed: $e');
      return false;
    }
  }

  Future<bool> updateFlightSchoolLogo({
    required String flightSchoolId,
    required String logoLink,
    required String logoId,
  }) async {
    try {
      final cfg = AppwriteConfig();
      await tablesDB.updateRow(
        databaseId: cfg.mainDatabaseId,
        tableId: cfg.flightSchoolsCollectionId,
        rowId: flightSchoolId,
        data: {
          'logo_link': logoLink,
          'logo_id': logoId,
        },
      );
      await AuditLogService().log(
        flightSchoolId: flightSchoolId,
        action: 'Logo aktualisiert',
        details: 'Neues Flugschul-Logo hochgeladen ($logoId)',
      );
      return true;
    } catch (e) {
      debugPrint('updateFlightSchoolLogo failed: $e');
      return false;
    }
  }

  Future<bool> updateAdmins({
    required String flightSchoolId,
    required List<String> adminUserIds,
  }) async {
    return SecurityPrivacyService().runAdminAction(
      flightSchoolId: flightSchoolId,
      operation: 'updateAdmins',
      params: {'adminUserIds': adminUserIds},
    );
  }

  // ==================== FLUGSCHULE LADEN ====================

  Future<FlightSchoolModelFlightSchoolView?> getFlightSchool(
    String id, {
    bool includeArchive = false,
  }) async {
    try {
      final cfg = AppwriteConfig();
      final fsDoc = await tablesDB.getRow(
        databaseId: cfg.mainDatabaseId,
        tableId: cfg.flightSchoolsCollectionId,
        rowId: id,
      );
      final fs = fsDoc.data;

      final databaseId =
          (fs["database_id"] ?? cfg.seasonPlannerDatabaseId).toString();
      final teamAssignmentsId = (fs["team_assigments_events_id"] ??
              cfg.teamAssignmentsEventsTableId)
          .toString();
      final eventsCollectionId =
          (fs["events_id"] ?? cfg.eventsTableId).toString();

      final tandemEnabled = fs["tandem_enabled"] != false;
      final timesheetEnabled = fs["timesheet_enabled"] != false;
      final timesheetQualificationIds =
          (fs["timesheet_qualification_ids"] as List? ?? const [])
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList();
      final auditExportsEnabled = fs["audit_exports_enabled"] != false;
      final auditProfile = FlightSchoolAuditProfile.fromJsonString(
        fs["audit_profile_json"]?.toString(),
      );

      // Standard-Qualifikationen, Teamrollen, Planungsperioden, Mitglieder & Tandem parallel laden
      final parallelResults = await Future.wait([
        QualificationService().ensureDefaultQualifications(id),
        QualificationService().ensureDefaultRoles(id),
        PlanningService().listPeriods(id),
        _fetchMembersAndRequestsFromCoreDb(id),
        if (tandemEnabled)
          TandemService().listDutiesForSchool(
            id,
            includeArchive: includeArchive,
          )
        else
          Future<List<TandemDuty>>.value(const []),
        if (tandemEnabled)
          TandemService().listDemandsForSchool(id)
        else
          Future<List<TandemDemand>>.value(const []),
      ]);
      final qualifications = parallelResults[0] as List<Qualification>;
      final teamRoles = parallelResults[1] as List<TeamRole>;
      final planningPeriods = parallelResults[2] as List<PlanningPeriod>;
      final membershipsResult = parallelResults[3]
          as ({List<UserSummary> members, List<UserSummary> pendingRequests});
      final tandemDuties = parallelResults[4] as List<TandemDuty>;
      final tandemDemands = parallelResults[5] as List<TandemDemand>;

      final events = await _fetchEvents(
        flightSchoolId: id,
        databaseId: databaseId,
        eventsCollectionId: eventsCollectionId,
        teamAssignmentsId: teamAssignmentsId,
        planningPeriods: planningPeriods,
        members: membershipsResult.members,
        includeArchive: includeArchive,
      );

      final settings =
          (fs["settings"] as Map<String, dynamic>?) ?? <String, dynamic>{};

      return FlightSchoolModelFlightSchoolView(
        id: fsDoc.$id,
        displayName: (fs["display_name"] ?? "").toString(),
        displayShortName: (fs["display_short_name"] ?? "").toString(),
        databaseId: databaseId,
        teamAssignmentsEventsCollectionId: teamAssignmentsId,
        eventsCollectionId: eventsCollectionId,
        auditLogsCollectionId:
            (fs["audit_logs_id"] ?? cfg.auditLogsTableId).toString(),
        logoLink: (fs["logo_link"] ?? "").toString(),
        logoId: (fs["logo_id"] ?? "").toString(),
        adminUserIds: List<String>.from(fs["admin_users"] ?? const []),
        subscriptionStatus:
            SubscriptionStatusEnumX.parse(fs["subscription_status"]),
        icsToken: (fs["ics_token"] ?? "").toString(),
        members: membershipsResult.members,
        pendingRequests: membershipsResult.pendingRequests,
        events: events,
        teamRoles: teamRoles,
        qualifications: qualifications,
        planningPeriods: planningPeriods,
        tandemEnabled: tandemEnabled,
        tandemDuties: tandemDuties,
        tandemDemands: tandemDemands,
        timesheetEnabled: timesheetEnabled,
        timesheetQualificationIds: timesheetQualificationIds,
        auditExportsEnabled: auditExportsEnabled,
        auditProfile: auditProfile,
        settings: settings,
        hasLoadedArchive: includeArchive,
      );
    } catch (e) {
      debugPrint("getFlightSchool (FS view) error: $e");
      return null;
    }
  }

  /// Selektives Nachladen nur der Events (inkl. Team-Zuweisungen) für Realtime-Updates.
  Future<FlightSchoolModelFlightSchoolView?> refreshEventsOnly(
    FlightSchoolModelFlightSchoolView current, {
    bool? includeArchive,
  }) async {
    try {
      final effArchive = includeArchive ?? current.hasLoadedArchive;
      final events = await _fetchEvents(
        flightSchoolId: current.id,
        databaseId: current.databaseId,
        eventsCollectionId: current.eventsCollectionId,
        teamAssignmentsId: current.teamAssignmentsEventsCollectionId,
        planningPeriods: current.planningPeriods,
        members: current.members,
        includeArchive: effArchive,
      );
      return current.copyWith(
        events: events,
        hasLoadedArchive: effArchive,
      );
    } catch (e) {
      debugPrint('refreshEventsOnly error: $e');
      return null;
    }
  }

  /// Selektives Nachladen nur der Tandem-Dienste und -Bedarfe für Realtime-Updates.
  Future<FlightSchoolModelFlightSchoolView?> refreshTandemOnly(
    FlightSchoolModelFlightSchoolView current, {
    bool? includeArchive,
  }) async {
    if (!current.tandemEnabled) return current;
    try {
      final effArchive = includeArchive ?? current.hasLoadedArchive;
      final results = await Future.wait([
        TandemService().listDutiesForSchool(
          current.id,
          includeArchive: effArchive,
        ),
        TandemService().listDemandsForSchool(current.id),
      ]);
      return current.copyWith(
        tandemDuties: results[0] as List<TandemDuty>,
        tandemDemands: results[1] as List<TandemDemand>,
        hasLoadedArchive: effArchive,
      );
    } catch (e) {
      debugPrint('refreshTandemOnly error: $e');
      return null;
    }
  }

  /// Selektives Nachladen nur der Mitglieder & Beitrittsanfragen für Realtime-Updates.
  Future<FlightSchoolModelFlightSchoolView?> refreshMembersOnly(
    FlightSchoolModelFlightSchoolView current,
  ) async {
    try {
      final res = await _fetchMembersAndRequestsFromCoreDb(current.id);
      return current.copyWith(
        members: res.members,
        pendingRequests: res.pendingRequests,
      );
    } catch (e) {
      debugPrint('refreshMembersOnly error: $e');
      return null;
    }
  }

  /// Selektives Nachladen nur der Planungsperioden (inkl. lokaler Neuberechnung der Event-Stufen).
  Future<FlightSchoolModelFlightSchoolView?> refreshPlanningOnly(
    FlightSchoolModelFlightSchoolView current,
  ) async {
    try {
      final periods = await PlanningService().listPeriods(current.id);
      final updatedEvents = current.events.map((ev) {
        final resolved = resolvePlanningPeriod(
          periods,
          ev.startTime,
          fallbackPeriodId: ev.planningPeriodId,
        );
        return ev.copyWith(
          planningPeriodId: resolved?.id ?? ev.planningPeriodId,
          planningStage: resolved?.stage.value ?? 3,
        );
      }).toList();
      return current.copyWith(
        planningPeriods: periods,
        events: updatedEvents,
      );
    } catch (e) {
      debugPrint('refreshPlanningOnly error: $e');
      return null;
    }
  }

  Future<({List<UserSummary> members, List<UserSummary> pendingRequests})>
      _fetchMembersAndRequestsFromCoreDb(String flightSchoolId) async {
    final members = <UserSummary>[];
    final pendingRequests = <UserSummary>[];

    try {
      final cfg = AppwriteConfig();
      final rows = await listAllRows(
        tablesDB,
        databaseId: cfg.mainDatabaseId,
        tableId: cfg.membershipsId,
        queries: [
          Query.equal('flightSchools', flightSchoolId),
          Query.select(['*', 'users.*']),
        ],
      );

      for (final m in rows) {
        final status = MembershipStatusEnumX.parse(m.data['status']);
        if (status == MembershipStatusEnum.inactive) continue;

        final userRaw = m.data['users'];
        String userId = '';
        String userRowId = '';
        String name = '';
        String email = '';
        String phone = '';
        String avatarUrl = '';
        String emergencyContactName = '';
        String emergencyContactRelation = '';
        String emergencyContactPhone = '';
        String birthDate = '';
        String address = '';
        String licenseNumber = '';
        String licenseRatings = '';
        String employmentType = '';
        String activeSince = '';

        if (userRaw is Map) {
          final rowId = (userRaw['\$id'] ?? '').toString();
          final authId = (userRaw['auth_id'] ?? '').toString();
          userId = authId.isNotEmpty ? authId : rowId;
          userRowId = rowId;
          name = (userRaw['name'] ?? '').toString();
          email = (userRaw['email'] ?? '').toString();
          phone = (userRaw['phone'] ?? '').toString();
          avatarUrl = (userRaw['avatar_url'] ?? '').toString();
          emergencyContactName =
              (userRaw['emergency_contact_name'] ?? '').toString();
          emergencyContactRelation =
              (userRaw['emergency_contact_relation'] ?? '').toString();
          emergencyContactPhone =
              (userRaw['emergency_contact_phone'] ?? '').toString();
          birthDate = (userRaw['birth_date'] ?? '').toString();
          address = (userRaw['address'] ?? '').toString();
          licenseNumber = (userRaw['license_number'] ?? '').toString();
          licenseRatings = (userRaw['license_ratings'] ?? '').toString();
          employmentType = (userRaw['employment_type'] ?? '').toString();
          activeSince = (userRaw['active_since'] ?? '').toString();
        } else if (userRaw is String) {
          userId = userRaw;
          userRowId = userRaw;
        }

        final summary = UserSummary(
          id: userId,
          userRowId: userRowId,
          name: name.isEmpty ? email : name,
          mail: email,
          phone: phone,
          avatarUrl: avatarUrl,
          emergencyContactName: emergencyContactName,
          emergencyContactRelation: emergencyContactRelation,
          emergencyContactPhone: emergencyContactPhone,
          birthDate: birthDate,
          address: address,
          licenseNumber: licenseNumber,
          licenseRatings: licenseRatings,
          employmentType: employmentType,
          activeSince: activeSince,
          membershipId: m.$id,
          roles: UserSummary.parseRoles(m.data['roles']),
          qualificationIds: UserSummary.parseRoles(m.data['qualifications']),
          requestedQualificationIds:
              UserSummary.parseRoles(m.data['requested_qualifications']),
          membershipStatus: status,
          teamTier: TeamTierEnum.parse(m.data['team_tier']),
        );

        if (status == MembershipStatusEnum.requested) {
          pendingRequests.add(summary);
        } else {
          members.add(summary);
        }
      }
    } catch (e) {
      debugPrint('_fetchMembersAndRequestsFromCoreDb error: $e');
    }

    return (members: members, pendingRequests: pendingRequests);
  }

  Future<List<Event>> _fetchEvents({
    required String flightSchoolId,
    required String databaseId,
    required String eventsCollectionId,
    required String teamAssignmentsId,
    required List<PlanningPeriod> planningPeriods,
    required List<UserSummary> members,
    bool includeArchive = false,
  }) async {
    List<Event> events = [];

    String avatarForUser(String uid) {
      if (uid.isEmpty || uid.startsWith('slot_')) return '';
      for (final m in members) {
        if (m.matchesId(uid)) return m.avatarUrl;
      }
      return '';
    }

    try {
      if (databaseId.isNotEmpty && eventsCollectionId.isNotEmpty) {
        // Serverseitige Filterung über zusammengesetzten Index (flight_school_id, start_time / end_time)
        final queries = <String>[
          Query.equal('flight_school_id', flightSchoolId),
          if (!includeArchive) ...[
            Query.greaterThanEqual(
              'end_time',
              DataWindow.defaultStart().toIso8601String(),
            ),
            Query.lessThanEqual(
              'start_time',
              DataWindow.defaultEnd().toIso8601String(),
            ),
          ],
          Query.orderDesc("start_time"),
        ];

        final schoolEventRows = await listAllRows(
          tablesDB,
          databaseId: databaseId,
          tableId: eventsCollectionId,
          queries: queries,
        );

        // Alle Team-Zuweisungen gebündelt in 100er-Chunks statt N+1 Einzel-Queries laden
        final Map<String, List<Map<String, dynamic>>> assignmentsByEventId = {};
        final eventIds = schoolEventRows.map((e) => e.$id).toList();
        if (eventIds.isNotEmpty) {
          final chunkFutures = chunkList(eventIds, size: 100).map((chunk) {
            return listAllRows(
              tablesDB,
              databaseId: databaseId,
              tableId: teamAssignmentsId,
              queries: [
                Query.equal("events", chunk),
                Query.select(['*', 'events.\$id']),
              ],
            );
          }).toList();

          final chunkResults = await Future.wait(chunkFutures);
          for (final rows in chunkResults) {
            for (final d in rows) {
              final rawEvent = d.data['events'];
              final String evId = rawEvent is Map
                  ? (rawEvent['\$id'] ?? '').toString()
                  : (rawEvent ?? '').toString();
              if (evId.isEmpty) continue;
              final mapWithId = Map<String, dynamic>.from(d.data);
              mapWithId['\$id'] = d.$id;
              assignmentsByEventId.putIfAbsent(evId, () => []).add(mapWithId);
            }
          }
        }

        final List<Event> eventList = [];

        for (final eventDoc in schoolEventRows) {
          try {
            final eventData = eventDoc.data;
            final teamMaps = assignmentsByEventId[eventDoc.$id] ?? const [];

            final teamMembers = teamMaps.map((data) {
              final tm = TeamMember.fromMap(data);
              return tm.isSlot
                  ? tm
                  : tm.copyWith(avatarUrl: avatarForUser(tm.userId));
            }).toList();

            final firstAssignment = teamMaps.isNotEmpty ? teamMaps.first : null;

            final startTime = DateTime.parse(eventData["start_time"]);
            final endTime = DateTime.parse(eventData["end_time"]);
            final prevStartRaw =
                (eventData["previous_start_time"] ?? "").toString().trim();
            final prevEndRaw =
                (eventData["previous_end_time"] ?? "").toString().trim();
            final previousStartTime =
                prevStartRaw.isEmpty ? null : DateTime.tryParse(prevStartRaw);
            final previousEndTime =
                prevEndRaw.isEmpty ? null : DateTime.tryParse(prevEndRaw);
            final storedPeriodId =
                (eventData['planning_period_id'] ?? '').toString();
            final resolvedPeriod = resolvePlanningPeriod(
              planningPeriods,
              startTime,
              fallbackPeriodId: storedPeriodId,
            );
            final stage = resolvedPeriod?.stage.value ?? 3;

            eventList.add(
              Event(
                id: eventDoc.$id,
                eventDocId: eventDoc.$id,
                flightSchoolId: flightSchoolId,
                identifier: (eventData["identifier"] ?? "").toString(),
                status: EventStatusEnum.parse(eventData["status"]),
                startTime: startTime,
                endTime: endTime,
                displayName: (eventData["display_name"] ?? "Event").toString(),
                team: teamMembers,
                notes: (eventData["notes"] ?? "").toString(),
                location: (eventData["location"] ?? "").toString(),
                role: firstAssignment != null
                    ? (firstAssignment["role"] ?? "").toString()
                    : "",
                assignmentStatus: firstAssignment != null
                    ? EventUserStatusLabelX.parse(firstAssignment["status"])
                    : EventUserStatusEnum.open,
                planningPeriodId: resolvedPeriod?.id ??
                    (storedPeriodId.isEmpty ? null : storedPeriodId),
                planningStage: stage,
                seriesId: eventData["series_id"]?.toString(),
                previousStartTime: previousStartTime,
                previousEndTime: previousEndTime,
              ),
            );
          } catch (rowErr) {
            debugPrint(
              'Skipping malformed event row ${eventDoc.$id}: $rowErr',
            );
          }
        }

        events = eventList;
      }
    } catch (e) {
      debugPrint("events loading error: $e");
      events = [];
    }

    return events;
  }

  // ==================== PERSONAL & BEITRITTSANFRAGEN ====================

  /// Zentrale Prüfung auf Datenschicht: sperrt geschützte Schreibaktionen,
  /// solange `subscription_status != active` ist.
  Future<void> _assertSubscriptionActive(String flightSchoolId) async {
    final cfg = AppwriteConfig();
    final row = await tablesDB.getRow(
      databaseId: cfg.mainDatabaseId,
      tableId: cfg.flightSchoolsCollectionId,
      rowId: flightSchoolId,
    );
    final status =
        SubscriptionStatusEnumX.parse(row.data['subscription_status']);
    if (!status.isActive) {
      throw Exception(
        'Diese Aktion ist erst nach Aktivierung des Flugschul-Abos verfügbar.',
      );
    }
  }

  Future<bool> approveJoinRequest({
    required String flightSchoolId,
    required String membershipId,
    String memberName = '',
  }) async {
    return SecurityPrivacyService().runAdminAction(
      flightSchoolId: flightSchoolId,
      operation: 'approveJoinRequest',
      params: {
        'membershipId': membershipId,
        'memberName': memberName,
      },
    );
  }

  Future<bool> rejectJoinRequest({
    required String flightSchoolId,
    required String membershipId,
    String memberName = '',
    String? targetUserId,
  }) async {
    return SecurityPrivacyService().runAdminAction(
      flightSchoolId: flightSchoolId,
      operation: 'rejectJoinRequest',
      params: {
        'membershipId': membershipId,
        'memberName': memberName,
        if (targetUserId != null && targetUserId.isNotEmpty)
          'targetUserId': targetUserId,
      },
    );
  }

  /// Bestätigt oder lehnt eine offene Bewerbung (`pending_flight_school`)
  /// direkt auf dem jeweiligen `team_assignments_events`-Eintrag ab.
  Future<bool> decideEventApplication({
    required String flightSchoolId,
    required String databaseId,
    required String tableId,
    required String assignmentId,
    required bool approve,
    String eventName = '',
    String memberName = '',
    String roleName = '',
  }) async {
    try {
      await _assertSubscriptionActive(flightSchoolId);
      final nextStatus = approve
          ? EventUserStatusEnum.accepted_flight_school
          : EventUserStatusEnum.denied_flight_school;

      await tablesDB.updateRow(
        databaseId: databaseId,
        tableId: tableId,
        rowId: assignmentId,
        data: {'status': nextStatus.name},
      );

      await AuditLogService().log(
        flightSchoolId: flightSchoolId,
        action: approve ? 'Bewerbung angenommen' : 'Bewerbung abgelehnt',
        details:
            'Event „$eventName“${roleName.isNotEmpty ? ' ($roleName)' : ''}: $memberName',
      );
      return true;
    } catch (e) {
      debugPrint('decideEventApplication error: $e');
      return false;
    }
  }

  Future<bool> removeMemberOfFlightSchool(
    String membershipId, {
    String? flightSchoolId,
    String? targetUserId,
    String memberName = '',
  }) async {
    try {
      if (flightSchoolId != null && flightSchoolId.isNotEmpty) {
        await _assertSubscriptionActive(flightSchoolId);
      }
      final cfg = AppwriteConfig();
      String resolvedTargetUserId = (targetUserId ?? '').trim();
      if (resolvedTargetUserId.isEmpty) {
        try {
          final mRow = await tablesDB.getRow(
            databaseId: cfg.mainDatabaseId,
            tableId: cfg.membershipsId,
            rowId: membershipId,
          );
          final u = mRow.data['users'];
          if (u is Map) {
            resolvedTargetUserId = (u['auth_id'] ?? u['\$id'] ?? '').toString();
          } else if (u is String) {
            resolvedTargetUserId = u;
          }
        } catch (_) {}
      }
      await tablesDB.deleteRow(
        databaseId: cfg.mainDatabaseId,
        tableId: cfg.membershipsId,
        rowId: membershipId,
      );
      if (flightSchoolId != null && flightSchoolId.isNotEmpty) {
        if (resolvedTargetUserId.isNotEmpty) {
          await SecurityPrivacyService().revokeSchoolAccess(
            flightSchoolId: flightSchoolId,
            targetUserId: resolvedTargetUserId,
          );
        } else {
          await SecurityPrivacyService().syncSchoolTeam(flightSchoolId);
        }
        await AuditLogService().log(
          flightSchoolId: flightSchoolId,
          action: 'Mitglied entfernt',
          details: 'Mitglied „$memberName“ entfernt',
        );
      }
      return true;
    } catch (e) {
      debugPrint('removeMemberOfFlightSchool error: $e');
      return false;
    }
  }

  Future<bool> updateMemberRolesAndQualifications(
    String membershipId, {
    required List<String> roles,
    required List<String> qualificationIds,
    List<String>? remainingRequestedQualificationIds,
    TeamTierEnum? teamTier,
    String? flightSchoolId,
    String memberName = '',
    String? qualificationLabels,
  }) async {
    try {
      if (flightSchoolId != null && flightSchoolId.isNotEmpty) {
        await _assertSubscriptionActive(flightSchoolId);
      }
      final cfg = AppwriteConfig();
      await tablesDB.updateRow(
        databaseId: cfg.mainDatabaseId,
        tableId: cfg.membershipsId,
        rowId: membershipId,
        data: {
          "roles": roles,
          "qualifications": qualificationIds,
          if (remainingRequestedQualificationIds != null)
            "requested_qualifications": remainingRequestedQualificationIds,
          if (teamTier != null) "team_tier": teamTier.wireValue,
        },
      );
      if (flightSchoolId != null) {
        await AuditLogService().log(
          flightSchoolId: flightSchoolId,
          action: 'Rollen & Qualifikationen aktualisiert',
          details:
              '$memberName → Rollen: ${roles.isEmpty ? "keine" : roles.join(', ')}'
              '${qualificationLabels != null ? ' · Qualifikationen: $qualificationLabels' : ''}'
              '${teamTier != null ? ' · Team: ${teamTier.label}' : ''}',
        );
      }
      return true;
    } catch (e) {
      debugPrint('updateMemberRolesAndQualifications error: $e');
      return false;
    }
  }

  Future<bool> updateRolesInMemberOfFlightSchool(
    String membershipId,
    List<String> roles, {
    String? flightSchoolId,
    String memberName = '',
  }) async {
    try {
      if (flightSchoolId != null && flightSchoolId.isNotEmpty) {
        await _assertSubscriptionActive(flightSchoolId);
      }
      final cfg = AppwriteConfig();
      await tablesDB.updateRow(
        databaseId: cfg.mainDatabaseId,
        tableId: cfg.membershipsId,
        rowId: membershipId,
        data: {"roles": roles},
      );
      if (flightSchoolId != null) {
        await AuditLogService().log(
          flightSchoolId: flightSchoolId,
          action: 'Mitgliedsrollen aktualisiert',
          details: '$memberName → ${roles.join(', ')}',
        );
      }
      return true;
    } catch (e) {
      debugPrint('updateRolesInMemberOfFlightSchool error: $e');
      return false;
    }
  }

  Future<void> inviteMember({
    required String flightSchoolId,
    required String email,
    List<String> roles = const [],
  }) async {
    await _assertSubscriptionActive(flightSchoolId);
    final cfg = AppwriteConfig();
    final trimmed = email.trim();

    // 1) Direkt in core_db.users suchen (funktioniert ohne externe Function)
    final usersRes = await tablesDB.listRows(
      databaseId: cfg.mainDatabaseId,
      tableId: cfg.usersCollectionID,
      queries: [
        Query.equal('email', trimmed),
        Query.limit(1),
      ],
    );

    if (usersRes.rows.isNotEmpty) {
      final targetUser = usersRes.rows.first;
      final existing = await tablesDB.listRows(
        databaseId: cfg.mainDatabaseId,
        tableId: cfg.membershipsId,
        queries: [
          Query.equal('users', targetUser.$id),
          Query.equal('flightSchools', flightSchoolId),
          Query.limit(1),
        ],
      );
      if (existing.rows.isNotEmpty) {
        throw Exception('Dieser Benutzer ist bereits Mitglied oder eingeladen.');
      }

      await tablesDB.createRow(
        databaseId: cfg.mainDatabaseId,
        tableId: cfg.membershipsId,
        rowId: ID.unique(),
        data: {
          'users': targetUser.$id,
          'flightSchools': flightSchoolId,
          'status': MembershipStatusEnum.invited.name,
          'roles': roles,
        },
      );
      await AuditLogService().log(
        flightSchoolId: flightSchoolId,
        action: 'Mitglied eingeladen',
        details: '$trimmed eingeladen',
      );
      return;
    }

    // 2) Fallback über Appwrite Function (falls Nutzer noch nicht registriert)
    try {
      final res = await flighSchoolFunctions.inviteUserToFlightSchool(
        flightSchoolId: flightSchoolId,
        userMail: trimmed,
        roles: roles,
      );
      if (res["ok"] != true) {
        throw Exception(
          'Kein registrierter Tragegurt-Account mit $trimmed gefunden. '
          'Der Benutzer kann sich registrieren und direkt deiner Flugschule beitreten.',
        );
      }
    } catch (_) {
      throw Exception(
        'Kein registrierter Account mit „$trimmed“ gefunden. '
        'Bitte lass die Person zuerst einen Account registrieren und über „Flugschule beitreten“ anfragen.',
      );
    }
  }

  // ==================== ICS-KALENDER-ABO (FLUGSCHULE) ====================

  String _generateRandomToken() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rand = Random.secure();
    return List.generate(32, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  Future<String> getOrCreateSchoolIcsFeedUrl(
    String flightSchoolId, {
    bool forceRegenerate = false,
  }) async {
    final cfg = AppwriteConfig();
    final row = await tablesDB.getRow(
      databaseId: cfg.mainDatabaseId,
      tableId: cfg.flightSchoolsCollectionId,
      rowId: flightSchoolId,
    );

    String token = (row.data['ics_token'] ?? '').toString();
    if (forceRegenerate || token.isEmpty) {
      token = _generateRandomToken();
      await tablesDB.updateRow(
        databaseId: cfg.mainDatabaseId,
        tableId: cfg.flightSchoolsCollectionId,
        rowId: flightSchoolId,
        data: {'ics_token': token},
      );
    }

    return '${cfg.icsFeedBaseUrl}/?type=school&id=${Uri.encodeQueryComponent(flightSchoolId)}&token=$token';
  }
}
