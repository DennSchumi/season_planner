import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/core/data/enums/event_user_status_enum.dart';
import 'package:season_planner/core/data/models/event_model.dart';
import 'package:season_planner/core/data/models/planning_period_model.dart';
import 'package:season_planner/core/services/planning_service.dart';
import 'package:season_planner/core/services/qualification_service.dart';
import 'package:season_planner/core/services/security_privacy_service.dart';
import 'package:season_planner/core/services/tandem_service.dart';
import 'package:season_planner/core/theme.dart';
import 'package:season_planner/core/widgets/event_role_docs_section.dart';
import 'package:season_planner/core/widgets/user_avatar.dart';
import 'package:season_planner/core/widgets/ux_components.dart';
import 'package:season_planner/user/data/models/flight_school_model_user_view.dart';
import 'package:season_planner/user/features/availability/my_availability_view.dart';
import 'package:season_planner/user/services/database_service.dart';
import 'package:season_planner/user/user_provider.dart';
import '../../../../user/data/models/user_model_userView.dart';

class EventDetailView extends StatefulWidget {
  final Event event;
  final List<Event> siblingOpportunities;

  const EventDetailView({
    super.key,
    required this.event,
    this.siblingOpportunities = const [],
  });

  @override
  State<EventDetailView> createState() => _EventDetailViewState();
}

class _EventDetailViewState extends State<EventDetailView> {
  late UserModelUserView user;
  late String _activeEventId;
  List<AvailabilitySubmission> _userSubmissions = [];
  bool _loadingSubmissions = false;
  bool _savingAvailability = false;

  @override
  void initState() {
    super.initState();
    user = context.read<UserProvider>().user!;
    _activeEventId = widget.event.id;
    _loadSubmissions();
  }

  Future<void> _loadSubmissions() async {
    setState(() => _loadingSubmissions = true);
    final list = await PlanningService().listUserSubmissions(user.id);
    if (!mounted) return;
    setState(() {
      _userSubmissions = list;
      _loadingSubmissions = false;
    });
  }

  Future<void> _saveQuickAvailability({
    required Event event,
    required FlightSchoolUserView? fs,
    required AvailabilityKind kind,
  }) async {
    setState(() => _savingAvailability = true);
    try {
      final period = fs?.periodForEvent(event);
      final startDay = DateTime(
        event.startTime.year,
        event.startTime.month,
        event.startTime.day,
      );
      final endDay = DateTime(
        event.endTime.year,
        event.endTime.month,
        event.endTime.day,
      );
      await PlanningService().createSubmission(
        userId: user.id,
        flightSchoolId: event.flightSchoolId,
        planningPeriodId:
            kind == AvailabilityKind.available ? period?.id : null,
        kind: kind,
        startDate: startDay,
        endDate: endDay,
        notes: event.displayName,
      );
      await _loadSubmissions();
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              kind == AvailabilityKind.available
                  ? 'Verfügbarkeit für „${event.displayName}“ eingetragen.'
                  : 'Abwesenheit für „${event.displayName}“ eingetragen.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingAvailability = false);
    }
  }

  Future<void> _deleteAvailability(AvailabilitySubmission item) async {
    setState(() => _savingAvailability = true);
    try {
      await PlanningService().deleteSubmission(item.id);
      await _loadSubmissions();
      if (mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(const SnackBar(content: Text('Rückmeldung entfernt.')));
      }
    } finally {
      if (mounted) setState(() => _savingAvailability = false);
    }
  }

  Future<void> _reloadEvents() async {
    final currentUser = context.read<UserProvider>().user;
    if (currentUser == null) return;
    final updatedEvents = await DatabaseService().loadUserEvents(currentUser);
    if (!mounted) return;
    context.read<UserProvider>().updateEvents(updatedEvents);
  }

  String? _bookingConflictFor(Event activeEvent) {
    final evKey = (activeEvent.eventDocId != null &&
            activeEvent.eventDocId!.isNotEmpty)
        ? activeEvent.eventDocId!
        : activeEvent.id;
    return TandemService.findUserEventBookingConflict(
      userId: user.id,
      startTime: activeEvent.startTime,
      endTime: activeEvent.endTime,
      userEvents: user.events,
      userTandemDuties: user.tandemDuties,
      ignoreEventKey: evKey,
    );
  }

  Future<String?> _checkFullBookingConflict(Event activeEvent) async {
    final local = _bookingConflictFor(activeEvent);
    if (local != null) return local;
    final evKey = (activeEvent.eventDocId != null &&
            activeEvent.eventDocId!.isNotEmpty)
        ? activeEvent.eventDocId!
        : activeEvent.id;
    final serverMap = await SecurityPrivacyService().checkCrossSchoolConflicts(
      userIds: [user.id],
      startTime: activeEvent.startTime,
      endTime: activeEvent.endTime,
      ignoreEventId: evKey,
      otherSchoolsOnly: false,
    );
    final serverList = serverMap.values.expand((e) => e).toList();
    return serverList.isNotEmpty ? serverList.join(' · ') : null;
  }

  Future<bool> _changeStatus(
    Event activeEvent,
    EventUserStatusEnum newStatus,
  ) async {
    if (newStatus == EventUserStatusEnum.pending_flight_school ||
        newStatus == EventUserStatusEnum.accepted_user) {
      final conflict = await _checkFullBookingConflict(activeEvent);
      if (conflict != null) {
        if (mounted) {
          await showUserBookingConflictDialog(context, reason: conflict);
        }
        return false;
      }
    }
    final success = await DatabaseService().changeEventAssignmentStatus(
      user: user,
      event: activeEvent,
      newStatus: newStatus,
    );
    if (success) await _reloadEvents();
    return success;
  }

  Future<bool> _toggleSwapOffer(Event event, bool offer) async {
    final fs = user.flightSchools.firstWhere(
      (s) => s.id == event.flightSchoolId,
    );
    final ok = await PlanningService().setSwapOffered(
      databaseId: fs.databaseId,
      tableId: fs.teamAssignmentsEventsCollectionId,
      assignmentId: event.id,
      offered: offer,
    );
    if (ok) await _reloadEvents();
    return ok;
  }

  Future<bool> _requestSwapTakeover(Event event) async {
    final conflict = await _checkFullBookingConflict(event);
    if (conflict != null) {
      if (mounted) {
        await showUserBookingConflictDialog(context, reason: conflict);
      }
      return false;
    }
    final fs = user.flightSchools.firstWhere(
      (s) => s.id == event.flightSchoolId,
    );
    final ok = await PlanningService().requestSwapTakeover(
      databaseId: fs.databaseId,
      tableId: fs.teamAssignmentsEventsCollectionId,
      assignmentId: event.id,
      requesterUserId: user.id,
      requesterName: user.name.isEmpty ? user.mail : user.name,
    );
    if (ok) await _reloadEvents();
    return ok;
  }

  Future<void> _requestQualificationForRole(
    FlightSchoolUserView fs,
    String qualId,
    String qualName,
  ) async {
    if (fs.membershipId.isEmpty) return;
    final ok = await QualificationService().requestQualification(
      membershipId: fs.membershipId,
      flightSchoolId: fs.id,
      currentRequestedIds: fs.requestedQualificationIds,
      qualificationId: qualId,
      qualificationName: qualName,
    );
    if (!ok || !mounted) return;
    final fresh = await DatabaseService().getUserInformation();
    if (fresh != null && mounted) {
      context.read<UserProvider>().setUser(fresh);
    }
    if (mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            'Qualifikation „$qualName“ bei ${fs.displayName} angefragt.',
          ),
        ),
      );
    }
  }

  Future<void> _showActionDialog({
    required String title,
    required String message,
    required Future<bool> Function() action,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) =>
              _ActionDialog(title: title, message: message, action: action),
    );
    if (ok == null || !mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Erfolgreich gespeichert.' : 'Aktion fehlgeschlagen.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userFromProvider = context.watch<UserProvider>().user;
    if (userFromProvider == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    user = userFromProvider;

    final event = userFromProvider.events.firstWhere(
      (e) => e.id == _activeEventId,
      orElse: () => widget.siblingOpportunities.firstWhere(
        (e) => e.id == _activeEventId,
        orElse: () => widget.event,
      ),
    );

    // Alle zugehörigen offenen Positionen dieses Events live aus dem Provider auflösen
    // (doppelte identische offene Slots derselben Rolle werden für die Auswahl zusammengefasst)
    final liveSiblings = <Event>[];
    if (widget.siblingOpportunities.length > 1) {
      final seenSigs = <String>{};
      for (final s in widget.siblingOpportunities) {
        final live = userFromProvider.events.firstWhere(
          (e) => e.id == s.id,
          orElse: () => s,
        );
        final sig =
            '${live.roleLabel.toLowerCase()}|${live.assignmentStatus.name}|${live.isSwapOfferFromOther}';
        if (live.id == event.id || seenSigs.add(sig)) {
          // Falls wir das aktive Element später treffen, überschreiben wir den älteren Vertreter derselben Signatur
          liveSiblings.removeWhere(
            (x) =>
                '${x.roleLabel.toLowerCase()}|${x.assignmentStatus.name}|${x.isSwapOfferFromOther}' ==
                sig,
          );
          liveSiblings.add(live);
        }
      }
    }

    final fsMatches =
        userFromProvider.flightSchools
            .where((x) => x.id == event.flightSchoolId)
            .toList();
    final fs = fsMatches.isNotEmpty ? fsMatches.first : null;

    final String fsName =
        fs == null
            ? "Unbekannte Flugschule"
            : (fs.displayShortName.isNotEmpty
                ? fs.displayShortName
                : fs.displayName);
    final String fsLogoLink = fs?.logoLink ?? "";

    final effectiveStage = fs?.effectiveStageFor(event) ?? event.planningStage;
    final isStage1 = effectiveStage == 1;
    final isStage3 = effectiveStage == 3;
    final isOwnBinding = event.isOwnBindingAssignment;
    final isOwnDirectRequest = !event.isSwapOfferFromOther &&
        event.assignmentStatus == EventUserStatusEnum.pending_user;
    final isExtendedRedacted =
        (fs?.isExtendedTeam == true) && !isOwnBinding && !isOwnDirectRequest;
    final isStage1Preview =
        (isStage1 || isExtendedRedacted) && !isOwnBinding && !isOwnDirectRequest;
    // Team-Besetzung der anderen Positionen nur in Stufe 2 & 3 UND nur,
    // wenn der Nutzer selbst in diesem Event eingeplant ist!
    final canSeeOtherTeamPositions = effectiveStage >= 2 && isOwnBinding;

    final overlappingSubmissions =
        _userSubmissions
            .where(
              (s) =>
                  s.flightSchoolId == event.flightSchoolId &&
                  s.overlaps(event.startTime, event.endTime),
            )
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          event.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      bottomNavigationBar:
          isStage1Preview
              ? null
              : _BottomActionBar(
                event: event,
                currentUserId: user.id,
                isStage3: isStage3,
                isOwnAccepted: isOwnBinding,
                onRequest: () async {
                  final conflict = await _checkFullBookingConflict(event);
                  if (!mounted) return;
                  if (conflict != null) {
                    await showUserBookingConflictDialog(
                      context,
                      reason: conflict,
                    );
                    return;
                  }
                  await _showActionDialog(
                    title: "Auf Stelle bewerben",
                    message:
                        "Möchtest du dich auf die offene Rolle „${event.roleLabel}“ bewerben?",
                    action: () => _changeStatus(
                      event,
                      EventUserStatusEnum.pending_flight_school,
                    ),
                  );
                },
                onAccept: () async {
                  final conflict = await _checkFullBookingConflict(event);
                  if (!mounted) return;
                  if (conflict != null) {
                    await showUserBookingConflictDialog(
                      context,
                      reason: conflict,
                    );
                    return;
                  }
                  await _showActionDialog(
                    title: "Zuweisung annehmen",
                    message:
                        "Möchtest du diese Zuweisung verbindlich annehmen?",
                    action: () => _changeStatus(
                      event,
                      EventUserStatusEnum.accepted_user,
                    ),
                  );
                },
                onDecline:
                    () => _showActionDialog(
                      title: "Zuweisung ablehnen",
                      message: "Möchtest du diese Anfrage wirklich ablehnen?",
                      action:
                          () => _changeStatus(
                            event,
                            EventUserStatusEnum.denied_user,
                          ),
                    ),
                onChange:
                    () => _showActionDialog(
                      title: "Änderung anfragen",
                      message:
                          "Möchtest du bei der Flugschule eine Änderung bzw. Ersatz anfragen?",
                      action:
                          () => _changeStatus(
                            event,
                            EventUserStatusEnum.user_requests_change,
                          ),
                    ),
                onOfferSwap:
                    () => _showActionDialog(
                      title:
                          event.swapOffered
                              ? "Tausch-Freigabe zurückziehen"
                              : "Platz zum Tausch freigeben",
                      message:
                          event.swapOffered
                              ? "Dein Platz wird nicht mehr anderen Teammitgliedern zum Tausch angeboten."
                              : "Andere qualifizierte Teammitglieder mit gleicher Rolle können diesen Platz anfragen. Der Admin bestätigt den Tausch abschließend.",
                      action: () => _toggleSwapOffer(event, !event.swapOffered),
                    ),
                onRequestSwap:
                    () => _showActionDialog(
                      title: "Tauschplatz übernehmen",
                      message:
                          "Möchtest du diesen zum Tausch angebotenen Platz anfragen? Ein Admin der Flugschule muss den Tausch anschließend bestätigen.",
                      action: () => _requestSwapTakeover(event),
                    ),
              ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          children: [
            _HeaderCard(
              fsName: fsName,
              fsLogoLink: fsLogoLink,
              event: event,
              effectiveStage: effectiveStage,
              isStage1Preview: isStage1Preview,
            ),
            if (!isStage1Preview && !isOwnBinding && liveSiblings.length > 1) ...[
              const SizedBox(height: 12),
              _SectionCard(
                title: 'Offene Position wählen',
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: liveSiblings.map((slot) {
                      final isSelected = slot.id == event.id;
                      final suffix = slot.isSwapOfferFromOther
                          ? ' (Tausch)'
                          : slot.assignmentStatus ==
                                  EventUserStatusEnum.pending_flight_school
                              ? ' (Beworben)'
                              : '';
                      return ChoiceChip(
                        label: Text('${slot.roleLabel}$suffix'),
                        selected: isSelected,
                        onSelected: (_) {
                          if (!isSelected) {
                            setState(() => _activeEventId = slot.id);
                          }
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ],
            if (isStage1 && !isOwnBinding) ...[
              const SizedBox(height: 12),
              _Stage1AvailabilityCard(
                event: event,
                isOwnBinding: isOwnBinding,
                submissions: overlappingSubmissions,
                isLoading: _loadingSubmissions,
                isSaving: _savingAvailability,
                onMarkAvailable:
                    () => _saveQuickAvailability(
                      event: event,
                      fs: fs,
                      kind: AvailabilityKind.available,
                    ),
                onMarkUnavailable:
                    () => _saveQuickAvailability(
                      event: event,
                      fs: fs,
                      kind: AvailabilityKind.blackout,
                    ),
                onDeleteSubmission: _deleteAvailability,
                onManageAll: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MyAvailabilityView(initialTab: 0),
                    ),
                  );
                  if (mounted) _loadSubmissions();
                },
              ),
            ],
            const SizedBox(height: 12),
            _SectionCard(
              title: "Allgemein",
              children: [
                if (!isStage1Preview && event.identifier.isNotEmpty)
                  _InfoRow(
                    icon: Icons.badge_outlined,
                    label: "Kennung",
                    value: event.identifier,
                  ),
                _InfoRow(
                  icon: Icons.schedule,
                  label: "Beginn",
                  value: _formatDate(event.startTime),
                ),
                _InfoRow(
                  icon: Icons.schedule_outlined,
                  label: "Ende",
                  value: _formatDate(event.endTime),
                ),
                if (event.location.isNotEmpty)
                  _InfoRow(
                    icon: Icons.place_outlined,
                    label: "Ort",
                    value: event.location,
                  ),
                if (!isStage1Preview) ...[
                  _InfoRow(
                    icon: Icons.flag_outlined,
                    label: "Event-Status",
                    value: event.status.label,
                  ),
                  if (event.role.isNotEmpty)
                    _InfoRow(
                      icon: Icons.account_circle_outlined,
                      label: isOwnBinding ? "Deine Rolle" : "Rolle",
                      value: event.roleLabel,
                    ),
                ],
              ],
            ),
            if (!isStage1Preview && fs != null && event.role.isNotEmpty) ...[
              Builder(
                builder: (context) {
                  final qCheck = fs.checkRoleQualificationStatus(event.role);
                  if (qCheck.satisfied) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Card(
                      color: AppTheme.warningColor.withValues(alpha: 0.10),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: AppTheme.warningColor.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.workspace_premium,
                                  color: AppTheme.warningColor,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    qCheck.requireAll ||
                                            qCheck.missing.length == 1
                                        ? 'Qualifikation für „${event.roleLabel}“ fehlt'
                                        : 'Eine Qualifikation für „${event.roleLabel}“ erforderlich',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Dir wurde diese Qualifikation noch nicht vom Admin zugeteilt. Du kannst sie direkt anfragen:',
                              style: TextStyle(
                                fontSize: 12.5,
                                color:
                                    Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children:
                                  qCheck.missing.map((q) {
                                    final alreadyReq = fs
                                        .hasRequestedQualification(q.id);
                                    return alreadyReq
                                        ? Chip(
                                          avatar: const Icon(
                                            Icons.hourglass_top,
                                            size: 16,
                                            color: AppTheme.warningColor,
                                          ),
                                          label: Text(
                                            '${q.name}: Angefragt',
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                        )
                                        : FilledButton.tonalIcon(
                                          onPressed:
                                              () =>
                                                  _requestQualificationForRole(
                                                    fs,
                                                    q.id,
                                                    q.name,
                                                  ),
                                          icon: const Icon(
                                            Icons.add_task,
                                            size: 16,
                                          ),
                                          label: Text('„${q.name}“ anfragen'),
                                        );
                                  }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
            if (isOwnBinding && fs != null) ...[
              const SizedBox(height: 12),
              EventRoleDocsSection(
                event: event,
                flightSchool: fs,
                userId: user.id,
              ),
            ],
            if (isStage3 && event.swapOffered) ...[
              const SizedBox(height: 12),
              Card(
                color: AppTheme.swapColor.withValues(alpha: 0.08),
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const Icon(Icons.swap_horiz, color: AppTheme.swapColor),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          event.hasOpenSwapRequest
                              ? 'Tausch angefragt von ${event.swapRequestedByName ?? "Teammitglied"} – warte auf Admin-Bestätigung.'
                              : 'Dieser Platz ist aktuell zum Tausch freigegeben.',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            // Team-Besetzung der anderen Positionen NUR in Planungsstufe 2 & 3
            // und NUR bei Events, bei denen der Nutzer selbst eingeplant ist!
            if (canSeeOtherTeamPositions) ...[
              const SizedBox(height: 12),
              _SectionCard(
                title: "Team",
                children:
                    event.team.isEmpty
                        ? [
                          Text(
                            "Noch keine weiteren Teammitglieder eingeteilt.",
                            style: TextStyle(
                              color:
                                  Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ]
                        : event.team
                            .map(
                              (t) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Row(
                                  children: [
                                    UserAvatar(
                                      avatarUrl: t.avatarUrl,
                                      name: t.isSlot ? '' : t.name,
                                      radius: 15,
                                      isOpenSlot: t.isSlot,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        t.isSlot
                                            ? 'Offene Stelle'
                                            : (t.name.isEmpty
                                                ? 'Teammitglied'
                                                : t.name),
                                      ),
                                    ),
                                    Text(
                                      t.roleLabel,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
              ),
            ],
            if (!isStage1Preview && (isOwnBinding || effectiveStage >= 2)) ...[
              const SizedBox(height: 12),
              _SectionCard(
                title: "Notizen",
                children: [
                  Text(
                    event.notes.isEmpty
                        ? "Keine Notizen hinterlegt."
                        : event.notes,
                    style:
                        event.notes.isEmpty
                            ? TextStyle(
                              color:
                                  Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                            )
                            : null,
                  ),
                ],
              ),
            ],
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class _HeaderCard extends StatelessWidget {
  final String fsName;
  final String fsLogoLink;
  final Event event;
  final int effectiveStage;
  final bool isStage1Preview;

  const _HeaderCard({
    required this.fsName,
    required this.fsLogoLink,
    required this.event,
    required this.effectiveStage,
    required this.isStage1Preview,
  });

  (String, Color, Color) _assignmentPillStyle() {
    if (event.isSwapOfferFromOther) {
      return ('Tauschplatz frei', AppTheme.swapColor, AppTheme.swapBg);
    }
    if (event.swapOffered && event.isOwnBindingAssignment) {
      return ('Zum Tausch offen', AppTheme.swapColor, AppTheme.swapBg);
    }
    switch (event.assignmentStatus) {
      case EventUserStatusEnum.accepted_user:
      case EventUserStatusEnum.accepted_flight_school:
        return (
          'Arbeitseinsatz bestätigt',
          AppTheme.successColor,
          AppTheme.successBg,
        );
      case EventUserStatusEnum.pending_user:
        return (
          'Arbeitseinsatz angefragt',
          AppTheme.warningColor,
          AppTheme.warningBg,
        );
      case EventUserStatusEnum.user_requests_change:
        return (
          'Änderung angefragt',
          AppTheme.warningColor,
          AppTheme.warningBg,
        );
      case EventUserStatusEnum.pending_flight_school:
        return ('Beworben', AppTheme.infoColor, AppTheme.infoBg);
      case EventUserStatusEnum.denied_user:
      case EventUserStatusEnum.denied_flight_school:
        return (
          'Arbeitseinsatz abgelehnt',
          AppTheme.dangerColor,
          AppTheme.dangerBg,
        );
      case EventUserStatusEnum.open:
        return ('Offene Stelle', AppTheme.infoColor, AppTheme.infoBg);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (assignLabel, assignFg, assignBg) = _assignmentPillStyle();
    final (stageLabel, stageFg, stageBg) = switch (effectiveStage) {
      1 => ('Stufe 1 – Verfügbarkeit', AppTheme.stage1Color, AppTheme.stage1Bg),
      2 => ('Stufe 2 – Bewerbung', AppTheme.infoColor, AppTheme.infoBg),
      _ => ('Stufe 3 – Produktion', AppTheme.textSecondary, AppTheme.backgroundColor),
    };

    return SoftCard(
      radius: 20,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipOval(
            child: fsLogoLink.isEmpty
                ? Container(
                    width: 46,
                    height: 46,
                    color: AppTheme.primaryTint,
                    child: const Icon(
                      Icons.flight,
                      color: AppTheme.primaryColor,
                      size: 22,
                    ),
                  )
                : Image.network(
                    fsLogoLink,
                    width: 46,
                    height: 46,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 46,
                      height: 46,
                      color: AppTheme.primaryTint,
                      child: const Icon(
                        Icons.flight,
                        color: AppTheme.primaryColor,
                        size: 22,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fsName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (!isStage1Preview)
                      StatusPill(
                        label: assignLabel,
                        foreground: assignFg,
                        background: assignBg,
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
                    StatusPill(
                      icon: Icons.layers_outlined,
                      label: stageLabel,
                      foreground: stageFg,
                      background: stageBg,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stage1AvailabilityCard extends StatelessWidget {
  final Event event;
  final bool isOwnBinding;
  final List<AvailabilitySubmission> submissions;
  final bool isLoading;
  final bool isSaving;
  final VoidCallback onMarkAvailable;
  final VoidCallback onMarkUnavailable;
  final ValueChanged<AvailabilitySubmission> onDeleteSubmission;
  final VoidCallback onManageAll;

  const _Stage1AvailabilityCard({
    required this.event,
    required this.isOwnBinding,
    required this.submissions,
    required this.isLoading,
    required this.isSaving,
    required this.onMarkAvailable,
    required this.onMarkUnavailable,
    required this.onDeleteSubmission,
    required this.onManageAll,
  });

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SoftCard(
      radius: 20,
      padding: const EdgeInsets.all(16),
      color: isDark ? AppTheme.darkCard : AppTheme.stage1Bg,
      border: Border.all(
        color: AppTheme.stage1Color.withValues(alpha: 0.25),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const TintedIconBadge(
                icon: Icons.event_available_rounded,
                iconColor: AppTheme.stage1Color,
                backgroundColor: Colors.white,
                size: 36,
                iconSize: 19,
                radius: 10,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Planungsstufe 1 – Verfügbarkeit',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
              TextButton(
                onPressed: onManageAll,
                child: const Text('Alle Zeiträume'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            isOwnBinding
                ? 'Du wurdest für dieses Event bereits fest eingeteilt. Andere Team-Positionen werden erst ab Planungsstufe 2 angezeigt.'
                : 'Gib an, ob du für dieses Event verfügbar bist oder nicht. Offene Rollen und Teambesetzungen folgen ab Planungsstufe 2.',
            style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          if (isLoading || isSaving)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (submissions.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: submissions.map((s) {
                final isAvail = s.kind == AvailabilityKind.available;
                final color =
                    isAvail ? AppTheme.successColor : AppTheme.dangerColor;
                final bg = isAvail ? AppTheme.successBg : AppTheme.dangerBg;
                return InputChip(
                  avatar: Icon(
                    isAvail ? Icons.event_available : Icons.event_busy,
                    size: 16,
                    color: color,
                  ),
                  label: Text(
                    '${isAvail ? "Verfügbar" : "Nicht verfügbar"} (${_fmtDate(s.startDate)}–${_fmtDate(s.endDate)})',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  backgroundColor: isDark ? color.withValues(alpha: 0.16) : bg,
                  side: BorderSide(color: color.withValues(alpha: 0.35)),
                  onDeleted: isSaving ? null : () => onDeleteSubmission(s),
                  deleteButtonTooltipMessage: 'Rückmeldung entfernen',
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.successColor,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: isSaving ? null : onMarkAvailable,
                    icon: const Icon(Icons.event_available, size: 18),
                    label: const Text('Verfügbar'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: TextButton.icon(
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
                    ),
                    onPressed: isSaving ? null : onMarkUnavailable,
                    icon: const Icon(Icons.event_busy, size: 18),
                    label: const Text('Nicht verfügbar'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BottomActionBar extends StatelessWidget {
  final Event event;
  final String currentUserId;
  final bool isStage3;
  final bool isOwnAccepted;
  final VoidCallback onRequest;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onChange;
  final VoidCallback onOfferSwap;
  final VoidCallback onRequestSwap;

  const _BottomActionBar({
    required this.event,
    required this.currentUserId,
    required this.isStage3,
    required this.isOwnAccepted,
    required this.onRequest,
    required this.onAccept,
    required this.onDecline,
    required this.onChange,
    required this.onOfferSwap,
    required this.onRequestSwap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final actions = <Widget>[];

    Widget softDangerBtn({
      required IconData icon,
      required String label,
      required VoidCallback onPressed,
    }) {
      return SizedBox(
        height: 48,
        child: TextButton.icon(
          style: TextButton.styleFrom(
            backgroundColor: isDark
                ? AppTheme.dangerColor.withValues(alpha: 0.18)
                : AppTheme.dangerBg,
            foregroundColor:
                isDark ? const Color(0xFFFCA5A5) : AppTheme.dangerColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      );
    }

    Widget primaryBtn({
      required IconData icon,
      required String label,
      required VoidCallback? onPressed,
    }) {
      return Container(
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: onPressed != null ? AppTheme.primaryGlow : null,
        ),
        child: FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      );
    }

    if (event.isSwapOfferFromOther && isStage3) {
      final alreadyRequestedByMe = event.swapRequestedBy == currentUserId;
      final requestedByOther =
          event.hasOpenSwapRequest && !alreadyRequestedByMe;
      actions.add(
        Expanded(
          child: primaryBtn(
            onPressed: (alreadyRequestedByMe || requestedByOther)
                ? null
                : onRequestSwap,
            icon: Icons.swap_horiz_rounded,
            label: alreadyRequestedByMe
                ? 'Übernahme angefragt (warte auf Admin)'
                : requestedByOther
                    ? 'Bereits von anderem Mitglied angefragt'
                    : 'Tauschplatz anfragen',
          ),
        ),
      );
    } else {
      switch (event.assignmentStatus) {
        case EventUserStatusEnum.open:
          actions.add(
            Expanded(
              child: primaryBtn(
                onPressed: onRequest,
                icon: Icons.how_to_reg_outlined,
                label: 'Auf Rolle bewerben',
              ),
            ),
          );
          break;
        case EventUserStatusEnum.pending_user:
          actions.addAll([
            Expanded(
              child: softDangerBtn(
                onPressed: onDecline,
                icon: Icons.close_rounded,
                label: 'Ablehnen',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: primaryBtn(
                onPressed: onAccept,
                icon: Icons.check_rounded,
                label: 'Zusagen',
              ),
            ),
          ]);
          break;
        case EventUserStatusEnum.accepted_user:
        case EventUserStatusEnum.accepted_flight_school:
          actions.add(
            Expanded(
              child: softDangerBtn(
                onPressed: onChange,
                icon: Icons.change_circle_outlined,
                label: 'Änderung anfragen',
              ),
            ),
          );
          if (isStage3) {
            actions.add(const SizedBox(width: 10));
            actions.add(
              Expanded(
                child: primaryBtn(
                  onPressed: onOfferSwap,
                  icon: Icons.swap_horiz_rounded,
                  label: event.swapOffered
                      ? 'Tausch abbrechen'
                      : 'Tausch anfragen',
                ),
              ),
            );
          }
          break;
        default:
          break;
      }
    }

    if (actions.isEmpty) return const SizedBox.shrink();

    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          child: Row(children: actions),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SoftCard(
      radius: 20,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          TintedIconBadge(
            icon: icon,
            iconColor: AppTheme.primaryColor,
            backgroundColor: AppTheme.primaryTint,
            size: 32,
            iconSize: 16,
            radius: 9,
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionDialog extends StatefulWidget {
  final String title;
  final String message;
  final Future<bool> Function() action;

  const _ActionDialog({
    required this.title,
    required this.message,
    required this.action,
  });

  @override
  State<_ActionDialog> createState() => _ActionDialogState();
}

class _ActionDialogState extends State<_ActionDialog> {
  bool _running = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content:
          _running
              ? const SizedBox(
                height: 60,
                child: Center(child: CircularProgressIndicator()),
              )
              : Text(widget.message),
      actions:
          _running
              ? null
              : [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Abbrechen'),
                ),
                FilledButton(
                  onPressed: () async {
                    setState(() => _running = true);
                    final ok = await widget.action();
                    if (!context.mounted) return;
                    Navigator.pop(context, ok);
                  },
                  child: const Text('Bestätigen'),
                ),
              ],
    );
  }
}
