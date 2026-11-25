import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:season_planner/core/appwrite_config.dart';
import 'package:season_planner/core/data/models/planning_period_model.dart';
import 'package:season_planner/core/services/appwrite_pagination.dart';
import 'package:season_planner/core/services/audit_log_service.dart';
import 'package:season_planner/core/services/auth_service.dart';
import 'package:season_planner/core/services/security_privacy_service.dart';

class PlanningService {
  static final PlanningService _instance = PlanningService._internal();
  factory PlanningService() => _instance;
  PlanningService._internal();

  Client get _client => AuthService().client;

  late final TablesDB _tablesDB = TablesDB(_client);

  // ==================== PLANUNGSPERIODEN (STUFEN 1/2/3) ====================

  Future<List<PlanningPeriod>> listPeriods(String flightSchoolId) async {
    try {
      final cfg = AppwriteConfig();
      final res = await _tablesDB.listRows(
        databaseId: cfg.seasonPlannerDatabaseId,
        tableId: cfg.planningPeriodsTableId,
        queries: [
          Query.equal('flight_school_id', flightSchoolId),
          Query.limit(100),
        ],
      );
      final list =
          res.rows.map((r) => PlanningPeriod.fromMap(r.$id, r.data)).toList();
      list.sort((a, b) {
        if (a.startDate != null && b.startDate != null) {
          return b.startDate!.compareTo(a.startDate!);
        }
        if (a.startDate != null) return -1;
        if (b.startDate != null) return 1;
        return b.seasonLabel.compareTo(a.seasonLabel);
      });
      return list;
    } catch (e) {
      debugPrint('listPeriods error: $e');
      return [];
    }
  }

  Future<PlanningPeriod?> createPeriod({
    required String flightSchoolId,
    required String seasonLabel,
    PlanningStage stage = PlanningStage.availability,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final cfg = AppwriteConfig();
      final row = await _tablesDB.createRow(
        databaseId: cfg.seasonPlannerDatabaseId,
        tableId: cfg.planningPeriodsTableId,
        rowId: ID.unique(),
        data: {
          'flight_school_id': flightSchoolId,
          'season_label': seasonLabel.trim(),
          'stage': stage.value,
          if (startDate != null) 'start_date': startDate.toIso8601String(),
          if (endDate != null) 'end_date': endDate.toIso8601String(),
        },
        permissions: SecurityPrivacyService.schoolReadAdminWritePerms(
          flightSchoolId,
        ),
      );
      await AuditLogService().log(
        flightSchoolId: flightSchoolId,
        action: 'Planungsperiode erstellt',
        details: '${seasonLabel.trim()} (${stage.label})',
      );
      return PlanningPeriod.fromMap(row.$id, row.data);
    } catch (e) {
      debugPrint('createPeriod error: $e');
      return null;
    }
  }

  Future<bool> updatePeriodStage({
    required PlanningPeriod period,
    required PlanningStage newStage,
  }) async {
    try {
      final cfg = AppwriteConfig();
      await _tablesDB.updateRow(
        databaseId: cfg.seasonPlannerDatabaseId,
        tableId: cfg.planningPeriodsTableId,
        rowId: period.id,
        data: {'stage': newStage.value},
      );
      await AuditLogService().log(
        flightSchoolId: period.flightSchoolId,
        action: 'Planungsstufe geändert',
        details:
            '${period.seasonLabel}: ${period.stage.shortLabel} → ${newStage.shortLabel}',
      );
      return true;
    } catch (e) {
      debugPrint('updatePeriodStage error: $e');
      return false;
    }
  }

  Future<bool> updatePeriod({
    required PlanningPeriod period,
    required String seasonLabel,
    required PlanningStage stage,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final cfg = AppwriteConfig();
      final trimmed = seasonLabel.trim();
      await _tablesDB.updateRow(
        databaseId: cfg.seasonPlannerDatabaseId,
        tableId: cfg.planningPeriodsTableId,
        rowId: period.id,
        data: {
          'season_label': trimmed,
          'stage': stage.value,
          'start_date': startDate.toIso8601String(),
          'end_date': endDate.toIso8601String(),
        },
      );
      String f(DateTime d) =>
          '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
      await AuditLogService().log(
        flightSchoolId: period.flightSchoolId,
        action: 'Saison aktualisiert',
        details:
            '$trimmed (${f(startDate)} – ${f(endDate)}, ${stage.shortLabel})',
      );
      return true;
    } catch (e) {
      debugPrint('updatePeriod error: $e');
      return false;
    }
  }

  Future<bool> deletePeriod(PlanningPeriod period) async {
    try {
      final cfg = AppwriteConfig();
      await _tablesDB.deleteRow(
        databaseId: cfg.seasonPlannerDatabaseId,
        tableId: cfg.planningPeriodsTableId,
        rowId: period.id,
      );
      await AuditLogService().log(
        flightSchoolId: period.flightSchoolId,
        action: 'Planungsperiode gelöscht',
        details: period.seasonLabel,
      );
      return true;
    } catch (e) {
      debugPrint('deletePeriod error: $e');
      return false;
    }
  }

  // ==================== VERFÜGBARKEITEN & BLACKOUT-TAGE ====================

  Future<List<AvailabilitySubmission>> listUserSubmissions(
    String userId,
  ) async {
    try {
      final cfg = AppwriteConfig();
      final res = await _tablesDB.listRows(
        databaseId: cfg.seasonPlannerDatabaseId,
        tableId: cfg.availabilitySubmissionsTableId,
        queries: [
          Query.equal('user_id', userId),
          Query.orderAsc('start_date'),
          Query.limit(200),
        ],
      );
      return res.rows
          .map((r) => AvailabilitySubmission.fromMap(r.$id, r.data))
          .toList();
    } catch (e) {
      debugPrint('listUserSubmissions error: $e');
      return [];
    }
  }

  Future<List<AvailabilitySubmission>> listSchoolSubmissions(
    String flightSchoolId, {
    String? planningPeriodId,
  }) async {
    try {
      final cfg = AppwriteConfig();
      final queries = <String>[
        Query.equal('flight_school_id', flightSchoolId),
        if (planningPeriodId != null && planningPeriodId.isNotEmpty)
          Query.equal('planning_period_id', planningPeriodId),
        Query.orderAsc('start_date'),
      ];
      final rows = await listAllRows(
        _tablesDB,
        databaseId: cfg.seasonPlannerDatabaseId,
        tableId: cfg.availabilitySubmissionsTableId,
        queries: queries,
      );
      return rows
          .map((r) => AvailabilitySubmission.fromMap(r.$id, r.data))
          .toList();
    } catch (e) {
      debugPrint('listSchoolSubmissions error: $e');
      return [];
    }
  }

  Future<AvailabilitySubmission?> createSubmission({
    required String userId,
    required String flightSchoolId,
    String? planningPeriodId,
    required AvailabilityKind kind,
    required DateTime startDate,
    required DateTime endDate,
    String notes = '',
  }) async {
    try {
      final cfg = AppwriteConfig();
      final row = await _tablesDB.createRow(
        databaseId: cfg.seasonPlannerDatabaseId,
        tableId: cfg.availabilitySubmissionsTableId,
        rowId: ID.unique(),
        data: {
          'user_id': userId,
          'flight_school_id': flightSchoolId,
          if (planningPeriodId != null && planningPeriodId.isNotEmpty)
            'planning_period_id': planningPeriodId,
          'kind': kind.name,
          'start_date': startDate.toIso8601String(),
          'end_date': endDate.toIso8601String(),
          'notes': notes.trim(),
        },
        permissions: [
          Permission.read(Role.user(userId)),
          Permission.update(Role.user(userId)),
          Permission.delete(Role.user(userId)),
          Permission.read(Role.team(flightSchoolId, 'admin')),
        ],
      );
      return AvailabilitySubmission.fromMap(row.$id, row.data);
    } catch (e) {
      debugPrint('createSubmission error: $e');
      return null;
    }
  }

  Future<bool> deleteSubmission(String submissionId) async {
    try {
      final cfg = AppwriteConfig();
      await _tablesDB.deleteRow(
        databaseId: cfg.seasonPlannerDatabaseId,
        tableId: cfg.availabilitySubmissionsTableId,
        rowId: submissionId,
      );
      return true;
    } catch (e) {
      debugPrint('deleteSubmission error: $e');
      return false;
    }
  }

  // ==================== STUFE 3: PLATZ-TAUSCH (SWAP MIT ADMIN-BESTÄTIGUNG) ====================

  Future<bool> setSwapOffered({
    required String databaseId,
    required String tableId,
    required String assignmentId,
    required bool offered,
  }) async {
    try {
      await _tablesDB.updateRow(
        databaseId: databaseId,
        tableId: tableId,
        rowId: assignmentId,
        data: {
          'swap_offered': offered,
          if (!offered) 'swap_requested_by': '',
          if (!offered) 'swap_requested_by_name': '',
        },
      );
      return true;
    } catch (e) {
      debugPrint('setSwapOffered error: $e');
      return false;
    }
  }

  Future<bool> requestSwapTakeover({
    required String databaseId,
    required String tableId,
    required String assignmentId,
    required String requesterUserId,
    required String requesterName,
  }) async {
    try {
      // Identität des Anfragenden bevorzugt aus der aktiven Auth-Session ableiten
      final authUser = await AuthService().getCurrentUser();
      final effectiveUserId = authUser?.$id ?? requesterUserId;
      final effectiveName =
          (authUser != null && authUser.name.trim().isNotEmpty)
              ? authUser.name.trim()
              : requesterName;

      await _tablesDB.updateRow(
        databaseId: databaseId,
        tableId: tableId,
        rowId: assignmentId,
        data: {
          'swap_requested_by': effectiveUserId,
          'swap_requested_by_name': effectiveName,
        },
      );
      return true;
    } catch (e) {
      debugPrint('requestSwapTakeover error: $e');
      return false;
    }
  }

  Future<bool> approveSwap({
    required String flightSchoolId,
    required String databaseId,
    required String tableId,
    required String assignmentId,
    required String newUserId,
    required String newUserName,
    String eventName = '',
  }) async {
    return SecurityPrivacyService().runAdminAction(
      flightSchoolId: flightSchoolId,
      operation: 'approveSwap',
      params: {
        'assignmentId': assignmentId,
        'newUserId': newUserId,
        'newUserName': newUserName,
        'eventName': eventName,
      },
    );
  }

  Future<bool> rejectSwap({
    required String flightSchoolId,
    required String databaseId,
    required String tableId,
    required String assignmentId,
    String eventName = '',
  }) async {
    try {
      await _tablesDB.updateRow(
        databaseId: databaseId,
        tableId: tableId,
        rowId: assignmentId,
        data: {'swap_requested_by': '', 'swap_requested_by_name': ''},
      );
      await AuditLogService().log(
        flightSchoolId: flightSchoolId,
        action: 'Platztausch abgelehnt',
        details: 'Tauschanfrage für Event „$eventName“ abgelehnt',
      );
      return true;
    } catch (e) {
      debugPrint('rejectSwap error: $e');
      return false;
    }
  }
}
