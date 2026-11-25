import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/core/data/enums/event_role_enum.dart';
import 'package:season_planner/core/data/enums/event_status_enum.dart';
import 'package:season_planner/core/data/enums/event_user_status_enum.dart';
import 'package:season_planner/core/data/models/event_model.dart';
import 'package:season_planner/core/data/models/event_template_model.dart';
import 'package:season_planner/core/data/models/planning_period_model.dart';
import 'package:season_planner/core/data/models/role_document_model.dart';
import 'package:season_planner/core/services/event_template_service.dart';
import 'package:season_planner/core/services/planning_service.dart';
import 'package:season_planner/core/services/qualification_service.dart';
import 'package:season_planner/core/services/role_document_service.dart';
import 'package:season_planner/core/services/security_privacy_service.dart';
import 'package:season_planner/core/services/tandem_service.dart';
import 'package:season_planner/core/theme.dart';
import 'package:season_planner/core/widgets/checklist_runner_view.dart';
import 'package:season_planner/core/widgets/user_avatar.dart';
import 'package:season_planner/core/widgets/ux_components.dart';
import 'package:season_planner/fsAdmin/data/models/flight_school_model_flight_school_view.dart';
import 'package:season_planner/fsAdmin/data/models/user_summary_flight_school_view.dart';
import 'package:season_planner/fsAdmin/flight_school_provider.dart';
import 'package:season_planner/fsAdmin/services/flight_school_service.dart';

class EventUpsertView extends StatefulWidget {
  final Event? initialEvent;
  final DateTime? initialDate;
  final Event? duplicateFromEvent;
  final Future<void> Function(Event event) onSave;
  final Future<bool> Function(Event event)? onDelete;
  final void Function(Event event)? onDuplicate;

  const EventUpsertView({
    super.key,
    required this.initialEvent,
    this.initialDate,
    this.duplicateFromEvent,
    required this.onSave,
    this.onDelete,
    this.onDuplicate,
  });

  @override
  State<EventUpsertView> createState() => _EventUpsertViewState();
}

class _EventUpsertViewState extends State<EventUpsertView> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _identifierCtrl;
  late final TextEditingController _locationCtrl;
  late final TextEditingController _notesCtrl;

  late DateTime _start;
  late DateTime _end;
  late EventStatusEnum _status;

  // Event-Vorlagen & Dauer-Sperre
  List<EventTemplate> _templates = [];
  bool _loadingTemplates = false;
  bool _savingTemplate = false;
  bool _templateDialogOpen = false;
  String? _selectedTemplateId;
  bool _lockDuration = false;
  Duration? _lockedDuration;

  late List<TeamMember> _team;
  late final Set<String> _persistedTeamKeys;

  // Dirty-State Ausgangswerte (1.3)
  late final String _origName;
  late final String _origIdentifier;
  late final String _origLocation;
  late final String _origNotes;
  late final DateTime _origStart;
  late final DateTime _origEnd;
  late final EventStatusEnum _origStatus;
  late final String _origTeamSignature;

  // Verfügbarkeiten & Blackouts der Schule für Zeitraum-Checks
  List<AvailabilitySubmission> _schoolSubmissions = [];

  // Schulübergreifende Doppelbesetzungen (DSGVO-datensparsam vom Server)
  Map<String, List<String>> _crossSchoolConflictsByUserId = {};
  int _crossConflictSeq = 0;

  // Checklisten-Stände & Unterschriften je assignmentId (nur bei Bearbeitung)
  Map<String, ChecklistCompletion> _completionsByAssignmentId = {};

  bool _saving = false;
  bool get isEdit => widget.initialEvent != null;

  @override
  void initState() {
    super.initState();
    final e = widget.initialEvent;
    final dup = widget.duplicateFromEvent;

    if (e != null) {
      _nameCtrl = TextEditingController(text: e.displayName);
      _identifierCtrl = TextEditingController(text: e.identifier);
      _locationCtrl = TextEditingController(text: e.location);
      _notesCtrl = TextEditingController(text: e.notes);
      _start = e.startTime;
      _end = e.endTime;
      _status = e.status;
      _team = List<TeamMember>.from(e.team);
    } else if (dup != null) {
      _nameCtrl = TextEditingController(text: '${dup.displayName} (Kopie)');
      _identifierCtrl = TextEditingController(text: dup.identifier);
      _locationCtrl = TextEditingController(text: dup.location);
      _notesCtrl = TextEditingController(text: dup.notes);
      final duration = dup.endTime.difference(dup.startTime);
      final nextStart = dup.startTime.add(const Duration(days: 7));
      _start = nextStart;
      _end = nextStart.add(
        duration.inMinutes > 0 ? duration : const Duration(hours: 2),
      );
      _status = EventStatusEnum.scheduled;
      // Team-Struktur kopieren: direkt zugewiesene Personen sind verbindlich eingeteilt
      _team = dup.team.map((tm) {
        if (tm.isSlot) {
          return TeamMember(
            userId: 'slot_${DateTime.now().microsecondsSinceEpoch}_${tm.role}',
            name: 'Offene Stelle',
            role: tm.role,
            status: EventUserStatusEnum.open.name,
          );
        }
        return TeamMember(
          userId: tm.userId,
          name: tm.name,
          role: tm.role,
          status: EventUserStatusEnum.accepted_flight_school.name,
        );
      }).toList();
    } else {
      final baseDay = widget.initialDate ?? DateTime.now();
      _nameCtrl = TextEditingController();
      _identifierCtrl = TextEditingController();
      _locationCtrl = TextEditingController();
      _notesCtrl = TextEditingController();
      if (widget.initialDate != null) {
        _start = DateTime(baseDay.year, baseDay.month, baseDay.day, 9, 0);
        _end = DateTime(baseDay.year, baseDay.month, baseDay.day, 17, 0);
      } else {
        final nextHour = DateTime.now().add(const Duration(hours: 1));
        _start = DateTime(
          nextHour.year,
          nextHour.month,
          nextHour.day,
          nextHour.hour,
          0,
        );
        _end = _start.add(const Duration(hours: 2));
      }
      _status = EventStatusEnum.scheduled;
      _team = [];
    }

    _persistedTeamKeys =
        isEdit ? _team.map(_teamKey).toSet() : <String>{};

    // Ausgangszustand für Dirty-Check sichern
    _origName = _nameCtrl.text;
    _origIdentifier = _identifierCtrl.text;
    _origLocation = _locationCtrl.text;
    _origNotes = _notesCtrl.text;
    _origStart = _start;
    _origEnd = _end;
    _origStatus = _status;
    _origTeamSignature = _teamSignature(_team);

    _loadSubmissions();
    _loadTemplates();
    _loadCrossSchoolConflicts();
    if (e != null) {
      _loadChecklistCompletions(e.eventDocId ?? e.id);
    }
  }

  String _teamSignature(List<TeamMember> list) =>
      list.map((t) => '${t.userId}|${t.role}|${t.status}').join(';');

  bool get _isDirty =>
      _nameCtrl.text != _origName ||
      _identifierCtrl.text != _origIdentifier ||
      _locationCtrl.text != _origLocation ||
      _notesCtrl.text != _origNotes ||
      _start != _origStart ||
      _end != _origEnd ||
      _status != _origStatus ||
      _teamSignature(_team) != _origTeamSignature;

  Future<void> _loadTemplates() async {
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null) return;
    setState(() => _loadingTemplates = true);
    final list = await EventTemplateService().listTemplates(fs.id);
    if (!mounted) return;
    setState(() {
      _templates = list;
      _loadingTemplates = false;
    });
  }

  void _applyTemplate(EventTemplate tpl) {
    final nowMicros = DateTime.now().microsecondsSinceEpoch;
    final newStart = DateTime(
      _start.year,
      _start.month,
      _start.day,
      tpl.defaultStartHour,
      tpl.defaultStartMinute,
    );
    final lockedDur = tpl.duration;
    setState(() {
      _selectedTemplateId = tpl.id;
      _nameCtrl.text = tpl.displayName;
      _identifierCtrl.text = tpl.identifier;
      _locationCtrl.text = tpl.location;
      _notesCtrl.text = tpl.notes;
      _status = tpl.status;
      _start = newStart;
      _end = newStart.add(lockedDur);
      _lockDuration = true;
      _lockedDuration = lockedDur;
      _team = List.generate(
        tpl.roles.length,
        (i) => TeamMember(
          userId: 'slot_${nowMicros}_$i',
          name: 'Offene Stelle',
          role: tpl.roles[i],
          status: EventUserStatusEnum.open.name,
        ),
      );
    });
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          'Vorlage „${tpl.templateName}“ geladen (${tpl.durationLabel} gesperrt, ${tpl.roles.length} offene Rolle(n)).',
        ),
      ),
    );
  }

  Future<void> _saveAsTemplateDialog() async {
    if (_templateDialogOpen || _savingTemplate || _saving) return;
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null) return;

    if (!_end.isAfter(_start)) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Bitte zuerst einen gültigen Zeitraum wählen.'),
        ),
      );
      return;
    }

    final duration = _end.difference(_start);
    final roles = _team.map((t) => t.role).toList();
    final initialName = _nameCtrl.text.trim().isNotEmpty
        ? _nameCtrl.text.trim()
        : 'Neue Vorlage';

    _templateDialogOpen = true;
    String? templateName;
    try {
      templateName = await showDialog<String>(
        context: context,
        builder: (_) => _SaveTemplateDialog(
          initialName: initialName,
          durationLabel: formatDurationCompact(_start, _end),
          startTimeLabel: _fmtTime(_start),
          roles: roles,
        ),
      );
    } finally {
      _templateDialogOpen = false;
    }

    if (!mounted || templateName == null || templateName.trim().isEmpty) return;
    final trimmedName = templateName.trim();

    setState(() => _savingTemplate = true);
    try {
      final created = await EventTemplateService().createTemplate(
        flightSchoolId: fs.id,
        templateName: trimmedName,
        displayName: _nameCtrl.text.trim().isNotEmpty
            ? _nameCtrl.text.trim()
            : trimmedName,
        identifier: _identifierCtrl.text.trim(),
        location: _locationCtrl.text.trim(),
        notes: _notesCtrl.text.trim(),
        status: _status,
        durationMinutes: duration.inMinutes,
        defaultStartHour: _start.hour,
        defaultStartMinute: _start.minute,
        roles: roles,
      );
      await _loadTemplates();
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            created != null
                ? 'Vorlage „$trimmedName“ gespeichert.'
                : 'Vorlage konnte nicht gespeichert werden.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingTemplate = false);
    }
  }

  Future<void> _openTemplatePickerSheet() async {
    if (_templates.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final cs = Theme.of(ctx).colorScheme;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.65,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Event-Vorlage auswählen',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Übernimmt Daten, sperrt die Dauer (Ende passt sich automatisch dem Startdatum an) und legt alle Rollen als offene Stellen an.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_templates.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'Keine Vorlagen vorhanden.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: _templates.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, idx) {
                            final tpl = _templates[idx];
                            final selected = tpl.id == _selectedTemplateId;
                            return Card(
                              margin: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: selected
                                      ? cs.primary
                                      : cs.outlineVariant,
                                  width: selected ? 1.5 : 1,
                                ),
                              ),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor:
                                      cs.primaryContainer.withValues(alpha: 0.7),
                                  child: Icon(
                                    Icons.bookmarks_outlined,
                                    color: cs.primary,
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  tpl.templateName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  [
                                    tpl.durationLabel,
                                    if (tpl.location.isNotEmpty) tpl.location,
                                    '${tpl.roles.length} Rolle(n)',
                                  ].join(' · '),
                                  style: const TextStyle(fontSize: 12.5),
                                ),
                                trailing: IconButton(
                                  tooltip: 'Vorlage löschen',
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: AppTheme.dangerColor,
                                    size: 20,
                                  ),
                                  onPressed: () async {
                                    final ok = await EventTemplateService()
                                        .deleteTemplate(tpl);
                                    if (ok) {
                                      setState(() {
                                        _templates.removeWhere(
                                          (t) => t.id == tpl.id,
                                        );
                                        if (_selectedTemplateId == tpl.id) {
                                          _selectedTemplateId = null;
                                        }
                                      });
                                      setSheetState(() {});
                                    }
                                  },
                                ),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _applyTemplate(tpl);
                                },
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _loadChecklistCompletions(String eventId) async {
    final list = await RoleDocumentService().listCompletionsForEvent(eventId);
    if (!mounted) return;
    setState(() {
      _completionsByAssignmentId = {
        for (final c in list) c.assignmentId: c,
      };
    });
  }

  Future<void> _loadSubmissions() async {
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null) return;
    final list = await PlanningService().listSchoolSubmissions(fs.id);
    if (!mounted) return;
    setState(() => _schoolSubmissions = list);
  }

  Future<void> _loadCrossSchoolConflicts() async {
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null || fs.members.isEmpty || !_end.isAfter(_start)) return;
    final seq = ++_crossConflictSeq;
    final userIds = fs.members
        .expand((m) => [m.id, if (m.userRowId.isNotEmpty) m.userRowId])
        .toSet()
        .toList();
    final map = await SecurityPrivacyService().checkCrossSchoolConflicts(
      flightSchoolId: fs.id,
      userIds: userIds,
      startTime: _start,
      endTime: _end,
      ignoreEventId: widget.initialEvent?.id,
      otherSchoolsOnly: true,
    );
    if (!mounted || seq != _crossConflictSeq) return;
    setState(() => _crossSchoolConflictsByUserId = map);
  }

  List<String> _crossSchoolConflictsFor(
    String userId,
    FlightSchoolModelFlightSchoolView fs,
  ) {
    final out = <String>{};
    final direct = _crossSchoolConflictsByUserId[userId];
    if (direct != null) out.addAll(direct);
    final member = fs.findMemberByAnyId(userId);
    if (member != null) {
      final byAuth = _crossSchoolConflictsByUserId[member.id];
      if (byAuth != null) out.addAll(byAuth);
      if (member.userRowId.isNotEmpty) {
        final byRow = _crossSchoolConflictsByUserId[member.userRowId];
        if (byRow != null) out.addAll(byRow);
      }
    }
    return out.toList();
  }

  List<String> _allConflictLabelsFor(
    String userId,
    FlightSchoolModelFlightSchoolView fs,
  ) {
    final evConflicts = _conflictingEventsFor(userId, fs);
    final tdConflict = _tandemConflictFor(userId, fs);
    final cross = _crossSchoolConflictsFor(userId, fs);
    return <String>[
      ...evConflicts.map((e) => 'Event „${e.displayName}“'),
      if (tdConflict != null) tdConflict,
      ...cross,
    ];
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _identifierCtrl.dispose();
    _locationCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  String _teamKey(TeamMember tm) => "${tm.userId}|${tm.role}|${tm.status}";
  bool _isPersisted(TeamMember tm) => _persistedTeamKeys.contains(_teamKey(tm));
  EventUserStatusEnum _statusOf(TeamMember tm) =>
      EventUserStatusLabelX.parse(tm.status);

  bool _isOpenSlot(TeamMember tm) =>
      tm.userId.isEmpty || tm.userId.startsWith("slot_");

  String _resolveAvatarUrl(TeamMember tm, List<UserSummary> members) {
    if (_isOpenSlot(tm)) return '';
    if (tm.avatarUrl.trim().isNotEmpty) return tm.avatarUrl.trim();
    final hit = members.where((m) => m.matchesId(tm.userId)).toList();
    if (hit.isNotEmpty) return hit.first.avatarUrl;
    return '';
  }

  String _resolveName(TeamMember tm, List<UserSummary> members) {
    if (tm.name.trim().isNotEmpty) return tm.name.trim();
    if (_isOpenSlot(tm)) return "Offene Stelle";
    final hit = members.where((m) => m.matchesId(tm.userId)).toList();
    if (hit.isNotEmpty && hit.first.name.trim().isNotEmpty) {
      return hit.first.name.trim();
    }
    return "Teammitglied";
  }

  ({bool hasAvailability, bool hasBlackout}) _availabilityStatusFor(
    String userId,
  ) {
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    final member = fs?.findMemberByAnyId(userId);
    final userSubs = _schoolSubmissions.where((s) {
      if (s.userId == userId) return true;
      return member != null && member.matchesId(s.userId);
    }).toList();
    final hasBlackout = userSubs.any(
      (s) => s.kind == AvailabilityKind.blackout && s.overlaps(_start, _end),
    );
    final hasAvailability = userSubs.any(
      (s) => s.kind == AvailabilityKind.available && s.overlaps(_start, _end),
    );
    return (hasAvailability: hasAvailability, hasBlackout: hasBlackout);
  }

  String? _tandemConflictFor(
    String userId,
    FlightSchoolModelFlightSchoolView fs,
  ) {
    if (!fs.tandemEnabled || fs.tandemDuties.isEmpty) return null;
    final member = fs.findMemberByAnyId(userId);
    return TandemService.findTandemConflictForEvent(
      userId: member?.id ?? userId,
      userRowId: member?.userRowId,
      eventStart: _start,
      eventEnd: _end,
      tandemDuties: fs.tandemDuties,
    );
  }

  /// Sortiert Mitglieder für die Besetzungs-Dropdowns:
  /// 1) Verfügbar gemeldete (ohne Abwesenheit/Konflikt) immer ganz oben
  /// 2) Neutral ohne Eintrag
  /// 3) Konflikte / Abwesenheiten (Blackout) / Tandem-Doppelbelegungen unten
  List<UserSummary> _sortMembersForAssignment(
    Iterable<UserSummary> source,
    FlightSchoolModelFlightSchoolView fs,
  ) {
    int rank(UserSummary m) {
      final st = _availabilityStatusFor(m.id);
      final hasConflict = _allConflictLabelsFor(m.id, fs).isNotEmpty;
      if (st.hasBlackout) return 4;
      if (st.hasAvailability && !hasConflict) return 0;
      if (st.hasAvailability && hasConflict) return 1;
      if (!hasConflict) return 2;
      return 3;
    }

    final list = source.toList();
    list.sort((a, b) {
      final cmp = rank(a).compareTo(rank(b));
      if (cmp != 0) return cmp;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    return list;
  }

  /// Einheitliche Dropdown-Zeile für die Mitgliedsauswahl:
  /// Im Zeitraum verfügbar gemeldete Mitglieder werden klar grün hinterlegt.
  Widget _buildMemberDropdownRow(
    UserSummary m,
    FlightSchoolModelFlightSchoolView fs,
  ) {
    final st = _availabilityStatusFor(m.id);
    final hasEventConflict = _conflictingEventsFor(m.id, fs).isNotEmpty;
    final tandemConflict = _tandemConflictFor(m.id, fs);
    final crossConflicts = _crossSchoolConflictsFor(m.id, fs);
    final hasConflict =
        hasEventConflict || tandemConflict != null || crossConflicts.isNotEmpty;
    final isAvailable = st.hasAvailability && !st.hasBlackout && !hasConflict;

    final Color? bg =
        (st.hasBlackout || hasConflict)
            ? AppTheme.dangerColor.withValues(alpha: 0.10)
            : isAvailable
            ? AppTheme.successColor.withValues(alpha: 0.16)
            : null;
    final Color? borderColor =
        (st.hasBlackout || hasConflict)
            ? AppTheme.dangerColor.withValues(alpha: 0.35)
            : isAvailable
            ? AppTheme.successColor.withValues(alpha: 0.45)
            : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration:
          bg != null
              ? BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: borderColor!),
              )
              : null,
      child: Row(
        children: [
          UserAvatar(
            avatarUrl: m.avatarUrl,
            name: m.displayName,
            radius: 12,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              m.displayName,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: isAvailable ? FontWeight.w700 : FontWeight.w500,
                color: hasConflict ? AppTheme.dangerColor : null,
              ),
            ),
          ),
          if (tandemConflict != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.dangerColor.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'Tandem',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.dangerColor,
                ),
              ),
            ),
          ] else if (hasEventConflict || crossConflicts.isNotEmpty) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.dangerColor.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                hasEventConflict ? 'Event' : 'Verplant',
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.dangerColor,
                ),
              ),
            ),
          ],
          if (st.hasBlackout) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.dangerColor.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'Abwesend',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.dangerColor,
                ),
              ),
            ),
          ] else if (isAvailable) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.successColor.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'Verfügbar',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.successColor,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Prüft Doppelbuchungen derselben Person in zeitgleichen Events der Flugschule (1.8).
  List<Event> _conflictingEventsFor(
    String userId,
    FlightSchoolModelFlightSchoolView fs,
  ) {
    final member = fs.findMemberByAnyId(userId);
    final currentEventId = widget.initialEvent?.id;
    final conflicts = <Event>[];
    for (final ev in fs.events) {
      if (currentEventId != null && ev.id == currentEventId) continue;
      if (ev.status == EventStatusEnum.canceled) continue;
      final overlapsTime =
          ev.startTime.isBefore(_end) && ev.endTime.isAfter(_start);
      if (!overlapsTime) continue;

      final booked = ev.team.any((t) {
        if (t.isSlot) return false;
        final st = EventUserStatusLabelX.parse(t.status);
        if (st == EventUserStatusEnum.denied_user ||
            st == EventUserStatusEnum.denied_flight_school) {
          return false;
        }
        return t.userId == userId ||
            (member != null && member.matchesId(t.userId));
      });
      if (booked) conflicts.add(ev);
    }
    return conflicts;
  }

  // ----------------- Aktionen -----------------

  Future<void> _confirmDiscard() async {
    // Nur fragen, wenn tatsächlich Änderungen vorgenommen wurden (1.3)
    if (!_isDirty) {
      if (mounted) Navigator.pop(context);
      return;
    }

    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Änderungen verwerfen?"),
        content: const Text("Alle ungespeicherten Änderungen gehen verloren."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Abbrechen"),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.dangerColor,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Verwerfen"),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.pop(context);
  }

  Future<void> _confirmDelete() async {
    if (!isEdit || widget.onDelete == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Event dauerhaft löschen?"),
        content: const Text(
          "Das Event wird inklusive aller Team-Zuweisungen vollständig gelöscht. Alternativ kannst du den Status auf „Abgesagt“ setzen.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Abbrechen"),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.dangerColor,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Endgültig löschen"),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      final ok = await widget.onDelete!(widget.initialEvent!);
      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text("Event wurde gelöscht.")),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text("Löschen fehlgeschlagen.")),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Kombiniertes Datum- & Uhrzeit-Bottom-Sheet in einem einzigen Schritt (1.1 & Runde 2: 1.2/4.1).
  Future<DateTime?> _pickDateTimeSheet({
    required DateTime initial,
    required String title,
  }) async {
    return showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DateTimePickerSheet(
        initial: initial,
        title: title,
      ),
    );
  }

  Future<void> _pickStart() async {
    final picked = await _pickDateTimeSheet(
      initial: _start,
      title: 'Beginn wählen',
    );
    if (!mounted || picked == null) return;
    final previousDuration = _end.difference(_start);
    setState(() {
      _start = picked;
      if (_lockDuration && _lockedDuration != null) {
        // Dauer ist durch Vorlage gesperrt → Enddatum automatisch mitverschieben
        _end = _start.add(_lockedDuration!);
      } else if (!_end.isAfter(_start)) {
        _end = _start.add(
          previousDuration.inMinutes > 0
              ? previousDuration
              : const Duration(hours: 2),
        );
      }
    });
    _loadCrossSchoolConflicts();
  }

  Future<void> _pickEnd() async {
    if (_lockDuration) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text(
            'Die Dauer ist durch die Vorlage gesperrt. Tippe auf das Schloss-Symbol neben der Dauer, um sie zu entsperren.',
          ),
        ),
      );
      return;
    }
    final picked = await _pickDateTimeSheet(
      initial: _end,
      title: 'Ende wählen',
    );
    if (!mounted || picked == null) return;
    setState(() => _end = picked);
    _loadCrossSchoolConflicts();
  }

  void _toggleDurationLock() {
    setState(() {
      if (_lockDuration) {
        _lockDuration = false;
      } else {
        final dur = _end.difference(_start);
        _lockedDuration =
            dur.inMinutes > 0 ? dur : const Duration(hours: 2);
        _lockDuration = true;
      }
    });
  }

  // ----------------- Teammitglied hinzufügen (inkl. Verfügbarkeit, Doppelbuchung & Qualifikations-Check!) -----------------

  Future<void> _addTeamMemberDialog() async {
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null) return;

    final roleNames = fs.availableRoleNames;
    String selectedRole = roleNames.first;
    String? selectedMemberId;
    String? qualWarning;
    bool checkingQual = false;
    int qualCheckSeq = 0;

    final result = await showDialog<TeamMember>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final availableMembers = _sortMembersForAssignment(
            fs.members.where((m) => !_team.any((t) => t.userId == m.id)),
            fs,
          );
          final selectedMember = selectedMemberId == null
              ? null
              : availableMembers
                  .where((m) => m.id == selectedMemberId)
                  .firstOrNull;
          if (selectedMemberId != null && selectedMember == null) {
            selectedMemberId = null;
          }

          Future<void> runQualCheck(UserSummary? member, String role) async {
            final seq = ++qualCheckSeq;
            if (member == null) {
              setLocal(() {
                checkingQual = false;
                qualWarning = null;
              });
              return;
            }
            setLocal(() => checkingQual = true);
            final res = await QualificationService().checkQualification(
              userId: member.id,
              flightSchoolId: fs.id,
              roleName: role,
              schoolRoles: fs.teamRoles,
              schoolQualifications: fs.qualifications,
              memberQualificationIds: member.qualificationIds,
            );
            if (!ctx.mounted || seq != qualCheckSeq) return;
            setLocal(() {
              checkingQual = false;
              qualWarning = res.isFullyQualified ? null : res.summaryText;
            });
          }

          final availStatus = selectedMember != null
              ? _availabilityStatusFor(selectedMember.id)
              : null;
          final conflicts = selectedMember != null
              ? _conflictingEventsFor(selectedMember.id, fs)
              : const <Event>[];
          final tandemConflict = selectedMember != null
              ? _tandemConflictFor(selectedMember.id, fs)
              : null;
          final crossConflicts = selectedMember != null
              ? _crossSchoolConflictsFor(selectedMember.id, fs)
              : const <String>[];
          final allConflictLabels = <String>[
            ...conflicts.map((e) => 'Event „${e.displayName}“'),
            if (tandemConflict != null) tandemConflict,
            ...crossConflicts,
          ];
          final doubleBooked = allConflictLabels.isNotEmpty;

          return AlertDialog(
            title: const Text("Team-Eintrag hinzufügen"),
            content: SizedBox(
              width: 450,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: "Mitglied (optional)",
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          value: selectedMemberId,
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Row(
                                children: [
                                  Icon(Icons.person_add_alt, size: 17),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      "Offene Stelle (Open Opportunity)",
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ...availableMembers.map((m) {
                              return DropdownMenuItem<String?>(
                                value: m.id,
                                child: _buildMemberDropdownRow(m, fs),
                              );
                            }),
                          ],
                          onChanged: (v) {
                            final nextMember = v == null
                                ? null
                                : availableMembers
                                    .where((m) => m.id == v)
                                    .firstOrNull;
                            setLocal(() {
                              selectedMemberId = v;
                              qualWarning = null;
                            });
                            runQualCheck(nextMember, selectedRole);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: "Teamrolle",
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedRole,
                          isExpanded: true,
                          items: roleNames
                              .map(
                                (r) =>
                                    DropdownMenuItem(value: r, child: Text(r)),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            setLocal(() => selectedRole = v);
                            runQualCheck(selectedMember, v);
                          },
                        ),
                      ),
                    ),
                    if (tandemConflict != null) ...[
                      const SizedBox(height: 10),
                      _NoticeBanner(
                        icon: Icons.warning_amber_rounded,
                        color: AppTheme.dangerColor,
                        text:
                            'Achtung Doppelbesetzung: Mitglied ist zeitgleich bereits als Tandempilot eingetragen ($tandemConflict). Anfragen ist deaktiviert – bitte direkt fest einteilen.',
                      ),
                    ],
                    if (conflicts.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _NoticeBanner(
                        icon: Icons.event_repeat,
                        color: AppTheme.dangerColor,
                        text:
                            'Achtung Doppelbesetzung: Mitglied ist zeitgleich bereits eingeplant in „${conflicts.map((e) => e.displayName).join(', ')}“. Anfragen ist deaktiviert – bitte direkt fest einteilen.',
                      ),
                    ],
                    if (crossConflicts.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _NoticeBanner(
                        icon: Icons.warning_amber_rounded,
                        color: AppTheme.dangerColor,
                        text:
                            'Achtung Doppelbesetzung (andere Flugschule): ${crossConflicts.join(' · ')}. Anfragen ist deaktiviert – bitte direkt fest einteilen.',
                      ),
                    ],
                    if (availStatus != null && availStatus.hasBlackout) ...[
                      const SizedBox(height: 10),
                      const _NoticeBanner(
                        icon: Icons.event_busy,
                        color: AppTheme.dangerColor,
                        text:
                            'Achtung: Mitglied hat für diesen Zeitraum eine Abwesenheit (Blackout) eingetragen!',
                      ),
                    ],
                    if (checkingQual)
                      const Padding(
                        padding: EdgeInsets.only(top: 10),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                    if (qualWarning != null) ...[
                      const SizedBox(height: 10),
                      _NoticeBanner(
                        icon: Icons.warning_amber_rounded,
                        color: AppTheme.warningColor,
                        text:
                            'Qualifikationshinweis: $qualWarning\n(Zuweisung ist im Notfall trotzdem möglich.)',
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Abbrechen"),
              ),
              if (selectedMember != null)
                Tooltip(
                  message: doubleBooked
                      ? 'Bei Doppelbesetzung nicht möglich – bitte direkt fest einteilen'
                      : '',
                  child: FilledButton.tonalIcon(
                    onPressed: doubleBooked
                        ? null
                        : () {
                            Navigator.pop(
                              ctx,
                              TeamMember(
                                userId: selectedMember.id,
                                name: selectedMember.displayName,
                                avatarUrl: selectedMember.avatarUrl,
                                role: selectedRole,
                                status: EventUserStatusEnum.pending_user.name,
                              ),
                            );
                          },
                    icon: const Icon(Icons.send_outlined, size: 17),
                    label: const Text("Anfragen"),
                  ),
                ),
              FilledButton(
                onPressed: () async {
                  if (selectedMember == null) {
                    Navigator.pop(
                      ctx,
                      TeamMember(
                        userId:
                            "slot_${DateTime.now().microsecondsSinceEpoch}",
                        name: "Offene Stelle",
                        role: selectedRole,
                        status: EventUserStatusEnum.open.name,
                      ),
                    );
                    return;
                  }
                  if (doubleBooked) {
                    final ok = await showAdminDoubleBookingConfirmDialog(
                      ctx,
                      title: 'Doppelbesetzung bestätigen',
                      message:
                          '${selectedMember.displayName} ist in diesem Zeitraum bereits anderweitig verplant. Möchtest du die Person trotzdem fest einteilen?',
                      conflicts: allConflictLabels,
                      confirmLabel: 'Trotzdem einteilen',
                    );
                    if (!ok || !ctx.mounted) return;
                  }
                  Navigator.pop(
                    ctx,
                    TeamMember(
                      userId: selectedMember.id,
                      name: selectedMember.displayName,
                      avatarUrl: selectedMember.avatarUrl,
                      role: selectedRole,
                      // Admin-Zuweisung ist unabhängig von der Planungsstufe verbindlich
                      status: EventUserStatusEnum.accepted_flight_school.name,
                    ),
                  );
                },
                child: Text(
                  selectedMember == null ? "Hinzufügen" : "Fest einteilen",
                ),
              ),
            ],
          );
        },
      ),
    );

    if (result != null) {
      setState(() => _team.add(result));
    }
  }

  // ----------------- Team-Eintrag bearbeiten (inkl. Swap bestätigen/ablehnen!) -----------------

  Future<void> _openTeamEditDialog({
    required int index,
    required TeamMember tm,
    required List<UserSummary> members,
  }) async {
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null) return;

    final currentStatus = _statusOf(tm);
    final roleNames = <String>{
      ...fs.availableRoleNames,
      EventRoleEnum.displayLabel(tm.role),
    }.toList();

    String role = EventRoleEnum.displayLabel(tm.role);
    if (!roleNames.contains(role)) role = roleNames.first;
    String? selectedUserId = _isOpenSlot(tm) ? null : tm.userId;
    final userReqChange =
        currentStatus == EventUserStatusEnum.user_requests_change;
    final pendingFs =
        currentStatus == EventUserStatusEnum.pending_flight_school;

    final res = await showDialog<String?>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final availableMembers = _sortMembersForAssignment(
            members.where((m) {
              final alreadyInOtherSlot = _team.asMap().entries.any(
                    (e) => e.key != index && e.value.userId == m.id,
                  );
              if (userReqChange && m.id == tm.userId) return false;
              return !alreadyInOtherSlot;
            }),
            fs,
          );

          if (selectedUserId != null &&
              !availableMembers.any((m) => m.id == selectedUserId)) {
            selectedUserId = null;
          }

          final availStatus = selectedUserId != null
              ? _availabilityStatusFor(selectedUserId!)
              : null;
          final conflicts = selectedUserId != null
              ? _conflictingEventsFor(selectedUserId!, fs)
              : const <Event>[];
          final tandemConflict = selectedUserId != null
              ? _tandemConflictFor(selectedUserId!, fs)
              : null;
          final crossConflicts = selectedUserId != null
              ? _crossSchoolConflictsFor(selectedUserId!, fs)
              : const <String>[];
          final allConflictLabels = <String>[
            ...conflicts.map((e) => 'Event „${e.displayName}“'),
            if (tandemConflict != null) tandemConflict,
            ...crossConflicts,
          ];
          final doubleBooked = allConflictLabels.isNotEmpty;

          return AlertDialog(
            title: Text(
              userReqChange ? "Änderungsanfrage" : _resolveName(tm, members),
            ),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (tm.hasOpenSwapRequest) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.swapColor.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Tauschanfrage: ${tm.swapRequestedByName ?? "Teammitglied"} möchte diesen Platz übernehmen.',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                FilledButton.icon(
                                  onPressed: () async {
                                    if (tm.assignmentId != null &&
                                        tm.swapRequestedBy != null) {
                                      final swapUid = tm.swapRequestedBy!;
                                      final swapName =
                                          (tm.swapRequestedByName ?? '')
                                                  .trim()
                                                  .isNotEmpty
                                              ? tm.swapRequestedByName!
                                              : fs.resolveMemberName(swapUid);
                                      final swapMember =
                                          fs.findMemberByAnyId(swapUid);
                                      final swapConflicts = <String>[
                                        ...TandemService
                                            .findMemberEventConflicts(
                                          userId: swapMember?.id ?? swapUid,
                                          userRowId: swapMember?.userRowId,
                                          startTime: _start,
                                          endTime: _end,
                                          events: fs.events,
                                          tandemDuties: fs.tandemDuties,
                                          ignoreEventId:
                                              widget.initialEvent?.id,
                                        ),
                                        ..._crossSchoolConflictsFor(
                                          swapUid,
                                          fs,
                                        ),
                                      ];
                                      if (swapConflicts.isNotEmpty) {
                                        final ok =
                                            await showAdminDoubleBookingConfirmDialog(
                                          ctx,
                                          title: 'Doppelbesetzung bestätigen',
                                          message:
                                              '$swapName ist in diesem Zeitraum bereits anderweitig verplant. Möchtest du den Platztausch trotzdem bestätigen?',
                                          conflicts: swapConflicts,
                                          confirmLabel: 'Trotzdem tauschen',
                                        );
                                        if (!ok || !ctx.mounted) return;
                                      }
                                      await PlanningService().approveSwap(
                                        flightSchoolId: fs.id,
                                        databaseId: fs.databaseId,
                                        tableId:
                                            fs.teamAssignmentsEventsCollectionId,
                                        assignmentId: tm.assignmentId!,
                                        newUserId: swapUid,
                                        newUserName: swapName,
                                        eventName: _nameCtrl.text.trim(),
                                      );
                                      setState(() {
                                        _team[index] = tm.copyWith(
                                          userId: swapUid,
                                          name: swapName,
                                          status: EventUserStatusEnum
                                              .accepted_flight_school.name,
                                          clearSwap: true,
                                        );
                                      });
                                      if (mounted) {
                                        context
                                            .read<FlightSchoolProvider>()
                                            .reloadFlightSchoolInBackground(
                                              FlightSchoolService()
                                                  .getFlightSchool,
                                            );
                                      }
                                      if (ctx.mounted) Navigator.pop(ctx);
                                    }
                                  },
                                  icon: const Icon(Icons.check, size: 16),
                                  label: const Text('Bestätigen'),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    if (tm.assignmentId != null) {
                                      await PlanningService().rejectSwap(
                                        flightSchoolId: fs.id,
                                        databaseId: fs.databaseId,
                                        tableId:
                                            fs.teamAssignmentsEventsCollectionId,
                                        assignmentId: tm.assignmentId!,
                                        eventName: _nameCtrl.text.trim(),
                                      );
                                      setState(() {
                                        _team[index] = tm.copyWith(
                                          swapRequestedBy: '',
                                          swapRequestedByName: '',
                                        );
                                      });
                                      if (ctx.mounted) Navigator.pop(ctx);
                                    }
                                  },
                                  icon: const Icon(Icons.close, size: 16),
                                  label: const Text('Ablehnen'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (userReqChange) ...[
                      _NoticeBanner(
                        icon: Icons.change_circle_outlined,
                        color: AppTheme.warningColor,
                        text:
                            '${_resolveName(tm, members)} bittet um Ersatz. Du kannst den Platz als offene Stelle freigeben oder direkt ein anderes Mitglied zuweisen.',
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (pendingFs) ...[
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () async {
                                if (doubleBooked) {
                                  final ok =
                                      await showAdminDoubleBookingConfirmDialog(
                                    ctx,
                                    title: 'Doppelbesetzung bestätigen',
                                    message:
                                        '${_resolveName(tm, members)} ist in diesem Zeitraum bereits anderweitig verplant. Möchtest du die Bewerbung trotzdem annehmen?',
                                    conflicts: allConflictLabels,
                                    confirmLabel: 'Trotzdem annehmen',
                                  );
                                  if (!ok || !ctx.mounted) return;
                                }
                                setState(() {
                                  _team[index] = tm.copyWith(
                                    status: EventUserStatusEnum
                                        .accepted_flight_school.name,
                                  );
                                });
                                Navigator.pop(ctx);
                              },
                              icon: const Icon(Icons.check),
                              label: const Text("Bewerbung annehmen"),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.dangerColor,
                        ),
                        onPressed: () {
                          setState(() {
                            _team[index] = tm.copyWith(
                              status: EventUserStatusEnum
                                  .denied_flight_school.name,
                            );
                          });
                          Navigator.pop(ctx);
                        },
                        icon: const Icon(Icons.close),
                        label: const Text("Bewerbung ablehnen"),
                      ),
                      const SizedBox(height: 12),
                    ],
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: "Mitglied",
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          value: selectedUserId,
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Row(
                                children: [
                                  Icon(Icons.person_add_alt, size: 17),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      "Offene Stelle (Open Opportunity)",
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ...availableMembers.map(
                              (m) => DropdownMenuItem<String?>(
                                value: m.id,
                                child: _buildMemberDropdownRow(m, fs),
                              ),
                            ),
                          ],
                          onChanged: (v) => setLocal(() => selectedUserId = v),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: "Teamrolle",
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: role,
                          isExpanded: true,
                          items: roleNames
                              .map(
                                (r) =>
                                    DropdownMenuItem(value: r, child: Text(r)),
                              )
                              .toList(),
                          onChanged: (v) => setLocal(() => role = v ?? role),
                        ),
                      ),
                    ),
                    if (tandemConflict != null) ...[
                      const SizedBox(height: 10),
                      _NoticeBanner(
                        icon: Icons.warning_amber_rounded,
                        color: AppTheme.dangerColor,
                        text:
                            'Achtung Doppelbesetzung: Mitglied ist zeitgleich bereits als Tandempilot eingetragen ($tandemConflict). Anfragen ist deaktiviert – bitte direkt übernehmen.',
                      ),
                    ],
                    if (conflicts.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _NoticeBanner(
                        icon: Icons.event_repeat,
                        color: AppTheme.dangerColor,
                        text:
                            'Achtung Doppelbesetzung: Terminüberschneidung mit „${conflicts.map((e) => e.displayName).join(', ')}“. Anfragen ist deaktiviert – bitte direkt übernehmen.',
                      ),
                    ],
                    if (crossConflicts.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _NoticeBanner(
                        icon: Icons.warning_amber_rounded,
                        color: AppTheme.dangerColor,
                        text:
                            'Achtung Doppelbesetzung (andere Flugschule): ${crossConflicts.join(' · ')}. Anfragen ist deaktiviert – bitte direkt übernehmen.',
                      ),
                    ],
                    if (availStatus != null && availStatus.hasBlackout) ...[
                      const SizedBox(height: 10),
                      const _NoticeBanner(
                        icon: Icons.event_busy,
                        color: AppTheme.dangerColor,
                        text:
                            'Achtung: Mitglied hat für diesen Zeitraum eine Abwesenheit (Blackout) eingetragen!',
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.dangerColor,
                ),
                onPressed: () => Navigator.pop(ctx, 'delete'),
                child: const Text("Entfernen"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Abbrechen"),
              ),
              if (selectedUserId != null)
                Tooltip(
                  message: doubleBooked
                      ? 'Bei Doppelbesetzung nicht möglich – bitte direkt übernehmen'
                      : '',
                  child: FilledButton.tonalIcon(
                    onPressed: doubleBooked
                        ? null
                        : () {
                            final m = members
                                .firstWhere((x) => x.id == selectedUserId);
                            setState(() {
                              _team[index] = tm.copyWith(
                                userId: m.id,
                                name: m.displayName,
                                avatarUrl: m.avatarUrl,
                                role: role,
                                status: EventUserStatusEnum.pending_user.name,
                                clearSwap: true,
                              );
                            });
                            Navigator.pop(ctx);
                          },
                    icon: const Icon(Icons.send_outlined, size: 17),
                    label: const Text("Anfragen"),
                  ),
                ),
              FilledButton(
                onPressed: () async {
                  if (selectedUserId == null) {
                    setState(() {
                      _team[index] = tm.copyWith(
                        userId:
                            "slot_${DateTime.now().microsecondsSinceEpoch}",
                        name: "Offene Stelle",
                        avatarUrl: '',
                        role: role,
                        status: EventUserStatusEnum.open.name,
                        clearSwap: true,
                      );
                    });
                    Navigator.pop(ctx);
                    return;
                  }
                  final m = members.firstWhere((x) => x.id == selectedUserId);
                  if (doubleBooked) {
                    final ok = await showAdminDoubleBookingConfirmDialog(
                      ctx,
                      title: 'Doppelbesetzung bestätigen',
                      message:
                          '${m.displayName} ist in diesem Zeitraum bereits anderweitig verplant. Möchtest du die Zuweisung trotzdem übernehmen?',
                      conflicts: allConflictLabels,
                      confirmLabel: 'Trotzdem übernehmen',
                    );
                    if (!ok || !ctx.mounted) return;
                  }
                  final changedPerson = selectedUserId != tm.userId;
                  setState(() {
                    _team[index] = tm.copyWith(
                      userId: m.id,
                      name: m.displayName,
                      avatarUrl: m.avatarUrl,
                      role: role,
                      // Direktes Übernehmen teilt verbindlich ein
                      status: changedPerson
                          ? EventUserStatusEnum.accepted_flight_school.name
                          : tm.status,
                    );
                  });
                  Navigator.pop(ctx);
                },
                child: const Text("Übernehmen"),
              ),
            ],
          );
        },
      ),
    );

    if (res == 'delete') {
      setState(() => _team.removeAt(index));
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_end.isAfter(_start)) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text("Das Ende muss nach dem Beginn liegen.")),
      );
      return;
    }

    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null) return;

    final bool dateChanged =
        isEdit && (_start != _origStart || _end != _origEnd);

    // Doppelbesetzungen prüfen (inkl. anderer Flugschulen & Terminverschiebung)
    if (_status != EventStatusEnum.canceled) {
      // Sicherstellen, dass schulübergreifende Konflikte für den finalen Zeitraum aktuell sind
      final activeMemberIds = _team
          .where((tm) {
            if (_isOpenSlot(tm)) return false;
            final st = _statusOf(tm);
            return st != EventUserStatusEnum.denied_user &&
                st != EventUserStatusEnum.denied_flight_school &&
                st != EventUserStatusEnum.open;
          })
          .map((tm) => tm.userId)
          .toSet()
          .toList();
      if (activeMemberIds.isNotEmpty) {
        final liveCross = await SecurityPrivacyService()
            .checkCrossSchoolConflicts(
          flightSchoolId: fs.id,
          userIds: activeMemberIds,
          startTime: _start,
          endTime: _end,
          ignoreEventId: widget.initialEvent?.id,
          otherSchoolsOnly: true,
        );
        if (!mounted) return;
        _crossSchoolConflictsByUserId = {
          ..._crossSchoolConflictsByUserId,
          ...liveCross,
        };
      }

      final conflictLines = <String>[];
      for (final tm in _team) {
        if (_isOpenSlot(tm)) continue;
        final st = _statusOf(tm);
        if (st == EventUserStatusEnum.denied_user ||
            st == EventUserStatusEnum.denied_flight_school ||
            st == EventUserStatusEnum.open) {
          continue;
        }
        final parts = _allConflictLabelsFor(tm.userId, fs);
        if (parts.isNotEmpty) {
          final personName = _resolveName(tm, fs.members);
          conflictLines.add('$personName: ${parts.join(', ')}');
        }
      }

      if (conflictLines.isNotEmpty) {
        final confirmed = await showAdminDoubleBookingConfirmDialog(
          context,
          title: dateChanged
              ? 'Doppelbesetzung durch Terminverschiebung'
              : 'Doppelbesetzung bestätigen',
          message: dateChanged
              ? 'Durch das Verschieben dieses Events entstehen personelle Doppelbesetzungen. Die eingeteilten Personen werden zudem über die Terminänderung informiert. Möchtest du trotzdem speichern?'
              : 'Folgende eingeteilte Personen sind im gewählten Zeitraum bereits anderweitig verplant. Möchtest du das Event trotzdem so speichern?',
          conflicts: conflictLines,
          confirmLabel:
              dateChanged ? 'Trotzdem verschieben' : 'Trotzdem speichern',
        );
        if (!confirmed || !mounted) return;
      }
    }

    final matchedPeriod = fs.periodForDate(_start);

    setState(() => _saving = true);
    try {
      final event = Event(
        id: widget.initialEvent?.id ?? "",
        eventDocId: widget.initialEvent?.eventDocId,
        flightSchoolId: fs.id,
        identifier: _identifierCtrl.text.trim(),
        status: _status,
        startTime: _start,
        endTime: _end,
        displayName: _nameCtrl.text.trim(),
        location: _locationCtrl.text.trim(),
        team: _team,
        notes: _notesCtrl.text.trim(),
        role: _team.isNotEmpty ? _team.first.role : fs.availableRoleNames.first,
        assignmentStatus: _team.isNotEmpty
            ? _statusOf(_team.first)
            : EventUserStatusEnum.open,
        planningPeriodId: matchedPeriod?.id,
        planningStage: matchedPeriod?.stage.value ?? 3,
        seriesId: widget.initialEvent?.seriesId,
        previousStartTime:
            dateChanged ? _origStart : widget.initialEvent?.previousStartTime,
        previousEndTime:
            dateChanged ? _origEnd : widget.initialEvent?.previousEndTime,
      );

      await widget.onSave(event);

      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text("Event erfolgreich gespeichert.")),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text("Speichern fehlgeschlagen: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  String _fmtTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} Uhr';

  @override
  Widget build(BuildContext context) {
    final fs = context.watch<FlightSchoolProvider>().flightSchool;
    if (fs == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final cs = Theme.of(context).colorScheme;

    return PopScope(
      canPop: !_isDirty && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_saving) _confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            isEdit
                ? "Event bearbeiten"
                : (widget.duplicateFromEvent != null
                    ? "Event kopieren"
                    : "Neues Event"),
          ),
          leading: IconButton(
            tooltip: 'Schließen',
            icon: const Icon(Icons.close),
            onPressed: _saving ? null : _confirmDiscard,
          ),
          actions: [
            if (isEdit && widget.onDuplicate != null)
              IconButton(
                tooltip: "Als Kopie neu anlegen",
                icon: const Icon(Icons.copy_outlined),
                onPressed: _saving
                    ? null
                    : () {
                        final src = widget.initialEvent!;
                        Navigator.pop(context);
                        widget.onDuplicate!(src);
                      },
              ),
            if (isEdit && widget.onDelete != null)
              IconButton(
                tooltip: "Event löschen",
                icon: const Icon(Icons.delete_outline),
                onPressed: _saving ? null : _confirmDelete,
              ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (_saving) const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      if (!isEdit && widget.duplicateFromEvent != null) ...[
                        _NoticeBanner(
                          icon: Icons.copy_outlined,
                          color: AppTheme.infoColor,
                          text:
                              'Kopie von „${widget.duplicateFromEvent!.displayName}“ – Beginn und Ende wurden automatisch um +7 Tage verschoben. Bitte Datum prüfen und ggf. anpassen.',
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (!isEdit &&
                          (_loadingTemplates || _templates.isNotEmpty)) ...[
                        Material(
                          color: cs.primaryContainer.withValues(alpha: 0.35),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: cs.primary.withValues(alpha: 0.35),
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: ListTile(
                            dense: true,
                            leading: Icon(
                              Icons.bookmarks_outlined,
                              color: cs.primary,
                            ),
                            title: Text(
                              _selectedTemplateId != null
                                  ? 'Vorlage aktiv: ${_templates.where((t) => t.id == _selectedTemplateId).map((t) => t.templateName).firstOrNull ?? ""}'
                                  : 'Aus Vorlage erstellen',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                              ),
                            ),
                            subtitle: Text(
                              _loadingTemplates
                                  ? 'Lade Vorlagen...'
                                  : '${_templates.length} gespeicherte Vorlage${_templates.length == 1 ? "" : "n"} verfügbar',
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: _loadingTemplates
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : FilledButton.tonal(
                                    onPressed:
                                        _saving ? null : _openTemplatePickerSheet,
                                    child: const Text('Wählen'),
                                  ),
                            onTap: _saving || _loadingTemplates
                                ? null
                                : _openTemplatePickerSheet,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextFormField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(
                          labelText: "Event-Name *",
                          hintText: "z. B. Sicherheitstraining Gardasee",
                        ),
                        validator: (v) => (v ?? '').trim().isEmpty
                            ? "Bitte Event-Namen eingeben."
                            : null,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _identifierCtrl,
                              decoration: const InputDecoration(
                                labelText: "Kennung (optional)",
                                hintText: "z. B. SHT-2026-01",
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButtonFormField<EventStatusEnum>(
                              initialValue: _status,
                              decoration: const InputDecoration(
                                labelText: "Status",
                              ),
                              items: EventStatusEnum.values
                                  .map(
                                    (s) => DropdownMenuItem(
                                      value: s,
                                      child: Text(s.label),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _status = v ?? _status),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Automatische Saison- & Planungsstufen-Zuordnung anhand des Event-Datums
                      Builder(
                        builder: (context) {
                          final matched = fs.periodForDate(_start);
                          final stageColor = matched == null
                              ? AppTheme.successColor
                              : switch (matched.stage) {
                                  PlanningStage.availability =>
                                    AppTheme.stage1Color,
                                  PlanningStage.application =>
                                    AppTheme.infoColor,
                                  PlanningStage.production =>
                                    AppTheme.successColor,
                                };
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: stageColor.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: stageColor.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.layers_outlined,
                                  size: 18,
                                  color: stageColor,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        matched != null
                                            ? '${matched.seasonLabel} · ${matched.stage.label}'
                                            : 'Keine Saison im Zeitraum · Standard: Stufe 3 (Produktion)',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: stageColor,
                                        ),
                                      ),
                                      Text(
                                        matched != null
                                            ? 'Gilt automatisch für Events im Zeitraum ${matched.dateRangeLabel}'
                                            : 'Die Planungsstufe richtet sich automatisch nach dem Event-Datum.',
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
                          );
                        },
                      ),
                      const SizedBox(height: 12),

                      // Zweizeilige Start-/Ende-Auswahl + Dauer + Schnellauswahl (1.1 & 5.1)
                      Row(
                        children: [
                          Expanded(
                            child: _DateTimeTileButton(
                              label: 'Beginn',
                              dateText: _fmtDate(_start),
                              timeText: _fmtTime(_start),
                              icon: Icons.play_arrow_rounded,
                              onTap: _saving ? null : _pickStart,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _DateTimeTileButton(
                              label: _lockDuration
                                  ? 'Ende (automatisch)'
                                  : 'Ende',
                              dateText: _fmtDate(_end),
                              timeText: _fmtTime(_end),
                              icon: _lockDuration
                                  ? Icons.lock_outline
                                  : Icons.stop_rounded,
                              locked: _lockDuration,
                              onTap: _saving ? null : _pickEnd,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Chip(
                            avatar: Icon(
                              Icons.timelapse,
                              size: 15,
                              color: cs.primary,
                            ),
                            label: Text(
                              'Dauer: ${formatDurationCompact(_start, _end)}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          ActionChip(
                            avatar: Icon(
                              _lockDuration
                                  ? Icons.lock
                                  : Icons.lock_open_outlined,
                              size: 15,
                              color: _lockDuration
                                  ? cs.primary
                                  : cs.onSurfaceVariant,
                            ),
                            label: Text(
                              _lockDuration
                                  ? 'Dauer gesperrt'
                                  : 'Dauer sperren',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: _lockDuration
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: _lockDuration ? cs.primary : null,
                              ),
                            ),
                            backgroundColor: _lockDuration
                                ? cs.primaryContainer.withValues(alpha: 0.55)
                                : null,
                            visualDensity: VisualDensity.compact,
                            tooltip: _lockDuration
                                ? 'Sperre aufheben, um Enddatum frei zu ändern'
                                : 'Dauer sperren – Enddatum passt sich automatisch dem Startdatum an',
                            onPressed: _saving ? null : _toggleDurationLock,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _locationCtrl,
                        decoration: const InputDecoration(
                          labelText: "Ort",
                          prefixIcon: Icon(Icons.place_outlined),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _notesCtrl,
                        maxLines: 3,
                        decoration: const InputDecoration(labelText: "Notizen"),
                      ),

                      // Event als wiederverwendbare Vorlage speichern
                      const SizedBox(height: 12),
                      Card(
                        elevation: 0,
                        color: cs.surfaceContainerHighest
                            .withValues(alpha: 0.45),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: cs.outlineVariant),
                        ),
                        child: ListTile(
                          leading: Icon(
                            Icons.bookmark_add_outlined,
                            color: cs.primary,
                          ),
                          title: const Text(
                            'Als Event-Vorlage speichern',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: const Text(
                            'Speichert Dauer, Ort, Notizen und alle Teamrollen als offene Stellen für zukünftige Events.',
                            style: TextStyle(fontSize: 12),
                          ),
                          trailing: _savingTemplate
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : FilledButton.tonal(
                                  onPressed: _saving
                                      ? null
                                      : _saveAsTemplateDialog,
                                  child: const Text('Speichern'),
                                ),
                        ),
                      ),

                      const SizedBox(height: 18),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              "Team-Zusammenstellung",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: _saving ? null : _addTeamMemberDialog,
                            icon: const Icon(Icons.person_add, size: 18),
                            label: const Text("Hinzufügen"),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_team.isEmpty)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Text(
                              "Noch keine Team-Plätze angelegt. Tippe auf „Hinzufügen“.",
                              style: TextStyle(color: cs.onSurfaceVariant),
                            ),
                          ),
                        )
                      else
                        ...List.generate(_team.length, (i) {
                          final tm = _team[i];
                          final st = _statusOf(tm);
                          final avail = !_isOpenSlot(tm)
                              ? _availabilityStatusFor(tm.userId)
                              : null;
                          final allConflicts = !_isOpenSlot(tm)
                              ? _allConflictLabelsFor(tm.userId, fs)
                              : const <String>[];
                          final completion = tm.assignmentId != null
                              ? _completionsByAssignmentId[tm.assignmentId!]
                              : null;
                          final memberName = _resolveName(tm, fs.members);
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ListTile(
                                  leading: UserAvatar(
                                    avatarUrl: _resolveAvatarUrl(tm, fs.members),
                                    name: memberName,
                                    radius: 20,
                                    isOpenSlot: _isOpenSlot(tm),
                                  ),
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          memberName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      if (tm.hasOpenSwapRequest)
                                        Chip(
                                          label: const Text(
                                            'Tausch offen',
                                            style: TextStyle(fontSize: 11),
                                          ),
                                          backgroundColor: AppTheme.swapColor
                                              .withValues(alpha: 0.2),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                      if (allConflicts.isNotEmpty)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(left: 4),
                                          child: Tooltip(
                                            message:
                                                'Doppelbesetzung: ${allConflicts.join(', ')}',
                                            child: const Icon(
                                              Icons.event_repeat,
                                              color: AppTheme.dangerColor,
                                              size: 18,
                                            ),
                                          ),
                                        ),
                                      if (avail != null && avail.hasBlackout)
                                        const Padding(
                                          padding: EdgeInsets.only(left: 4),
                                          child: Tooltip(
                                            message: 'Abwesenheit eingetragen!',
                                            child: Icon(
                                              Icons.event_busy,
                                              color: AppTheme.dangerColor,
                                              size: 18,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  subtitle: Text(
                                    '${tm.roleLabel} · ${st.label()}${_isPersisted(tm) ? "" : " (neu)"}',
                                  ),
                                  trailing: const Icon(Icons.edit_outlined),
                                  onTap: _saving
                                      ? null
                                      : () => _openTeamEditDialog(
                                            index: i,
                                            tm: tm,
                                            members: fs.members,
                                          ),
                                ),
                                if (completion != null)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      0,
                                      16,
                                      10,
                                    ),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: ActionChip(
                                        avatar: Icon(
                                          completion.isSigned
                                              ? (completion.isComplete
                                                  ? Icons.verified
                                                  : Icons.warning_amber_rounded)
                                              : Icons.checklist,
                                          size: 16,
                                          color: completion.isSigned
                                              ? (completion.isComplete
                                                  ? AppTheme.successColor
                                                  : AppTheme.warningColor)
                                              : AppTheme.infoColor,
                                        ),
                                        label: Text(
                                          completion.isSigned
                                              ? (completion.isComplete
                                                  ? 'Checkliste unterschrieben (${completion.checkedCount}/${completion.totalCount})'
                                                  : 'Unterschrieben mit offenen Punkten (${completion.checkedCount}/${completion.totalCount})')
                                              : 'Checkliste in Bearbeitung (${completion.checkedCount}/${completion.totalCount})',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        onPressed: () {
                                          showChecklistProtocolDialog(
                                            context: context,
                                            completion: completion,
                                            memberName: memberName,
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving ? null : _confirmDiscard,
                        child: const Text("Abbrechen"),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: const Icon(Icons.save),
                        label: Text(
                          isEdit ? "Änderungen speichern" : "Speichern",
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateTimeTileButton extends StatelessWidget {
  final String label;
  final String dateText;
  final String timeText;
  final IconData icon;
  final bool locked;
  final VoidCallback? onTap;

  const _DateTimeTileButton({
    required this.label,
    required this.dateText,
    required this.timeText,
    required this.icon,
    this.locked = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: locked
          ? cs.surfaceContainerHighest.withValues(alpha: 0.5)
          : cs.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: locked ? cs.primary.withValues(alpha: 0.45) : cs.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      dateText,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      timeText,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: cs.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoticeBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _NoticeBanner({
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5))),
        ],
      ),
    );
  }
}

/// Crash-sicherer Dialog zum Speichern einer Event-Vorlage: verwaltet seinen
/// eigenen `TextEditingController` im State und gibt ihn erst in `dispose()`
/// frei, nachdem die Dialog-Ausblendanimation vollständig abgeschlossen ist.
class _SaveTemplateDialog extends StatefulWidget {
  final String initialName;
  final String durationLabel;
  final String startTimeLabel;
  final List<String> roles;

  const _SaveTemplateDialog({
    required this.initialName,
    required this.durationLabel,
    required this.startTimeLabel,
    required this.roles,
  });

  @override
  State<_SaveTemplateDialog> createState() => _SaveTemplateDialogState();
}

class _SaveTemplateDialogState extends State<_SaveTemplateDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _ctrl.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Als Event-Vorlage speichern'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _ctrl,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Vorlagenname *',
                hintText: 'z. B. SHT Idrosee (4 Tage)',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Gespeichert werden:\n'
              '• Name, Kennung, Ort, Notizen & Status\n'
              '• Dauer: ${widget.durationLabel} (Start: ${widget.startTimeLabel})\n'
              '• ${widget.roles.length} Teamrolle(n) als offene Stellen: ${widget.roles.isEmpty ? "keine" : widget.roles.join(", ")}',
              style: TextStyle(
                fontSize: 12.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.bookmark_add_outlined, size: 18),
          label: const Text('Vorlage speichern'),
        ),
      ],
    );
  }
}

/// Eigenständiges Datum+Uhrzeit-Bottom-Sheet mit zweibuchstabigen deutschen
/// Wochentags-Kürzeln (Mo–So), direkter Tagesauswahl ohne Gesten-Konflikte
/// und synchronisierten Stunden-/Minuten-Dropdowns + Schnellwahl-Chips.
class _DateTimePickerSheet extends StatefulWidget {
  final DateTime initial;
  final String title;

  const _DateTimePickerSheet({
    required this.initial,
    required this.title,
  });

  @override
  State<_DateTimePickerSheet> createState() => _DateTimePickerSheetState();
}

class _DateTimePickerSheetState extends State<_DateTimePickerSheet> {
  static const _weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
  static const _months = [
    'Januar',
    'Februar',
    'März',
    'April',
    'Mai',
    'Juni',
    'Juli',
    'August',
    'September',
    'Oktober',
    'November',
    'Dezember',
  ];
  static const _quickTimes = [
    (8, 0),
    (9, 0),
    (10, 0),
    (12, 0),
    (14, 0),
    (17, 0),
    (18, 0),
  ];

  late DateTime _pickedDate;
  late DateTime _visibleMonth;
  late int _hour;
  late int _minute;

  @override
  void initState() {
    super.initState();
    _pickedDate = DateTime(
      widget.initial.year,
      widget.initial.month,
      widget.initial.day,
    );
    _visibleMonth = DateTime(_pickedDate.year, _pickedDate.month, 1);
    _hour = widget.initial.hour;
    _minute = (widget.initial.minute ~/ 5) * 5;
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<DateTime> _monthGridDays(DateTime monthFirst) {
    final startOffset = monthFirst.weekday - 1;
    final gridStart = monthFirst.subtract(Duration(days: startOffset));
    final nextMonth = DateTime(monthFirst.year, monthFirst.month + 1, 1);
    final lastOfMonth = nextMonth.subtract(const Duration(days: 1));
    final endOffset = 7 - lastOfMonth.weekday;
    final gridEnd = lastOfMonth.add(Duration(days: endOffset));

    final days = <DateTime>[];
    for (var d = gridStart;
        !d.isAfter(gridEnd);
        d = d.add(const Duration(days: 1))) {
      days.add(d);
    }
    return days;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final today = DateTime.now();
    final days = _monthGridDays(_visibleMonth);
    final weeks = <List<DateTime>>[];
    for (var i = 0; i < days.length; i += 7) {
      weeks.add(days.sublist(i, i + 7));
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${_fmtDate(_pickedDate)} · ${_hour.toString().padLeft(2, '0')}:${_minute.toString().padLeft(2, '0')} Uhr',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Monatsnavigation
              Row(
                children: [
                  IconButton(
                    tooltip: 'Vorheriger Monat',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() {
                      _visibleMonth = DateTime(
                        _visibleMonth.year,
                        _visibleMonth.month - 1,
                        1,
                      );
                    }),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Text(
                      '${_months[_visibleMonth.month - 1]} ${_visibleMonth.year}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Nächster Monat',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() {
                      _visibleMonth = DateTime(
                        _visibleMonth.year,
                        _visibleMonth.month + 1,
                        1,
                      );
                    }),
                    icon: const Icon(Icons.chevron_right),
                  ),
                  const SizedBox(width: 4),
                  ActionChip(
                    label: const Text('Heute', style: TextStyle(fontSize: 11.5)),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() {
                      _pickedDate = DateTime(today.year, today.month, today.day);
                      _visibleMonth = DateTime(today.year, today.month, 1);
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Zweibuchstabige Wochentage (Mo–So)
              Row(
                children: _weekdays
                    .map(
                      (w) => Expanded(
                        child: Center(
                          child: Text(
                            w,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 4),
              // Kompaktes Monatsraster mit klaren, zuverlässig antippbaren Tageszellen
              ...weeks.map(
                (week) => Row(
                  children: week.map((day) {
                    final inMonth = day.month == _visibleMonth.month;
                    final isSelected = _isSameDay(day, _pickedDate);
                    final isToday = _isSameDay(day, today);
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Material(
                          color: isSelected
                              ? cs.primary
                              : Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: isToday && !isSelected
                                ? BorderSide(color: cs.primary, width: 1.4)
                                : BorderSide.none,
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => setState(() {
                              _pickedDate = day;
                              if (day.month != _visibleMonth.month ||
                                  day.year != _visibleMonth.year) {
                                _visibleMonth = DateTime(day.year, day.month, 1);
                              }
                            }),
                            child: SizedBox(
                              height: 36,
                              child: Center(
                                child: Text(
                                  '${day.day}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isSelected || isToday
                                        ? FontWeight.w800
                                        : FontWeight.w500,
                                    color: isSelected
                                        ? cs.onPrimary
                                        : (inMonth
                                            ? cs.onSurface
                                            : cs.onSurfaceVariant
                                                .withValues(alpha: 0.45)),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const Divider(height: 16),
              const Text(
                'Uhrzeit (24h)',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Stunde',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: _hour,
                          isExpanded: true,
                          isDense: true,
                          items: List.generate(
                            24,
                            (h) => DropdownMenuItem(
                              value: h,
                              child: Text('${h.toString().padLeft(2, '0')} Uhr'),
                            ),
                          ),
                          onChanged: (v) {
                            if (v != null) setState(() => _hour = v);
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Minute',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: _minute,
                          isExpanded: true,
                          isDense: true,
                          items: List.generate(
                            12,
                            (i) => DropdownMenuItem(
                              value: i * 5,
                              child: Text(
                                ':${(i * 5).toString().padLeft(2, '0')}',
                              ),
                            ),
                          ),
                          onChanged: (v) {
                            if (v != null) setState(() => _minute = v);
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _quickTimes.map((t) {
                  final selected = _hour == t.$1 && _minute == t.$2;
                  return ChoiceChip(
                    label: Text(
                      '${t.$1.toString().padLeft(2, '0')}:${t.$2.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    selected: selected,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() {
                      _hour = t.$1;
                      _minute = t.$2;
                    }),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Abbrechen'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(
                        context,
                        DateTime(
                          _pickedDate.year,
                          _pickedDate.month,
                          _pickedDate.day,
                          _hour,
                          _minute,
                        ),
                      ),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Übernehmen'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
