import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:season_planner/core/appwrite_config.dart';
import 'package:season_planner/core/data/enums/event_status_enum.dart';
import 'package:season_planner/core/data/models/event_template_model.dart';
import 'package:season_planner/core/services/audit_log_service.dart';
import 'package:season_planner/core/services/auth_service.dart';
import 'package:season_planner/core/services/security_privacy_service.dart';

class EventTemplateService {
  static final EventTemplateService _instance =
      EventTemplateService._internal();
  factory EventTemplateService() => _instance;
  EventTemplateService._internal();

  Client get _client => AuthService().client;

  late final TablesDB _tablesDB = TablesDB(_client);

  Future<List<EventTemplate>> listTemplates(String flightSchoolId) async {
    try {
      final cfg = AppwriteConfig();
      final res = await _tablesDB.listRows(
        databaseId: cfg.seasonPlannerDatabaseId,
        tableId: cfg.eventTemplatesTableId,
        queries: [
          Query.equal('flight_school_id', flightSchoolId),
          Query.limit(200),
        ],
      );
      final list = res.rows
          .map((r) => EventTemplate.fromMap(r.$id, r.data))
          .toList();
      list.sort(
        (a, b) => a.templateName
            .toLowerCase()
            .compareTo(b.templateName.toLowerCase()),
      );
      return list;
    } catch (e) {
      debugPrint('listTemplates error: $e');
      return [];
    }
  }

  Future<EventTemplate?> createTemplate({
    required String flightSchoolId,
    required String templateName,
    required String displayName,
    String identifier = '',
    String location = '',
    String notes = '',
    EventStatusEnum status = EventStatusEnum.scheduled,
    required int durationMinutes,
    required int defaultStartHour,
    required int defaultStartMinute,
    required List<String> roles,
  }) async {
    try {
      final cfg = AppwriteConfig();
      final trimmedName = templateName.trim();
      final row = await _tablesDB.createRow(
        databaseId: cfg.seasonPlannerDatabaseId,
        tableId: cfg.eventTemplatesTableId,
        rowId: ID.unique(),
        data: {
          'flight_school_id': flightSchoolId,
          'template_name': trimmedName,
          'display_name': displayName.trim(),
          'identifier': identifier.trim(),
          'location': location.trim(),
          'notes': notes.trim(),
          'status': status.name,
          'duration_minutes': durationMinutes < 1 ? 60 : durationMinutes,
          'default_start_hour': defaultStartHour.clamp(0, 23),
          'default_start_minute': defaultStartMinute.clamp(0, 59),
          'roles': roles,
        },
        permissions: SecurityPrivacyService.schoolReadAdminWritePerms(
          flightSchoolId,
        ),
      );
      await AuditLogService().log(
        flightSchoolId: flightSchoolId,
        action: 'Event-Vorlage erstellt',
        details: '„$trimmedName“ (${roles.length} Rolle(n))',
      );
      return EventTemplate.fromMap(row.$id, row.data);
    } catch (e) {
      debugPrint('createTemplate error: $e');
      return null;
    }
  }

  Future<bool> deleteTemplate(EventTemplate template) async {
    try {
      final cfg = AppwriteConfig();
      await _tablesDB.deleteRow(
        databaseId: cfg.seasonPlannerDatabaseId,
        tableId: cfg.eventTemplatesTableId,
        rowId: template.id,
      );
      await AuditLogService().log(
        flightSchoolId: template.flightSchoolId,
        action: 'Event-Vorlage gelöscht',
        details: '„${template.templateName}“',
      );
      return true;
    } catch (e) {
      debugPrint('deleteTemplate error: $e');
      return false;
    }
  }
}
