import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:season_planner/core/appwrite_config.dart';
import 'package:season_planner/core/data/models/audit_log_model.dart';
import 'package:season_planner/core/services/auth_service.dart';

class AuditLogService {
  static final AuditLogService _instance = AuditLogService._internal();
  factory AuditLogService() => _instance;
  AuditLogService._internal();

  Client get _client => AuthService().client;

  late final TablesDB _tablesDB = TablesDB(_client);

  Future<void> log({
    required String flightSchoolId,
    required String action,
    String details = '',
    String? userId,
  }) async {
    try {
      // Immer bevorzugt die tatsächlich authentifizierte Session-ID verwenden
      final authUser = await AuthService().getCurrentUser();
      final uid = authUser?.$id ?? userId ?? '';
      final cfg = AppwriteConfig();
      await _tablesDB.createRow(
        databaseId: cfg.seasonPlannerDatabaseId,
        tableId: cfg.auditLogsTableId,
        rowId: ID.unique(),
        data: {
          'flight_school_id': flightSchoolId,
          'user_id': uid,
          'action': action,
          'details': details,
          'timestamp': DateTime.now().toIso8601String(),
        },
        permissions: [
          Permission.read(Role.team(flightSchoolId, 'admin')),
        ],
      );
    } catch (e) {
      debugPrint('AuditLogService.log error: $e');
    }
  }

  Future<List<AuditLogEntry>> listLogs({
    required String flightSchoolId,
    int limit = 100,
    String? cursorAfter,
  }) async {
    try {
      final cfg = AppwriteConfig();
      final res = await _tablesDB.listRows(
        databaseId: cfg.seasonPlannerDatabaseId,
        tableId: cfg.auditLogsTableId,
        queries: [
          Query.equal('flight_school_id', flightSchoolId),
          Query.orderDesc('timestamp'),
          Query.limit(limit),
          if (cursorAfter != null && cursorAfter.isNotEmpty)
            Query.cursorAfter(cursorAfter),
        ],
      );
      return res.rows.map((r) => AuditLogEntry.fromMap(r.$id, r.data)).toList();
    } catch (e) {
      debugPrint('AuditLogService.listLogs error: $e');
      return [];
    }
  }
}
