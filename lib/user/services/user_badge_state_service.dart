import 'package:flutter/foundation.dart';
import 'package:season_planner/core/data/enums/event_status_enum.dart';
import 'package:season_planner/core/data/enums/event_user_status_enum.dart';
import 'package:season_planner/core/data/enums/membership_status_enum.dart';
import 'package:season_planner/core/data/models/event_model.dart';
import 'package:season_planner/core/data/models/planning_period_model.dart';
import 'package:season_planner/core/data/models/qualification_model.dart';
import 'package:season_planner/core/data/models/role_document_model.dart';
import 'package:season_planner/core/data/models/tandem_model.dart';
import 'package:season_planner/core/data/models/timesheet_model.dart';
import 'package:season_planner/core/services/inventory_todo_service.dart';
import 'package:season_planner/core/services/qualification_service.dart';
import 'package:season_planner/core/services/role_document_service.dart';
import 'package:season_planner/core/services/tandem_service.dart';
import 'package:season_planner/core/services/timesheet_service.dart';
import 'package:season_planner/user/data/models/user_model_userView.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Zentraler Zustand für alle Nutzer-Badges & Status-Punkte:
/// - Start-Tab: roter Counter für neue Direktanfragen, dezenter blauer Punkt für neue offene Stellen
/// - Wichtiges-Tab (Glocke): roter Counter für neue/ungesehene Meldungen & To-Dos
///   (verschwindet nach dem Öffnen des Tabs, erscheint wieder bei neuen Einträgen)
/// - Konto → Mein Profil: dauerhafter roter Punkt bei „Qualifikationen & Nachweise“
///   und „Stundenzettel & Lehrtätigkeit“, solange dort noch etwas offen ist.
class UserBadgeStateService extends ChangeNotifier {
  static final UserBadgeStateService _instance =
      UserBadgeStateService._internal();
  factory UserBadgeStateService() => _instance;
  UserBadgeStateService._internal();

  String _loadedUserId = '';
  bool _isViewingImportantTab = false;

  Set<String> _activeImportantIds = {};
  Set<String> _seenImportantIds = {};
  Set<String> _dismissedImportantIds = {};

  Set<String> _activeDirectRequestIds = {};
  Set<String> _seenDirectRequestIds = {};

  Set<String> _activeOpenOpportunityIds = {};
  Set<String> _seenOpenOpportunityIds = {};

  bool _hasOpenQualifications = false;
  bool _hasOpenTimesheets = false;

  int get unseenImportantCount =>
      _activeImportantIds.difference(_seenImportantIds).length;

  int get unseenDirectRequestCount =>
      _activeDirectRequestIds.difference(_seenDirectRequestIds).length;

  bool get hasUnseenOpenOpportunities =>
      _activeOpenOpportunityIds.difference(_seenOpenOpportunityIds).isNotEmpty;

  bool get hasOpenQualifications => _hasOpenQualifications;
  bool get hasOpenTimesheets => _hasOpenTimesheets;

  String _keyImportant(String uid) => 'sp_seen_important_ids_$uid';
  String _keyDismissedImportant(String uid) => 'sp_dismissed_important_ids_$uid';
  String _keyDirectReq(String uid) => 'sp_seen_direct_req_ids_$uid';
  String _keyOpenOpp(String uid) => 'sp_seen_open_opp_ids_$uid';

  /// Stabile Benachrichtigungs-ID für Event-Statusänderungen (Zugesagt / Abgesagt).
  /// Wechselt ein Event später z. B. von `provisional` auf `canceled`, entsteht eine
  /// neue ID, sodass die neue Meldung automatisch wieder erscheint.
  static String eventStatusNoticeId(Event e) {
    final key =
        (e.eventDocId != null && e.eventDocId!.isNotEmpty) ? e.eventDocId! : e.id;
    return 'ev_status:$key:${e.status.name}';
  }

  /// Stabile Benachrichtigungs-ID für Event-Terminverschiebungen.
  /// Bei jeder weiteren Verschiebung entsteht eine neue ID.
  static String eventRescheduleNoticeId(Event e) {
    final key =
        (e.eventDocId != null && e.eventDocId!.isNotEmpty) ? e.eventDocId! : e.id;
    return 'ev_rescheduled:$key:${e.startTime.toUtc().toIso8601String()}_${e.endTime.toUtc().toIso8601String()}';
  }

  bool isImportantDismissed(String id) => _dismissedImportantIds.contains(id);

  Future<void> dismissImportantId(String id) async {
    if (id.isEmpty) return;
    _dismissedImportantIds = {..._dismissedImportantIds, id};
    _activeImportantIds.remove(id);
    _seenImportantIds.remove(id);
    await _persistSeen();
    notifyListeners();
  }

  Future<void> _ensureSeenLoaded(String uid) async {
    if (uid.isEmpty || _loadedUserId == uid) return;
    _loadedUserId = uid;
    try {
      final prefs = await SharedPreferences.getInstance();
      _seenImportantIds =
          (prefs.getStringList(_keyImportant(uid)) ?? const []).toSet();
      _dismissedImportantIds =
          (prefs.getStringList(_keyDismissedImportant(uid)) ?? const []).toSet();
      _seenDirectRequestIds =
          (prefs.getStringList(_keyDirectReq(uid)) ?? const []).toSet();
      _seenOpenOpportunityIds =
          (prefs.getStringList(_keyOpenOpp(uid)) ?? const []).toSet();
    } catch (_) {}
  }

  Future<void> _persistSeen() async {
    if (_loadedUserId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _keyImportant(_loadedUserId),
        _seenImportantIds.toList(),
      );
      await prefs.setStringList(
        _keyDismissedImportant(_loadedUserId),
        _dismissedImportantIds.toList(),
      );
      await prefs.setStringList(
        _keyDirectReq(_loadedUserId),
        _seenDirectRequestIds.toList(),
      );
      await prefs.setStringList(
        _keyOpenOpp(_loadedUserId),
        _seenOpenOpportunityIds.toList(),
      );
    } catch (_) {}
  }

  void setViewingImportantTab(bool viewing) {
    _isViewingImportantTab = viewing;
    if (viewing) {
      markImportantSeen();
    }
  }

  Future<void> markImportantSeen() async {
    if (_activeImportantIds.isEmpty) return;
    final before = unseenImportantCount;
    _seenImportantIds = {..._seenImportantIds, ..._activeImportantIds};
    await _persistSeen();
    if (before != unseenImportantCount) {
      notifyListeners();
    }
  }

  Future<void> markStartOpportunitiesSeen() async {
    final beforeReq = unseenDirectRequestCount;
    final beforeOpp = hasUnseenOpenOpportunities;
    _seenDirectRequestIds = {
      ..._seenDirectRequestIds,
      ..._activeDirectRequestIds,
    };
    _seenOpenOpportunityIds = {
      ..._seenOpenOpportunityIds,
      ..._activeOpenOpportunityIds,
    };
    await _persistSeen();
    if (beforeReq != unseenDirectRequestCount ||
        beforeOpp != hasUnseenOpenOpportunities) {
      notifyListeners();
    }
  }

  void clearOnLogout() {
    _loadedUserId = '';
    _isViewingImportantTab = false;
    _activeImportantIds = {};
    _seenImportantIds = {};
    _dismissedImportantIds = {};
    _activeDirectRequestIds = {};
    _seenDirectRequestIds = {};
    _activeOpenOpportunityIds = {};
    _seenOpenOpportunityIds = {};
    _hasOpenQualifications = false;
    _hasOpenTimesheets = false;
    notifyListeners();
  }

  String _eventKey(Event e) =>
      (e.eventDocId != null && e.eventDocId!.isNotEmpty) ? e.eventDocId! : e.id;

  /// Aktualisiert alle Badge-Zustände anhand des aktuellen User-Snapshots.
  Future<void> refreshFromUser(UserModelUserView user) async {
    if (user.id.isEmpty) return;
    await _ensureSeenLoaded(user.id);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final fsById = {for (final fs in user.flightSchools) fs.id: fs};

    // ==================== 1) START-TAB: Direktanfragen & Offene Stellen ====================
    final scheduledEvents = user.events
        .where(
          (e) =>
              e.isOwnBindingAssignment && e.status != EventStatusEnum.canceled,
        )
        .toList();
    final scheduledKeys = scheduledEvents.map(_eventKey).toSet();

    bool isBlockedBySchedule(Event candidate) {
      if (scheduledKeys.contains(_eventKey(candidate))) return true;
      final conflict = TandemService.findUserEventBookingConflict(
        userId: user.id,
        startTime: candidate.startTime,
        endTime: candidate.endTime,
        userEvents: user.events,
        userTandemDuties: user.tandemDuties,
        ignoreEventKey: _eventKey(candidate),
      );
      return conflict != null;
    }

    final directReqIds = <String>{};
    final openOppIds = <String>{};

    // Tandem-Anfragen durch Admin
    for (final d in user.tandemDuties) {
      final fs = fsById[d.flightSchoolId];
      if (fs == null ||
          !fs.tandemEnabled ||
          !fs.isTandemPilot ||
          fs.membershipStatus != MembershipStatusEnum.active) {
        continue;
      }
      if (d.userId == user.id &&
          !d.endDay.isBefore(today) &&
          d.status == TandemDutyStatus.requestedByAdmin) {
        final tandemConflict = TandemService.findScheduleConflict(
          userId: user.id,
          startDate: d.startDate,
          endDate: d.endDate,
          isFullDay: d.isFullDay,
          events: user.events,
          tandemDuties: user.tandemDuties,
          ignoreDutyId: d.id,
          isUserOwnEventsView: true,
        );
        if (tandemConflict == null) {
          directReqIds.add('tandem_req:${d.id}');
        }
      }
    }

    // Event-Direktanfragen & Offene Stellen
    for (final ev in user.events) {
      if (ev.endTime.isBefore(now)) continue;
      final fs = fsById[ev.flightSchoolId];
      if (fs == null || fs.membershipStatus != MembershipStatusEnum.active) {
        continue;
      }
      if (ev.isOwnBindingAssignment) continue;
      if (isBlockedBySchedule(ev)) continue;

      final stage = fs.effectiveStageFor(ev);
      if (!ev.isSwapOfferFromOther &&
          ev.assignmentStatus == EventUserStatusEnum.pending_user) {
        directReqIds.add('event_req:${ev.id}');
      } else if (fs.isTandemOnly || fs.isExtendedTeam) {
        // Keine offenen Stellen / Stufe-1-Badges für reine Tandempiloten oder erweitertes Team
        continue;
      } else if (stage == 1) {
        openOppIds.add('stage1_ev:${_eventKey(ev)}');
      } else if ((ev.isSwapOfferFromOther ||
              ev.assignmentStatus == EventUserStatusEnum.open) &&
          fs.hasRole(ev.role)) {
        openOppIds.add('open_ev:${ev.id}');
      }
    }

    _activeDirectRequestIds = directReqIds;
    _activeOpenOpportunityIds = openOppIds;
    // Bereinige nicht mehr aktive gesehen-IDs, damit spätere neue Anfragen sauber zählen
    _seenDirectRequestIds =
        _seenDirectRequestIds.intersection(_activeDirectRequestIds);
    _seenOpenOpportunityIds =
        _seenOpenOpportunityIds.intersection(_activeOpenOpportunityIds);

    // ==================== 2) WICHTIGES-TAB & KONTO-PUNKTE ====================
    final importantIds = <String>{};

    // Event-Statusänderungen (Zugesagt / Abgesagt) & Terminverschiebungen
    // für eigene verbindlich eingeteilte Events
    final statusNoticeCutoff = now.subtract(const Duration(days: 14));
    for (final ev in user.events) {
      if (!ev.isOwnBindingAssignment) continue;
      if (ev.endTime.isBefore(statusNoticeCutoff)) continue;
      final fs = fsById[ev.flightSchoolId];
      if (fs == null || fs.membershipStatus != MembershipStatusEnum.active) {
        continue;
      }
      if (ev.status == EventStatusEnum.provisional ||
          ev.status == EventStatusEnum.canceled) {
        final noticeId = eventStatusNoticeId(ev);
        if (!_dismissedImportantIds.contains(noticeId)) {
          importantIds.add(noticeId);
        }
      }
      if (ev.status != EventStatusEnum.canceled && ev.wasRescheduled) {
        final rescheduleId = eventRescheduleNoticeId(ev);
        if (!_dismissedImportantIds.contains(rescheduleId)) {
          importantIds.add(rescheduleId);
        }
      }
    }

    // Saisonplanung Stufe 1
    for (final fs in user.flightSchools) {
      if (fs.membershipStatus != MembershipStatusEnum.active) continue;
      if (fs.isTandemOnly) continue;
      final stage1Periods = fs.planningPeriods
          .where((p) => p.stage == PlanningStage.availability)
          .toList();
      if (stage1Periods.isNotEmpty) {
        final periodKey = stage1Periods.map((p) => p.id).join('_');
        importantIds.add('stage1:${fs.id}:$periodKey');
      }
    }

    // Offene Einladungen
    for (final fs in user.flightSchools) {
      if (fs.membershipStatus == MembershipStatusEnum.invited) {
        importantIds.add('invite:${fs.id}');
      }
    }

    // Profil-Hinweise
    if (!user.hasEmergencyContact) importantIds.add('profile:emergency');
    if (user.phone.trim().isEmpty) importantIds.add('profile:phone');
    if (user.avatarUrl.trim().isEmpty) importantIds.add('profile:avatar');

    // Asynchrone Prüfungen (Dokumente, Checklisten, Stundenzettel, Inventar)
    final runningSchoolIds = user.events
        .where(
          (e) =>
              e.isOwnBindingAssignment &&
              e.status != EventStatusEnum.canceled &&
              !e.startTime.isAfter(now) &&
              e.endTime.isAfter(now),
        )
        .map((e) => e.flightSchoolId)
        .toSet();

    bool asyncSuccess = false;
    bool openQuals = false;
    bool openTimesheets = false;

    try {
      final results = await Future.wait([
        QualificationService().listUserDocuments(user.id),
        QualificationService().listUserApprovals(user.id),
        RoleDocumentService().listCompletionsForUser(user.id),
        TimesheetService().listTimesheetsForUser(user.id),
        Future.wait(
          runningSchoolIds.map(
            (sid) => InventoryTodoService().fetchOpenTodosForSchool(sid),
          ),
        ),
      ]);

      final docs = results[0] as List<QualificationDocument>;
      final approvals = results[1] as List<QualificationApproval>;
      final completions = results[2] as List<ChecklistCompletion>;
      final timesheets = results[3] as List<EventTimesheet>;
      final invSummaries = results[4] as List<SchoolInventoryTodoSummary>;

      final completionsByAssignment = {
        for (final c in completions) c.assignmentId: c,
      };
      final timesheetsByAssignment = {
        for (final t in timesheets) t.assignmentId: t,
      };

      // Inventarmanager bei laufendem Event
      for (final s in invSummaries) {
        if (s.troubleTickets.isNotEmpty) {
          importantIds.add('inv_tickets:${s.flightSchoolId}:${s.troubleTickets.length}');
        }
        if (s.repacksDue.isNotEmpty) {
          importantIds.add('inv_repacks:${s.flightSchoolId}:${s.repacksDue.length}');
        }
        if (s.checksDue.isNotEmpty) {
          importantIds.add('inv_checks:${s.flightSchoolId}:${s.checksDue.length}');
        }
        if (s.lockedItems.isNotEmpty) {
          importantIds.add('inv_locked:${s.flightSchoolId}:${s.lockedItems.length}');
        }
      }

      // Vergangene Events: Checklisten & Stundenzettel
      final pastBindingEvents = user.events.where(
        (e) =>
            e.isOwnBindingAssignment &&
            e.status != EventStatusEnum.canceled &&
            e.endTime.isBefore(now),
      );
      for (final ev in pastBindingEvents) {
        final fs = fsById[ev.flightSchoolId];
        if (fs == null || fs.membershipStatus != MembershipStatusEnum.active) {
          continue;
        }
        final checklistId = fs.findTeamRole(ev.role)?.checklistId?.trim() ?? '';
        if (checklistId.isNotEmpty) {
          final c = completionsByAssignment[ev.id];
          if (c == null || !c.isSigned) {
            importantIds.add('checklist:${ev.id}');
          }
        }
        if (fs.userRequiresTimesheet) {
          final ts = timesheetsByAssignment[ev.id];
          if (ts == null || !ts.isSubmitted) {
            importantIds.add('timesheet:${ev.id}');
            openTimesheets = true;
          }
        }
      }

      // Pflichtdokumente für zugeteilte Qualifikationen
      final docsById = {for (final d in docs) d.id: d};
      final missingDocs = <String>{};
      final expiredDocs = <String>{};

      for (final fs in user.flightSchools) {
        if (fs.membershipStatus != MembershipStatusEnum.active) continue;
        final requiredTypes = <String>{};
        for (final qId in fs.assignedQualificationIds) {
          final q = fs.findQualificationById(qId);
          if (q != null) requiredTypes.addAll(q.requiredDocuments);
        }
        if (requiredTypes.isEmpty) continue;

        final schoolApprovals =
            approvals.where((a) => a.flightSchoolId == fs.id).toList();
        for (final reqType in requiredTypes) {
          final matching = schoolApprovals
              .where(
                (a) => a.documentType.toLowerCase() == reqType.toLowerCase(),
              )
              .toList();
          if (matching.isEmpty) {
            missingDocs.add(reqType);
            continue;
          }
          final hasValidSubmitted = matching.any((a) {
            if (a.status != ApprovalStatusEnum.submitted) return false;
            final doc = docsById[a.documentId];
            return doc != null && !doc.isExpired;
          });
          final approvedOnes = matching
              .where((a) => a.status == ApprovalStatusEnum.approved)
              .toList();
          if (approvedOnes.isEmpty) {
            if (!hasValidSubmitted) {
              final hasAnyExpired = matching.any((a) {
                final doc = docsById[a.documentId];
                return doc != null && doc.isExpired;
              });
              if (hasAnyExpired) {
                expiredDocs.add(reqType);
              } else {
                missingDocs.add(reqType);
              }
            }
            continue;
          }
          final hasValid = approvedOnes.any((a) {
            final doc = docsById[a.documentId];
            return doc != null && !doc.isExpired;
          });
          if (!hasValid && !hasValidSubmitted) {
            expiredDocs.add(reqType);
          }
        }
      }

      for (final d in expiredDocs) {
        importantIds.add('doc_expired:${d.toLowerCase()}');
      }
      for (final d in missingDocs) {
        importantIds.add('doc_missing:${d.toLowerCase()}');
      }
      openQuals = expiredDocs.isNotEmpty || missingDocs.isNotEmpty;
      asyncSuccess = true;
    } catch (_) {}

    _activeImportantIds = importantIds;
    if (asyncSuccess) {
      _hasOpenQualifications = openQuals;
      _hasOpenTimesheets = openTimesheets;
      // Veraltete seen-IDs bereinigen, sobald der vollständige Stand geladen ist
      _seenImportantIds = _seenImportantIds.intersection(_activeImportantIds);
    }

    if (_isViewingImportantTab) {
      _seenImportantIds = {..._seenImportantIds, ..._activeImportantIds};
    }

    await _persistSeen();
    notifyListeners();
  }
}
