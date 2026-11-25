import 'package:flutter/material.dart';
import 'package:season_planner/core/data/enums/event_role_enum.dart';
import 'package:season_planner/core/data/enums/event_status_enum.dart';
import 'package:season_planner/core/data/models/event_model.dart';
import 'package:season_planner/core/data/models/role_document_model.dart';
import 'package:season_planner/core/data/models/team_role_model.dart';
import 'package:season_planner/core/data/models/timesheet_model.dart';
import 'package:season_planner/core/services/role_document_service.dart';
import 'package:season_planner/core/services/timesheet_service.dart';
import 'package:season_planner/core/theme.dart';
import 'package:season_planner/core/widgets/checklist_runner_view.dart';
import 'package:season_planner/core/widgets/markdown_document_view.dart';
import 'package:season_planner/core/widgets/timesheet_runner_view.dart';
import 'package:season_planner/core/widgets/ux_components.dart';
import 'package:season_planner/user/data/models/flight_school_model_user_view.dart';

/// Zeigt in `EventDetailView` und `CurrentEventView` automatisch die zur
/// zugewiesenen Rolle gehörenden Arbeitsanweisungen und die interaktive Checkliste an.
class EventRoleDocsSection extends StatefulWidget {
  final Event event;
  final FlightSchoolUserView flightSchool;
  final String userId;

  const EventRoleDocsSection({
    super.key,
    required this.event,
    required this.flightSchool,
    required this.userId,
  });

  @override
  State<EventRoleDocsSection> createState() => _EventRoleDocsSectionState();
}

class _EventRoleDocsSectionState extends State<EventRoleDocsSection> {
  final _service = RoleDocumentService();
  final _timesheetService = TimesheetService();
  bool _loading = true;
  List<RoleDocument> _instructions = [];
  RoleDocument? _checklist;
  ChecklistCompletion? _completion;
  EventTimesheet? _timesheet;

  bool get _showTimesheet {
    if (widget.event.status == EventStatusEnum.canceled) return false;
    if (!widget.flightSchool.userRequiresTimesheet) return false;
    return !DateTime.now().isBefore(widget.event.startTime);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant EventRoleDocsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.event.id != widget.event.id ||
        oldWidget.event.role != widget.event.role) {
      _load();
    }
  }

  TeamRole? _matchingRole() {
    final roleName = widget.event.role.trim();
    if (roleName.isEmpty) return null;
    final normalized = EventRoleEnum.displayLabel(roleName).toLowerCase();
    for (final r in widget.flightSchool.teamRoles) {
      if (r.name.toLowerCase() == roleName.toLowerCase() ||
          r.name.toLowerCase() == normalized) {
        return r;
      }
    }
    return null;
  }

  Future<void> _load() async {
    final role = _matchingRole();
    final hasRoleDocs = role != null &&
        ((role.checklistId != null && role.checklistId!.isNotEmpty) ||
            role.instructionIds.isNotEmpty);
    final needTimesheet = _showTimesheet;

    if (!hasRoleDocs && !needTimesheet) {
      if (mounted) {
        setState(() {
          _instructions = [];
          _checklist = null;
          _completion = null;
          _timesheet = null;
          _loading = false;
        });
      }
      return;
    }

    setState(() => _loading = true);
    final instructions = hasRoleDocs
        ? await _service.getDocumentsByIds(role.instructionIds)
        : <RoleDocument>[];
    final checklist =
        (hasRoleDocs && role.checklistId != null && role.checklistId!.isNotEmpty)
            ? await _service.getDocumentById(role.checklistId!)
            : null;
    final completion = checklist != null
        ? await _service.getCompletionForAssignment(widget.event.id)
        : null;
    final timesheet = needTimesheet
        ? await _timesheetService.getTimesheetForAssignment(widget.event.id)
        : null;

    if (!mounted) return;
    setState(() {
      _instructions = instructions;
      _checklist = checklist;
      _completion = completion;
      _timesheet = timesheet;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final showTimesheet = _showTimesheet;
    if (_loading) {
      final role = _matchingRole();
      final hasRoleDocs = role != null &&
          ((role.checklistId != null && role.checklistId!.isNotEmpty) ||
              role.instructionIds.isNotEmpty);
      if (!hasRoleDocs && !showTimesheet) {
        return const SizedBox.shrink();
      }
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }

    if (_instructions.isEmpty && _checklist == null && !showTimesheet) {
      return const SizedBox.shrink();
    }

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SoftCard(
      radius: 20,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const TintedIconBadge(
                icon: Icons.assignment_outlined,
                iconColor: AppTheme.primaryColor,
                backgroundColor: AppTheme.primaryTint,
                size: 34,
                iconSize: 18,
                radius: 10,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Aufgaben & Anweisungen (${widget.event.roleLabel})',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
          if (showTimesheet) ...[
            const SizedBox(height: 12),
            _buildTimesheetTile(context),
          ],
          if (_checklist != null) ...[
            const SizedBox(height: 12),
            _buildChecklistTile(context, _checklist!),
          ],
          if (_instructions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'ARBEITSANWEISUNGEN',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            ..._instructions.map((doc) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: isDark
                      ? AppTheme.darkCardElevated
                      : AppTheme.backgroundColor,
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MarkdownDocumentView(document: doc),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 11,
                      ),
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
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              doc.title,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 20,
                            color: cs.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildTimesheetTile(BuildContext context) {
    final sheet = _timesheet;
    final isSubmitted = sheet?.isSubmitted == true;
    final isEnded = widget.event.endTime.isBefore(DateTime.now());
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color accent;
    final Color bg;
    final String statusText;
    final IconData icon;

    if (isSubmitted) {
      accent = AppTheme.successColor;
      bg = AppTheme.successBg;
      statusText =
          'Abgesendet · ${sheet!.formattedTotalHours} (${sheet.activeDays} ${sheet.activeDays == 1 ? "Tag" : "Tage"})';
      icon = Icons.verified_outlined;
    } else if (isEnded) {
      accent = AppTheme.dangerColor;
      bg = AppTheme.dangerBg;
      statusText = sheet != null
          ? 'Entwurf (${sheet.formattedTotalHours}) · Bitte jetzt absenden'
          : 'Fällig – Arbeitszeiten eintragen & unterschreiben';
      icon = Icons.access_time_filled_rounded;
    } else if (sheet != null) {
      accent = AppTheme.infoColor;
      bg = AppTheme.infoBg;
      statusText = 'Entwurf gespeichert · ${sheet.formattedTotalHours}';
      icon = Icons.access_time_rounded;
    } else {
      accent = AppTheme.primaryColor;
      bg = AppTheme.primaryTint;
      statusText = 'Bereit zum Eintragen der täglichen Arbeitszeiten';
      icon = Icons.access_time_rounded;
    }

    return Material(
      color: isDark ? accent.withValues(alpha: 0.14) : bg,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TimesheetRunnerView(
                event: widget.event,
                userId: widget.userId,
                initialTimesheet: _timesheet,
              ),
            ),
          );
          if (mounted) _load();
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              TintedIconBadge(
                icon: icon,
                iconColor: accent,
                backgroundColor:
                    isDark ? accent.withValues(alpha: 0.22) : Colors.white,
                size: 38,
                iconSize: 20,
                radius: 11,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Stundenzettel',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: accent),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChecklistTile(BuildContext context, RoleDocument checklist) {
    final comp = _completion;
    final total = comp?.totalCount ?? checklist.parseChecklistItems().length;
    final checked = comp?.checkedCount ?? 0;
    final isSigned = comp?.isSigned == true;
    final isComplete = comp?.isComplete == true;
    final now = DateTime.now();
    final editUnlock = widget.event.startTime.subtract(const Duration(hours: 24));
    final canEdit = !now.isBefore(editUnlock);
    final canSign = !now.isBefore(widget.event.startTime);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color accent;
    final Color bg;
    final String statusText;
    final IconData icon;

    if (isSigned && isComplete) {
      accent = AppTheme.successColor;
      bg = AppTheme.successBg;
      statusText = 'Vollständig unterschrieben ($checked/$total)';
      icon = Icons.verified_outlined;
    } else if (isSigned && !isComplete) {
      accent = AppTheme.warningColor;
      bg = AppTheme.warningBg;
      statusText = 'Mit offenen Punkten unterschrieben ($checked/$total)';
      icon = Icons.warning_amber_rounded;
    } else if (!canEdit) {
      accent = AppTheme.infoColor;
      bg = AppTheme.infoBg;
      statusText =
          'Vorschau ($total Punkte) · Bearbeitung ab 24 Std. vor Beginn';
      icon = Icons.visibility_outlined;
    } else if (!canSign) {
      accent = AppTheme.infoColor;
      bg = AppTheme.infoBg;
      statusText = checked > 0
          ? 'In Bearbeitung ($checked/$total) · Unterschrift ab Beginn'
          : 'Bereit zum Abhaken ($total Punkte) · Unterschrift ab Beginn';
      icon = Icons.checklist_rounded;
    } else if (checked > 0) {
      accent = AppTheme.infoColor;
      bg = AppTheme.infoBg;
      statusText = 'In Bearbeitung: $checked von $total erledigt';
      icon = Icons.checklist_rounded;
    } else {
      accent = AppTheme.primaryColor;
      bg = AppTheme.primaryTint;
      statusText = 'Offen ($total Punkte) – zum Abhaken tippen';
      icon = Icons.checklist_rounded;
    }

    return Material(
      color: isDark ? accent.withValues(alpha: 0.14) : bg,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChecklistRunnerView(
                event: widget.event,
                userId: widget.userId,
                checklist: checklist,
                initialCompletion: _completion,
              ),
            ),
          );
          if (mounted) _load();
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              TintedIconBadge(
                icon: icon,
                iconColor: accent,
                backgroundColor:
                    isDark ? accent.withValues(alpha: 0.22) : Colors.white,
                size: 38,
                iconSize: 20,
                radius: 11,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      checklist.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}
