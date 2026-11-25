import 'dart:async';
import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:season_planner/core/appwrite_config.dart';
import 'package:season_planner/core/services/auth_service.dart';

/// Granulare Fachbereiche für selektive Realtime-Aktualisierungen.
/// Vermeidet Vollladungen (8–12 Queries je Client), wenn sich nur ein
/// Teilbereich (z. B. Events oder Tandem-Dienste) geändert hat.
enum RealtimeChangeDomain {
  events,
  tandem,
  members,
  planning,
  metadata,
  documents,
  timesheets,
  full,
}

/// Appwrite 2.x Realtime-Dienst für Echtzeit-Updates bei Datenbankänderungen.
/// Ergänzt das Fallback-Polling mit entprellten, fachbereichsbezogenen Updates.
class RealtimeService {
  static final RealtimeService _instance = RealtimeService._internal();
  factory RealtimeService() => _instance;
  RealtimeService._internal();

  /// Standard-Entprellung von 2,5 Sekunden: fasst schnelle Bearbeitungs-Serien
  /// (z. B. Admin bearbeitet 10 Events hintereinander) zu genau einem Update zusammen.
  static const Duration defaultDebounce = Duration(milliseconds: 2500);

  Client get _client => AuthService().client;

  Realtime? _realtime;

  Realtime get _rt => _realtime ??= Realtime(_client);

  /// Ordnet ein eingehendes Appwrite-Realtime-Event seinem Fachbereich zu.
  static RealtimeChangeDomain classifyEvent(
    RealtimeMessage message,
    AppwriteConfig cfg,
  ) {
    final sources = <String>[...message.channels, ...message.events];
    final joined = sources.join(' ');

    bool matchesTable(String tableId) =>
        joined.contains('.tables.$tableId.') ||
        joined.contains('.collections.$tableId.');

    if (matchesTable(cfg.eventsTableId) ||
        matchesTable(cfg.teamAssignmentsEventsTableId) ||
        matchesTable(cfg.checklistCompletionsTableId)) {
      return RealtimeChangeDomain.events;
    }
    if (matchesTable(cfg.tandemDutiesTableId) ||
        matchesTable(cfg.tandemDemandsTableId)) {
      return RealtimeChangeDomain.tandem;
    }
    if (matchesTable(cfg.membershipsId)) {
      return RealtimeChangeDomain.members;
    }
    if (matchesTable(cfg.planningPeriodsTableId) ||
        matchesTable(cfg.availabilitySubmissionsTableId)) {
      return RealtimeChangeDomain.planning;
    }
    if (matchesTable(cfg.qualificationApprovalsTableId) ||
        matchesTable(cfg.roleDocumentsTableId)) {
      return RealtimeChangeDomain.documents;
    }
    if (matchesTable(cfg.eventTimesheetsTableId)) {
      return RealtimeChangeDomain.timesheets;
    }
    if (matchesTable(cfg.flightSchoolsCollectionId) ||
        matchesTable(cfg.teamRolesTableId) ||
        matchesTable(cfg.qualificationsTableId)) {
      return RealtimeChangeDomain.metadata;
    }
    return RealtimeChangeDomain.full;
  }

  /// Abonniert alle relevanten Appwrite 2.x TablesDB-Channels und bündelt
  /// eingehende Signale über [debounceDuration] (Standard: 2,5 Sek.).
  /// Ruft [onDomainsChanged] mit der Menge der betroffenen Fachbereiche auf
  /// (und/oder optional das Legacy-Callback [onChange]).
  RealtimeSubscription? subscribeToSeasonPlanner({
    ValueChanged<Set<RealtimeChangeDomain>>? onDomainsChanged,
    VoidCallback? onChange,
    Set<String> Function()? relevantFlightSchoolIds,
    Duration debounceDuration = defaultDebounce,
  }) {
    final cfg = AppwriteConfig();
    Timer? debounce;
    final pendingDomains = <RealtimeChangeDomain>{};

    bool isRelevantPayload(Map<String, dynamic> payload) {
      if (relevantFlightSchoolIds == null) return true;
      final allowed = relevantFlightSchoolIds();
      if (allowed.isEmpty) return true;

      final fsId = (payload['flight_school_id'] ?? '').toString().trim();
      if (fsId.isNotEmpty) {
        return allowed.contains(fsId);
      }

      final relFs = payload['flightSchools'];
      if (relFs is String && relFs.trim().isNotEmpty) {
        return allowed.contains(relFs.trim());
      }
      if (relFs is Map && relFs['\$id'] != null) {
        return allowed.contains(relFs['\$id'].toString());
      }

      // Verschachtelte Event-Relation (z. B. bei team_assignments_events) prüfen
      final relEv = payload['events'];
      if (relEv is Map) {
        final evSchoolId = (relEv['flight_school_id'] ?? '').toString().trim();
        if (evSchoolId.isNotEmpty) {
          return allowed.contains(evSchoolId);
        }
      }

      // Zeilen ohne explizites Schul-Feld sicherheitshalber durchlassen
      return true;
    }

    try {
      final channels = <Object>[
        Channel.tablesdb(cfg.mainDatabaseId).table(cfg.membershipsId).row(),
        Channel.tablesdb(cfg.mainDatabaseId)
            .table(cfg.flightSchoolsCollectionId)
            .row(),
        Channel.tablesdb(cfg.mainDatabaseId).table(cfg.teamRolesTableId).row(),
        Channel.tablesdb(cfg.mainDatabaseId)
            .table(cfg.qualificationsTableId)
            .row(),
        Channel.tablesdb(cfg.mainDatabaseId)
            .table(cfg.qualificationApprovalsTableId)
            .row(),
        Channel.tablesdb(cfg.seasonPlannerDatabaseId)
            .table(cfg.eventsTableId)
            .row(),
        Channel.tablesdb(cfg.seasonPlannerDatabaseId)
            .table(cfg.teamAssignmentsEventsTableId)
            .row(),
        Channel.tablesdb(cfg.seasonPlannerDatabaseId)
            .table(cfg.planningPeriodsTableId)
            .row(),
        Channel.tablesdb(cfg.seasonPlannerDatabaseId)
            .table(cfg.availabilitySubmissionsTableId)
            .row(),
        Channel.tablesdb(cfg.seasonPlannerDatabaseId)
            .table(cfg.roleDocumentsTableId)
            .row(),
        Channel.tablesdb(cfg.seasonPlannerDatabaseId)
            .table(cfg.checklistCompletionsTableId)
            .row(),
        Channel.tablesdb(cfg.seasonPlannerDatabaseId)
            .table(cfg.tandemDutiesTableId)
            .row(),
        Channel.tablesdb(cfg.seasonPlannerDatabaseId)
            .table(cfg.tandemDemandsTableId)
            .row(),
        Channel.tablesdb(cfg.seasonPlannerDatabaseId)
            .table(cfg.eventTimesheetsTableId)
            .row(),
      ];

      final sub = _rt.subscribe(channels);
      sub.stream.listen(
        (event) {
          if (!isRelevantPayload(event.payload)) return;
          pendingDomains.add(classifyEvent(event, cfg));
          debounce?.cancel();
          debounce = Timer(debounceDuration, () {
            final batch = Set<RealtimeChangeDomain>.from(pendingDomains);
            pendingDomains.clear();
            if (batch.isEmpty) return;
            onDomainsChanged?.call(batch);
            onChange?.call();
          });
        },
        onError: (e) {
          debugPrint('Realtime stream error: $e');
        },
        onDone: () {
          debounce?.cancel();
          pendingDomains.clear();
        },
      );
      return sub;
    } catch (e) {
      debugPrint('Realtime subscribe error: $e');
      return null;
    }
  }
}
