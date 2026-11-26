import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:season_planner/core/data/enums/event_status_enum.dart';
import 'package:season_planner/core/data/enums/event_user_status_enum.dart';
import 'package:season_planner/core/data/enums/membership_status_enum.dart';
import 'package:season_planner/core/data/models/event_model.dart';
import 'package:season_planner/core/data/models/notification_preferences_model.dart';
import 'package:season_planner/core/data/models/planning_period_model.dart';
import 'package:season_planner/core/data/models/tandem_model.dart';
import 'package:season_planner/core/services/auth_service.dart';
import 'package:season_planner/core/services/inventory_todo_service.dart';
import 'package:season_planner/core/services/native_push_bridge.dart';
import 'package:season_planner/core/services/role_document_service.dart';
import 'package:season_planner/core/services/tandem_service.dart';
import 'package:season_planner/core/services/timesheet_service.dart';
import 'package:season_planner/core/services/web_notification_bridge.dart';
import 'package:season_planner/core/theme.dart';
import 'package:season_planner/fsAdmin/data/models/flight_school_model_flight_school_view.dart';
import 'package:season_planner/user/data/models/user_model_userView.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Zentraler Benachrichtigungsdienst:
/// - Speichert Nutzer-Einstellungen lokal (`SharedPreferences`) und geräteübergreifend
///   in Appwrite `account.prefs['notif_prefs']` (lesbar für serverseitige Push-Functions).
/// - Erkennt über Diff-Snapshots neue Einsatzanfragen, Tauschanfragen, offene Stellen,
///   Stufe-1-Zeiträume, To-Dos (inkl. Inventarmanager) und Admin-Aufgaben ohne Spam.
/// - Liefert im Web/PWA echte System-/Browser-Benachrichtigungen sowie überall
///   dezente In-App-Overlay-Banner.
class NotificationService extends ChangeNotifier {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static const String _kPrefsStorageKey = 'sp_notification_prefs_v1';
  static const String _kSeenKeysStorageKey = 'sp_notification_seen_keys_v1';
  static const String _kAppwritePrefField = 'notif_prefs';
  static const int _kMaxSeenKeys = 500;
  static const int _kMaxHistory = 30;

  NotificationPreferences _prefs = const NotificationPreferences();
  final List<AppNotificationEntry> _history = [];
  final Set<String> _seenKeys = {};

  bool _initialized = false;
  bool _primedUser = false;
  bool _primedAdmin = false;
  String? _loadedForUserId;
  OverlayEntry? _activeOverlay;
  Timer? _overlayTimer;

  NotificationPreferences get prefs => _prefs;
  List<AppNotificationEntry> get history => List.unmodifiable(_history);

  bool get isSystemPushSupported =>
      kIsWeb ? isWebNotificationSupported : isNativePushSupported;
  String get systemPermissionStatus =>
      kIsWeb ? webNotificationPermission : nativeNotificationPermission;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await _loadFromLocal();
    if (!kIsWeb) {
      await initNativePush(
        onForegroundFcmMessage: (title, body) {
          _recordHistory(
            AppNotificationEntry(
              key: 'fcm_${DateTime.now().millisecondsSinceEpoch}',
              category: NotificationCategory.assignmentRequests,
              title: title,
              body: body,
              createdAt: DateTime.now(),
            ),
          );
        },
      );
    }
    notifyListeners();
  }

  Future<void> _loadFromLocal() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final rawPrefs = sp.getString(_kPrefsStorageKey);
      if (rawPrefs != null && rawPrefs.isNotEmpty) {
        _prefs = NotificationPreferences.decode(rawPrefs);
      }
      final seenList = sp.getStringList(_kSeenKeysStorageKey);
      if (seenList != null) {
        _seenKeys
          ..clear()
          ..addAll(seenList);
      }
    } catch (e) {
      debugPrint('NotificationService _loadFromLocal error: $e');
    }
  }

  /// Synchronisiert die Präferenzen aus Appwrite `account.prefs` (geräteübergreifend).
  Future<void> syncFromAccountPrefs({String? userId}) async {
    if (!_initialized) await init();
    if (userId != null && userId.isNotEmpty && _loadedForUserId == userId) {
      return;
    }
    try {
      final authUser = await AuthService().getCurrentUser();
      if (authUser == null) return;
      _loadedForUserId = authUser.$id;
      if (!kIsWeb) {
        unawaited(syncNativePushTarget(userId: authUser.$id));
      }

      final raw = authUser.prefs.data[_kAppwritePrefField];
      if (raw is String && raw.isNotEmpty) {
        _prefs = NotificationPreferences.decode(raw);
        await _persistLocalPrefs(_prefs);
        notifyListeners();
      } else if (raw is Map<String, dynamic>) {
        _prefs = NotificationPreferences.fromJson(raw);
        await _persistLocalPrefs(_prefs);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('NotificationService syncFromAccountPrefs error: $e');
    }
  }

  Future<void> _persistLocalPrefs(NotificationPreferences next) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_kPrefsStorageKey, next.encode());
    } catch (_) {}
  }

  Future<void> _persistSeenKeys() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final trimmed = _seenKeys.length > _kMaxSeenKeys
          ? _seenKeys.toList().sublist(_seenKeys.length - _kMaxSeenKeys)
          : _seenKeys.toList();
      await sp.setStringList(_kSeenKeysStorageKey, trimmed);
    } catch (_) {}
  }

  /// Aktualisiert die Benachrichtigungs-Einstellungen lokal + in Appwrite `account.prefs`.
  Future<void> updatePreferences(NotificationPreferences next) async {
    _prefs = next;
    notifyListeners();
    await _persistLocalPrefs(next);

    try {
      final authUser = await AuthService().getCurrentUser();
      if (authUser == null) return;
      final existing = Map<String, dynamic>.from(authUser.prefs.data);
      existing[_kAppwritePrefField] = jsonEncode(next.toJson());
      await AuthService().account.updatePrefs(prefs: existing);
    } catch (e) {
      debugPrint('NotificationService updatePreferences remote error: $e');
    }
  }

  Future<String> requestSystemPermission() async {
    final result = kIsWeb
        ? await requestWebNotificationPermission()
        : await requestNativeNotificationPermission();
    notifyListeners();
    return result;
  }

  void clearHistory() {
    _history.clear();
    notifyListeners();
  }

  /// Markiert einen Benachrichtigungs-Key vorab als gesehen (z. B. nach eigener
  /// Bestätigung oder Abgabe eines Stundenzettels/einer Checkliste), damit der
  /// anschließende Snapshot-Diff keine überflüssige Push-Meldung auslöst.
  void markKeyAsSeen(String key) {
    if (key.trim().isEmpty) return;
    if (_seenKeys.add(key)) {
      unawaited(_persistSeenKeys());
    }
  }

  Future<void> resetOnLogout() async {
    _primedUser = false;
    _primedAdmin = false;
    _loadedForUserId = null;
    _history.clear();
    _seenKeys.clear();
    _dismissOverlay();
    if (!kIsWeb) {
      await unregisterNativePushTarget();
    }
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_kSeenKeysStorageKey);
    } catch (_) {}
    notifyListeners();
  }

  /// Sendet eine Test-Benachrichtigung (Browser-/OS-Push + In-App-Banner).
  Future<bool> sendTestNotification({BuildContext? context}) async {
    final actual = AppNotificationEntry(
      key: 'test_${DateTime.now().millisecondsSinceEpoch}',
      category: NotificationCategory.assignmentRequests,
      title: 'Test-Benachrichtigung',
      body: 'Benachrichtigungen für Season Planner sind aktiv und bereit.',
      createdAt: DateTime.now(),
    );

    _recordHistory(actual);
    final nativeSent = kIsWeb
        ? showWebNotification(
            title: actual.title,
            body: actual.body,
            tag: 'season_planner_test',
          )
        : await showNativeNotification(
            title: actual.title,
            body: actual.body,
            tag: 'season_planner_test',
          );
    if (context != null && context.mounted) {
      showInAppBanner(context, actual);
    }
    return nativeSent;
  }

  // ==================== USER SNAPSHOT DIFFING ====================

  Future<void> evaluateUserSnapshot({
    required UserModelUserView user,
    BuildContext? context,
  }) async {
    if (!_initialized) await init();
    await syncFromAccountPrefs(userId: user.id);

    final now = DateTime.now();
    final fsById = {for (final fs in user.flightSchools) fs.id: fs};
    final candidates = <AppNotificationEntry>[];

    // 1) Flugschul-Einladungen
    for (final fs in user.flightSchools) {
      if (fs.membershipStatus == MembershipStatusEnum.invited) {
        candidates.add(
          AppNotificationEntry(
            key: 'u_invite:${fs.id}',
            category: NotificationCategory.flightSchoolInvites,
            title: 'Neue Flugschul-Einladung',
            body: '${fs.displayName} hat dich ins Team eingeladen.',
            createdAt: now,
          ),
        );
      }

      // 2) Planungsstufe 1 (Verfügbarkeit eintragen)
      if (fs.membershipStatus == MembershipStatusEnum.active &&
          !fs.isTandemOnly) {
        for (final p in fs.planningPeriods) {
          if (p.stage == PlanningStage.availability) {
            final schoolName = fs.displayShortName.isNotEmpty
                ? fs.displayShortName
                : fs.displayName;
            candidates.add(
              AppNotificationEntry(
                key: 'u_stage1:${fs.id}:${p.id}',
                category: NotificationCategory.stage1Availability,
                title: 'Verfügbarkeit eintragen ($schoolName)',
                body:
                    '${p.seasonLabel} ist in Stufe 1 – trage jetzt deine verfügbaren Tage ein.',
                createdAt: now,
              ),
            );
          }
        }
      }
    }

    // 3) Events: Direktanfragen, Zuteilungen, Tauschplätze, offene Stellen
    String eventKey(Event e) =>
        (e.eventDocId != null && e.eventDocId!.isNotEmpty) ? e.eventDocId! : e.id;
    final scheduledKeys = user.events
        .where(
          (e) =>
              e.isOwnBindingAssignment && e.status != EventStatusEnum.canceled,
        )
        .map(eventKey)
        .toSet();

    bool isBlockedBySchedule(Event candidate) {
      if (scheduledKeys.contains(eventKey(candidate))) return true;
      final conflict = TandemService.findUserEventBookingConflict(
        userId: user.id,
        startTime: candidate.startTime,
        endTime: candidate.endTime,
        userEvents: user.events,
        userTandemDuties: user.tandemDuties,
        ignoreEventKey: eventKey(candidate),
      );
      return conflict != null;
    }

    final runningSchoolIds = <String>{};
    final recentChecklistDueEvents =
        <({String id, String eventDocId, String name, String role})>[];
    final recentTimesheetDueEvents =
        <({String id, String eventDocId, String name, String role})>[];
    for (final ev in user.events) {
      final fs = fsById[ev.flightSchoolId];
      if (fs == null || fs.membershipStatus != MembershipStatusEnum.active) {
        continue;
      }

      // Laufendes eigenes Event für Inventarmanager-Check merken
      if (ev.isOwnBindingAssignment &&
          ev.status != EventStatusEnum.canceled &&
          !ev.startTime.isAfter(now) &&
          ev.endTime.isAfter(now)) {
        runningSchoolIds.add(ev.flightSchoolId);
      }

      if (ev.endTime.isBefore(now) || ev.status == EventStatusEnum.canceled) {
        // Beendetes Event mit Rollen-Checkliste & Stundenzettel-Pflicht als Erinnerung prüfen
        // (nicht mehr für bereits abgeschlossene Events mit Status `done`)
        if (ev.isOwnBindingAssignment &&
            ev.status != EventStatusEnum.canceled &&
            ev.status != EventStatusEnum.done &&
            ev.endTime.isBefore(now) &&
            ev.endTime.isAfter(now.subtract(const Duration(days: 7)))) {
          final role = fs.findTeamRole(ev.role);
          if ((role?.checklistId ?? '').trim().isNotEmpty) {
            recentChecklistDueEvents.add((
              id: ev.id,
              eventDocId: ev.eventDocId ?? '',
              name: ev.displayName,
              role: ev.roleLabel,
            ));
          }
          if (fs.userRequiresTimesheet) {
            recentTimesheetDueEvents.add((
              id: ev.id,
              eventDocId: ev.eventDocId ?? '',
              name: ev.displayName,
              role: ev.roleLabel,
            ));
          }
        }
        continue;
      }

      final stage = fs.effectiveStageFor(ev);
      final dateStr =
          '${ev.startTime.day.toString().padLeft(2, '0')}.${ev.startTime.month.toString().padLeft(2, '0')}.';

      // 3a) Direktanfrage vom Admin an den Nutzer (nur wenn nicht zeitlich blockiert)
      if (!ev.isSwapOfferFromOther &&
          ev.assignmentStatus == EventUserStatusEnum.pending_user) {
        if (!isBlockedBySchedule(ev)) {
          candidates.add(
            AppNotificationEntry(
              key: 'u_direct_req:${ev.id}',
              category: NotificationCategory.assignmentRequests,
              title: 'Neue Einsatz-Anfrage',
              body:
                  '${ev.displayName} ($dateStr)${ev.role.isNotEmpty ? ' als ${ev.roleLabel}' : ''} – bitte bestätigen oder ablehnen.',
              createdAt: now,
            ),
          );
        }
      }
      // 3b) Verbindliche Zuteilung / bestätigte Bewerbung durch Admin
      // Hinweis: `accepted_user` ist immer die eigene Zusage des Nutzers -> keine überflüssige Push!
      else if (ev.assignmentStatus ==
          EventUserStatusEnum.accepted_flight_school) {
        candidates.add(
          AppNotificationEntry(
            key: 'u_assigned:${ev.id}:${ev.assignmentStatus.name}',
            category: NotificationCategory.assignmentRequests,
            title: 'Einsatz bestätigt',
            body:
                'Du bist für „${ev.displayName}“ ($dateStr)${ev.role.isNotEmpty ? ' als ${ev.roleLabel}' : ''} eingeplant.',
            createdAt: now,
          ),
        );
      }
      // 3c) Abgelehnte Bewerbung
      else if (ev.assignmentStatus ==
          EventUserStatusEnum.denied_flight_school) {
        candidates.add(
          AppNotificationEntry(
            key: 'u_denied:${ev.id}',
            category: NotificationCategory.assignmentRequests,
            title: 'Rückmeldung zu deiner Bewerbung',
            body:
                'Deine Bewerbung für „${ev.displayName}“ ($dateStr) wurde nicht berücksichtigt.',
            createdAt: now,
          ),
        );
      }
      // 3d) Offenes Tauschangebot eines Kollegen (Stufe 3 – nur wenn frei & berechtigt)
      else if (ev.isSwapOfferFromOther &&
          stage == 3 &&
          !fs.isTandemOnly &&
          !fs.isExtendedTeam &&
          fs.hasRole(ev.role) &&
          !isBlockedBySchedule(ev)) {
        candidates.add(
          AppNotificationEntry(
            key: 'u_swap_offer:${ev.id}',
            category: NotificationCategory.swapRequests,
            title: 'Tauschplatz verfügbar',
            body:
                '${ev.displayName} ($dateStr)${ev.role.isNotEmpty ? ' · ${ev.roleLabel}' : ''} wurde zum Tausch freigegeben.',
            createdAt: now,
          ),
        );
      }
      // 3e) Offene Stelle in Stufe 2/3 passend zur eigenen Rolle (nur wenn zeitlich frei)
      else if (ev.assignmentStatus == EventUserStatusEnum.open &&
          stage >= 2 &&
          !fs.isTandemOnly &&
          !fs.isExtendedTeam &&
          fs.hasRole(ev.role) &&
          !isBlockedBySchedule(ev)) {
        candidates.add(
          AppNotificationEntry(
            key: 'u_open_slot:${ev.id}',
            category: NotificationCategory.openOpportunities,
            title: 'Neue offene Stelle',
            body:
                '${ev.displayName} ($dateStr)${ev.role.isNotEmpty ? ' · ${ev.roleLabel}' : ''} sucht Verstärkung.',
            createdAt: now,
          ),
        );
      }
    }

    // 3a1) Fehlende Checklisten (nur wenn Abruf erfolgreich UND tatsächlich noch nicht unterschrieben)
    if (recentChecklistDueEvents.isNotEmpty) {
      final completions =
          await RoleDocumentService().tryListCompletionsForUser(user.id);
      if (completions != null) {
        final signedAssignmentIds = completions
            .where((c) => c.isSigned)
            .map((c) => c.assignmentId)
            .where((id) => id.isNotEmpty)
            .toSet();
        final signedEventIds = completions
            .where((c) => c.isSigned)
            .map((c) => c.eventId)
            .where((id) => id.isNotEmpty)
            .toSet();
        for (final item in recentChecklistDueEvents) {
          final alreadySigned = signedAssignmentIds.contains(item.id) ||
              (item.eventDocId.isNotEmpty &&
                  signedEventIds.contains(item.eventDocId));
          if (alreadySigned) continue;
          candidates.add(
            AppNotificationEntry(
              key: 'u_checklist_due:${item.id}',
              category: NotificationCategory.checklistsAndDocs,
              title: 'Checkliste prüfen',
              body:
                  'Bitte Checkliste für „${item.name}“ (${item.role}) abschließen.',
              createdAt: now,
            ),
          );
        }
      }
    }

    // 3a2) Fehlende Stundenzettel (nur wenn Abruf erfolgreich UND tatsächlich noch nicht abgesendet)
    if (recentTimesheetDueEvents.isNotEmpty) {
      final sheets = await TimesheetService().tryListTimesheetsForUser(user.id);
      if (sheets != null) {
        final submittedAssignmentIds = sheets
            .where((s) => s.isSubmitted)
            .map((s) => s.assignmentId)
            .where((id) => id.isNotEmpty)
            .toSet();
        final submittedEventIds = sheets
            .where((s) => s.isSubmitted)
            .map((s) => s.eventId)
            .where((id) => id.isNotEmpty)
            .toSet();
        for (final item in recentTimesheetDueEvents) {
          final alreadySubmitted = submittedAssignmentIds.contains(item.id) ||
              (item.eventDocId.isNotEmpty &&
                  submittedEventIds.contains(item.eventDocId));
          if (alreadySubmitted) continue;
          candidates.add(
            AppNotificationEntry(
              key: 'u_timesheet_due:${item.id}',
              category: NotificationCategory.checklistsAndDocs,
              title: 'Stundenzettel ausfüllen',
              body:
                  'Bitte Stundenzettel für „${item.name}“ (${item.role}) vervollständigen und absenden.',
              createdAt: now,
            ),
          );
        }
      }
    }

    // 3b) Tandem-Einsätze & -Anfragen (für qualifizierte Tandempiloten)
    final today = DateTime(now.year, now.month, now.day);
    for (final duty in user.tandemDuties) {
      if (duty.userId != user.id || duty.endDay.isBefore(today)) continue;
      final fs = fsById[duty.flightSchoolId];
      if (fs == null ||
          !fs.tandemEnabled ||
          !fs.isTandemPilot ||
          fs.membershipStatus != MembershipStatusEnum.active) {
        continue;
      }
      final schoolLabel = fs.displayShortName.trim().isNotEmpty
          ? fs.displayShortName.trim()
          : fs.displayName;
      if (duty.status == TandemDutyStatus.requestedByAdmin) {
        final tandemConflict = TandemService.findScheduleConflict(
          userId: user.id,
          startDate: duty.startDate,
          endDate: duty.endDate,
          isFullDay: duty.isFullDay,
          events: user.events,
          tandemDuties: user.tandemDuties,
          ignoreDutyId: duty.id,
          isUserOwnEventsView: true,
        );
        if (tandemConflict == null) {
          candidates.add(
            AppNotificationEntry(
              key: 'u_tandem_req:${duty.id}',
              category: NotificationCategory.assignmentRequests,
              title: 'Neue Tandem-Anfrage ($schoolLabel)',
              body:
                  'Tandempilot am ${duty.dateRangeLabel} (${duty.timeWindowLabel}) – bitte zusagen oder ablehnen.',
              createdAt: now,
            ),
          );
        }
      } else if (duty.status == TandemDutyStatus.confirmed) {
        candidates.add(
          AppNotificationEntry(
            key: 'u_tandem_confirmed:${duty.id}',
            category: NotificationCategory.assignmentRequests,
            title: 'Tandem-Einsatz bestätigt ($schoolLabel)',
            body:
                'Du bist für ${duty.dateRangeLabel} (${duty.timeWindowLabel}) als Tandempilot eingeteilt.',
            createdAt: now,
          ),
        );
      } else if (duty.status == TandemDutyStatus.declined) {
        candidates.add(
          AppNotificationEntry(
            key: 'u_tandem_declined:${duty.id}',
            category: NotificationCategory.assignmentRequests,
            title: 'Tandem-Anfrage abgelehnt ($schoolLabel)',
            body:
                'Deine Tandem-Anfrage für ${duty.dateRangeLabel} wurde nicht bestätigt.',
            createdAt: now,
          ),
        );
      }
    }

    // 4) Inventarmanager-Aufgaben bei laufendem eigenem Event
    if (runningSchoolIds.isNotEmpty &&
        _prefs.isCategoryEnabled(NotificationCategory.inventoryTodos)) {
      for (final sid in runningSchoolIds) {
        try {
          final summary =
              await InventoryTodoService().fetchOpenTodosForSchool(sid);
          if (summary.isEmpty) continue;
          final fs = fsById[sid];
          final schoolLabel = (fs?.displayShortName.trim().isNotEmpty == true)
              ? fs!.displayShortName.trim()
              : (fs?.displayName ?? 'Flugschule');

          if (summary.troubleTickets.isNotEmpty) {
            final n = summary.troubleTickets.length;
            candidates.add(
              AppNotificationEntry(
                key: 'u_inv_tickets:$sid:$n',
                category: NotificationCategory.inventoryTodos,
                title: 'Inventar ($schoolLabel): Troubletickets offen',
                body:
                    '$n offene${n == 1 ? "s Troubleticket" : " Troubletickets"} während deines laufenden Events.',
                createdAt: now,
              ),
            );
          }
          if (summary.repacksDue.isNotEmpty || summary.checksDue.isNotEmpty) {
            final totalDue =
                summary.repacksDue.length + summary.checksDue.length;
            candidates.add(
              AppNotificationEntry(
                key: 'u_inv_due:$sid:$totalDue',
                category: NotificationCategory.inventoryTodos,
                title: 'Inventar ($schoolLabel): Checks / Neupacken fällig',
                body:
                    '$totalDue fällige Wartungsaufgabe${totalDue == 1 ? "" : "n"} im Inventarmanager.',
                createdAt: now,
              ),
            );
          }
        } catch (_) {}
      }
    }

    final isFirstPrime = !_primedUser && _seenKeys.isEmpty;
    _primedUser = true;

    await _dispatchNewCandidates(
      candidates: candidates,
      silentPrime: isFirstPrime,
      context: context,
    );
  }

  // ==================== ADMIN SNAPSHOT DIFFING ====================

  Future<void> evaluateAdminSnapshot({
    required FlightSchoolModelFlightSchoolView fs,
    int? pendingDocsCount,
    BuildContext? context,
  }) async {
    if (!_initialized) await init();

    final now = DateTime.now();
    final soonHorizon = now.add(const Duration(days: 14));
    final schoolLabel = fs.displayShortName.trim().isNotEmpty
        ? fs.displayShortName.trim()
        : fs.displayName;
    final candidates = <AppNotificationEntry>[];

    // 1) Team-Beitrittsanfragen
    for (final req in fs.pendingRequests) {
      candidates.add(
        AppNotificationEntry(
          key: 'a_join:${fs.id}:${req.membershipId}',
          category: NotificationCategory.adminJoinRequests,
          title: 'Neue Beitrittsanfrage ($schoolLabel)',
          body: '${req.displayName} möchte dem Team beitreten.',
          createdAt: now,
        ),
      );
    }

    // 2) Qualifikations-Anfragen
    for (final m in fs.members) {
      for (final qId in m.requestedQualificationIds) {
        candidates.add(
          AppNotificationEntry(
            key: 'a_qual:${fs.id}:${m.membershipId}:$qId',
            category: NotificationCategory.adminDocumentsAndQuals,
            title: 'Qualifikations-Anfrage ($schoolLabel)',
            body:
                '${m.displayName} fragt „${fs.qualificationName(qId)}“ an.',
            createdAt: now,
          ),
        );
      }
    }

    // 3) Freizugebende Dokumente (falls bekannt)
    if (pendingDocsCount != null && pendingDocsCount > 0) {
      candidates.add(
        AppNotificationEntry(
          key: 'a_docs:${fs.id}:$pendingDocsCount',
          category: NotificationCategory.adminDocumentsAndQuals,
          title: 'Dokumente zur Prüfung ($schoolLabel)',
          body:
              '$pendingDocsCount eingereichte${pendingDocsCount == 1 ? "s Dokument wartet" : " Dokumente warten"} auf Freigabe.',
          createdAt: now,
        ),
      );
    }

    // 4) Event-bezogene Admin-Aufgaben
    for (final ev in fs.events) {
      if (ev.status == EventStatusEnum.canceled || ev.endTime.isBefore(now)) {
        continue;
      }

      int openSlots = 0;
      for (final tm in ev.team) {
        final assignKey = tm.assignmentId ?? '${ev.id}:${tm.userId}:${tm.role}';
        final memberName =
            tm.name.isNotEmpty ? tm.name : fs.resolveMemberName(tm.userId);

        if (tm.isSlot || tm.statusEnum == EventUserStatusEnum.open) {
          openSlots++;
          continue;
        }

        if (tm.statusEnum == EventUserStatusEnum.pending_flight_school) {
          candidates.add(
            AppNotificationEntry(
              key: 'a_app:${fs.id}:$assignKey',
              category: NotificationCategory.adminApplicationsAndSwaps,
              title: 'Neue Bewerbung ($schoolLabel)',
              body:
                  '$memberName bewirbt sich für „${ev.displayName}“ (${tm.roleLabel}).',
              createdAt: now,
            ),
          );
        } else if (tm.statusEnum == EventUserStatusEnum.user_requests_change) {
          candidates.add(
            AppNotificationEntry(
              key: 'a_change:${fs.id}:$assignKey',
              category: NotificationCategory.adminApplicationsAndSwaps,
              title: 'Änderungsanfrage ($schoolLabel)',
              body:
                  '$memberName bittet um Ersatz bei „${ev.displayName}“ (${tm.roleLabel}).',
              createdAt: now,
            ),
          );
        } else if (tm.statusEnum == EventUserStatusEnum.denied_user) {
          candidates.add(
            AppNotificationEntry(
              key: 'a_denied:${fs.id}:$assignKey',
              category: NotificationCategory.adminApplicationsAndSwaps,
              title: 'Einteilung abgelehnt ($schoolLabel)',
              body:
                  '$memberName hat „${ev.displayName}“ (${tm.roleLabel}) abgelehnt.',
              createdAt: now,
            ),
          );
        }

        if (tm.hasOpenSwapRequest) {
          final swapBy = (tm.swapRequestedByName ?? '').trim().isNotEmpty
              ? tm.swapRequestedByName!
              : fs.resolveMemberName(tm.swapRequestedBy ?? '');
          candidates.add(
            AppNotificationEntry(
              key: 'a_swap:${fs.id}:$assignKey:${tm.swapRequestedBy ?? ""}',
              category: NotificationCategory.adminApplicationsAndSwaps,
              title: 'Neue Tauschanfrage ($schoolLabel)',
              body:
                  '$memberName → $swapBy bei „${ev.displayName}“ (${tm.roleLabel}).',
              createdAt: now,
            ),
          );
        }
      }

      if (openSlots > 0 && !ev.startTime.isAfter(soonHorizon)) {
        candidates.add(
          AppNotificationEntry(
            key: 'a_unfilled:${fs.id}:${ev.id}:$openSlots',
            category: NotificationCategory.adminUnfilledAndChecklists,
            title: 'Unbesetzte Stelle in Kürze ($schoolLabel)',
            body:
                'Bei „${ev.displayName}“ ${openSlots == 1 ? "ist noch 1 Position" : "sind noch $openSlots Positionen"} offen.',
            createdAt: now,
          ),
        );
      }
    }

    // 5) Tandem-Anfragen von Piloten (sofern Tandemplanung aktiv)
    if (fs.tandemEnabled) {
      final today = DateTime(now.year, now.month, now.day);
      for (final duty in fs.tandemDuties) {
        if (duty.status != TandemDutyStatus.requestedByPilot &&
            duty.status != TandemDutyStatus.cancellationRequested) {
          continue;
        }
        if (duty.endDay.isBefore(today)) continue;
        final pilotName = fs.resolveMemberName(duty.userId);
        final isCancelReq =
            duty.status == TandemDutyStatus.cancellationRequested;
        candidates.add(
          AppNotificationEntry(
            key: isCancelReq
                ? 'a_tandem_cancel:${fs.id}:${duty.id}'
                : 'a_tandem_req:${fs.id}:${duty.id}',
            category: NotificationCategory.adminApplicationsAndSwaps,
            title: isCancelReq
                ? 'Tandem-Absage angefragt ($schoolLabel)'
                : 'Neue Tandem-Anfrage ($schoolLabel)',
            body: isCancelReq
                ? '$pilotName möchte Tandem am ${duty.dateRangeLabel} (${duty.timeWindowLabel}) absagen.'
                : '$pilotName fragt Tandem am ${duty.dateRangeLabel} (${duty.timeWindowLabel}) an.',
            createdAt: now,
          ),
        );
      }
    }

    final isFirstPrime = !_primedAdmin;
    _primedAdmin = true;

    await _dispatchNewCandidates(
      candidates: candidates,
      silentPrime: isFirstPrime,
      context: context,
    );
  }

  // ==================== DISPATCH & IN-APP BANNER ====================

  Future<void> _dispatchNewCandidates({
    required List<AppNotificationEntry> candidates,
    required bool silentPrime,
    BuildContext? context,
  }) async {
    final fresh = <AppNotificationEntry>[];
    bool keysChanged = false;

    for (final c in candidates) {
      if (_seenKeys.contains(c.key)) continue;
      _seenKeys.add(c.key);
      keysChanged = true;
      if (!silentPrime && _prefs.isCategoryEnabled(c.category)) {
        fresh.add(c);
      }
    }

    if (keysChanged) {
      await _persistSeenKeys();
    }
    if (fresh.isEmpty) return;

    for (final entry in fresh) {
      _recordHistory(entry);
    }

    // Bei mehreren gleichzeitigen neuen Einträgen sauber bündeln (kein Spam)
    final toShow = fresh.length == 1
        ? fresh.first
        : AppNotificationEntry(
            key: 'bundle_${DateTime.now().millisecondsSinceEpoch}',
            category: fresh.first.category,
            title: '${fresh.length} neue Benachrichtigungen',
            body: '${fresh.first.title}: ${fresh.first.body}',
            createdAt: DateTime.now(),
          );

    if (kIsWeb) {
      showWebNotification(
        title: toShow.title,
        body: toShow.body,
        tag: toShow.key,
      );
    } else {
      unawaited(
        showNativeNotification(
          title: toShow.title,
          body: toShow.body,
          tag: toShow.key,
        ),
      );
    }

    if (_prefs.inAppBanners && context != null && context.mounted) {
      showInAppBanner(context, toShow);
    }
  }

  void _recordHistory(AppNotificationEntry entry) {
    _history.insert(0, entry);
    if (_history.length > _kMaxHistory) {
      _history.removeRange(_kMaxHistory, _history.length);
    }
    notifyListeners();
  }

  void _dismissOverlay() {
    _overlayTimer?.cancel();
    _overlayTimer = null;
    _activeOverlay?.remove();
    _activeOverlay = null;
  }

  void showInAppBanner(BuildContext context, AppNotificationEntry entry) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    _dismissOverlay();

    final overlayEntry = OverlayEntry(
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final topPad = MediaQuery.of(ctx).padding.top;
        return Positioned(
          top: topPad + 10,
          left: 14,
          right: 14,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Material(
                color: cs.surface,
                elevation: 8,
                shadowColor: const Color(0x28101828),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(
                    color: AppTheme.primaryColor.withValues(alpha: 0.25),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _dismissOverlay,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryTint,
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: const Icon(
                            Icons.notifications_active_rounded,
                            color: AppTheme.primaryColor,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                entry.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13.5,
                                  color: cs.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                entry.body,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: cs.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    _activeOverlay = overlayEntry;
    overlay.insert(overlayEntry);
    _overlayTimer = Timer(const Duration(seconds: 5), _dismissOverlay);
  }
}
