import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/core/data/enums/event_role_enum.dart';
import 'package:season_planner/core/data/enums/membership_status_enum.dart';
import 'package:season_planner/core/data/enums/team_tier_enum.dart';
import 'package:season_planner/core/data/models/qualification_model.dart';
import 'package:season_planner/core/services/qualification_service.dart';
import 'package:season_planner/core/theme.dart';
import 'package:season_planner/core/widgets/document_preview_dialog.dart';
import 'package:season_planner/core/widgets/user_avatar.dart';
import 'package:season_planner/core/widgets/ux_components.dart';
import 'package:season_planner/fsAdmin/data/models/flight_school_model_flight_school_view.dart';
import 'package:season_planner/fsAdmin/data/models/user_summary_flight_school_view.dart';
import 'package:season_planner/fsAdmin/features/manage_qualifications/manage_qualifications_view.dart';
import 'package:season_planner/fsAdmin/flight_school_provider.dart';
import 'package:season_planner/fsAdmin/services/flight_school_service.dart';
import 'package:url_launcher/url_launcher.dart';

class ManagePersonalView extends StatefulWidget {
  final bool isLoading;
  final bool hasConnection;
  final DateTime? lastUpdated;

  const ManagePersonalView({
    super.key,
    this.isLoading = false,
    this.hasConnection = true,
    this.lastUpdated,
  });

  @override
  State<ManagePersonalView> createState() => _ManagePersonalViewState();
}

class _ManagePersonalViewState extends State<ManagePersonalView> {
  final _flightSchoolService = FlightSchoolService();
  final _searchCtrl = TextEditingController();
  String _search = "";
  bool _busy = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<UserSummary> _filteredMembers(List<UserSummary> members) {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return members;
    return members.where((m) {
      return m.name.toLowerCase().contains(q) ||
          m.mail.toLowerCase().contains(q) ||
          m.phone.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _openInviteDialog() async {
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null) return;

    final emailCtrl = TextEditingController();
    final selectedRoles = <String>{};

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text("Mitglied einladen"),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: "E-Mail-Adresse",
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "Rollen vorab zuweisen (optional):",
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  ...fs.availableRoleNames.map((roleName) {
                    return CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: selectedRoles.contains(roleName),
                      title: Text(roleName),
                      onChanged: (v) {
                        setLocal(() {
                          if (v == true) {
                            selectedRoles.add(roleName);
                          } else {
                            selectedRoles.remove(roleName);
                          }
                        });
                      },
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Abbrechen"),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Einladen"),
            ),
          ],
        ),
      ),
    );

    final email = emailCtrl.text.trim();
    emailCtrl.dispose();
    if (ok != true) return;

    if (email.isEmpty || !email.contains("@")) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Bitte eine gültige E-Mail-Adresse eingeben."),
        ),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      await _flightSchoolService.inviteMember(
        flightSchoolId: fs.id,
        email: email,
        roles: selectedRoles.toList(),
      );

      if (!mounted) return;
      context.read<FlightSchoolProvider>().reloadFlightSchoolInBackground(
            _flightSchoolService.getFlightSchool,
          );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Einladung an $email gesendet.")),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Einladung fehlgeschlagen: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editRolesForUser(UserSummary user) async {
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null) return;

    final allRoleNames = <String>{
      ...fs.availableRoleNames,
      ...user.roles.map(EventRoleEnum.displayLabel),
    }.toList();

    final workingRoles = user.roles.map(EventRoleEnum.displayLabel).toSet();
    final workingQualIds = user.qualificationIds.toSet();
    final requestedQualIds = user.requestedQualificationIds.toSet();
    TeamTierEnum workingTier = user.teamTier;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(
            "Team-Einstellungen: ${user.displayName}",
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    "Team-Einstufung (nur für Admins sichtbar):",
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<TeamTierEnum>(
                    segments: const [
                      ButtonSegment<TeamTierEnum>(
                        value: TeamTierEnum.core,
                        label: Text('Stammteam'),
                        icon: Icon(Icons.verified_user_outlined, size: 16),
                      ),
                      ButtonSegment<TeamTierEnum>(
                        value: TeamTierEnum.extended,
                        label: Text('Erweitertes Team'),
                        icon: Icon(Icons.group_outlined, size: 16),
                      ),
                    ],
                    selected: {workingTier},
                    onSelectionChanged: (sel) {
                      if (sel.isNotEmpty) {
                        setLocal(() => workingTier = sel.first);
                      }
                    },
                  ),
                  const SizedBox(height: 6),
                  Text(
                    workingTier == TeamTierEnum.core
                        ? 'Sieht alle Event-Details und kann sich selbstständig auf offene Stellen bewerben.'
                        : 'Sieht nicht zugewiesene Events nur grau ohne Details und kann sich nicht direkt bewerben – nur direkte Admin-Anfragen & Einteilungen. Für das Mitglied unsichtbar.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                  const Divider(height: 22),
                  const Text(
                    "Qualifikationen (für Pflichtnachweise & Rollen-Voraussetzungen):",
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  if (fs.qualifications.isEmpty)
                    const Text(
                      "Keine Qualifikationen definiert.",
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    )
                  else
                    ...fs.qualifications.map((q) {
                      final isRequested = requestedQualIds.contains(q.id);
                      return CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: workingQualIds.contains(q.id),
                        title: Row(
                          children: [
                            Expanded(child: Text(q.name)),
                            if (isRequested && !workingQualIds.contains(q.id))
                              const Chip(
                                label: Text(
                                  "Angefragt",
                                  style: TextStyle(fontSize: 11),
                                ),
                                backgroundColor: Color(0xFFFFE0B2),
                                visualDensity: VisualDensity.compact,
                              ),
                          ],
                        ),
                        subtitle: q.requiredDocuments.isEmpty
                            ? null
                            : Text(
                                "Nachweise: ${q.requiredDocuments.join(', ')}",
                                style: const TextStyle(fontSize: 11.5),
                              ),
                        onChanged: (v) {
                          setLocal(() {
                            if (v == true) {
                              workingQualIds.add(q.id);
                            } else {
                              workingQualIds.remove(q.id);
                            }
                          });
                        },
                      );
                    }),
                  const Divider(height: 22),
                  const Text(
                    "Freigeschaltete Teamrollen (Einsatzpositionen):",
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  ...allRoleNames.map((roleName) {
                    final roleMatches = fs.teamRoles
                        .where((r) =>
                            r.name.toLowerCase() == roleName.toLowerCase())
                        .toList();
                    String? missingHint;
                    if (roleMatches.isNotEmpty) {
                      final r = roleMatches.first;
                      if (r.requiredQualificationIds.isNotEmpty) {
                        final hasAll = r.requiredQualificationIds
                            .every(workingQualIds.contains);
                        final hasAny = r.requiredQualificationIds
                            .any(workingQualIds.contains);
                        final ok =
                            r.requireAllQualifications ? hasAll : hasAny;
                        if (!ok) {
                          final names = r.requiredQualificationIds
                              .map(fs.qualificationName)
                              .join(r.requireAllQualifications
                                  ? ' & '
                                  : ' ODER ');
                          missingHint = 'Erfordert Qualifikation: $names';
                        }
                      }
                    }

                    return CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: workingRoles.contains(roleName),
                      title: Text(roleName),
                      subtitle: missingHint == null
                          ? null
                          : Text(
                              missingHint,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Colors.orange.shade800,
                              ),
                            ),
                      onChanged: (v) {
                        setLocal(() {
                          if (v == true) {
                            workingRoles.add(roleName);
                          } else {
                            workingRoles.remove(roleName);
                          }
                        });
                      },
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Abbrechen"),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Speichern"),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    // Zugeteilte Qualifikationen automatisch aus offenen Anfragen entfernen
    final remainingRequests = requestedQualIds
        .where((id) => !workingQualIds.contains(id))
        .toList();
    final qualLabelStr = workingQualIds.isEmpty
        ? 'keine'
        : workingQualIds.map(fs.qualificationName).join(', ');

    setState(() => _busy = true);
    try {
      await _flightSchoolService.updateMemberRolesAndQualifications(
        user.membershipId,
        roles: workingRoles.toList(),
        qualificationIds: workingQualIds.toList(),
        remainingRequestedQualificationIds: remainingRequests,
        teamTier: workingTier,
        flightSchoolId: fs.id,
        memberName: user.displayName,
        qualificationLabels: qualLabelStr,
      );

      if (!mounted) return;
      context.read<FlightSchoolProvider>().reloadFlightSchoolInBackground(
            _flightSchoolService.getFlightSchool,
          );
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text("Qualifikationen & Einsatzrollen gespeichert."),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text("Aktualisierung fehlgeschlagen: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showMemberDetailSheet(UserSummary member) async {
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null) return;

    await showAdaptiveSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      desktopMaxWidth: 560,
      builder: (ctx) => _MemberDetailSheet(
        flightSchool: fs,
        member: member,
        onEditRoles: () async {
          Navigator.pop(ctx);
          await _editRolesForUser(member);
        },
      ),
    );
  }

  Future<void> _showEmergencyContactDialog(UserSummary user) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.emergency_outlined, color: AppTheme.dangerColor),
              const SizedBox(width: 8),
              Expanded(child: Text('Notfallkontakt: ${user.displayName}')),
            ],
          ),
          content: user.hasEmergencyContact
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (user.emergencyContactName.isNotEmpty)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.person_outline),
                        title: const Text(
                          'Name',
                          style: TextStyle(fontSize: 12),
                        ),
                        subtitle: Text(
                          user.emergencyContactName,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    if (user.emergencyContactRelation.isNotEmpty)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.favorite_border),
                        title: const Text(
                          'Beziehung',
                          style: TextStyle(fontSize: 12),
                        ),
                        subtitle: Text(
                          user.emergencyContactRelation,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (user.emergencyContactPhone.isNotEmpty)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.phone_in_talk_outlined,
                          color: AppTheme.dangerColor,
                        ),
                        title: const Text(
                          'Telefonnummer',
                          style: TextStyle(fontSize: 12),
                        ),
                        subtitle: SelectableText(
                          user.emergencyContactPhone,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        trailing: FilledButton.tonalIcon(
                          onPressed: () async {
                            final uri = Uri(
                              scheme: 'tel',
                              path: user.emergencyContactPhone.trim(),
                            );
                            await launchUrl(uri);
                          },
                          icon: const Icon(Icons.call, size: 16),
                          label: const Text('Anrufen'),
                        ),
                      ),
                  ],
                )
              : Text(
                  '${user.displayName} hat noch keinen Notfallkontakt im Profil hinterlegt.',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Schließen'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _removeMember(UserSummary user) async {
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Mitglied entfernen?"),
        content: Text(
          "Möchtest du ${user.name.isEmpty ? user.mail : user.name} wirklich aus dem Team entfernen?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Abbrechen"),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.dangerColor),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Entfernen"),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await _flightSchoolService.removeMemberOfFlightSchool(
        user.membershipId,
        flightSchoolId: fs.id,
        memberName: user.name.isEmpty ? user.mail : user.name,
      );
      if (!mounted) return;
      context.read<FlightSchoolProvider>().reloadFlightSchoolInBackground(
            _flightSchoolService.getFlightSchool,
          );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Mitglied entfernt.")),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approveRequest(UserSummary req) async {
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null) return;

    setState(() => _busy = true);
    try {
      await _flightSchoolService.approveJoinRequest(
        flightSchoolId: fs.id,
        membershipId: req.membershipId,
        memberName: req.name.isEmpty ? req.mail : req.name,
      );
      if (!mounted) return;
      await context.read<FlightSchoolProvider>().reloadFlightSchool(
            _flightSchoolService.getFlightSchool,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Teammitglied „${req.name.isEmpty ? req.mail : req.name}“ angenommen.",
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rejectRequest(UserSummary req) async {
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null) return;

    setState(() => _busy = true);
    try {
      await _flightSchoolService.rejectJoinRequest(
        flightSchoolId: fs.id,
        membershipId: req.membershipId,
        memberName: req.name.isEmpty ? req.mail : req.name,
      );
      if (!mounted) return;
      await context.read<FlightSchoolProvider>().reloadFlightSchool(
            _flightSchoolService.getFlightSchool,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Beitrittsanfrage abgelehnt.")),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fs = context.watch<FlightSchoolProvider>().flightSchool;
    if (fs == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final members = _filteredMembers(fs.members);
    final pendingRequests = fs.pendingRequests;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Personal verwalten"),
          automaticallyImplyLeading: false,
          actions: [
            const AdminFlightSchoolSwitcherChip(),
            const AppModeSwitchChip(isAdminMode: true),
            const AppBarActionDivider(),
            ConnectionStatusAction(
              isLoading: widget.isLoading,
              hasConnection: widget.hasConnection,
              lastUpdated: widget.lastUpdated,
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: 'Team (${fs.members.length})'),
              Tab(
                text: pendingRequests.isEmpty
                    ? 'Beitrittsanfragen'
                    : 'Beitrittsanfragen (${pendingRequests.length})',
              ),
            ],
          ),
        ),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              if (_busy) const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: TabBarView(
                  children: [
                    // TAB 1: Aktive & eingeladene Mitglieder
                    Column(
                      children: [
                        if (fs.openQualificationRequestCount > 0)
                          SoftCard(
                            margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 11,
                            ),
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                    ? AppTheme.darkCard
                                    : AppTheme.warningBg,
                            border: Border.all(
                              color:
                                  AppTheme.warningColor.withValues(alpha: 0.25),
                            ),
                            child: Row(
                              children: [
                                const TintedIconBadge(
                                  icon: Icons.workspace_premium_outlined,
                                  iconColor: AppTheme.warningColor,
                                  backgroundColor: Colors.white,
                                  size: 38,
                                  iconSize: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    '${fs.openQualificationRequestCount} offene Qualifikations-Anfrage${fs.openQualificationRequestCount == 1 ? "" : "n"}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppTheme.warningColor,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 9,
                                    ),
                                  ),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const ManageQualificationsView(
                                          initialTab: 1,
                                        ),
                                      ),
                                    );
                                  },
                                  child: const Text('Prüfen'),
                                ),
                              ],
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                          child: TextField(
                            controller: _searchCtrl,
                            decoration: InputDecoration(
                              hintText: "Suchen (Name / E-Mail / Telefon)",
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: _search.isEmpty
                                  ? null
                                  : IconButton(
                                      icon: const Icon(Icons.clear),
                                      onPressed: () {
                                        _searchCtrl.clear();
                                        setState(() => _search = "");
                                      },
                                    ),
                            ),
                            onChanged: (v) => setState(() => _search = v),
                          ),
                        ),
                        Expanded(
                          child: members.isEmpty
                              ? (_search.trim().isNotEmpty
                                  ? EmptyStateView(
                                      icon: Icons.search_off_outlined,
                                      title: 'Keine Treffer für „$_search“',
                                      subtitle:
                                          'Prüfe die Schreibweise oder setze die Suche zurück.',
                                      actionLabel: 'Suche zurücksetzen',
                                      actionIcon: Icons.clear,
                                      onAction: () {
                                        _searchCtrl.clear();
                                        setState(() => _search = '');
                                      },
                                    )
                                  : EmptyStateView(
                                      icon: Icons.groups_outlined,
                                      title: 'Noch keine Teammitglieder',
                                      subtitle:
                                          'Lade dein Team per E-Mail ein oder bestätige eingehende Beitrittsanfragen.',
                                      actionLabel: 'Mitglied einladen',
                                      actionIcon: Icons.mail_outline,
                                      onAction:
                                          _busy ? null : _openInviteDialog,
                                    ))
                              : ListView.separated(
                                  padding:
                                      const EdgeInsets.fromLTRB(12, 8, 12, 148),
                                  itemCount: members.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (context, index) {
                                    final m = members[index];
                                    final cs = Theme.of(context).colorScheme;
                                    final isInvited = m.membershipStatus ==
                                        MembershipStatusEnum.invited;
                                    final roleLabels = m.roles
                                        .map(EventRoleEnum.displayLabel)
                                        .toList();
                                    return SoftCard(
                                      padding: const EdgeInsets.fromLTRB(
                                        14,
                                        12,
                                        6,
                                        12,
                                      ),
                                      onTap: _busy
                                          ? null
                                          : () => _showMemberDetailSheet(m),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 2),
                                            child: UserAvatar(
                                              avatarUrl: m.avatarUrl,
                                              name: m.displayName,
                                              radius: 22,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        m.name.isEmpty
                                                            ? "Unbenannter Nutzer"
                                                            : m.name,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          fontSize: 15,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    if (m.isExtendedTeam) ...[
                                                      StatusPill(
                                                        label: 'Erweitert',
                                                        foreground: cs
                                                            .onSurfaceVariant,
                                                        background: cs
                                                            .surfaceContainerHighest,
                                                        fontSize: 10.5,
                                                      ),
                                                      const SizedBox(width: 4),
                                                    ],
                                                    StatusPill(
                                                      label: isInvited
                                                          ? 'Eingeladen'
                                                          : 'Aktiv',
                                                      foreground: isInvited
                                                          ? AppTheme
                                                              .warningColor
                                                          : AppTheme
                                                              .successColor,
                                                      background: isInvited
                                                          ? AppTheme.warningBg
                                                          : AppTheme.successBg,
                                                      fontSize: 10.5,
                                                    ),
                                                  ],
                                                ),
                                                if (m.mail.isNotEmpty ||
                                                    m.phone.isNotEmpty) ...[
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    [
                                                      if (m.mail.isNotEmpty)
                                                        m.mail,
                                                      if (m.phone.isNotEmpty)
                                                        m.phone,
                                                    ].join(' · '),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color:
                                                          cs.onSurfaceVariant,
                                                      fontSize: 12.5,
                                                    ),
                                                  ),
                                                ],
                                                if (m.hasEmergencyContact)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                      top: 4,
                                                    ),
                                                    child: InkWell(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        6,
                                                      ),
                                                      onTap: () =>
                                                          _showEmergencyContactDialog(
                                                        m,
                                                      ),
                                                      child: const Padding(
                                                        padding:
                                                            EdgeInsets.symmetric(
                                                          vertical: 2,
                                                        ),
                                                        child: Row(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            Icon(
                                                              Icons
                                                                  .emergency_outlined,
                                                              size: 13,
                                                              color: AppTheme
                                                                  .dangerColor,
                                                            ),
                                                            SizedBox(width: 4),
                                                            Text(
                                                              'Notfallkontakt hinterlegt · Anzeigen',
                                                              style: TextStyle(
                                                                fontSize: 11.5,
                                                                color: AppTheme
                                                                    .dangerColor,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                const SizedBox(height: 8),
                                                Wrap(
                                                  spacing: 6,
                                                  runSpacing: 5,
                                                  children: [
                                                    if (roleLabels.isEmpty)
                                                      const StatusPill(
                                                        label: 'Keine Rolle',
                                                        foreground: AppTheme
                                                            .textSecondary,
                                                        background:
                                                            Color(0xFFECEEF3),
                                                        fontSize: 11,
                                                      )
                                                    else
                                                      ...roleLabels.map(
                                                        (r) => StatusPill(
                                                          label: r,
                                                          foreground: AppTheme
                                                              .primaryColor,
                                                          background: AppTheme
                                                              .primaryTint,
                                                          fontSize: 11,
                                                        ),
                                                      ),
                                                    ...m.qualificationIds.map(
                                                      (qId) => StatusPill(
                                                        label: fs
                                                            .qualificationName(
                                                          qId,
                                                        ),
                                                        foreground:
                                                            AppTheme.swapColor,
                                                        background:
                                                            AppTheme.swapBg,
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                    if (m
                                                        .requestedQualificationIds
                                                        .isNotEmpty)
                                                      StatusPill(
                                                        label:
                                                            'Angefragt: ${m.requestedQualificationIds.map(fs.qualificationName).join(', ')}',
                                                        foreground: AppTheme
                                                            .warningColor,
                                                        background:
                                                            AppTheme.warningBg,
                                                        fontSize: 11,
                                                      ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          PopupMenuButton<String>(
                                            tooltip: "Aktionen",
                                            onSelected: (value) {
                                              if (value == "details") {
                                                _showMemberDetailSheet(m);
                                              }
                                              if (value == "emergency") {
                                                _showEmergencyContactDialog(m);
                                              }
                                              if (value == "remove") {
                                                _removeMember(m);
                                              }
                                              if (value == "roles") {
                                                _editRolesForUser(m);
                                              }
                                            },
                                            itemBuilder: (_) => const [
                                              PopupMenuItem(
                                                value: "details",
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      Icons.badge_outlined,
                                                      size: 20,
                                                    ),
                                                    SizedBox(width: 12),
                                                    Text(
                                                      "Details & Dokumente",
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              PopupMenuItem(
                                                value: "roles",
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      Icons.edit_outlined,
                                                      size: 20,
                                                    ),
                                                    SizedBox(width: 12),
                                                    Text(
                                                      "Qualifikationen & Rollen",
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              PopupMenuItem(
                                                value: "emergency",
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      Icons.emergency_outlined,
                                                      size: 20,
                                                      color:
                                                          AppTheme.dangerColor,
                                                    ),
                                                    SizedBox(width: 12),
                                                    Text(
                                                      "Notfallkontakt anzeigen",
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              PopupMenuItem(
                                                value: "remove",
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      Icons
                                                          .person_remove_outlined,
                                                      size: 20,
                                                      color:
                                                          AppTheme.dangerColor,
                                                    ),
                                                    SizedBox(width: 12),
                                                    Text(
                                                      "Entfernen",
                                                      style: TextStyle(
                                                        color: AppTheme
                                                            .dangerColor,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),

                    // TAB 2: Beitrittsanfragen (Option A)
                    pendingRequests.isEmpty
                        ? const EmptyStateView(
                            icon: Icons.person_add_disabled_outlined,
                            title: 'Keine offenen Beitrittsanfragen',
                            subtitle:
                                'Wenn sich neue Teammitglieder über den Flugschul-Code bewerben, erscheinen ihre Anfragen hier.',
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(12),
                            itemCount: pendingRequests.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final req = pendingRequests[index];
                              return SoftCard(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        UserAvatar(
                                          avatarUrl: req.avatarUrl,
                                          name: req.displayName,
                                          radius: 22,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                req.name.isEmpty
                                                    ? "Unbenannter Nutzer"
                                                    : req.name,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 15,
                                                ),
                                              ),
                                              if (req.mail.isNotEmpty)
                                                Text(
                                                  req.mail,
                                                  style: TextStyle(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      children: [
                                        FilledButton.icon(
                                          onPressed: _busy
                                              ? null
                                              : () => _approveRequest(req),
                                          icon: const Icon(
                                            Icons.check,
                                            size: 18,
                                          ),
                                          label: const Text(
                                            "Teammitglied annehmen",
                                          ),
                                        ),
                                        OutlinedButton.icon(
                                          onPressed: _busy
                                              ? null
                                              : () => _rejectRequest(req),
                                          icon: const Icon(
                                            Icons.close,
                                            size: 18,
                                          ),
                                          label: const Text("Ablehnen"),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ],
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: AdaptiveFloatingActionButton(
          onPressed: _busy ? null : _openInviteDialog,
          icon: Icons.mail_outline,
          label: "Einladen",
        ),
      ),
    );
  }
}

class _MemberDetailSheet extends StatefulWidget {
  final FlightSchoolModelFlightSchoolView flightSchool;
  final UserSummary member;
  final Future<void> Function() onEditRoles;

  const _MemberDetailSheet({
    required this.flightSchool,
    required this.member,
    required this.onEditRoles,
  });

  @override
  State<_MemberDetailSheet> createState() => _MemberDetailSheetState();
}

class _MemberDetailSheetState extends State<_MemberDetailSheet> {
  final _qualService = QualificationService();
  bool _loadingDocs = true;
  bool _busyDoc = false;
  bool _showExpiredDocs = false;
  List<QualificationApproval> _approvals = [];
  final Map<String, QualificationDocument?> _docsById = {};

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  Future<void> _loadDocuments() async {
    setState(() => _loadingDocs = true);
    try {
      final allApprovals =
          await _qualService.listSchoolApprovals(widget.flightSchool.id);
      final memberApprovals = allApprovals
          .where((a) => widget.member.matchesId(a.userId))
          .toList()
        ..sort((a, b) => a.documentType.compareTo(b.documentType));

      final docIds = memberApprovals.map((a) => a.documentId).toSet().toList();
      final fetched = await Future.wait(
        docIds.map((id) => _qualService.getDocumentById(id)),
      );
      final map = <String, QualificationDocument?>{};
      for (var i = 0; i < docIds.length; i++) {
        map[docIds[i]] = fetched[i];
      }

      if (!mounted) return;
      setState(() {
        _approvals = memberApprovals;
        _docsById
          ..clear()
          ..addAll(map);
        _loadingDocs = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingDocs = false);
    }
  }

  Future<void> _openDocument(
    QualificationDocument doc, {
    QualificationApproval? approval,
  }) async {
    final changed = await showQualificationDocumentPopup(
      context: context,
      document: doc,
      approval: approval,
      ownerName: widget.member.displayName,
      flightSchoolId: widget.flightSchool.id,
      canReview: true,
    );
    if (changed && mounted) {
      await _loadDocuments();
    }
  }

  Future<void> _approveDoc(QualificationApproval approval) async {
    setState(() => _busyDoc = true);
    try {
      await _qualService.reviewApproval(
        approval: approval,
        decision: ApprovalStatusEnum.approved,
        comment: '',
      );
      await _loadDocuments();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Nachweis „${approval.documentType}“ bestätigt.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busyDoc = false);
    }
  }

  Future<void> _editDocExpiry(QualificationDocument doc) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: doc.expiresAt ?? now.add(const Duration(days: 365)),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Gültig bis anpassen (${doc.documentType})',
    );
    if (picked == null || !mounted) return;
    setState(() => _busyDoc = true);
    try {
      final updated = await _qualService.updateDocumentExpiry(
        doc: doc,
        expiresAt: picked,
        flightSchoolId: widget.flightSchool.id,
      );
      if (!mounted) return;
      if (updated != null) {
        setState(() => _docsById[doc.id] = updated);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Gültig bis für „${doc.documentType}“ auf ${_fmtDate(picked)} aktualisiert.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busyDoc = false);
    }
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return 'Unbefristet';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final m = widget.member;
    final fs = widget.flightSchool;
    final isInvited = m.membershipStatus == MembershipStatusEnum.invited;
    final roleLabels = m.roles.map(EventRoleEnum.displayLabel).toList();

    final personalEntries = <(IconData, String, String)>[
      if (m.mail.trim().isNotEmpty)
        (Icons.email_outlined, 'E-Mail', m.mail.trim()),
      if (m.phone.trim().isNotEmpty)
        (Icons.phone_outlined, 'Telefon', m.phone.trim()),
      if (m.birthDate.trim().isNotEmpty)
        (Icons.cake_outlined, 'Geburtsdatum', m.birthDate.trim()),
      if (m.address.trim().isNotEmpty)
        (Icons.home_outlined, 'Anschrift', m.address.trim()),
      if (m.licenseNumber.trim().isNotEmpty)
        (Icons.credit_card_outlined, 'Scheinnummer / Lizenz-Nr.', m.licenseNumber.trim()),
      if (m.licenseRatings.trim().isNotEmpty)
        (Icons.verified_outlined, 'Berechtigungen', m.licenseRatings.trim()),
      if (m.employmentType.trim().isNotEmpty)
        (Icons.work_outline, 'Beschäftigungsart', m.employmentType.trim()),
      if (m.activeSince.trim().isNotEmpty)
        (Icons.event_available_outlined, 'Tätig seit', m.activeSince.trim()),
    ];

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 16, 12),
              child: Row(
                children: [
                  UserAvatar(
                    avatarUrl: m.avatarUrl,
                    name: m.displayName,
                    radius: 26,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                m.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 17,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            StatusPill(
                              label: isInvited ? 'Eingeladen' : 'Aktiv',
                              foreground: isInvited
                                  ? AppTheme.warningColor
                                  : AppTheme.successColor,
                              background: isInvited
                                  ? AppTheme.warningBg
                                  : AppTheme.successBg,
                              fontSize: 11,
                            ),
                          ],
                        ),
                        if (m.mail.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            m.mail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (m.phone.trim().isNotEmpty)
                    IconButton.filledTonal(
                      tooltip: 'Anrufen',
                      icon: const Icon(Icons.call_outlined, size: 19),
                      onPressed: () async {
                        await launchUrl(Uri(scheme: 'tel', path: m.phone.trim()));
                      },
                    ),
                ],
              ),
            ),
            if (_busyDoc) const LinearProgressIndicator(minHeight: 2),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Schnellaktion: Rollen & Qualifikationen bearbeiten
                    FilledButton.tonalIcon(
                      onPressed: widget.onEditRoles,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Qualifikationen & Rollen bearbeiten'),
                    ),
                    const SizedBox(height: 16),

                    // Qualifikationen & Rollen
                    _DetailSectionTitle(title: 'QUALIFIKATIONEN & ROLLEN'),
                    SoftCard(
                      padding: const EdgeInsets.all(14),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (roleLabels.isEmpty && m.qualificationIds.isEmpty)
                            Text(
                              'Noch keine Rollen oder Qualifikationen zugewiesen.',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ...roleLabels.map(
                            (r) => StatusPill(
                              label: r,
                              foreground: AppTheme.primaryColor,
                              background: AppTheme.primaryTint,
                              fontSize: 11.5,
                            ),
                          ),
                          ...m.qualificationIds.map(
                            (qId) => StatusPill(
                              label: fs.qualificationName(qId),
                              foreground: AppTheme.swapColor,
                              background: AppTheme.swapBg,
                              fontSize: 11.5,
                            ),
                          ),
                          if (m.requestedQualificationIds.isNotEmpty)
                            StatusPill(
                              label:
                                  'Angefragt: ${m.requestedQualificationIds.map(fs.qualificationName).join(', ')}',
                              foreground: AppTheme.warningColor,
                              background: AppTheme.warningBg,
                              fontSize: 11.5,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Persönliche Daten & Lizenzdaten
                    _DetailSectionTitle(title: 'PERSÖNLICHE & LIZENZDATEN'),
                    SoftCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: personalEntries.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Text(
                                'Keine weiteren persönlichen Daten hinterlegt.',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            )
                          : Column(
                              children: List.generate(personalEntries.length, (i) {
                                final (icon, label, value) = personalEntries[i];
                                return Column(
                                  children: [
                                    if (i > 0)
                                      Divider(
                                        height: 1,
                                        color: cs.outlineVariant,
                                      ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(
                                            icon,
                                            size: 18,
                                            color: cs.onSurfaceVariant,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  label,
                                                  style: TextStyle(
                                                    fontSize: 11.5,
                                                    color: cs.onSurfaceVariant,
                                                  ),
                                                ),
                                                const SizedBox(height: 1),
                                                SelectableText(
                                                  value,
                                                  style: const TextStyle(
                                                    fontSize: 13.5,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              }),
                            ),
                    ),
                    const SizedBox(height: 16),

                    // Notfallkontakt
                    _DetailSectionTitle(title: 'NOTFALLKONTAKT'),
                    SoftCard(
                      padding: const EdgeInsets.all(14),
                      child: m.hasEmergencyContact
                          ? Row(
                              children: [
                                const TintedIconBadge(
                                  icon: Icons.emergency_outlined,
                                  iconColor: AppTheme.dangerColor,
                                  backgroundColor: AppTheme.dangerBg,
                                  size: 38,
                                  iconSize: 19,
                                  radius: 10,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        [
                                          if (m.emergencyContactName.isNotEmpty)
                                            m.emergencyContactName,
                                          if (m.emergencyContactRelation
                                              .isNotEmpty)
                                            '(${m.emergencyContactRelation})',
                                        ].join(' '),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13.5,
                                        ),
                                      ),
                                      if (m.emergencyContactPhone.isNotEmpty)
                                        SelectableText(
                                          m.emergencyContactPhone,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: cs.onSurfaceVariant,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (m.emergencyContactPhone.trim().isNotEmpty)
                                  FilledButton.tonalIcon(
                                    onPressed: () async {
                                      await launchUrl(
                                        Uri(
                                          scheme: 'tel',
                                          path: m.emergencyContactPhone.trim(),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.call, size: 16),
                                    label: const Text('Anrufen'),
                                  ),
                              ],
                            )
                          : Text(
                              'Noch kein Notfallkontakt im Profil hinterlegt.',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                    ),
                    const SizedBox(height: 16),

                    // Eingereichte Dokumente
                    Builder(
                      builder: (context) {
                        final activeApprovals = _approvals
                            .where((a) => !(_docsById[a.documentId]?.isExpired ?? false))
                            .toList();
                        final expiredApprovals = _approvals
                            .where((a) => _docsById[a.documentId]?.isExpired ?? false)
                            .toList();
                        final visibleApprovals = _showExpiredDocs
                            ? [...activeApprovals, ...expiredApprovals]
                            : activeApprovals;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                const Expanded(
                                  child: _DetailSectionTitle(
                                    title: 'EINGEREICHTE DOKUMENTE',
                                  ),
                                ),
                                if (!_loadingDocs && expiredApprovals.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 6, right: 6),
                                    child: TextButton.icon(
                                      style: TextButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(horizontal: 8),
                                      ),
                                      onPressed: () => setState(
                                        () => _showExpiredDocs = !_showExpiredDocs,
                                      ),
                                      icon: Icon(
                                        _showExpiredDocs
                                            ? Icons.visibility_off_outlined
                                            : Icons.history_rounded,
                                        size: 15,
                                      ),
                                      label: Text(
                                        _showExpiredDocs
                                            ? 'Alte ausblenden'
                                            : 'Alte anzeigen (${expiredApprovals.length})',
                                        style: const TextStyle(fontSize: 11.5),
                                      ),
                                    ),
                                  ),
                                if (!_loadingDocs)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: StatusPill(
                                      label: '${activeApprovals.length}',
                                      foreground: AppTheme.primaryColor,
                                      background: AppTheme.primaryTint,
                                      fontSize: 11,
                                    ),
                                  ),
                              ],
                            ),
                            if (_loadingDocs)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 20),
                                child: Center(child: CircularProgressIndicator()),
                              )
                            else if (visibleApprovals.isEmpty)
                              SoftCard(
                                padding: const EdgeInsets.all(14),
                                child: Text(
                                  expiredApprovals.isNotEmpty
                                      ? 'Keine aktuell gültigen Dokumente vorhanden (${expiredApprovals.length} abgelaufen).'
                                      : 'Dieses Mitglied hat noch keine Nachweise für ${fs.displayName} eingereicht.',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              )
                            else
                              SoftCard(
                                child: Column(
                                  children: List.generate(visibleApprovals.length, (i) {
                                    final a = visibleApprovals[i];
                                    final doc = _docsById[a.documentId];
                                    final isExpired = doc?.isExpired ?? false;
                                    final (statusFg, statusBg) = switch (a.status) {
                                      ApprovalStatusEnum.approved => (
                                        AppTheme.successColor,
                                        AppTheme.successBg,
                                      ),
                                      ApprovalStatusEnum.rejected => (
                                        AppTheme.dangerColor,
                                        AppTheme.dangerBg,
                                      ),
                                      ApprovalStatusEnum.submitted => (
                                        AppTheme.warningColor,
                                        AppTheme.warningBg,
                                      ),
                                    };

                                    return Opacity(
                                      opacity: isExpired ? 0.68 : 1.0,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (i > 0)
                                            Divider(
                                              height: 1,
                                              indent: 62,
                                              color: cs.outlineVariant,
                                            ),
                                          InkWell(
                                            onTap: doc == null
                                                ? null
                                                : () => _openDocument(
                                                      doc,
                                                      approval: a,
                                                    ),
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 14,
                                                vertical: 11,
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      TintedIconBadge(
                                                        icon: Icons.description_outlined,
                                                        iconColor: isExpired
                                                            ? AppTheme.dangerColor
                                                            : statusFg,
                                                        backgroundColor: isExpired
                                                            ? AppTheme.dangerBg
                                                            : statusBg,
                                                        size: 36,
                                                        iconSize: 18,
                                                        radius: 10,
                                                      ),
                                                      const SizedBox(width: 12),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment.start,
                                                          children: [
                                                            Row(
                                                              children: [
                                                                Expanded(
                                                                  child: Text(
                                                                    a.documentType,
                                                                    style: const TextStyle(
                                                                      fontWeight:
                                                                          FontWeight.w700,
                                                                      fontSize: 13.5,
                                                                    ),
                                                                  ),
                                                                ),
                                                                const SizedBox(width: 6),
                                                                StatusPill(
                                                                  label: isExpired
                                                                      ? 'Abgelaufen'
                                                                      : a.status.label,
                                                                  foreground: isExpired
                                                                      ? AppTheme
                                                                          .dangerColor
                                                                      : statusFg,
                                                                  background: isExpired
                                                                      ? AppTheme.dangerBg
                                                                      : statusBg,
                                                                  fontSize: 10.5,
                                                                ),
                                                              ],
                                                            ),
                                                            if (doc != null) ...[
                                                              const SizedBox(height: 2),
                                                              Text(
                                                                '${doc.fileName} · Gültig bis: ${_fmtDate(doc.expiresAt)}',
                                                                maxLines: 2,
                                                                overflow:
                                                                    TextOverflow.ellipsis,
                                                                style: TextStyle(
                                                                  fontSize: 11.5,
                                                                  color: isExpired
                                                                      ? AppTheme
                                                                          .dangerColor
                                                                      : cs.onSurfaceVariant,
                                                                ),
                                                              ),
                                                            ],
                                                            if ((a.comment ?? '')
                                                                .trim()
                                                                .isNotEmpty) ...[
                                                              const SizedBox(height: 2),
                                                              Text(
                                                                'Hinweis: ${a.comment!.trim()}',
                                                                style: TextStyle(
                                                                  fontSize: 11.5,
                                                                  color:
                                                                      cs.onSurfaceVariant,
                                                                ),
                                                              ),
                                                            ],
                                                          ],
                                                        ),
                                                      ),
                                                      if (doc != null) ...[
                                                        const SizedBox(width: 4),
                                                        IconButton(
                                                          tooltip: 'Gültig bis ändern',
                                                          visualDensity: VisualDensity.compact,
                                                          onPressed: _busyDoc
                                                              ? null
                                                              : () => _editDocExpiry(doc),
                                                          icon: Icon(
                                                            Icons.edit_calendar_outlined,
                                                            size: 18,
                                                            color: cs.onSurfaceVariant,
                                                          ),
                                                        ),
                                                        IconButton(
                                                          tooltip: 'Dokument öffnen',
                                                          visualDensity: VisualDensity.compact,
                                                          onPressed: () =>
                                                              _openDocument(
                                                                doc,
                                                                approval: a,
                                                              ),
                                                          icon: Icon(
                                                            Icons.visibility_outlined,
                                                            size: 19,
                                                            color: cs.primary,
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                  if (a.status ==
                                                          ApprovalStatusEnum.submitted &&
                                                      !isExpired) ...[
                                                    const SizedBox(height: 8),
                                                    Align(
                                                      alignment: Alignment.centerRight,
                                                      child: FilledButton.tonalIcon(
                                                        onPressed: _busyDoc
                                                            ? null
                                                            : () => _approveDoc(a),
                                                        icon: const Icon(
                                                          Icons.check_rounded,
                                                          size: 16,
                                                        ),
                                                        label: const Text('Freigeben'),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailSectionTitle extends StatelessWidget {
  final String title;
  const _DetailSectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.7,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
