import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:season_planner/core/appwrite_config.dart';
import 'package:season_planner/core/data/models/timesheet_model.dart';
import 'package:season_planner/core/services/appwrite_pagination.dart';
import 'package:season_planner/core/services/audit_log_service.dart';
import 'package:season_planner/core/services/auth_service.dart';
import 'package:season_planner/core/services/notification_service.dart';
import 'package:season_planner/core/services/security_privacy_service.dart';

class TimesheetService {
  static final TimesheetService _instance = TimesheetService._internal();
  factory TimesheetService() => _instance;
  TimesheetService._internal();

  Client get _client => AuthService().client;
  late final TablesDB _tablesDB = TablesDB(_client);
  late final Storage _storage = Storage(_client);

  // ==================== SCHOOL CONFIGURATION ====================

  Future<bool> updateSchoolTimesheetConfig({
    required String flightSchoolId,
    required bool enabled,
    required List<String> qualificationIds,
  }) async {
    try {
      final cfg = AppwriteConfig();
      await _tablesDB.updateRow(
        databaseId: cfg.mainDatabaseId,
        tableId: cfg.flightSchoolsCollectionId,
        rowId: flightSchoolId,
        data: {
          'timesheet_enabled': enabled,
          'timesheet_qualification_ids': qualificationIds,
        },
      );
      await AuditLogService().log(
        flightSchoolId: flightSchoolId,
        action: enabled ? 'timesheet_config_updated' : 'timesheet_disabled',
        details: enabled
            ? 'Stundenzettel aktiv (${qualificationIds.isEmpty ? "Standard: Lehrer/Trainer/Anwärter" : "${qualificationIds.length} Qualifikation(en)"})'
            : 'Stundenzettel-Funktion für Flugschule deaktiviert',
      );
      return true;
    } catch (e) {
      debugPrint('TimesheetService.updateSchoolTimesheetConfig error: $e');
      return false;
    }
  }

  // ==================== READ ====================

  Future<EventTimesheet?> getTimesheetForAssignment(String assignmentId) async {
    if (assignmentId.trim().isEmpty) return null;
    try {
      final cfg = AppwriteConfig();
      final res = await _tablesDB.listRows(
        databaseId: cfg.seasonPlannerDatabaseId,
        tableId: cfg.eventTimesheetsTableId,
        queries: [
          Query.equal('assignment_id', assignmentId),
          Query.limit(1),
        ],
      );
      if (res.rows.isEmpty) return null;
      return EventTimesheet.fromMap(res.rows.first.$id, res.rows.first.data);
    } catch (e) {
      debugPrint('TimesheetService.getTimesheetForAssignment error: $e');
      return null;
    }
  }

  Future<List<EventTimesheet>> listTimesheetsForUser(String userId) async {
    return await tryListTimesheetsForUser(userId) ?? const [];
  }

  /// Gibt bei einem Netzwerk-/Abfragefehler `null` zurück statt einer leeren Liste,
  /// damit Benachrichtigungs-Checks nicht fälschlich bereits abgegebene Stundenzettel anmahnen.
  Future<List<EventTimesheet>?> tryListTimesheetsForUser(String userId) async {
    if (userId.trim().isEmpty) return const [];
    try {
      final cfg = AppwriteConfig();
      final rows = await listAllRows(
        _tablesDB,
        databaseId: cfg.seasonPlannerDatabaseId,
        tableId: cfg.eventTimesheetsTableId,
        queries: [Query.equal('user_id', userId)],
      );
      final list = rows
          .map((r) => EventTimesheet.fromMap(r.$id, r.data))
          .toList()
        ..sort((a, b) => b.eventStart.compareTo(a.eventStart));
      return list;
    } catch (e) {
      debugPrint('TimesheetService.tryListTimesheetsForUser error: $e');
      return null;
    }
  }

  Future<List<EventTimesheet>> listTimesheetsForSchool(
    String flightSchoolId,
  ) async {
    if (flightSchoolId.trim().isEmpty) return const [];
    try {
      final cfg = AppwriteConfig();
      final rows = await listAllRows(
        _tablesDB,
        databaseId: cfg.seasonPlannerDatabaseId,
        tableId: cfg.eventTimesheetsTableId,
        queries: [Query.equal('flight_school_id', flightSchoolId)],
      );
      final list = rows
          .map((r) => EventTimesheet.fromMap(r.$id, r.data))
          .toList()
        ..sort((a, b) => b.eventStart.compareTo(a.eventStart));
      return list;
    } catch (e) {
      debugPrint('TimesheetService.listTimesheetsForSchool error: $e');
      return const [];
    }
  }

  // ==================== WRITE / SUBMIT ====================

  Future<EventTimesheet?> saveDraft(EventTimesheet sheet) async {
    try {
      final cfg = AppwriteConfig();
      final updated = sheet.copyWith(
        status: TimesheetStatus.draft,
        updatedAt: DateTime.now(),
      );

      final existing = sheet.id.isNotEmpty
          ? sheet
          : await getTimesheetForAssignment(sheet.assignmentId);

      if (existing != null && existing.id.isNotEmpty) {
        if (existing.isSubmitted) return existing;
        final row = await _tablesDB.updateRow(
          databaseId: cfg.seasonPlannerDatabaseId,
          tableId: cfg.eventTimesheetsTableId,
          rowId: existing.id,
          data: updated.toMap(),
        );
        return EventTimesheet.fromMap(row.$id, row.data);
      } else {
        final row = await _tablesDB.createRow(
          databaseId: cfg.seasonPlannerDatabaseId,
          tableId: cfg.eventTimesheetsTableId,
          rowId: ID.unique(),
          data: updated.toMap(),
          permissions: SecurityPrivacyService.ownerAndSchoolAdminPerms(
            userId: sheet.userId,
            flightSchoolId: sheet.flightSchoolId,
          ),
        );
        return EventTimesheet.fromMap(row.$id, row.data);
      }
    } catch (e) {
      debugPrint('TimesheetService.saveDraft error: $e');
      return null;
    }
  }

  Future<EventTimesheet?> submitWithSignature({
    required EventTimesheet sheet,
    required Uint8List signaturePng,
  }) async {
    try {
      final cfg = AppwriteConfig();
      final fileName =
          'timesheet_${sheet.assignmentId}_${DateTime.now().millisecondsSinceEpoch}.png';

      final sigPerms = [
        Permission.read(Role.user(sheet.userId)),
        Permission.delete(Role.user(sheet.userId)),
        Permission.read(Role.team(sheet.flightSchoolId, 'admin')),
        Permission.delete(Role.team(sheet.flightSchoolId, 'admin')),
      ];

      String bucketId = cfg.timesheetSignaturesBucketId;
      String? fileId;
      try {
        final uploaded = await _storage.createFile(
          bucketId: bucketId,
          fileId: ID.unique(),
          file: InputFile.fromBytes(bytes: signaturePng, filename: fileName),
          permissions: sigPerms,
        );
        fileId = uploaded.$id;
      } catch (_) {
        // Fallback auf checklist_signatures falls neuer Bucket noch nicht existiert
        bucketId = cfg.checklistSignaturesBucketId;
        final uploaded = await _storage.createFile(
          bucketId: bucketId,
          fileId: ID.unique(),
          file: InputFile.fromBytes(bytes: signaturePng, filename: fileName),
          permissions: sigPerms,
        );
        fileId = uploaded.$id;
      }

      final now = DateTime.now();
      final submitted = sheet.copyWith(
        status: TimesheetStatus.submitted,
        signatureFileId: fileId,
        submittedAt: now,
        updatedAt: now,
      );

      final existing = sheet.id.isNotEmpty
          ? sheet
          : await getTimesheetForAssignment(sheet.assignmentId);

      final row = (existing != null && existing.id.isNotEmpty)
          ? await _tablesDB.updateRow(
              databaseId: cfg.seasonPlannerDatabaseId,
              tableId: cfg.eventTimesheetsTableId,
              rowId: existing.id,
              data: submitted.toMap(),
            )
          : await _tablesDB.createRow(
              databaseId: cfg.seasonPlannerDatabaseId,
              tableId: cfg.eventTimesheetsTableId,
              rowId: ID.unique(),
              data: submitted.toMap(),
              permissions: SecurityPrivacyService.ownerAndSchoolAdminPerms(
                userId: sheet.userId,
                flightSchoolId: sheet.flightSchoolId,
              ),
            );

      final saved = EventTimesheet.fromMap(row.$id, row.data);
      NotificationService().markKeyAsSeen('u_timesheet_due:${sheet.assignmentId}');
      await AuditLogService().log(
        flightSchoolId: sheet.flightSchoolId,
        action: 'timesheet_submitted',
        details:
            'Stundenzettel eingereicht: ${sheet.eventName} (${sheet.roleName}) · ${saved.formattedTotalHours}',
      );
      // Prüfe automatisch, ob das Event nun vollständig abgeschlossen werden kann
      SecurityPrivacyService().checkEventCompletion(
        flightSchoolId: sheet.flightSchoolId,
        eventId: sheet.eventId,
      );
      return saved;
    } catch (e) {
      debugPrint('TimesheetService.submitWithSignature error: $e');
      return null;
    }
  }

  /// Admin kann einen eingereichten Stundenzettel bei Bedarf zur Korrektur wieder entsperren.
  Future<bool> reopenForCorrection(EventTimesheet sheet) async {
    if (sheet.id.isEmpty) return false;
    try {
      final cfg = AppwriteConfig();
      await _tablesDB.updateRow(
        databaseId: cfg.seasonPlannerDatabaseId,
        tableId: cfg.eventTimesheetsTableId,
        rowId: sheet.id,
        data: {
          'status': TimesheetStatus.draft.wireValue,
          'submitted_at': null,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
      );
      await AuditLogService().log(
        flightSchoolId: sheet.flightSchoolId,
        action: 'timesheet_reopened',
        details: 'Stundenzettel zur Korrektur geöffnet: ${sheet.eventName}',
      );
      return true;
    } catch (e) {
      debugPrint('TimesheetService.reopenForCorrection error: $e');
      return false;
    }
  }

  Future<Uint8List?> loadSignatureBytes(String? fileId) async {
    if (fileId == null || fileId.trim().isEmpty) return null;
    final cfg = AppwriteConfig();
    try {
      return await _storage.getFileView(
        bucketId: cfg.timesheetSignaturesBucketId,
        fileId: fileId,
      );
    } catch (_) {
      try {
        return await _storage.getFileView(
          bucketId: cfg.checklistSignaturesBucketId,
          fileId: fileId,
        );
      } catch (e) {
        debugPrint('TimesheetService.loadSignatureBytes error: $e');
        return null;
      }
    }
  }
}
