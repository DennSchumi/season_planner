import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:season_planner/core/appwrite_config.dart';
import 'package:season_planner/core/data/enums/event_status_enum.dart';
import 'package:season_planner/core/data/enums/event_user_status_enum.dart';
import 'package:season_planner/core/data/models/event_model.dart';
import 'package:season_planner/core/data/models/tandem_model.dart';
import 'package:season_planner/core/services/appwrite_pagination.dart';
import 'package:season_planner/core/services/audit_log_service.dart';
import 'package:season_planner/core/services/auth_service.dart';
import 'package:season_planner/core/services/data_window.dart';
import 'package:season_planner/core/services/security_privacy_service.dart';

class TandemService {
  static final TandemService _instance = TandemService._internal();
  factory TandemService() => _instance;
  TandemService._internal();

  Client get _client => AuthService().client;
  late final TablesDB _tablesDB = TablesDB(_client);

  // ==================== FLIGHT SCHOOL TOGGLE ====================

  Future<bool> setTandemEnabled({
    required String flightSchoolId,
    required bool enabled,
  }) async {
    try {
      final cfg = AppwriteConfig();
      await _tablesDB.updateRow(
        databaseId: cfg.mainDatabaseId,
        tableId: cfg.flightSchoolsCollectionId,
        rowId: flightSchoolId,
        data: {'tandem_enabled': enabled},
      );
      await AuditLogService().log(
        flightSchoolId: flightSchoolId,
        action: enabled ? 'tandem_enabled' : 'tandem_disabled',
        details: enabled
            ? 'Tandemplanung für Flugschule aktiviert'
            : 'Tandemplanung für Flugschule deaktiviert',
      );
      return true;
    } catch (e) {
      debugPrint('TandemService.setTandemEnabled error: $e');
      return false;
    }
  }

  // ==================== TANDEM DUTIES (CRUD) ====================

  Future<List<TandemDuty>> listDutiesForSchool(
    String flightSchoolId, {
    bool includeArchive = false,
  }) async {
    if (flightSchoolId.trim().isEmpty) return const [];
    try {
      final cfg = AppwriteConfig();
      final queries = <String>[
        Query.equal('flight_school_id', flightSchoolId),
        if (!includeArchive) ...[
          Query.greaterThanEqual(
            'end_date',
            DataWindow.defaultStart().toIso8601String(),
          ),
          Query.lessThanEqual(
            'start_date',
            DataWindow.defaultEnd().toIso8601String(),
          ),
        ],
      ];
      final rows = await listAllRows(
        _tablesDB,
        databaseId: cfg.seasonPlannerDatabaseId,
        tableId: cfg.tandemDutiesTableId,
        queries: queries,
      );
      final list = rows
          .map((r) => TandemDuty.fromMap(r.$id, r.data))
          .toList()
        ..sort((a, b) => a.startDate.compareTo(b.startDate));
      return list;
    } catch (e) {
      debugPrint('TandemService.listDutiesForSchool error: $e');
      return const [];
    }
  }

  Future<TandemDuty?> createDuty({
    required String flightSchoolId,
    required String userId,
    required DateTime startDate,
    required DateTime endDate,
    required bool isFullDay,
    required TandemDutyStatus status,
    String notes = '',
    String pilotName = '',
  }) async {
    try {
      final cfg = AppwriteConfig();
      final authUser = await AuthService().getCurrentUser();
      final effectiveStart = isFullDay
          ? DateTime(startDate.year, startDate.month, startDate.day, 0, 0)
          : startDate;
      final effectiveEnd = isFullDay
          ? DateTime(endDate.year, endDate.month, endDate.day, 23, 59)
          : endDate;

      final payload = TandemDuty(
        id: '',
        flightSchoolId: flightSchoolId,
        userId: userId,
        startDate: effectiveStart,
        endDate: effectiveEnd.isBefore(effectiveStart)
            ? effectiveStart
            : effectiveEnd,
        isFullDay: isFullDay,
        status: status,
        notes: notes.trim(),
        createdBy: authUser?.$id ?? userId,
      );

      final row = await _tablesDB.createRow(
        databaseId: cfg.seasonPlannerDatabaseId,
        tableId: cfg.tandemDutiesTableId,
        rowId: ID.unique(),
        data: payload.toMap(),
        permissions: [
          Permission.read(Role.team(flightSchoolId)),
          Permission.update(Role.user(userId)),
          Permission.delete(Role.user(userId)),
          Permission.update(Role.team(flightSchoolId, 'admin')),
          Permission.delete(Role.team(flightSchoolId, 'admin')),
        ],
      );
      final created = TandemDuty.fromMap(row.$id, row.data);
      await AuditLogService().log(
        flightSchoolId: flightSchoolId,
        action: 'tandem_duty_created',
        details:
            'Tandem (${status.label}): ${pilotName.isNotEmpty ? pilotName : userId} · ${created.dateRangeLabel} (${created.timeWindowLabel})',
      );
      return created;
    } catch (e) {
      debugPrint('TandemService.createDuty error: $e');
      return null;
    }
  }

  Future<bool> updateDutyStatus({
    required String flightSchoolId,
    required String dutyId,
    required TandemDutyStatus newStatus,
    String summary = '',
  }) async {
    try {
      final cfg = AppwriteConfig();
      await _tablesDB.updateRow(
        databaseId: cfg.seasonPlannerDatabaseId,
        tableId: cfg.tandemDutiesTableId,
        rowId: dutyId,
        data: {'status': newStatus.wireValue},
      );
      await AuditLogService().log(
        flightSchoolId: flightSchoolId,
        action: 'tandem_duty_status_${newStatus.wireValue}',
        details: summary.isNotEmpty
            ? '$summary -> ${newStatus.label}'
            : 'Tandem-Status auf ${newStatus.label} gesetzt',
      );
      return true;
    } catch (e) {
      debugPrint('TandemService.updateDutyStatus error: $e');
      return false;
    }
  }

  Future<bool> deleteDuty({
    required String flightSchoolId,
    required String dutyId,
    String summary = '',
  }) async {
    try {
      final cfg = AppwriteConfig();
      await _tablesDB.deleteRow(
        databaseId: cfg.seasonPlannerDatabaseId,
        tableId: cfg.tandemDutiesTableId,
        rowId: dutyId,
      );
      await AuditLogService().log(
        flightSchoolId: flightSchoolId,
        action: 'tandem_duty_deleted',
        details: summary.isNotEmpty ? 'Entfernt: $summary' : 'Tandem-Einteilung entfernt',
      );
      return true;
    } catch (e) {
      debugPrint('TandemService.deleteDuty error: $e');
      return false;
    }
  }

  // ==================== TANDEM DEMANDS (CRUD) ====================

  Future<List<TandemDemand>> listDemandsForSchool(String flightSchoolId) async {
    if (flightSchoolId.trim().isEmpty) return const [];
    try {
      final cfg = AppwriteConfig();
      final rows = await listAllRows(
        _tablesDB,
        databaseId: cfg.seasonPlannerDatabaseId,
        tableId: cfg.tandemDemandsTableId,
        queries: [Query.equal('flight_school_id', flightSchoolId)],
      );
      final list = rows
          .map((r) => TandemDemand.fromMap(r.$id, r.data))
          .toList()
        ..sort((a, b) => a.startDate.compareTo(b.startDate));
      return list;
    } catch (e) {
      debugPrint('TandemService.listDemandsForSchool error: $e');
      return const [];
    }
  }

  Future<TandemDemand?> createDemand({
    required String flightSchoolId,
    required DateTime startDate,
    required DateTime endDate,
    required int targetPilots,
    required Set<int> weekdays,
    String label = '',
  }) async {
    try {
      final cfg = AppwriteConfig();
      final demand = TandemDemand(
        id: '',
        flightSchoolId: flightSchoolId,
        startDate: startDate,
        endDate: endDate,
        targetPilots: targetPilots,
        weekdays: weekdays,
        label: label.trim(),
      );
      final row = await _tablesDB.createRow(
        databaseId: cfg.seasonPlannerDatabaseId,
        tableId: cfg.tandemDemandsTableId,
        rowId: ID.unique(),
        data: demand.toMap(),
        permissions: SecurityPrivacyService.schoolReadAdminWritePerms(
          flightSchoolId,
        ),
      );
      final created = TandemDemand.fromMap(row.$id, row.data);
      await AuditLogService().log(
        flightSchoolId: flightSchoolId,
        action: 'tandem_demand_created',
        details:
            'Tandem-Bedarf: $targetPilots Piloten (${created.dateRangeLabel}, ${created.weekdaysLabel})',
      );
      return created;
    } catch (e) {
      debugPrint('TandemService.createDemand error: $e');
      return null;
    }
  }

  Future<bool> updateDemand(TandemDemand demand) async {
    try {
      final cfg = AppwriteConfig();
      await _tablesDB.updateRow(
        databaseId: cfg.seasonPlannerDatabaseId,
        tableId: cfg.tandemDemandsTableId,
        rowId: demand.id,
        data: demand.toMap(),
      );
      return true;
    } catch (e) {
      debugPrint('TandemService.updateDemand error: $e');
      return false;
    }
  }

  Future<bool> deleteDemand({
    required String flightSchoolId,
    required String demandId,
  }) async {
    try {
      final cfg = AppwriteConfig();
      await _tablesDB.deleteRow(
        databaseId: cfg.seasonPlannerDatabaseId,
        tableId: cfg.tandemDemandsTableId,
        rowId: demandId,
      );
      await AuditLogService().log(
        flightSchoolId: flightSchoolId,
        action: 'tandem_demand_deleted',
        details: 'Tandem-Bedarfszeitraum gelöscht',
      );
      return true;
    } catch (e) {
      debugPrint('TandemService.deleteDemand error: $e');
      return false;
    }
  }

  // ==================== DOPPELBELEGUNGS-PRÜFUNG ====================

  /// Prüft streng, ob [userId] im Zeitraum [startDate]–[endDate] bereits
  /// in einem normalen Event (bindend/angefragt) ODER als Tandempilot verplant ist.
  /// Gibt `null` zurück, wenn frei, ansonsten einen lesbaren Konflikt-Grund.
  static String? findScheduleConflict({
    required String userId,
    required DateTime startDate,
    required DateTime endDate,
    required bool isFullDay,
    required List<Event> events,
    required List<TandemDuty> tandemDuties,
    String? ignoreDutyId,
    String? userRowId,
    bool isUserOwnEventsView = false,
  }) {
    bool matchesUser(String candidateId) {
      if (candidateId.trim().isEmpty) return false;
      if (candidateId == userId) return true;
      if (userRowId != null &&
          userRowId.isNotEmpty &&
          candidateId == userRowId) {
        return true;
      }
      return false;
    }

    final reqStart = isFullDay
        ? DateTime(startDate.year, startDate.month, startDate.day, 0, 0)
        : startDate;
    final reqEnd = isFullDay
        ? DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59)
        : endDate;

    // 1) Normale Events prüfen
    for (final ev in events) {
      if (ev.status == EventStatusEnum.canceled) continue;
      final overlaps =
          reqStart.isBefore(ev.endTime) && ev.startTime.isBefore(reqEnd);
      if (!overlaps) continue;

      if (isUserOwnEventsView) {
        if (ev.isOwnBindingAssignment) {
          return 'Bereits eingeplant: ${ev.displayName}';
        }
        if (!ev.isSwapOfferFromOther &&
            ev.assignmentStatus == EventUserStatusEnum.pending_flight_school) {
          return 'Bereits beworben auf: ${ev.displayName}';
        }
        if (ev.isSwapOfferFromOther && ev.swapRequestedBy == userId) {
          return 'Bereits Tausch angefragt für: ${ev.displayName}';
        }
      } else {
        final assigned = ev.team.any((tm) {
          if (tm.isSlot) return false;
          if (!matchesUser(tm.userId)) return false;
          final st = tm.statusEnum;
          return st == EventUserStatusEnum.accepted_flight_school ||
              st == EventUserStatusEnum.accepted_user ||
              st == EventUserStatusEnum.pending_user ||
              st == EventUserStatusEnum.user_requests_change;
        });
        if (assigned) {
          return 'Bereits in Event „${ev.displayName}“ verplant';
        }
      }
    }

    // 2) Bestehende Tandem-Dienste prüfen
    for (final d in tandemDuties) {
      if (ignoreDutyId != null && d.id == ignoreDutyId) continue;
      final blocks = isUserOwnEventsView
          ? (d.status == TandemDutyStatus.confirmed ||
              d.status == TandemDutyStatus.requestedByPilot ||
              d.status == TandemDutyStatus.cancellationRequested)
          : d.status.blocksSchedule;
      if (!blocks) continue;
      if (!matchesUser(d.userId)) continue;
      if (d.overlapsTimeWindow(
        reqStart,
        reqEnd,
        otherIsFullDay: isFullDay,
      )) {
        return 'Bereits als Tandempilot eingetragen (${d.dateRangeLabel})';
      }
    }

    return null;
  }

  /// Nutzerseitige strikte Doppelbuchungs- & Mehrfachbewerbungs-Prüfung:
  /// Verhindert, dass ein Nutzer sich gleichzeitig für zwei Events meldet/einbucht
  /// oder parallel zu einem bestätigten/angefragten Tandem-Einsatz ein Event bucht.
  static String? findUserEventBookingConflict({
    required String userId,
    required DateTime startTime,
    required DateTime endTime,
    required List<Event> userEvents,
    required List<TandemDuty> userTandemDuties,
    String? ignoreEventKey,
  }) {
    String keyOf(Event e) =>
        (e.eventDocId != null && e.eventDocId!.isNotEmpty) ? e.eventDocId! : e.id;

    // 1) Andere zeitgleiche Events (bereits eingeteilt, beworben oder Tausch angefragt)
    for (final ev in userEvents) {
      if (ev.status == EventStatusEnum.canceled) continue;
      final evKey = keyOf(ev);
      if (ignoreEventKey != null &&
          ignoreEventKey.isNotEmpty &&
          evKey == ignoreEventKey) {
        continue;
      }
      final overlaps =
          startTime.isBefore(ev.endTime) && ev.startTime.isBefore(endTime);
      if (!overlaps) continue;

      if (ev.isOwnBindingAssignment) {
        return 'Bereits eingeteilt in „${ev.displayName}“';
      }
      if (!ev.isSwapOfferFromOther &&
          ev.assignmentStatus == EventUserStatusEnum.pending_flight_school) {
        return 'Bereits beworben auf „${ev.displayName}“';
      }
      if (ev.isSwapOfferFromOther && ev.swapRequestedBy == userId) {
        return 'Bereits Tausch angefragt für „${ev.displayName}“';
      }
    }

    // 2) Bestätigte oder selbst angefragte Tandem-Einsätze im selben Zeitraum
    for (final d in userTandemDuties) {
      if (d.userId != userId) continue;
      if (d.status != TandemDutyStatus.confirmed &&
          d.status != TandemDutyStatus.requestedByPilot &&
          d.status != TandemDutyStatus.cancellationRequested) {
        continue;
      }
      if (d.overlapsTimeWindow(startTime, endTime)) {
        return d.status == TandemDutyStatus.requestedByPilot
            ? 'Bereits als Tandempilot angefragt (${d.dateRangeLabel})'
            : 'Bereits als Tandempilot eingeteilt (${d.dateRangeLabel})';
      }
    }

    return null;
  }

  /// Admin-Konfliktprüfung: Liefert alle zeitgleichen Events und Tandem-Einsätze
  /// eines Teammitglieds (für Warnhinweise & Pflicht-Bestätigung).
  static List<String> findMemberEventConflicts({
    required String userId,
    String? userRowId,
    required DateTime startTime,
    required DateTime endTime,
    required List<Event> events,
    required List<TandemDuty> tandemDuties,
    String? ignoreEventId,
  }) {
    bool matchesUser(String candidateId) {
      if (candidateId.trim().isEmpty) return false;
      if (candidateId == userId) return true;
      if (userRowId != null &&
          userRowId.isNotEmpty &&
          candidateId == userRowId) {
        return true;
      }
      return false;
    }

    final conflicts = <String>[];

    for (final ev in events) {
      if (ignoreEventId != null &&
          ignoreEventId.isNotEmpty &&
          (ev.id == ignoreEventId || ev.eventDocId == ignoreEventId)) {
        continue;
      }
      if (ev.status == EventStatusEnum.canceled) continue;
      final overlaps =
          startTime.isBefore(ev.endTime) && ev.startTime.isBefore(endTime);
      if (!overlaps) continue;

      final booked = ev.team.any((tm) {
        if (tm.isSlot) return false;
        if (!matchesUser(tm.userId)) return false;
        final st = tm.statusEnum;
        return st != EventUserStatusEnum.denied_user &&
            st != EventUserStatusEnum.denied_flight_school &&
            st != EventUserStatusEnum.open;
      });
      if (booked) {
        conflicts.add('Event „${ev.displayName}“');
      }
    }

    for (final d in tandemDuties) {
      if (!d.status.blocksSchedule) continue;
      if (!matchesUser(d.userId)) continue;
      if (d.overlapsTimeWindow(startTime, endTime)) {
        conflicts.add('Tandem-Einsatz (${d.dateRangeLabel})');
      }
    }

    return conflicts;
  }

  /// Prüft für EventUpsertView, ob ein Mitarbeiter während eines Event-Zeitraums
  /// bereits als Tandempilot geblockt ist.
  static String? findTandemConflictForEvent({
    required String userId,
    String? userRowId,
    required DateTime eventStart,
    required DateTime eventEnd,
    required List<TandemDuty> tandemDuties,
  }) {
    for (final d in tandemDuties) {
      if (!d.status.blocksSchedule) continue;
      final sameUser = d.userId == userId ||
          (userRowId != null && userRowId.isNotEmpty && d.userId == userRowId);
      if (!sameUser) continue;
      if (d.overlapsTimeWindow(eventStart, eventEnd)) {
        return 'Tandem (${d.dateRangeLabel})';
      }
    }
    return null;
  }
}
