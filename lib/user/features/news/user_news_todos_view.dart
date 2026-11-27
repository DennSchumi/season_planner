import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/core/appwrite_config.dart';
import 'package:season_planner/core/data/enums/event_status_enum.dart';
import 'package:season_planner/core/data/enums/membership_status_enum.dart';
import 'package:season_planner/core/data/models/event_model.dart';
import 'package:season_planner/core/data/models/planning_period_model.dart';
import 'package:season_planner/core/data/models/qualification_model.dart';
import 'package:season_planner/core/data/models/role_document_model.dart';
import 'package:season_planner/core/data/models/timesheet_model.dart';
import 'package:season_planner/core/services/inventory_todo_service.dart';
import 'package:season_planner/core/services/qualification_service.dart';
import 'package:season_planner/core/services/role_document_service.dart';
import 'package:season_planner/core/services/timesheet_service.dart';
import 'package:season_planner/core/theme.dart';
import 'package:season_planner/core/widgets/checklist_runner_view.dart';
import 'package:season_planner/core/widgets/timesheet_runner_view.dart';
import 'package:season_planner/core/widgets/ux_components.dart';
import 'package:season_planner/user/data/models/flight_school_model_user_view.dart';
import 'package:season_planner/user/data/models/user_model_userView.dart';
import 'package:season_planner/user/features/account/widgets/manage_account.dart';
import 'package:season_planner/user/features/account/widgets/manage_flight_school_memberships.dart';
import 'package:season_planner/user/features/availability/my_availability_view.dart';
import 'package:season_planner/user/features/home/widgets/event_detail_view.dart';
import 'package:season_planner/user/features/home/widgets/event_preview_sheet.dart';
import 'package:season_planner/user/features/home/widgets/flight_school_selector_widget.dart';
import 'package:season_planner/user/features/qualifications/my_qualifications_view.dart';
import 'package:season_planner/user/services/user_badge_state_service.dart';
import 'package:season_planner/user/user_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class _UserTodoEntry {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final int priority;
  final Future<void> Function(BuildContext context) onTap;

  const _UserTodoEntry({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.priority,
    required this.onTap,
  });
}

/// Eigener Reiter „Wichtiges“ in der Nutzer-Navigation:
/// Bündelt alle wichtigen Meldungen (z. B. Saisonplanung Stufe 1) sowie alle
/// offenen To-Dos des Mitarbeiters (inkl. vergessener Checklisten & Stundenzettel).
class UserNewsTodosView extends StatefulWidget {
  final bool isLoading;
  final bool hasConnection;
  final DateTime? lastUpdated;

  const UserNewsTodosView({
    super.key,
    required this.isLoading,
    required this.hasConnection,
    required this.lastUpdated,
  });

  @override
  State<UserNewsTodosView> createState() => _UserNewsTodosViewState();
}

class _UserNewsTodosViewState extends State<UserNewsTodosView> {
  final _qualService = QualificationService();
  final _docService = RoleDocumentService();
  final _timesheetService = TimesheetService();
  final _inventoryService = InventoryTodoService();

  bool _loading = true;
  List<QualificationDocument> _userDocs = [];
  List<QualificationApproval> _userApprovals = [];
  Map<String, ChecklistCompletion> _completionsByAssignmentId = {};
  Map<String, EventTimesheet> _timesheetsByAssignmentId = {};
  Map<String, SchoolInventoryTodoSummary> _inventoryBySchoolId = {};
  String _loadedKey = '';

  void _onBadgeStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    UserBadgeStateService().addListener(_onBadgeStateChanged);
  }

  @override
  void dispose() {
    UserBadgeStateService().removeListener(_onBadgeStateChanged);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final user = context.read<UserProvider>().user;
    if (user == null) return;
    final key = '${user.id}_${user.events.length}_${user.flightSchools.length}';
    if (key != _loadedKey) {
      _loadedKey = key;
      _loadAsyncStatus(user);
    }
  }

  Set<String> _runningEventSchoolIds(UserModelUserView user) {
    final now = DateTime.now();
    return user.events
        .where(
          (e) =>
              e.isOwnBindingAssignment &&
              e.status != EventStatusEnum.canceled &&
              !e.startTime.isAfter(now) &&
              e.endTime.isAfter(now),
        )
        .map((e) => e.flightSchoolId)
        .toSet();
  }

  Future<void> _loadAsyncStatus(UserModelUserView user) async {
    final uid = user.id;
    if (uid.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final runningSchoolIds = _runningEventSchoolIds(user);

    try {
      final results = await Future.wait([
        _qualService.listUserDocuments(uid),
        _qualService.listUserApprovals(uid),
        _docService.listCompletionsForUser(uid),
        _timesheetService.listTimesheetsForUser(uid),
        Future.wait(
          runningSchoolIds.map(
            (sid) => _inventoryService.fetchOpenTodosForSchool(sid),
          ),
        ),
      ]);
      if (!mounted) return;

      final docs = results[0] as List<QualificationDocument>;
      final approvals = results[1] as List<QualificationApproval>;
      final completions = results[2] as List<ChecklistCompletion>;
      final timesheets = results[3] as List<EventTimesheet>;
      final invSummaries = results[4] as List<SchoolInventoryTodoSummary>;

      setState(() {
        _userDocs = docs;
        _userApprovals = approvals;
        _completionsByAssignmentId = {
          for (final c in completions) c.assignmentId: c,
        };
        _timesheetsByAssignmentId = {
          for (final t in timesheets) t.assignmentId: t,
        };
        _inventoryBySchoolId = {
          for (final s in invSummaries) s.flightSchoolId: s,
        };
        _loading = false;
      });
      // Synchronisiere zentrale Badges (Glocke als gesehen markiert + Konto-Punkte aktualisiert)
      UserBadgeStateService().refreshFromUser(user);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Event> _eventStatusNotices(
    UserModelUserView user,
    Set<String> schoolFilter,
  ) {
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(days: 14));
    final badgeService = UserBadgeStateService();
    final fsById = {for (final fs in user.flightSchools) fs.id: fs};
    final seenEventKeys = <String>{};
    final list = <Event>[];

    for (final ev in user.events) {
      if (!ev.isOwnBindingAssignment) continue;
      if (!schoolFilter.contains(ev.flightSchoolId)) continue;
      if (ev.status != EventStatusEnum.provisional &&
          ev.status != EventStatusEnum.canceled) {
        continue;
      }
      if (ev.endTime.isBefore(cutoff)) continue;
      final fs = fsById[ev.flightSchoolId];
      if (fs == null || fs.membershipStatus != MembershipStatusEnum.active) {
        continue;
      }
      final noticeId = UserBadgeStateService.eventStatusNoticeId(ev);
      if (badgeService.isImportantDismissed(noticeId)) continue;
      if (!seenEventKeys.add(noticeId)) continue;
      list.add(ev);
    }

    list.sort((a, b) => a.startTime.compareTo(b.startTime));
    return list;
  }

  List<Event> _eventRescheduleNotices(
    UserModelUserView user,
    Set<String> schoolFilter,
  ) {
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(days: 14));
    final badgeService = UserBadgeStateService();
    final fsById = {for (final fs in user.flightSchools) fs.id: fs};
    final seenKeys = <String>{};
    final list = <Event>[];

    for (final ev in user.events) {
      if (!ev.isOwnBindingAssignment) continue;
      if (!schoolFilter.contains(ev.flightSchoolId)) continue;
      if (ev.status == EventStatusEnum.canceled || !ev.wasRescheduled) continue;
      if (ev.endTime.isBefore(cutoff)) continue;
      final fs = fsById[ev.flightSchoolId];
      if (fs == null || fs.membershipStatus != MembershipStatusEnum.active) {
        continue;
      }
      final noticeId = UserBadgeStateService.eventRescheduleNoticeId(ev);
      if (badgeService.isImportantDismissed(noticeId)) continue;
      if (!seenKeys.add(noticeId)) continue;
      list.add(ev);
    }

    list.sort((a, b) => a.startTime.compareTo(b.startTime));
    return list;
  }

  String _fmtDateRangeCompact(DateTime start, DateTime end) {
    final sameDay =
        start.year == end.year &&
        start.month == end.month &&
        start.day == end.day;
    String hm(DateTime d) =>
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    if (sameDay) {
      return '${_fmtDate(start)} (${hm(start)}–${hm(end)})';
    }
    return '${_fmtDate(start)} – ${_fmtDate(end)}';
  }

  List<FlightSchoolUserView> _stage1Schools(
    UserModelUserView user,
    Set<String> schoolFilter,
  ) {
    return user.flightSchools
        .where(
          (fs) =>
              fs.membershipStatus == MembershipStatusEnum.active &&
              !fs.isTandemOnly &&
              schoolFilter.contains(fs.id) &&
              fs.planningPeriods.any(
                (p) => p.stage == PlanningStage.availability,
              ),
        )
        .toList();
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  Future<void> _openInventoryApp() async {
    final uri = Uri.tryParse(AppwriteConfig().inventoryWebUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _showInventoryTasksSheet({
    required BuildContext context,
    required UserModelUserView user,
    required String schoolName,
    required SchoolInventoryTodoSummary summary,
  }) async {
    await showAdaptiveSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      desktopMaxWidth: 560,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;

        Widget buildGroup({
          required String title,
          required IconData icon,
          required Color color,
          required List<InventoryTaskEntry> entries,
        }) {
          if (entries.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 17, color: color),
                    const SizedBox(width: 6),
                    Text(
                      '$title (${entries.length})',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        color: color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ...entries.map(
                  (e) => Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 15,
                        backgroundColor: color.withValues(alpha: 0.14),
                        child: Icon(icon, size: 16, color: color),
                      ),
                      title: Text(
                        e.displayItem,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                      subtitle: Text(
                        [
                          if (e.categoryName.isNotEmpty) e.categoryName,
                          e.detail,
                        ].join(' · '),
                        style: TextStyle(
                          fontSize: 12,
                          color: e.isOverdue
                              ? AppTheme.dangerColor
                              : cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.72,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.inventory_2_outlined,
                        color: AppTheme.warningColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Inventarmanager · $schoolName',
                              style: const TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              '${summary.totalCount} offene Aufgabe${summary.totalCount == 1 ? "" : "n"} während deines laufenden Events',
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          buildGroup(
                            title: 'Offene Troubletickets',
                            icon: Icons.build_rounded,
                            color: AppTheme.warningColor,
                            entries: summary.troubleTickets,
                          ),
                          buildGroup(
                            title: 'Neupacken fällig',
                            icon: Icons.replay_circle_filled_outlined,
                            color: summary.hasOverdueRepack
                                ? AppTheme.dangerColor
                                : AppTheme.warningColor,
                            entries: summary.repacksDue,
                          ),
                          buildGroup(
                            title: 'Checks / Service fällig',
                            icon: Icons.fact_check_outlined,
                            color: summary.hasOverdueCheck
                                ? AppTheme.dangerColor
                                : AppTheme.warningColor,
                            entries: summary.checksDue,
                          ),
                          buildGroup(
                            title: 'Gesperrtes Material',
                            icon: Icons.lock_outline,
                            color: AppTheme.stage1Color,
                            entries: summary.lockedItems,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _openInventoryApp();
                    },
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Im Inventarmanager öffnen'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (mounted) _loadAsyncStatus(user);
  }

  List<_UserTodoEntry> _buildTodos(
    UserModelUserView user,
    Set<String> schoolFilter,
  ) {
    final now = DateTime.now();
    final fsById = {for (final fs in user.flightSchools) fs.id: fs};
    final items = <_UserTodoEntry>[];

    // 1) Offene Flugschul-Einladungen
    for (final fs in user.flightSchools) {
      if (fs.membershipStatus == MembershipStatusEnum.invited) {
        items.add(
          _UserTodoEntry(
            icon: Icons.group_add_outlined,
            color: AppTheme.successColor,
            title: 'Einladung von ${fs.displayName}',
            subtitle: 'Mitgliedschaft annehmen oder ablehnen',
            priority: 0,
            onTap: (ctx) async {
              await Navigator.push(
                ctx,
                MaterialPageRoute(
                  builder: (_) => const ManageFlightSchoolMemberships(),
                ),
              );
              if (mounted) _loadAsyncStatus(user);
            },
          ),
        );
      }
    }

    if (!_loading) {
      // 1b) Inventarmanager-Aufgaben während laufender Events
      final runningSchoolIds = user.events
          .where(
            (e) =>
                e.isOwnBindingAssignment &&
                e.status != EventStatusEnum.canceled &&
                !e.startTime.isAfter(now) &&
                e.endTime.isAfter(now) &&
                schoolFilter.contains(e.flightSchoolId),
          )
          .map((e) => e.flightSchoolId)
          .toSet();

      for (final schoolId in runningSchoolIds) {
        final summary = _inventoryBySchoolId[schoolId];
        if (summary == null || summary.isEmpty) continue;
        final fs = fsById[schoolId];
        final schoolLabel = (fs?.displayShortName.trim().isNotEmpty == true)
            ? fs!.displayShortName.trim()
            : (fs?.displayName ?? 'Flugschule');
        final fullSchoolName = fs?.displayName ?? schoolLabel;

        String previewItems(List<InventoryTaskEntry> list) {
          final names = list.take(3).map((e) => e.displayItem).join(', ');
          return list.length > 3 ? '$names +${list.length - 3} weitere' : names;
        }

        if (summary.troubleTickets.isNotEmpty) {
          final n = summary.troubleTickets.length;
          items.add(
            _UserTodoEntry(
              icon: Icons.build_rounded,
              color: AppTheme.dangerColor,
              title:
                  'Inventar ($schoolLabel): $n Troubleticket${n == 1 ? "" : "s"} offen',
              subtitle: previewItems(summary.troubleTickets),
              priority: 1,
              onTap: (ctx) => _showInventoryTasksSheet(
                context: ctx,
                user: user,
                schoolName: fullSchoolName,
                summary: summary,
              ),
            ),
          );
        }

        if (summary.repacksDue.isNotEmpty) {
          final n = summary.repacksDue.length;
          items.add(
            _UserTodoEntry(
              icon: Icons.replay_circle_filled_outlined,
              color: summary.hasOverdueRepack
                  ? AppTheme.dangerColor
                  : AppTheme.warningColor,
              title:
                  'Inventar ($schoolLabel): $n× Neupacken ${summary.hasOverdueRepack ? "überfällig" : "fällig"}',
              subtitle: previewItems(summary.repacksDue),
              priority: summary.hasOverdueRepack ? 1 : 2,
              onTap: (ctx) => _showInventoryTasksSheet(
                context: ctx,
                user: user,
                schoolName: fullSchoolName,
                summary: summary,
              ),
            ),
          );
        }

        if (summary.checksDue.isNotEmpty) {
          final n = summary.checksDue.length;
          items.add(
            _UserTodoEntry(
              icon: Icons.fact_check_outlined,
              color: summary.hasOverdueCheck
                  ? AppTheme.dangerColor
                  : AppTheme.warningColor,
              title:
                  'Inventar ($schoolLabel): $n Check${n == 1 ? "" : "s"} ${summary.hasOverdueCheck ? "überfällig" : "fällig"}',
              subtitle: previewItems(summary.checksDue),
              priority: summary.hasOverdueCheck ? 1 : 2,
              onTap: (ctx) => _showInventoryTasksSheet(
                context: ctx,
                user: user,
                schoolName: fullSchoolName,
                summary: summary,
              ),
            ),
          );
        }

        if (summary.lockedItems.isNotEmpty) {
          final n = summary.lockedItems.length;
          items.add(
            _UserTodoEntry(
              icon: Icons.lock_outline,
              color: AppTheme.stage1Color,
              title: 'Inventar ($schoolLabel): $n Artikel gesperrt',
              subtitle: previewItems(summary.lockedItems),
              priority: 2,
              onTap: (ctx) => _showInventoryTasksSheet(
                context: ctx,
                user: user,
                schoolName: fullSchoolName,
                summary: summary,
              ),
            ),
          );
        }
      }

      // 2) Nicht unterschriebene Checklisten vergangener Events
      final pastBindingEvents = user.events
          .where(
            (e) =>
                e.isOwnBindingAssignment &&
                e.status != EventStatusEnum.canceled &&
                e.endTime.isBefore(now) &&
                schoolFilter.contains(e.flightSchoolId),
          )
          .toList()
        ..sort((a, b) => b.endTime.compareTo(a.endTime));

      for (final ev in pastBindingEvents) {
        final fs = fsById[ev.flightSchoolId];
        if (fs == null || fs.membershipStatus != MembershipStatusEnum.active) {
          continue;
        }
        final role = fs.findTeamRole(ev.role);
        final checklistId = role?.checklistId?.trim() ?? '';
        if (checklistId.isEmpty) continue;

        final completion = _completionsByAssignmentId[ev.id];
        if (completion != null && completion.isSigned) continue;

        items.add(
          _UserTodoEntry(
            icon: Icons.draw_outlined,
            color: AppTheme.dangerColor,
            title: 'Checkliste unterschreiben: ${ev.displayName}',
            subtitle: '${ev.roleLabel} · beendet am ${_fmtDate(ev.endTime)}',
            priority: 1,
            onTap: (ctx) async {
              final doc = await _docService.getDocumentById(checklistId);
              if (!ctx.mounted) return;
              if (doc != null) {
                await Navigator.push(
                  ctx,
                  MaterialPageRoute(
                    builder: (_) => ChecklistRunnerView(
                      event: ev,
                      userId: user.id,
                      checklist: doc,
                      initialCompletion: completion,
                    ),
                  ),
                );
              } else {
                await Navigator.push(
                  ctx,
                  MaterialPageRoute(
                    builder: (_) => EventDetailView(event: ev),
                  ),
                );
              }
              if (mounted) _loadAsyncStatus(user);
            },
          ),
        );
      }

      // 2b) Fehlende Stundenzettel vergangener Events (Lehrpersonal)
      for (final ev in pastBindingEvents) {
        final fs = fsById[ev.flightSchoolId];
        if (fs == null ||
            fs.membershipStatus != MembershipStatusEnum.active ||
            !fs.userRequiresTimesheet) {
          continue;
        }
        final sheet = _timesheetsByAssignmentId[ev.id];
        if (sheet != null && sheet.isSubmitted) continue;

        items.add(
          _UserTodoEntry(
            icon: Icons.access_time_filled_rounded,
            color: AppTheme.dangerColor,
            title: 'Stundenzettel ausfüllen: ${ev.displayName}',
            subtitle:
                '${sheet != null ? "Entwurf (${sheet.formattedTotalHours})" : ev.roleLabel} · beendet am ${_fmtDate(ev.endTime)}',
            priority: 1,
            onTap: (ctx) async {
              await Navigator.push(
                ctx,
                MaterialPageRoute(
                  builder: (_) => TimesheetRunnerView(
                    event: ev,
                    userId: user.id,
                    initialTimesheet: sheet,
                  ),
                ),
              );
              if (mounted) _loadAsyncStatus(user);
            },
          ),
        );
      }

      // 3) Fehlende, abgelaufene oder bald ablaufende (≤ 30 Tage) Pflichtdokumente
      final docsById = {for (final d in _userDocs) d.id: d};
      final missingDocs = <String>{};
      final expiredDocs = <String>{};
      final expiringSoonByType = <String, DateTime>{};

      for (final fs in user.flightSchools) {
        if (fs.membershipStatus != MembershipStatusEnum.active) continue;
        if (!schoolFilter.contains(fs.id)) continue;

        final requiredTypes = <String>{};
        for (final qId in fs.assignedQualificationIds) {
          final q = fs.findQualificationById(qId);
          if (q != null) requiredTypes.addAll(q.requiredDocuments);
        }
        if (requiredTypes.isEmpty) continue;

        final schoolApprovals =
            _userApprovals.where((a) => a.flightSchoolId == fs.id).toList();

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
          final hasLongValidSubmitted = matching.any((a) {
            if (a.status != ApprovalStatusEnum.submitted) return false;
            final doc = docsById[a.documentId];
            return doc != null && !doc.isExpired && !doc.expiresSoon;
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

          final validApprovedDocs = approvedOnes
              .map((a) => docsById[a.documentId])
              .whereType<QualificationDocument>()
              .where((doc) => !doc.isExpired)
              .toList();
          if (validApprovedDocs.isEmpty) {
            if (!hasValidSubmitted) {
              expiredDocs.add(reqType);
            }
            continue;
          }

          final hasLongValidApproved =
              validApprovedDocs.any((doc) => !doc.expiresSoon);
          if (!hasLongValidApproved && !hasLongValidSubmitted) {
            DateTime? latestExp;
            for (final doc in validApprovedDocs) {
              final e = doc.expiresAt;
              if (e != null && (latestExp == null || e.isAfter(latestExp))) {
                latestExp = e;
              }
            }
            if (latestExp != null) {
              final existing = expiringSoonByType[reqType];
              if (existing == null || latestExp.isBefore(existing)) {
                expiringSoonByType[reqType] = latestExp;
              }
            }
          }
        }
      }

      if (expiredDocs.isNotEmpty) {
        items.add(
          _UserTodoEntry(
            icon: Icons.event_busy_outlined,
            color: AppTheme.dangerColor,
            title: expiredDocs.length == 1
                ? 'Nachweis abgelaufen: ${expiredDocs.first}'
                : '${expiredDocs.length} Nachweise abgelaufen',
            subtitle: expiredDocs.join(', '),
            priority: 2,
            onTap: (ctx) async {
              await Navigator.push(
                ctx,
                MaterialPageRoute(builder: (_) => const MyQualificationsView()),
              );
              if (mounted) _loadAsyncStatus(user);
            },
          ),
        );
      }

      if (expiringSoonByType.isNotEmpty) {
        final entries = expiringSoonByType.entries.toList()
          ..sort((a, b) => a.value.compareTo(b.value));
        final first = entries.first;
        final daysLeft = first.value.difference(now).inDays.clamp(0, 30);
        items.add(
          _UserTodoEntry(
            icon: Icons.schedule_rounded,
            color: AppTheme.warningColor,
            title: entries.length == 1
                ? 'Nachweis läuft bald ab: ${first.key}'
                : '${entries.length} Nachweise laufen bald ab',
            subtitle: entries.length == 1
                ? 'Gültig bis ${_fmtDate(first.value)} (${daysLeft == 0 ? "heute" : daysLeft == 1 ? "noch 1 Tag" : "noch $daysLeft Tage"}) – neues Dokument hochladen'
                : entries
                    .map((e) => '${e.key} (bis ${_fmtDate(e.value)})')
                    .join(', '),
            priority: 2,
            onTap: (ctx) async {
              await Navigator.push(
                ctx,
                MaterialPageRoute(builder: (_) => const MyQualificationsView()),
              );
              if (mounted) _loadAsyncStatus(user);
            },
          ),
        );
      }

      if (missingDocs.isNotEmpty) {
        items.add(
          _UserTodoEntry(
            icon: Icons.upload_file_outlined,
            color: AppTheme.warningColor,
            title: missingDocs.length == 1
                ? 'Dokument hochladen: ${missingDocs.first}'
                : '${missingDocs.length} Pflichtdokumente fehlen',
            subtitle: missingDocs.join(', '),
            priority: 3,
            onTap: (ctx) async {
              await Navigator.push(
                ctx,
                MaterialPageRoute(builder: (_) => const MyQualificationsView()),
              );
              if (mounted) _loadAsyncStatus(user);
            },
          ),
        );
      }
    }

    // 4) Fehlende Profil-Angaben
    if (!user.hasEmergencyContact) {
      items.add(
        _UserTodoEntry(
          icon: Icons.emergency_outlined,
          color: AppTheme.warningColor,
          title: 'Notfallkontakt hinterlegen',
          subtitle: 'Name, Beziehung & Telefonnummer im Profil ergänzen',
          priority: 4,
          onTap: (ctx) async {
            await Navigator.push(
              ctx,
              MaterialPageRoute(builder: (_) => const ManageAccountView()),
            );
            if (mounted) _loadAsyncStatus(user);
          },
        ),
      );
    }

    if (user.phone.trim().isEmpty) {
      items.add(
        _UserTodoEntry(
          icon: Icons.phone_outlined,
          color: AppTheme.infoColor,
          title: 'Telefonnummer ergänzen',
          subtitle: 'Für kurzfristige Rückfragen deiner Flugschule',
          priority: 5,
          onTap: (ctx) async {
            await Navigator.push(
              ctx,
              MaterialPageRoute(builder: (_) => const ManageAccountView()),
            );
            if (mounted) _loadAsyncStatus(user);
          },
        ),
      );
    }

    if (user.avatarUrl.trim().isEmpty) {
      items.add(
        _UserTodoEntry(
          icon: Icons.account_circle_outlined,
          color: AppTheme.infoColor,
          title: 'Profilbild hochladen',
          subtitle: 'Wird neben deinen Einsatzpositionen angezeigt',
          priority: 6,
          onTap: (ctx) async {
            await Navigator.push(
              ctx,
              MaterialPageRoute(builder: (_) => const ManageAccountView()),
            );
            if (mounted) _loadAsyncStatus(user);
          },
        ),
      );
    }

    items.sort((a, b) => a.priority.compareTo(b.priority));
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final user = userProvider.user;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final selectedFlightSchools = userProvider.selectedFlightSchoolIds;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fsById = {for (final fs in user.flightSchools) fs.id: fs};
    final statusNotices = _eventStatusNotices(user, selectedFlightSchools);
    final rescheduleNotices = _eventRescheduleNotices(
      user,
      selectedFlightSchools,
    );
    final stage1Schools = _stage1Schools(user, selectedFlightSchools);
    final todos = _buildTodos(user, selectedFlightSchools);
    final hasNotices =
        statusNotices.isNotEmpty ||
        rescheduleNotices.isNotEmpty ||
        stage1Schools.isNotEmpty;
    final hasAnything = hasNotices || todos.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Wichtiges'),
        actions: [
          const AppModeSwitchChip(isAdminMode: false),
          const AppBarActionDivider(),
          ConnectionStatusAction(
            isLoading: widget.isLoading || _loading,
            hasConnection: widget.hasConnection,
            lastUpdated: widget.lastUpdated,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadAsyncStatus(user),
        child: Column(
          children: [
            if (user.flightSchools.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 2),
                child: FlightSchoolSelector(
                  flightSchools: user.flightSchools,
                  selectedIds: selectedFlightSchools,
                  onSelectionChanged: (selected) {
                    context
                        .read<UserProvider>()
                        .setSelectedFlightSchoolIds(selected);
                  },
                ),
              ),
            Expanded(
              child: _loading && !hasAnything
                  ? const Center(child: CircularProgressIndicator())
                  : !hasAnything
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 80),
                            EmptyStateView(
                              icon: Icons.check_circle_outline_rounded,
                              title: 'Alles erledigt!',
                              subtitle:
                                  'Aktuell stehen keine offenen Aufgaben oder wichtigen Meldungen an.',
                            ),
                          ],
                        )
                      : ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 108),
                          children: [
                            if (hasNotices) ...[
                              _SectionHeading(
                                label: 'AKTUELLE MELDUNGEN',
                                count:
                                    statusNotices.length +
                                    rescheduleNotices.length +
                                    stage1Schools.length,
                              ),
                              ...rescheduleNotices.map((ev) {
                                final fs = fsById[ev.flightSchoolId];
                                final schoolName = fs == null
                                    ? ''
                                    : (fs.displayShortName.trim().isNotEmpty
                                        ? fs.displayShortName.trim()
                                        : fs.displayName);
                                final oldRange = _fmtDateRangeCompact(
                                  ev.previousStartTime!,
                                  ev.previousEndTime!,
                                );
                                final newRange = _fmtDateRangeCompact(
                                  ev.startTime,
                                  ev.endTime,
                                );
                                final noticeId = UserBadgeStateService
                                    .eventRescheduleNoticeId(ev);
                                final meta = [
                                  if (ev.role.isNotEmpty) ev.roleLabel,
                                  if (schoolName.isNotEmpty) schoolName,
                                ].join(' · ');

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: SoftCard(
                                    padding: const EdgeInsets.fromLTRB(
                                      14,
                                      12,
                                      8,
                                      12,
                                    ),
                                    color: isDark
                                        ? AppTheme.darkCard
                                        : AppTheme.warningBg,
                                    border: Border.all(
                                      color: AppTheme.warningColor
                                          .withValues(alpha: 0.30),
                                    ),
                                    onTap: () => showEventPreviewSheet(
                                      context,
                                      event: ev,
                                    ),
                                    child: Row(
                                      children: [
                                        TintedIconBadge(
                                          icon: Icons.update_rounded,
                                          iconColor: AppTheme.warningColor,
                                          backgroundColor: isDark
                                              ? AppTheme.warningColor
                                                  .withValues(alpha: 0.16)
                                              : Colors.white,
                                          size: 42,
                                          iconSize: 21,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'Termin verschoben',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w800,
                                                  letterSpacing: 0.3,
                                                  color: AppTheme.warningColor,
                                                ),
                                              ),
                                              const SizedBox(height: 1),
                                              Text(
                                                ev.displayName,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 14,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'Neu: $newRange\nAlt: $oldRange${meta.isNotEmpty ? ' · $meta' : ''}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  height: 1.35,
                                                  color: cs.onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Meldung ausblenden',
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () async {
                                            await UserBadgeStateService()
                                                .dismissImportantId(noticeId);
                                            if (mounted) setState(() {});
                                          },
                                          icon: Icon(
                                            Icons.close_rounded,
                                            size: 18,
                                            color: cs.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }),
                              ...statusNotices.map((ev) {
                                final isCanceled =
                                    ev.status == EventStatusEnum.canceled;
                                final accent = isCanceled
                                    ? AppTheme.dangerColor
                                    : AppTheme.successColor;
                                final bg = isDark
                                    ? AppTheme.darkCard
                                    : (isCanceled
                                        ? AppTheme.dangerBg
                                        : AppTheme.successBg);
                                final fs = fsById[ev.flightSchoolId];
                                final schoolName = fs == null
                                    ? ''
                                    : (fs.displayShortName.trim().isNotEmpty
                                        ? fs.displayShortName.trim()
                                        : fs.displayName);
                                final sameDay = ev.startTime.year ==
                                        ev.endTime.year &&
                                    ev.startTime.month == ev.endTime.month &&
                                    ev.startTime.day == ev.endTime.day;
                                final dateLabel = sameDay
                                    ? _fmtDate(ev.startTime)
                                    : '${_fmtDate(ev.startTime)} – ${_fmtDate(ev.endTime)}';
                                final detailParts = <String>[
                                  dateLabel,
                                  if (ev.role.isNotEmpty) ev.roleLabel,
                                  if (schoolName.isNotEmpty) schoolName,
                                ];
                                final noticeId =
                                    UserBadgeStateService.eventStatusNoticeId(
                                  ev,
                                );

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: CanceledEventDecorator(
                                    isCanceled: isCanceled,
                                    borderRadius: BorderRadius.circular(18),
                                    child: SoftCard(
                                      padding: const EdgeInsets.fromLTRB(
                                        14,
                                        12,
                                        8,
                                        12,
                                      ),
                                      color: bg,
                                      border: Border.all(
                                        color: accent.withValues(alpha: 0.28),
                                      ),
                                      onTap: () => showEventPreviewSheet(
                                        context,
                                        event: ev,
                                      ),
                                      child: Row(
                                        children: [
                                          TintedIconBadge(
                                            icon: isCanceled
                                                ? Icons.event_busy_rounded
                                                : Icons.event_available_rounded,
                                            iconColor: accent,
                                            backgroundColor: isDark
                                                ? accent.withValues(alpha: 0.16)
                                                : Colors.white,
                                            size: 42,
                                            iconSize: 21,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  isCanceled
                                                      ? 'Event abgesagt'
                                                      : 'Event zugesagt',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w800,
                                                    letterSpacing: 0.3,
                                                    color: accent,
                                                  ),
                                                ),
                                                const SizedBox(height: 1),
                                                Text(
                                                  ev.displayName,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 14,
                                                    decoration: isCanceled
                                                        ? TextDecoration
                                                            .lineThrough
                                                        : null,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  detailParts.join(' · '),
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: cs.onSurfaceVariant,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'Meldung ausblenden',
                                            visualDensity:
                                                VisualDensity.compact,
                                            onPressed: () async {
                                              await UserBadgeStateService()
                                                  .dismissImportantId(noticeId);
                                              if (mounted) setState(() {});
                                            },
                                            icon: Icon(
                                              Icons.close_rounded,
                                              size: 18,
                                              color: cs.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }),
                              ...stage1Schools.map((school) {
                                final schoolName =
                                    school.displayShortName.trim().isNotEmpty
                                        ? school.displayShortName.trim()
                                        : school.displayName;
                                final stage1Periods = school.planningPeriods
                                    .where(
                                      (p) =>
                                          p.stage == PlanningStage.availability,
                                    )
                                    .toList();
                                final periodInfo = stage1Periods
                                    .map((p) => p.seasonLabel)
                                    .where((s) => s.trim().isNotEmpty)
                                    .join(', ');

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: SoftCard(
                                    padding: const EdgeInsets.all(14),
                                    color: isDark
                                        ? AppTheme.darkCard
                                        : AppTheme.stage1Bg,
                                    border: Border.all(
                                      color: AppTheme.stage1Color
                                          .withValues(alpha: 0.25),
                                    ),
                                    child: Row(
                                      children: [
                                        const TintedIconBadge(
                                          icon: Icons.event_available_rounded,
                                          iconColor: AppTheme.stage1Color,
                                          backgroundColor: Colors.white,
                                          size: 42,
                                          iconSize: 21,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Saisonplanung · Stufe 1 ($schoolName)',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 13.5,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                periodInfo.isNotEmpty
                                                    ? 'Bitte trage deine Verfügbarkeiten für $periodInfo ein.'
                                                    : 'Bitte trage deine Verfügbarkeiten für $schoolName ein.',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: cs.onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        FilledButton(
                                          style: FilledButton.styleFrom(
                                            backgroundColor:
                                                AppTheme.stage1Color,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 10,
                                            ),
                                          ),
                                          onPressed: () async {
                                            await Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    const MyAvailabilityView(
                                                  initialTab: 0,
                                                ),
                                              ),
                                            );
                                            if (mounted) {
                                              _loadAsyncStatus(user);
                                            }
                                          },
                                          child: const Text('Eintragen'),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }),
                              const SizedBox(height: 12),
                            ],
                            if (todos.isNotEmpty) ...[
                              _SectionHeading(
                                label: 'ZU ERLEDIGEN',
                                count: todos.length,
                              ),
                              SoftCard(
                                child: Column(
                                  children: List.generate(todos.length, (idx) {
                                    final item = todos[idx];
                                    return Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (idx > 0)
                                          Divider(
                                            height: 1,
                                            indent: 66,
                                            color: cs.outlineVariant,
                                          ),
                                        InkWell(
                                          onTap: () => item.onTap(context),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 13,
                                            ),
                                            child: Row(
                                              children: [
                                                TintedIconBadge(
                                                  icon: item.icon,
                                                  iconColor: item.color,
                                                  backgroundColor: item.color
                                                      .withValues(alpha: 0.12),
                                                  size: 40,
                                                  iconSize: 20,
                                                  radius: 12,
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        item.title,
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          fontSize: 14,
                                                          color: cs.onSurface,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        item.subtitle,
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: cs
                                                              .onSurfaceVariant,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Icon(
                                                  Icons.chevron_right_rounded,
                                                  size: 20,
                                                  color: cs.onSurfaceVariant,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  }),
                                ),
                              ),
                            ],
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  final String label;
  final int count;

  const _SectionHeading({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          StatusPill(
            label: '$count',
            foreground: AppTheme.primaryColor,
            background: AppTheme.primaryTint,
            fontSize: 11,
          ),
        ],
      ),
    );
  }
}
