import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/core/data/enums/event_role_enum.dart';
import 'package:season_planner/core/data/enums/event_status_enum.dart';
import 'package:season_planner/core/data/enums/event_user_status_enum.dart';
import 'package:season_planner/core/data/models/event_model.dart';
import 'package:season_planner/core/data/models/planning_period_model.dart';
import 'package:season_planner/core/data/models/role_document_model.dart';
import 'package:season_planner/core/data/models/team_role_model.dart';
import 'package:season_planner/core/data/models/timesheet_model.dart';
import 'package:season_planner/core/services/planning_service.dart';
import 'package:season_planner/core/services/role_document_service.dart';
import 'package:season_planner/core/services/security_privacy_service.dart';
import 'package:season_planner/core/services/tandem_service.dart';
import 'package:season_planner/core/services/timesheet_service.dart';
import 'package:season_planner/core/theme.dart';
import 'package:season_planner/core/widgets/checklist_runner_view.dart';
import 'package:season_planner/core/widgets/markdown_document_view.dart';
import 'package:season_planner/core/widgets/timesheet_runner_view.dart';
import 'package:season_planner/core/widgets/user_avatar.dart';
import 'package:season_planner/core/widgets/ux_components.dart';
import 'package:season_planner/user/data/models/flight_school_model_user_view.dart';
import 'package:season_planner/user/features/home/widgets/event_detail_view.dart';
import 'package:season_planner/user/services/database_service.dart';
import 'package:season_planner/user/user_provider.dart';

/// Öffnet das moderne Event-Vorschau-Overlay (Mockup-Seite 5) über dem
/// abgedunkelten aktuellen Screen. Ein Wisch am oberen Rand nach oben (oder
/// ein Tipp auf „Alle Details“) öffnet direkt die vollständige `EventDetailView`.
Future<void> showEventPreviewSheet(
  BuildContext context, {
  required Event event,
  List<Event> siblingOpportunities = const [],
}) async {
  final rootNavigator = Navigator.of(context);
  final shouldOpenFull = await showAdaptiveSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.50),
    wrapDesktopCard: false,
    desktopMaxWidth: 560,
    builder: (ctx) => _EventPreviewOverlaySheet(
      event: event,
      siblingOpportunities: siblingOpportunities,
    ),
  );

  if (shouldOpenFull == true && rootNavigator.mounted) {
    await rootNavigator.push(
      PageRouteBuilder<void>(
        pageBuilder: (_, __, ___) => EventDetailView(
          event: event,
          siblingOpportunities: siblingOpportunities,
        ),
        transitionsBuilder: (_, anim, __, child) {
          final curved = CurvedAnimation(
            parent: anim,
            curve: Curves.easeOutCubic,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.14),
              end: Offset.zero,
            ).animate(curved),
            child: FadeTransition(opacity: curved, child: child),
          );
        },
        transitionDuration: const Duration(milliseconds: 240),
      ),
    );
  }
}

class _EventPreviewOverlaySheet extends StatefulWidget {
  final Event event;
  final List<Event> siblingOpportunities;

  const _EventPreviewOverlaySheet({
    required this.event,
    required this.siblingOpportunities,
  });

  @override
  State<_EventPreviewOverlaySheet> createState() =>
      _EventPreviewOverlaySheetState();
}

class _EventPreviewOverlaySheetState extends State<_EventPreviewOverlaySheet> {
  final _docService = RoleDocumentService();
  final _timesheetService = TimesheetService();
  bool _busy = false;
  double _upwardDragDelta = 0;

  bool _loadingDocs = false;
  RoleDocument? _checklist;
  ChecklistCompletion? _completion;
  List<RoleDocument> _instructions = const [];
  EventTimesheet? _timesheet;
  bool _requiresTimesheet = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRoleDocs();
    });
  }

  TeamRole? _matchingRole(FlightSchoolUserView fs, Event ev) {
    final roleName = ev.role.trim();
    if (roleName.isEmpty) return null;
    final normalized = EventRoleEnum.displayLabel(roleName).toLowerCase();
    for (final r in fs.teamRoles) {
      if (r.name.toLowerCase() == roleName.toLowerCase() ||
          r.name.toLowerCase() == normalized) {
        return r;
      }
    }
    return null;
  }

  Future<void> _loadRoleDocs() async {
    final user = context.read<UserProvider>().user;
    if (user == null) return;
    final ev = user.events.firstWhere(
      (e) => e.id == widget.event.id,
      orElse: () => widget.event,
    );
    if (!ev.isOwnBindingAssignment) return;

    FlightSchoolUserView? fs;
    for (final s in user.flightSchools) {
      if (s.id == ev.flightSchoolId) {
        fs = s;
        break;
      }
    }
    if (fs == null) return;

    final role = _matchingRole(fs, ev);
    final hasRoleDocs = role != null &&
        ((role.checklistId != null && role.checklistId!.isNotEmpty) ||
            role.instructionIds.isNotEmpty);
    final showTimesheet = ev.status != EventStatusEnum.canceled &&
        fs.userRequiresTimesheet &&
        !DateTime.now().isBefore(ev.startTime);
    if (mounted && _requiresTimesheet != showTimesheet) {
      setState(() => _requiresTimesheet = showTimesheet);
    }

    if (!hasRoleDocs && !showTimesheet) {
      return;
    }

    if (mounted) setState(() => _loadingDocs = true);
    try {
      final results = await Future.wait([
        if (hasRoleDocs)
          _docService.getDocumentsByIds(role.instructionIds)
        else
          Future<List<RoleDocument>>.value(const []),
        if (hasRoleDocs &&
            role.checklistId != null &&
            role.checklistId!.isNotEmpty)
          _docService.getDocumentById(role.checklistId!)
        else
          Future<RoleDocument?>.value(null),
        if (showTimesheet)
          _timesheetService.getTimesheetForAssignment(ev.id)
        else
          Future<EventTimesheet?>.value(null),
      ]);
      final instructions = results[0] as List<RoleDocument>;
      final checklist = results[1] as RoleDocument?;
      final timesheet = results[2] as EventTimesheet?;
      final completion = checklist != null
          ? await _docService.getCompletionForAssignment(ev.id)
          : null;
      if (!mounted) return;
      setState(() {
        _instructions = instructions;
        _checklist = checklist;
        _completion = completion;
        _timesheet = timesheet;
      });
    } catch (_) {
      // still fail-safe
    } finally {
      if (mounted) setState(() => _loadingDocs = false);
    }
  }

  Future<void> _openTimesheet(Event ev, String userId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TimesheetRunnerView(
          event: ev,
          userId: userId,
          initialTimesheet: _timesheet,
        ),
      ),
    );
    if (mounted) _loadRoleDocs();
  }

  Future<void> _openChecklist(Event ev, String userId) async {
    final checklist = _checklist;
    if (checklist == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChecklistRunnerView(
          event: ev,
          userId: userId,
          checklist: checklist,
          initialCompletion: _completion,
        ),
      ),
    );
    if (mounted) _loadRoleDocs();
  }

  Future<void> _openInstructions() async {
    if (_instructions.isEmpty) return;
    if (_instructions.length == 1) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MarkdownDocumentView(document: _instructions.first),
        ),
      );
      return;
    }

    final selected = await showModalBottomSheet<RoleDocument>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Arbeitsanweisungen',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              ..._instructions.map(
                (doc) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SoftCard(
                    radius: 14,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    onTap: () => Navigator.pop(ctx, doc),
                    child: Row(
                      children: [
                        const TintedIconBadge(
                          icon: Icons.menu_book_outlined,
                          iconColor: AppTheme.primaryColor,
                          backgroundColor: AppTheme.primaryTint,
                          size: 34,
                          iconSize: 18,
                          radius: 10,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            doc.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, size: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (selected != null && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MarkdownDocumentView(document: selected),
        ),
      );
    }
  }

  static const _shortWeekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
  static const _shortMonths = [
    'Jan',
    'Feb',
    'Mär',
    'Apr',
    'Mai',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Okt',
    'Nov',
    'Dez',
  ];

  static const _avatarPalette = [
    AppTheme.primaryColor,
    AppTheme.successColor,
    Color(0xFFC2410C),
    AppTheme.infoColor,
    AppTheme.swapColor,
  ];

  String _formatDateRange(DateTime start, DateTime end) {
    final sameDay =
        start.year == end.year &&
        start.month == end.month &&
        start.day == end.day;
    final startHm =
        '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
    final endHm =
        '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';

    if (sameDay) {
      final wd = _shortWeekdays[start.weekday - 1];
      final mon = _shortMonths[start.month - 1];
      return '$wd, ${start.day}. $mon · $startHm–$endHm Uhr';
    }
    String d(DateTime x) =>
        '${x.day.toString().padLeft(2, '0')}.${x.month.toString().padLeft(2, '0')}.${x.year}';
    return '${d(start)} $startHm – ${d(end)} $endHm';
  }

  void _openFullDetails() {
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (details.delta.dy < 0) {
      setState(() {
        _upwardDragDelta = (_upwardDragDelta - details.delta.dy).clamp(0, 90);
      });
    } else if (_upwardDragDelta > 0) {
      setState(() {
        _upwardDragDelta = (_upwardDragDelta - details.delta.dy).clamp(0, 90);
      });
    }
  }

  void _handleDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (_upwardDragDelta >= 42 || velocity < -260) {
      _openFullDetails();
      return;
    }
    if (velocity > 360) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() => _upwardDragDelta = 0);
  }

  Future<void> _reloadEvents() async {
    final currentUser = context.read<UserProvider>().user;
    if (currentUser == null) return;
    final updated = await DatabaseService().loadUserEvents(currentUser);
    if (!mounted) return;
    context.read<UserProvider>().updateEvents(updated);
  }

  Future<void> _runQuickAction({
    required Future<bool> Function() action,
    required String successText,
    bool closeOnSuccess = true,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ok = await action();
      if (!mounted) return;
      if (ok) {
        await _reloadEvents();
        if (!mounted) return;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(successText)),
        );
        if (closeOnSuccess) Navigator.of(context).pop(false);
      } else {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Aktion fehlgeschlagen.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: AppTheme.dangerColor)
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return res == true;
  }

  Future<void> _saveStage1Availability(
    Event event,
    FlightSchoolUserView? fs,
    AvailabilityKind kind,
  ) async {
    final user = context.read<UserProvider>().user;
    if (user == null || _busy) return;
    setState(() => _busy = true);
    try {
      final period = fs?.periodForEvent(event);
      final created = await PlanningService().createSubmission(
        flightSchoolId: event.flightSchoolId,
        userId: user.id,
        planningPeriodId:
            kind == AvailabilityKind.available ? period?.id : null,
        kind: kind,
        startDate: DateTime(
          event.startTime.year,
          event.startTime.month,
          event.startTime.day,
        ),
        endDate: DateTime(
          event.endTime.year,
          event.endTime.month,
          event.endTime.day,
        ),
        notes: event.displayName,
      );
      final ok = created != null;
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? (kind == AvailabilityKind.available
                    ? 'Verfügbarkeit eingetragen.'
                    : 'Abwesenheit eingetragen.')
                : 'Konnte nicht gespeichert werden.',
          ),
        ),
      );
      if (ok) Navigator.of(context).pop(false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserProvider>().user;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final event = user?.events.firstWhere(
          (e) => e.id == widget.event.id,
          orElse: () => widget.event,
        ) ??
        widget.event;

    FlightSchoolUserView? fs;
    if (user != null) {
      for (final s in user.flightSchools) {
        if (s.id == event.flightSchoolId) {
          fs = s;
          break;
        }
      }
    }

    final effectiveStage = fs?.effectiveStageFor(event) ?? event.planningStage;
    final isOwnBinding = event.isOwnBindingAssignment;
    final isStage1 = effectiveStage == 1;
    final isStage3 = effectiveStage == 3;
    final isDirectRequest =
        !event.isSwapOfferFromOther &&
        event.assignmentStatus == EventUserStatusEnum.pending_user;
    final isExtendedRedacted =
        (fs?.isExtendedTeam == true) && !isOwnBinding && !isDirectRequest;
    final isStage1Preview =
        (isStage1 || isExtendedRedacted) && !isOwnBinding && !isDirectRequest;
    final canSeeTeam = isOwnBinding && effectiveStage >= 2;
    final isApplied =
        !event.isSwapOfferFromOther &&
        event.assignmentStatus == EventUserStatusEnum.pending_flight_school;
    final isOpenOpportunity =
        !isOwnBinding &&
        !isStage1Preview &&
        (event.isSwapOfferFromOther ||
            event.assignmentStatus == EventUserStatusEnum.open);

    // Status-Pill-Stil bestimmen
    final (statusLabel, statusFg, statusBg) = _resolveStatusPill(
      event: event,
      isOwnBinding: isOwnBinding,
      isStage1Preview: isStage1Preview,
      isExtendedRedacted: isExtendedRedacted && !isStage1,
      isDirectRequest: isDirectRequest,
      isApplied: isApplied,
    );

    final schoolName = fs == null
        ? ''
        : (fs.displayShortName.trim().isNotEmpty
            ? fs.displayShortName.trim()
            : fs.displayName);

    final locationLine = event.location.trim().isNotEmpty
        ? (schoolName.isNotEmpty
            ? '${event.location.trim()}, $schoolName'
            : event.location.trim())
        : (fs?.displayName ?? '');

    final liftOffset = -_upwardDragDelta * 0.35;
    final isDesktop = context.isDesktop;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      transform: Matrix4.translationValues(0, isDesktop ? 0 : liftOffset, 0),
      child: Container(
        decoration: BoxDecoration(
          color: isDark
              ? AppTheme.darkCard
              : (isDesktop
                  ? AppTheme.desktopBackground
                  : AppTheme.backgroundColor),
          borderRadius: isDesktop
              ? BorderRadius.circular(24)
              : const BorderRadius.vertical(top: Radius.circular(28)),
          border: isDesktop
              ? Border.all(
                  color: isDark ? AppTheme.darkBorder : AppTheme.desktopBorder,
                )
              : null,
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 28,
              offset: Offset(0, -6),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, isDesktop ? 18 : 10, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Oberer Wisch-Bereich nur auf Mobilgeräten (auf Desktop unnötig)
                if (!isDesktop && !isExtendedRedacted)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragUpdate: _handleDragUpdate,
                    onVerticalDragEnd: _handleDragEnd,
                    onTap: _openFullDetails,
                    child: Column(
                      children: [
                        Center(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 140),
                            width: _upwardDragDelta > 10 ? 54 : 42,
                            height: 4.5,
                            decoration: BoxDecoration(
                              color: _upwardDragDelta > 10
                                  ? AppTheme.primaryColor
                                  : cs.outline,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.keyboard_arrow_up_rounded,
                              size: 15,
                              color: _upwardDragDelta > 10
                                  ? AppTheme.primaryColor
                                  : cs.onSurfaceVariant.withValues(alpha: 0.75),
                            ),
                            const SizedBox(width: 2),
                            Text(
                              _upwardDragDelta > 20
                                  ? 'Loslassen für alle Details'
                                  : 'Nach oben wischen für alle Details',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _upwardDragDelta > 10
                                    ? AppTheme.primaryColor
                                    : cs.onSurfaceVariant
                                        .withValues(alpha: 0.75),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ],
                    ),
                  )
                else if (!isDesktop)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Center(
                      child: Container(
                        width: 42,
                        height: 4.5,
                        decoration: BoxDecoration(
                          color: cs.outline,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ),

                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),

                // Status-Pills (Einsatz-Status + Event-Status + Rolle) + Close-Button
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          StatusPill(
                            label: statusLabel,
                            foreground: statusFg,
                            background: statusBg,
                          ),
                          if (!isStage1Preview)
                            StatusPill.fromEventStatus(
                              event.status.name,
                              'Event: ${event.status.label}',
                            ),
                          if (!isStage1Preview && event.role.isNotEmpty)
                            StatusPill(
                              label: event.roleLabel,
                              foreground: AppTheme.primaryColor,
                              background: AppTheme.primaryTint,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Material(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(10),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => Navigator.of(context).pop(false),
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: cs.outlineVariant),
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // Event-Titel (ebenfalls nach oben wischbar, außer bei ausgegrauter Vorschau)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate:
                      isExtendedRedacted ? null : _handleDragUpdate,
                  onVerticalDragEnd:
                      isExtendedRedacted ? null : _handleDragEnd,
                  onTap: isExtendedRedacted ? null : _openFullDetails,
                  child: Text(
                    event.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.45,
                      height: 1.15,
                      color: cs.onSurface,
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // Zeitraum-Kachel
                SoftCard(
                  radius: 15,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  onTap: _openFullDetails,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.schedule_outlined,
                        size: 19,
                        color: AppTheme.primaryColor,
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(
                          _formatDateRange(event.startTime, event.endTime),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                if (locationLine.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SoftCard(
                    radius: 15,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    onTap: _openFullDetails,
                    child: Row(
                      children: [
                        Icon(
                          event.location.trim().isNotEmpty
                              ? Icons.place_outlined
                              : Icons.school_outlined,
                          size: 19,
                          color: AppTheme.primaryColor,
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Text(
                            locationLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Team-Avatare (nur wenn der Nutzer andere Team-Positionen sehen darf)
                if (canSeeTeam && event.team.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'TEAM (${event.team.length})',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.7,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _OverlappingTeamAvatars(
                    team: event.team,
                    palette: _avatarPalette,
                    ringColor:
                        isDark ? AppTheme.darkCard : AppTheme.backgroundColor,
                  ),
                ],

                // Kompakte Kacheln für Checkliste, Arbeitsanweisungen & Stundenzettel
                if (isOwnBinding &&
                    user != null &&
                    (_loadingDocs ||
                        _checklist != null ||
                        _instructions.isNotEmpty ||
                        _requiresTimesheet)) ...[
                  const SizedBox(height: 14),
                  _buildRoleDocsQuickRow(
                    context: context,
                    event: event,
                    userId: user.id,
                  ),
                ],

                // Notizen-Vorschau
                if (!isStage1Preview && event.notes.trim().isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    event.notes.trim(),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.45,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],

                const SizedBox(height: 18),

                // Aktionsleiste unten (analog Mockup-Seite 5)
                _buildBottomActions(
                  context: context,
                  event: event,
                  fs: fs,
                  isOwnBinding: isOwnBinding,
                  isStage3: isStage3,
                  isStage1Preview: isStage1Preview,
                  isDirectRequest: isDirectRequest,
                  isApplied: isApplied,
                  isOpenOpportunity: isOpenOpportunity,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleDocsQuickRow({
    required BuildContext context,
    required Event event,
    required String userId,
  }) {
    final cs = Theme.of(context).colorScheme;
    if (_loadingDocs &&
        _checklist == null &&
        _instructions.isEmpty &&
        !_requiresTimesheet) {
      return const LinearProgressIndicator(minHeight: 2);
    }

    Widget? checklistTile;
    if (_checklist != null) {
      final comp = _completion;
      final total =
          comp?.totalCount ?? _checklist!.parseChecklistItems().length;
      final checked = comp?.checkedCount ?? 0;
      final isSigned = comp?.isSigned == true;
      final isComplete = comp?.isComplete == true;
      final now = DateTime.now();
      final canEdit = !now.isBefore(
        event.startTime.subtract(const Duration(hours: 24)),
      );

      final (IconData icon, Color fg, Color bg, String sub) =
          isSigned && isComplete
              ? (
                  Icons.verified_outlined,
                  AppTheme.successColor,
                  AppTheme.successBg,
                  'Erledigt ($checked/$total)',
                )
              : isSigned
                  ? (
                      Icons.warning_amber_rounded,
                      AppTheme.warningColor,
                      AppTheme.warningBg,
                      '$checked/$total abgehakt',
                    )
                  : !canEdit
                      ? (
                          Icons.visibility_outlined,
                          AppTheme.infoColor,
                          AppTheme.infoBg,
                          'Vorschau ($total Pkt.)',
                        )
                      : (
                          Icons.checklist_rounded,
                          AppTheme.primaryColor,
                          AppTheme.primaryTint,
                          checked > 0
                              ? '$checked/$total erledigt'
                              : 'Offen ($total Pkt.)',
                        );

      checklistTile = SoftCard(
        radius: 14,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
        onTap: () => _openChecklist(event, userId),
        child: Row(
          children: [
            TintedIconBadge(
              icon: icon,
              iconColor: fg,
              backgroundColor: bg,
              size: 32,
              iconSize: 17,
              radius: 9,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Checkliste',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    Widget? instructionsTile;
    if (_instructions.isNotEmpty) {
      final sub = _instructions.length == 1
          ? _instructions.first.title
          : '${_instructions.length} Dokumente';
      instructionsTile = SoftCard(
        radius: 14,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
        onTap: _openInstructions,
        child: Row(
          children: [
            const TintedIconBadge(
              icon: Icons.menu_book_outlined,
              iconColor: AppTheme.primaryColor,
              backgroundColor: AppTheme.primaryTint,
              size: 32,
              iconSize: 17,
              radius: 9,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Anweisungen',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    Widget? timesheetTile;
    if (_requiresTimesheet) {
      final sheet = _timesheet;
      final isSubmitted = sheet?.isSubmitted == true;
      final isEnded = event.endTime.isBefore(DateTime.now());
      final (IconData icon, Color fg, Color bg, String sub) = isSubmitted
          ? (
              Icons.verified_outlined,
              AppTheme.successColor,
              AppTheme.successBg,
              'Abgesendet · ${sheet!.formattedTotalHours}',
            )
          : isEnded
              ? (
                  Icons.access_time_filled_rounded,
                  AppTheme.dangerColor,
                  AppTheme.dangerBg,
                  sheet != null
                      ? 'Entwurf (${sheet.formattedTotalHours}) · fällig'
                      : 'Fällig · jetzt ausfüllen',
                )
              : sheet != null
                  ? (
                      Icons.access_time_rounded,
                      AppTheme.infoColor,
                      AppTheme.infoBg,
                      'Entwurf · ${sheet.formattedTotalHours}',
                    )
                  : (
                      Icons.access_time_rounded,
                      AppTheme.primaryColor,
                      AppTheme.primaryTint,
                      'Arbeitszeiten eintragen',
                    );

      timesheetTile = SoftCard(
        radius: 14,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
        onTap: () => _openTimesheet(event, userId),
        child: Row(
          children: [
            TintedIconBadge(
              icon: icon,
              iconColor: fg,
              backgroundColor: bg,
              size: 32,
              iconSize: 17,
              radius: 9,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Stundenzettel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: fg),
          ],
        ),
      );
    }

    Widget? docsRow;
    if (checklistTile != null && instructionsTile != null) {
      docsRow = Row(
        children: [
          Expanded(child: checklistTile),
          const SizedBox(width: 8),
          Expanded(child: instructionsTile),
        ],
      );
    } else {
      docsRow = checklistTile ?? instructionsTile;
    }

    if (timesheetTile != null && docsRow != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          timesheetTile,
          const SizedBox(height: 8),
          docsRow,
        ],
      );
    }
    return timesheetTile ?? docsRow ?? const SizedBox.shrink();
  }

  (String, Color, Color) _resolveStatusPill({
    required Event event,
    required bool isOwnBinding,
    required bool isStage1Preview,
    bool isExtendedRedacted = false,
    required bool isDirectRequest,
    required bool isApplied,
  }) {
    if (isExtendedRedacted) {
      return (
        'Termin',
        const Color(0xFF6B7280),
        const Color(0xFFECEEF3),
      );
    }
    if (isStage1Preview) {
      return ('Stufe 1 – Verfügbarkeit', AppTheme.stage1Color, AppTheme.stage1Bg);
    }
    if (isDirectRequest) {
      return (
        'Arbeitseinsatz angefragt',
        AppTheme.warningColor,
        AppTheme.warningBg,
      );
    }
    if (isApplied) {
      return ('Beworben', AppTheme.infoColor, AppTheme.infoBg);
    }
    if (event.isSwapOfferFromOther) {
      return ('Tauschplatz frei', AppTheme.swapColor, AppTheme.swapBg);
    }
    if (isOwnBinding) {
      if (event.assignmentStatus == EventUserStatusEnum.user_requests_change) {
        return (
          'Änderung angefragt',
          AppTheme.warningColor,
          AppTheme.warningBg,
        );
      }
      if (event.swapOffered) {
        return ('Zum Tausch offen', AppTheme.swapColor, AppTheme.swapBg);
      }
      return (
        'Arbeitseinsatz bestätigt',
        AppTheme.successColor,
        AppTheme.successBg,
      );
    }
    return ('Offene Stelle', AppTheme.infoColor, AppTheme.infoBg);
  }

  Widget _buildBottomActions({
    required BuildContext context,
    required Event event,
    required FlightSchoolUserView? fs,
    required bool isOwnBinding,
    required bool isStage3,
    required bool isStage1Preview,
    required bool isDirectRequest,
    required bool isApplied,
    required bool isOpenOpportunity,
  }) {
    final user = context.read<UserProvider>().user;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget softDangerBtn({
      required String label,
      required VoidCallback? onPressed,
    }) {
      return SizedBox(
        height: 48,
        child: TextButton(
          style: TextButton.styleFrom(
            backgroundColor: isDark
                ? AppTheme.dangerColor.withValues(alpha: 0.18)
                : AppTheme.dangerBg,
            foregroundColor: isDark
                ? const Color(0xFFFCA5A5)
                : AppTheme.dangerColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          onPressed: _busy ? null : onPressed,
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      );
    }

    Widget primaryBtn({
      required String label,
      required VoidCallback? onPressed,
      Color? backgroundColor,
    }) {
      return Container(
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: backgroundColor == null ? AppTheme.primaryGlow : null,
        ),
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: backgroundColor ?? AppTheme.primaryColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: _busy ? null : onPressed,
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      );
    }

    // 1) Bereits fest eingeplantes Event
    if (isOwnBinding && user != null) {
      final alreadyReqChange =
          event.assignmentStatus == EventUserStatusEnum.user_requests_change;
      return Row(
        children: [
          Expanded(
            child: softDangerBtn(
              label: alreadyReqChange ? 'Angefragt' : 'Änderung anfragen',
              onPressed: alreadyReqChange
                  ? null
                  : () async {
                      final ok = await _confirmDialog(
                        title: 'Änderung anfragen',
                        message:
                            'Möchtest du für „${event.displayName}“ eine Änderung / Ersatz bei deiner Flugschule anfragen?',
                        confirmLabel: 'Anfragen',
                        destructive: true,
                      );
                      if (!ok) return;
                      await _runQuickAction(
                        action: () =>
                            DatabaseService().changeEventAssignmentStatus(
                          user: user,
                          event: event,
                          newStatus: EventUserStatusEnum.user_requests_change,
                        ),
                        successText: 'Änderungsanfrage gesendet.',
                      );
                    },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: isStage3 && fs != null
                ? primaryBtn(
                    label: event.swapOffered
                        ? 'Tausch zurückziehen'
                        : 'Tausch anfragen',
                    onPressed: () async {
                      final nextOffer = !event.swapOffered;
                      final ok = await _confirmDialog(
                        title: nextOffer
                            ? 'Zum Tausch freigeben'
                            : 'Tausch-Angebot zurückziehen',
                        message: nextOffer
                            ? 'Andere qualifizierte Teammitglieder können deinen Platz dann anfragen.'
                            : 'Dein Platz wird nicht mehr zum Tausch angeboten.',
                        confirmLabel: nextOffer ? 'Freigeben' : 'Zurückziehen',
                      );
                      if (!ok) return;
                      await _runQuickAction(
                        action: () => PlanningService().setSwapOffered(
                          databaseId: fs.databaseId,
                          tableId: fs.teamAssignmentsEventsCollectionId,
                          assignmentId: event.id,
                          offered: nextOffer,
                        ),
                        successText: nextOffer
                            ? 'Platz zum Tausch freigegeben.'
                            : 'Tausch-Angebot zurückgezogen.',
                      );
                    },
                  )
                : primaryBtn(
                    label: 'Alle Details',
                    onPressed: _openFullDetails,
                  ),
          ),
        ],
      );
    }

    // 2) Direktanfrage vom Admin an den Nutzer
    if (isDirectRequest && user != null) {
      return Row(
        children: [
          Expanded(
            child: softDangerBtn(
              label: 'Ablehnen',
              onPressed: () async {
                final ok = await _confirmDialog(
                  title: 'Anfrage ablehnen',
                  message:
                      'Möchtest du die Anfrage für „${event.displayName}“ wirklich ablehnen?',
                  confirmLabel: 'Ablehnen',
                  destructive: true,
                );
                if (!ok) return;
                await _runQuickAction(
                  action: () => DatabaseService().changeEventAssignmentStatus(
                    user: user,
                    event: event,
                    newStatus: EventUserStatusEnum.denied_user,
                  ),
                  successText: 'Anfrage abgelehnt.',
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: primaryBtn(
              label: 'Zusagen',
              onPressed: () async {
                final evKey = (event.eventDocId != null &&
                        event.eventDocId!.isNotEmpty)
                    ? event.eventDocId!
                    : event.id;
                String? conflict = TandemService.findUserEventBookingConflict(
                  userId: user.id,
                  startTime: event.startTime,
                  endTime: event.endTime,
                  userEvents: user.events,
                  userTandemDuties: user.tandemDuties,
                  ignoreEventKey: evKey,
                );
                if (conflict == null) {
                  final serverMap = await SecurityPrivacyService()
                      .checkCrossSchoolConflicts(
                    userIds: [user.id],
                    startTime: event.startTime,
                    endTime: event.endTime,
                    ignoreEventId: evKey,
                    otherSchoolsOnly: false,
                  );
                  if (!context.mounted) return;
                  final serverList =
                      serverMap.values.expand((e) => e).toList();
                  if (serverList.isNotEmpty) {
                    conflict = serverList.join(' · ');
                  }
                }
                if (conflict != null) {
                  await showUserBookingConflictDialog(
                    context,
                    reason: conflict,
                  );
                  return;
                }
                await _runQuickAction(
                  action: () => DatabaseService().changeEventAssignmentStatus(
                    user: user,
                    event: event,
                    newStatus: EventUserStatusEnum.accepted_user,
                  ),
                  successText: 'Einsatz zugesagt!',
                );
              },
            ),
          ),
        ],
      );
    }

    // 3) Planungsstufe 1 Vorschau (noch nicht eingeplant)
    if (isStage1Preview) {
      return Row(
        children: [
          Expanded(
            child: softDangerBtn(
              label: 'Nicht verfügbar',
              onPressed: () =>
                  _saveStage1Availability(event, fs, AvailabilityKind.blackout),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: primaryBtn(
              label: 'Verfügbar',
              backgroundColor: AppTheme.successColor,
              onPressed: () => _saveStage1Availability(
                event,
                fs,
                AvailabilityKind.available,
              ),
            ),
          ),
        ],
      );
    }

    // 4) Offene Stelle oder Tauschplatz eines Kollegen
    if (isOpenOpportunity && user != null && fs != null) {
      final qualOk = event.role.isEmpty ||
          fs.checkRoleQualificationStatus(event.role).satisfied;
      return Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 48,
              child: OutlinedButton(
                onPressed: _busy ? null : _openFullDetails,
                child: const Text('Details'),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: primaryBtn(
              label: event.isSwapOfferFromOther
                  ? 'Tausch anfragen'
                  : (qualOk ? 'Bewerben' : 'Qualifikation prüfen'),
              onPressed: () async {
                if (!qualOk || widget.siblingOpportunities.length > 1) {
                  _openFullDetails();
                  return;
                }
                final evKey = (event.eventDocId != null &&
                        event.eventDocId!.isNotEmpty)
                    ? event.eventDocId!
                    : event.id;
                String? conflict = TandemService.findUserEventBookingConflict(
                  userId: user.id,
                  startTime: event.startTime,
                  endTime: event.endTime,
                  userEvents: user.events,
                  userTandemDuties: user.tandemDuties,
                  ignoreEventKey: evKey,
                );
                if (conflict == null) {
                  final serverMap = await SecurityPrivacyService()
                      .checkCrossSchoolConflicts(
                    userIds: [user.id],
                    startTime: event.startTime,
                    endTime: event.endTime,
                    ignoreEventId: evKey,
                    otherSchoolsOnly: false,
                  );
                  if (!context.mounted) return;
                  final serverList =
                      serverMap.values.expand((e) => e).toList();
                  if (serverList.isNotEmpty) {
                    conflict = serverList.join(' · ');
                  }
                }
                if (conflict != null) {
                  await showUserBookingConflictDialog(
                    context,
                    reason: conflict,
                  );
                  return;
                }
                if (event.isSwapOfferFromOther) {
                  final ok = await _confirmDialog(
                    title: 'Tauschplatz anfragen',
                    message:
                        'Möchtest du diesen Platz übernehmen? Ein Admin bestätigt den Tausch anschließend.',
                    confirmLabel: 'Anfragen',
                  );
                  if (!ok) return;
                  await _runQuickAction(
                    action: () => PlanningService().requestSwapTakeover(
                      databaseId: fs.databaseId,
                      tableId: fs.teamAssignmentsEventsCollectionId,
                      assignmentId: event.id,
                      requesterUserId: user.id,
                      requesterName: user.name.isEmpty ? user.mail : user.name,
                    ),
                    successText: 'Tauschanfrage gesendet.',
                  );
                } else {
                  await _runQuickAction(
                    action: () => DatabaseService().changeEventAssignmentStatus(
                      user: user,
                      event: event,
                      newStatus: EventUserStatusEnum.pending_flight_school,
                    ),
                    successText: 'Bewerbung gesendet.',
                  );
                }
              },
            ),
          ),
        ],
      );
    }

    // 5) Beworben / Sonstige
    return primaryBtn(
      label: isApplied ? 'Bewerbungsstatus & Details' : 'Alle Details öffnen',
      onPressed: _openFullDetails,
    );
  }
}

class _OverlappingTeamAvatars extends StatelessWidget {
  final List<TeamMember> team;
  final List<Color> palette;
  final Color ringColor;

  const _OverlappingTeamAvatars({
    required this.team,
    required this.palette,
    required this.ringColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final visible = team.take(4).toList();
    final overflow = team.length - visible.length;
    const double size = 40;
    const double step = 30;
    final totalCircles = visible.length + (overflow > 0 ? 1 : 0);
    final totalWidth = size + (totalCircles - 1) * step;

    return SizedBox(
      height: size,
      width: totalWidth,
      child: Stack(
        children: [
          for (var i = 0; i < visible.length; i++)
            Positioned(
              left: i * step,
              child: Tooltip(
                message: visible[i].isSlot
                    ? 'Offene Stelle · ${visible[i].roleLabel}'
                    : '${visible[i].name.isEmpty ? "Teammitglied" : visible[i].name} · ${visible[i].roleLabel}',
                child: Container(
                  width: size,
                  height: size,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: ringColor,
                    shape: BoxShape.circle,
                  ),
                  child: UserAvatar(
                    avatarUrl: visible[i].avatarUrl,
                    name: visible[i].isSlot ? '' : visible[i].name,
                    radius: (size - 4) / 2,
                    isOpenSlot: visible[i].isSlot,
                    backgroundColor: palette[i % palette.length],
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ),
          if (overflow > 0)
            Positioned(
              left: visible.length * step,
              child: Container(
                width: size,
                height: size,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: ringColor,
                  shape: BoxShape.circle,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '+$overflow',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
