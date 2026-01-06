import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:season_planer/data/models/admin_models/flight_school_model_flight_school_view.dart';
import 'package:season_planer/data/models/admin_models/user_summary_flight_school_view.dart';
import 'package:season_planer/services/flight_school_service.dart';
import 'package:season_planer/services/providers/user_provider.dart';
import 'package:season_planer/services/providers/flight_school_provider.dart';

class ManageAdminsPage extends StatefulWidget {
  const ManageAdminsPage({super.key});

  @override
  State<ManageAdminsPage> createState() => _ManageAdminsPageState();
}

class _ManageAdminsPageState extends State<ManageAdminsPage> {
  FlightSchoolService fsService = FlightSchoolService();
  bool _busy = false;

  Future<void> _setBusy(bool v) async {
    if (!mounted) return;
    setState(() => _busy = v);
  }



  bool _isSelf(String userId, String currentUserId) => userId == currentUserId;

  UserSummary? _memberById(FlightSchoolModelFlightSchoolView fs, String userId) {
    try {
      return fs.members.firstWhere((m) => m.id == userId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _removeAdmin({
    required FlightSchoolModelFlightSchoolView fs,
    required String adminId,
    required String currentUserId,
  }) async {
    if (_isSelf(adminId, currentUserId)) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Remove admin"),
        content: const Text("Do you really want to remove admin rights?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Remove"),
          ),
        ],
      ),
    );

    if (ok != true) return;

    await _setBusy(true);
    try {
      final updatedAdmins = List<String>.from(fs.adminUserIds)..remove(adminId);

      context.read<FlightSchoolProvider>().setFlightSchool(
        fs.copyWith(adminUserIds: updatedAdmins),
      );

      await fsService.updateAdmins(
        flightSchoolId: fs.id,
        adminUserIds: updatedAdmins,
      );

      context.read<FlightSchoolProvider>().reloadFlightSchoolInBackground();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Remove admin failed: $e")),
        );
      }
    } finally {
      await _setBusy(false);
    }
  }

  Future<void> _openAddAdminDialog(FlightSchoolModelFlightSchoolView fs) async {
    final currentUser = context.read<UserProvider>().user;
    if (currentUser == null) return;

    final candidates = fs.members
        .where((m) => !fs.adminUserIds.contains(m.id))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No members available to add as admin.")),
      );
      return;
    }

    final selectedIds = <String>{};

    final result = await showDialog<Set<String>>(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text("Add admins"),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: candidates.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final m = candidates[i];
                    final checked = selectedIds.contains(m.id);

                    return CheckboxListTile(
                      value: checked,
                      onChanged: (v) {
                        setLocalState(() {
                          if (v == true) {
                            selectedIds.add(m.id);
                          } else {
                            selectedIds.remove(m.id);
                          }
                        });
                      },
                      title: Text(m.name.isEmpty ? "Unnamed user" : m.name),
                      subtitle: Text(m.mail.isEmpty ? "—" : m.mail),
                      controlAffinity: ListTileControlAffinity.leading,
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                FilledButton(
                  onPressed: selectedIds.isEmpty
                      ? null
                      : () => Navigator.pop(context, selectedIds),
                  child: const Text("Add"),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null || result.isEmpty) return;

    await _setBusy(true);
    try {
      final updatedAdmins = {
        ...fs.adminUserIds,
        ...result,
      }.toList();

      context.read<FlightSchoolProvider>().setFlightSchool(
        fs.copyWith(adminUserIds: updatedAdmins),
      );

      await fsService.updateAdmins(
        flightSchoolId: fs.id,
        adminUserIds: updatedAdmins,
      );

      context.read<FlightSchoolProvider>().reloadFlightSchoolInBackground();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Add admin failed: $e")),
        );
      }
    } finally {
      await _setBusy(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fs = context.watch<FlightSchoolProvider>().flightSchool;
    final currentUser = context.watch<UserProvider>().user;

    if (fs == null || currentUser == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final currentUserId = currentUser.id;

    final admins = List<String>.from(fs.adminUserIds);
    admins.sort((a, b) {
      if (a == currentUserId) return -1;
      if (b == currentUserId) return 1;

      final am = _memberById(fs, a)?.name ?? "";
      final bm = _memberById(fs, b)?.name ?? "";
      return am.compareTo(bm);
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text("Manage Admin Users"),
        actions: [
          IconButton(
            tooltip: "Add admin",
            onPressed: _busy ? null : () => _openAddAdminDialog(fs),
            icon: const Icon(Icons.person_add_alt_1),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              children: [
                _HeaderInfo(fs: fs),
                const SizedBox(height: 12),

                Text(
                  "Admins (${admins.length})",
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),

                if (admins.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(14),
                      child: Text("No admins set."),
                    ),
                  )
                else
                  ...admins.map((adminId) {
                    final member = _memberById(fs, adminId);
                    final isSelf = _isSelf(adminId, currentUserId);

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: _AdminTile(
                        userId: adminId,
                        name: member?.name ?? "Unknown user",
                        mail: member?.mail ?? "—",
                        isSelf: isSelf,
                        onRemove: isSelf || _busy
                            ? null
                            : () => _removeAdmin(
                          fs: fs,
                          adminId: adminId,
                          currentUserId: currentUserId,
                        ),
                      ),
                    );
                  }).toList(),

                const SizedBox(height: 80),
              ],
            ),

            if (_busy)
              Positioned.fill(
                child: AbsorbPointer(
                  absorbing: true,
                  child: Container(
                    color: Colors.black.withOpacity(0.18),
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : () => _openAddAdminDialog(fs),
        icon: const Icon(Icons.admin_panel_settings_outlined),
        label: const Text("Add admin"),
      ),
    );
  }
}

class _HeaderInfo extends StatelessWidget {
  final FlightSchoolModelFlightSchoolView fs;

  const _HeaderInfo({required this.fs});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: cs.surfaceContainerHighest,
              child: fs.logoLink.isEmpty
                  ? Icon(Icons.flight, color: cs.onSurfaceVariant)
                  : ClipOval(
                child: Image.network(
                  fs.logoLink,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      Icon(Icons.flight, color: cs.onSurfaceVariant),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fs.displayShortName.isNotEmpty
                        ? fs.displayShortName
                        : fs.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "Manage who can administer this flight school.",
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminTile extends StatelessWidget {
  final String userId;
  final String name;
  final String mail;
  final bool isSelf;
  final VoidCallback? onRemove;

  const _AdminTile({
    required this.userId,
    required this.name,
    required this.mail,
    required this.isSelf,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Opacity(
      opacity: isSelf ? 0.55 : 1.0,
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ListTile(
          leading: CircleAvatar(
            radius: 18,
            backgroundColor: cs.surfaceContainerHighest,
            child: Icon(Icons.person, color: cs.onSurfaceVariant, size: 18),
          ),
          title: Text(
            name.isEmpty ? "Unnamed user" : name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            mail.isEmpty ? "—" : mail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: isSelf
              ? const Text(
            "You",
            style: TextStyle(fontWeight: FontWeight.w700),
          )
              : IconButton(
            tooltip: "Remove admin",
            onPressed: onRemove,
            icon: Icon(Icons.remove_circle_outline, color: cs.error),
          ),
        ),
      ),
    );
  }
}
