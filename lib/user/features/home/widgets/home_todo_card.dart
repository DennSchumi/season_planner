import 'package:flutter/material.dart';
import 'package:season_planner/core/appwrite_config.dart';
import 'package:season_planner/core/data/enums/event_status_enum.dart';
import 'package:season_planner/core/data/enums/membership_status_enum.dart';
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
import 'package:season_planner/user/data/models/user_model_userView.dart';
import 'package:season_planner/user/features/account/widgets/manage_account.dart';
import 'package:season_planner/user/features/account/widgets/manage_flight_school_memberships.dart';
import 'package:season_planner/user/features/home/widgets/event_detail_view.dart';
import 'package:season_planner/user/features/qualifications/my_qualifications_view.dart';
import 'package:url_launcher/url_launcher.dart';

class _TodoItem {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final int priority;
  final Future<void> Function(BuildContext context) onTap;

  const _TodoItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.priority,
    required this.onTap,
  });
}

/// Zeigt unter „Meine Events / Anfragen & Offen“ bei Bedarf offene Aufgaben des
/// Nutzers an (z. B. fehlende/abgelaufene Nachweise, fehlender Notfallkontakt,
/// nicht unterschriebene Checklisten vergangener Events, offene Einladungen).
/// Ist nichts offen, rendert das Widget `SizedBox.shrink()`.
class HomeTodoCard extends StatefulWidget {
  final UserModelUserView user;
  final Set<String> selectedFlightSchools;

  const HomeTodoCard({
    super.key,
    required this.user,
    required this.selectedFlightSchools,
  });

  @override
  State<HomeTodoCard> createState() => _HomeTodoCardState();
}

class _HomeTodoCardState extends State<HomeTodoCard> {
  final _qualService = QualificationService();
  final _docService = RoleDocumentService();
  final _timesheetService = TimesheetService();
  final _inventoryService = InventoryTodoService();

  bool _loading = true;
  bool _expanded = true;

  List<QualificationDocument> _userDocs = [];
  List<QualificationApproval> _userApprovals = [];
  Map<String, ChecklistCompletion> _completionsByAssignmentId = {};
  Map<String, EventTimesheet> _timesheetsByAssignmentId = {};
  Map<String, SchoolInventoryTodoSummary> _inventoryBySchoolId = {};
  String _loadedRunningSchoolsKey = '';

  @override
  void initState() {
    super.initState();
    _loadAsyncStatus();
  }

  Set<String> _runningEventSchoolIds() {
    final now = DateTime.now();
    return widget.user.events
        .where(
          (e) =>
              e.isOwnBindingAssignment &&
              e.status != EventStatusEnum.canceled &&
              !e.startTime.isAfter(now) &&
              e.endTime.isAfter(now) &&
              widget.selectedFlightSchools.contains(e.flightSchoolId),
        )
        .map((e) => e.flightSchoolId)
        .toSet();
  }

  String _schoolsKey(Set<String> ids) {
    final sorted = ids.toList()..sort();
    return sorted.join(',');
  }

  @override
  void didUpdateWidget(covariant HomeTodoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final runningKey = _schoolsKey(_runningEventSchoolIds());
    if (oldWidget.user.id != widget.user.id ||
        oldWidget.user.events.length != widget.user.events.length ||
        oldWidget.user.flightSchools.length !=
            widget.user.flightSchools.length ||
        runningKey != _loadedRunningSchoolsKey) {
      _loadAsyncStatus();
    }
  }

  Future<void> _loadAsyncStatus() async {
    final uid = widget.user.id;
    if (uid.isEmpty) return;

    final runningSchoolIds = _runningEventSchoolIds();
    _loadedRunningSchoolsKey = _schoolsKey(runningSchoolIds);

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
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openInventoryApp() async {
    final uri = Uri.tryParse(AppwriteConfig().inventoryWebUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _showInventoryTasksSheet({
    required BuildContext context,
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
                          color:
                              e.isOverdue
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
                            color:
                                summary.hasOverdueRepack
                                    ? AppTheme.dangerColor
                                    : AppTheme.warningColor,
                            entries: summary.repacksDue,
                          ),
                          buildGroup(
                            title: 'Checks / Service fällig',
                            icon: Icons.fact_check_outlined,
                            color:
                                summary.hasOverdueCheck
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
    if (mounted) _loadAsyncStatus();
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  List<_TodoItem> _buildTodos() {
    final user = widget.user;
    final now = DateTime.now();
    final fsById = {for (final fs in user.flightSchools) fs.id: fs};
    final items = <_TodoItem>[];

    // 1) Offene Flugschul-Einladungen
    for (final fs in user.flightSchools) {
      if (fs.membershipStatus == MembershipStatusEnum.invited) {
        items.add(
          _TodoItem(
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
              if (mounted) _loadAsyncStatus();
            },
          ),
        );
      }
    }

    // 1b) Offene Inventarmanager-Aufgaben der Flugschule bei laufendem eigenem Event
    if (!_loading) {
      final runningSchoolIds = _runningEventSchoolIds();
      for (final schoolId in runningSchoolIds) {
        final summary = _inventoryBySchoolId[schoolId];
        if (summary == null || summary.isEmpty) continue;
        final fs = fsById[schoolId];
        final schoolLabel =
            (fs?.displayShortName.trim().isNotEmpty == true)
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
            _TodoItem(
              icon: Icons.build_rounded,
              color: AppTheme.dangerColor,
              title:
                  'Inventar ($schoolLabel): $n Troubleticket${n == 1 ? "" : "s"} offen',
              subtitle: previewItems(summary.troubleTickets),
              priority: 1,
              onTap: (ctx) => _showInventoryTasksSheet(
                context: ctx,
                schoolName: fullSchoolName,
                summary: summary,
              ),
            ),
          );
        }

        if (summary.repacksDue.isNotEmpty) {
          final n = summary.repacksDue.length;
          items.add(
            _TodoItem(
              icon: Icons.replay_circle_filled_outlined,
              color:
                  summary.hasOverdueRepack
                      ? AppTheme.dangerColor
                      : AppTheme.warningColor,
              title:
                  'Inventar ($schoolLabel): $n× Neupacken ${summary.hasOverdueRepack ? "überfällig" : "fällig"}',
              subtitle: previewItems(summary.repacksDue),
              priority: summary.hasOverdueRepack ? 1 : 2,
              onTap: (ctx) => _showInventoryTasksSheet(
                context: ctx,
                schoolName: fullSchoolName,
                summary: summary,
              ),
            ),
          );
        }

        if (summary.checksDue.isNotEmpty) {
          final n = summary.checksDue.length;
          items.add(
            _TodoItem(
              icon: Icons.fact_check_outlined,
              color:
                  summary.hasOverdueCheck
                      ? AppTheme.dangerColor
                      : AppTheme.warningColor,
              title:
                  'Inventar ($schoolLabel): $n Check${n == 1 ? "" : "s"} ${summary.hasOverdueCheck ? "überfällig" : "fällig"}',
              subtitle: previewItems(summary.checksDue),
              priority: summary.hasOverdueCheck ? 1 : 2,
              onTap: (ctx) => _showInventoryTasksSheet(
                context: ctx,
                schoolName: fullSchoolName,
                summary: summary,
              ),
            ),
          );
        }

        if (summary.lockedItems.isNotEmpty) {
          final n = summary.lockedItems.length;
          items.add(
            _TodoItem(
              icon: Icons.lock_outline,
              color: AppTheme.stage1Color,
              title:
                  'Inventar ($schoolLabel): $n Artikel gesperrt',
              subtitle: previewItems(summary.lockedItems),
              priority: 2,
              onTap: (ctx) => _showInventoryTasksSheet(
                context: ctx,
                schoolName: fullSchoolName,
                summary: summary,
              ),
            ),
          );
        }
      }
    }

    // 2) Nicht unterschriebene Checklisten aus vergangenen Events
    if (!_loading) {
      final pastBindingEvents = user.events
          .where(
            (e) =>
                e.isOwnBindingAssignment &&
                e.status != EventStatusEnum.canceled &&
                e.endTime.isBefore(now) &&
                widget.selectedFlightSchools.contains(e.flightSchoolId),
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
          _TodoItem(
            icon: Icons.draw_outlined,
            color: AppTheme.dangerColor,
            title: 'Checkliste unterschreiben: ${ev.displayName}',
            subtitle:
                '${ev.roleLabel} · beendet am ${_fmtDate(ev.endTime)}',
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
              if (mounted) _loadAsyncStatus();
            },
          ),
        );
      }

      // 2b) Fehlende Stundenzettel aus vergangenen Events (Lehrpersonal)
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
          _TodoItem(
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
              if (mounted) _loadAsyncStatus();
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
        if (!widget.selectedFlightSchools.contains(fs.id)) continue;

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
          _TodoItem(
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
              if (mounted) _loadAsyncStatus();
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
          _TodoItem(
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
              if (mounted) _loadAsyncStatus();
            },
          ),
        );
      }

      if (missingDocs.isNotEmpty) {
        items.add(
          _TodoItem(
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
              if (mounted) _loadAsyncStatus();
            },
          ),
        );
      }
    }

    // 4) Fehlende Profil-Angaben (Notfallkontakt, Telefon, Profilbild)
    if (!user.hasEmergencyContact) {
      items.add(
        _TodoItem(
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
            if (mounted) _loadAsyncStatus();
          },
        ),
      );
    }

    if (user.phone.trim().isEmpty) {
      items.add(
        _TodoItem(
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
            if (mounted) _loadAsyncStatus();
          },
        ),
      );
    }

    if (user.avatarUrl.trim().isEmpty) {
      items.add(
        _TodoItem(
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
            if (mounted) _loadAsyncStatus();
          },
        ),
      );
    }

    items.sort((a, b) => a.priority.compareTo(b.priority));
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final todos = _buildTodos();
    if (todos.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasUrgent = todos.any(
      (t) => t.color == AppTheme.dangerColor || t.color == AppTheme.warningColor,
    );
    final accent = hasUrgent ? AppTheme.warningColor : cs.primary;
    final headerBg = isDark
        ? accent.withValues(alpha: 0.14)
        : (hasUrgent ? AppTheme.warningBg : AppTheme.primaryTint);

    return SoftCard(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      radius: 20,
      border: Border.all(color: accent.withValues(alpha: 0.25)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Ink(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 11,
              ),
              color: headerBg,
              child: Row(
                children: [
                  Icon(
                    Icons.assignment_late_outlined,
                    size: 19,
                    color: accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Zu erledigen',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  StatusPill(
                    label: '${todos.length}',
                    foreground: accent,
                    background: Colors.white,
                    fontSize: 11.5,
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_up_rounded,
                    size: 20,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: todos.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  indent: 62,
                  color: cs.outlineVariant,
                ),
                itemBuilder: (ctx, idx) {
                  final item = todos[idx];
                  return InkWell(
                    onTap: () => item.onTap(ctx),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          TintedIconBadge(
                            icon: item.icon,
                            iconColor: item.color,
                            backgroundColor: item.color.withValues(alpha: 0.12),
                            size: 36,
                            iconSize: 18,
                            radius: 10,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  item.subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
