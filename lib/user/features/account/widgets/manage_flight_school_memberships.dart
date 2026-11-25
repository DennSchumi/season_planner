import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/core/data/enums/event_role_enum.dart';
import 'package:season_planner/core/data/enums/membership_status_enum.dart';
import 'package:season_planner/core/features/onboarding/onboarding_choice_view.dart';
import 'package:season_planner/user/data/models/flight_school_model_user_view.dart';
import 'package:season_planner/user/user_provider.dart';
import '../../../services/database_service.dart';

class ManageFlightSchoolMemberships extends StatefulWidget {
  const ManageFlightSchoolMemberships({super.key});

  @override
  State<ManageFlightSchoolMemberships> createState() =>
      _ManageFlightSchoolMembershipsState();
}

class _ManageFlightSchoolMembershipsState
    extends State<ManageFlightSchoolMemberships> {
  final _service = DatabaseService();
  bool _busy = false;

  Widget _logo(String logoUrl) {
    if (logoUrl.isEmpty) {
      return Image.asset(
        "lib/assets/images/fsBaseImage.webp",
        width: 44,
        height: 44,
        fit: BoxFit.cover,
      );
    }

    return Image.network(
      logoUrl,
      width: 44,
      height: 44,
      fit: BoxFit.cover,
      errorBuilder:
          (_, __, ___) => Image.asset(
            "lib/assets/images/fsBaseImage.webp",
            width: 44,
            height: 44,
            fit: BoxFit.cover,
          ),
    );
  }

  Future<void> _accept(FlightSchoolUserView fs) async {
    final userProvider = context.read<UserProvider>();
    final user = userProvider.user;
    if (user == null) return;

    final oldSchools = user.flightSchools;
    final newSchools =
        oldSchools
            .map(
              (s) =>
                  s.id == fs.id
                      ? s.copyWith(
                        membershipStatus: MembershipStatusEnum.active,
                      )
                      : s,
            )
            .toList();

    userProvider.setUser(user.copyWith(flightSchools: newSchools));

    setState(() => _busy = true);
    try {
      await _service.acceptMembership(flightSchoolId: fs.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Einladung angenommen: ${fs.displayName}")),
      );
    } catch (e) {
      userProvider.setUser(user.copyWith(flightSchools: oldSchools));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Annehmen fehlgeschlagen: $e")));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave(FlightSchoolUserView fs) async {
    final isRequested = fs.membershipStatus == MembershipStatusEnum.requested;
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(
              isRequested
                  ? "Beitrittsanfrage zurückziehen?"
                  : "Flugschule verlassen?",
            ),
            content: Text(
              isRequested
                  ? "Möchtest du deine Beitrittsanfrage für „${fs.displayName}“ zurückziehen?"
                  : "Möchtest du deine Mitgliedschaft bei „${fs.displayName}“ wirklich beenden?",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("Abbrechen"),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(isRequested ? "Zurückziehen" : "Verlassen"),
              ),
            ],
          ),
    );

    if (ok != true) return;

    final userProvider = context.read<UserProvider>();
    final user = userProvider.user;
    if (user == null) return;

    final oldSchools = user.flightSchools;
    final newSchools = oldSchools.where((s) => s.id != fs.id).toList();
    userProvider.setUser(user.copyWith(flightSchools: newSchools));

    setState(() => _busy = true);
    try {
      await _service.leaveMembership(flightSchoolId: fs.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isRequested
                ? "Anfrage zurückgezogen: ${fs.displayName}"
                : "Flugschule verlassen: ${fs.displayName}",
          ),
        ),
      );
    } catch (e) {
      userProvider.setUser(user.copyWith(flightSchools: oldSchools));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Aktion fehlgeschlagen: $e")));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserProvider>().user;

    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final schools = user.flightSchools;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Meine Mitgliedschaften"),
        actions: [
          IconButton(
            tooltip: "Neue Flugschule anlegen",
            icon: const Icon(Icons.add_business_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (_) => const CreateFlightSchoolView(
                        isInitialOnboarding: false,
                      ),
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed:
            _busy
                ? null
                : () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (_) => const JoinFlightSchoolView(
                            isInitialOnboarding: false,
                          ),
                    ),
                  );
                },
        icon: const Icon(Icons.group_add),
        label: const Text("Flugschule beitreten"),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child:
                  schools.isEmpty
                      ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            "Noch keine Mitgliedschaften vorhanden.\nNutze „Flugschule beitreten“ oder lege oben eine neue Flugschule an.",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.black54),
                          ),
                        ),
                      )
                      : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                        itemCount: schools.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final fs = schools[index];
                          final isInvited =
                              fs.membershipStatus ==
                              MembershipStatusEnum.invited;
                          final isRequested =
                              fs.membershipStatus ==
                              MembershipStatusEnum.requested;

                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: _logo(fs.logoLink),
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
                                                fs.displayName,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 15,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            _StatusPill(
                                              status: fs.membershipStatus,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        if (fs.assignedQualificationIds
                                                .isNotEmpty ||
                                            fs.requestedQualificationIds
                                                .isNotEmpty) ...[
                                          Wrap(
                                            spacing: 6,
                                            runSpacing: 6,
                                            children: [
                                              ...fs.assignedQualificationIds
                                                  .map(
                                                    (qid) => _RoleChip(
                                                      label:
                                                          '✓ ${fs.findQualificationById(qid)?.name ?? qid}',
                                                    ),
                                                  ),
                                              ...fs.requestedQualificationIds
                                                  .map(
                                                    (qid) => _RoleChip(
                                                      label:
                                                          '⏳ ${fs.findQualificationById(qid)?.name ?? qid} (angefragt)',
                                                    ),
                                                  ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                        ],
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children:
                                              fs.availableRoles.isEmpty
                                                  ? const [
                                                    _RoleChip(
                                                      label:
                                                          "Noch keine Einsatzrollen",
                                                    ),
                                                  ]
                                                  : fs.availableRoles
                                                      .map(
                                                        (r) => _RoleChip(
                                                          label:
                                                              EventRoleEnum.displayLabel(
                                                                r,
                                                              ),
                                                        ),
                                                      )
                                                      .toList(),
                                        ),
                                        const SizedBox(height: 10),
                                        Row(
                                          children: [
                                            if (isInvited)
                                              FilledButton.icon(
                                                onPressed:
                                                    _busy
                                                        ? null
                                                        : () => _accept(fs),
                                                icon: const Icon(Icons.check),
                                                label: const Text("Annehmen"),
                                              )
                                            else
                                              OutlinedButton.icon(
                                                onPressed:
                                                    _busy
                                                        ? null
                                                        : () => _leave(fs),
                                                icon: Icon(
                                                  isRequested
                                                      ? Icons.close
                                                      : Icons.logout,
                                                ),
                                                label: Text(
                                                  isRequested
                                                      ? "Anfrage zurückziehen"
                                                      : "Verlassen",
                                                ),
                                              ),
                                          ],
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
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  final String label;
  const _RoleChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final MembershipStatusEnum status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color color = switch (status) {
      MembershipStatusEnum.active => Colors.green,
      MembershipStatusEnum.invited => Colors.orange,
      MembershipStatusEnum.requested => Colors.blue,
      MembershipStatusEnum.inactive => theme.colorScheme.error,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
