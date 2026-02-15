import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:season_planner/data/enums/membership_status_enum.dart';
import 'package:season_planner/data/models/user_models/flight_school_model_user_view.dart';
import 'package:season_planner/services/providers/user_provider.dart';

import '../../../../services/database_service.dart';
import '../../../../services/flight_school_service.dart';



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
      errorBuilder: (_, __, ___) => Image.asset(
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
    final newSchools = oldSchools
        .map((s) => s.id == fs.id
        ? s.copyWith(membershipStatus: MembershipStatusEnum.active)
        : s)
        .toList();

    userProvider.setUser(user.copyWith(flightSchools: newSchools));

    setState(() => _busy = true);
    try {
      await _service.acceptMembership(flightSchoolId: fs.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Membership accepted: ${fs.displayName}")),
      );

    } catch (e) {
      userProvider.setUser(user.copyWith(flightSchools: oldSchools));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Accept failed: $e")),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave(FlightSchoolUserView fs) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Leave flight school?"),
        content: Text(
          "Do you really want to remove your membership from “${fs.displayName}”?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Leave"),
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
        SnackBar(content: Text("Left: ${fs.displayName}")),
      );

      // optional: reload
      // userProvider.reloadUserInBackground();
    } catch (e) {
      userProvider.setUser(user.copyWith(flightSchools: oldSchools));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Leave failed: $e")),
      );
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
        title: const Text("My memberships"),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: schools.isEmpty
                  ? const Center(child: Text("No memberships found."))
                  : ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                itemCount: schools.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final fs = schools[index];

                  final isInvited =
                      fs.membershipStatus == MembershipStatusEnum.invited;

                  return Material(
                    borderRadius: BorderRadius.circular(14),
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
                              crossAxisAlignment: CrossAxisAlignment.start,
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
                                    _StatusPill(status: fs.membershipStatus),
                                  ],
                                ),
                                const SizedBox(height: 8),

                                Wrap(
                                  spacing: 6,
                                  runSpacing: -6,
                                  children: fs.availableRoles.isEmpty
                                      ? const [
                                    _RoleChip(label: "No roles"),
                                  ]
                                      : fs.availableRoles
                                      .map((r) => _RoleChip(label: r.name))
                                      .toList(),
                                ),

                                const SizedBox(height: 10),

                                Row(
                                  children: [
                                    if (isInvited)
                                      FilledButton.icon(
                                        onPressed: _busy ? null : () => _accept(fs),
                                        icon: const Icon(Icons.check),
                                        label: const Text("Accept"),
                                      )
                                    else
                                      OutlinedButton.icon(
                                        onPressed: _busy ? null : () => _leave(fs),
                                        icon: const Icon(Icons.logout),
                                        label: const Text("Leave"),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
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

    final text = status.name;
    final color = status == MembershipStatusEnum.invited
        ? theme.colorScheme.tertiary
        : theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
