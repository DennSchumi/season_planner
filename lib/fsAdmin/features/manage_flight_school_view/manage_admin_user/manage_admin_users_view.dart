import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/fsAdmin/data/models/flight_school_model_flight_school_view.dart';
import 'package:season_planner/fsAdmin/data/models/user_summary_flight_school_view.dart';
import 'package:season_planner/fsAdmin/flight_school_provider.dart';
import 'package:season_planner/fsAdmin/services/flight_school_service.dart';
import 'package:season_planner/user/user_provider.dart';

class ManageAdminsPage extends StatefulWidget {
  const ManageAdminsPage({super.key});

  @override
  State<ManageAdminsPage> createState() => _ManageAdminsPageState();
}

class _ManageAdminsPageState extends State<ManageAdminsPage> {
  final FlightSchoolService fsService = FlightSchoolService();
  bool _busy = false;

  Future<void> _setBusy(bool v) async {
    if (!mounted) return;
    setState(() => _busy = v);
  }

  bool _isSelf(String userId, String currentUserId) => userId == currentUserId;

  UserSummary? _memberById(
    FlightSchoolModelFlightSchoolView fs,
    String userId,
  ) {
    return fs.findMemberByAnyId(userId);
  }

  Future<void> _removeAdmin({
    required FlightSchoolModelFlightSchoolView fs,
    required String adminId,
    required String currentUserId,
  }) async {
    if (_isSelf(adminId, currentUserId)) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Admin-Rechte entfernen"),
        content: const Text(
          "Möchtest du dieser Person wirklich die Admin-Rechte entziehen?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Abbrechen"),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Entfernen"),
          ),
        ],
      ),
    );

    if (ok != true) return;
    await _setBusy(true);
    try {
      final cleanedAdmins =
          (List<String>.from(fs.adminUserIds)..remove(adminId)).toSet().toList();
      if (!mounted) return;
      context
          .read<FlightSchoolProvider>()
          .setFlightSchool(fs.copyWith(adminUserIds: cleanedAdmins));
      await fsService.updateAdmins(
        flightSchoolId: fs.id,
        adminUserIds: cleanedAdmins,
      );
      if (!mounted) return;
      context.read<FlightSchoolProvider>().reloadFlightSchoolInBackground();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Entfernen fehlgeschlagen: $e")),
        );
      }
    } finally {
      await _setBusy(false);
    }
  }

  Future<void> _openAddAdminDialog(FlightSchoolModelFlightSchoolView fs) async {
    final uniqueMembers = <String, UserSummary>{
      for (final m in fs.members) m.id: m,
    };
    final candidates = uniqueMembers.values
        .where((m) => !fs.adminUserIds.any((aid) => m.matchesId(aid)))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Alle Teammitglieder sind bereits Administratoren."),
        ),
      );
      return;
    }

    final selected = <String>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text("Admin hinzufügen"),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: candidates.map((m) {
                  return CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: selected.contains(m.id),
                    title: Text(m.name.isEmpty ? m.mail : m.name),
                    subtitle: m.mail.isNotEmpty ? Text(m.mail) : null,
                    onChanged: (v) {
                      setLocal(() {
                        if (v == true) {
                          selected.add(m.id);
                        } else {
                          selected.remove(m.id);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Abbrechen"),
            ),
            FilledButton(
              onPressed:
                  selected.isEmpty ? null : () => Navigator.pop(ctx, true),
              child: const Text("Hinzufügen"),
            ),
          ],
        ),
      ),
    );

    if (ok != true || selected.isEmpty) return;

    await _setBusy(true);
    try {
      final updated = {...fs.adminUserIds, ...selected}.toList();
      if (!mounted) return;
      context
          .read<FlightSchoolProvider>()
          .setFlightSchool(fs.copyWith(adminUserIds: updated));
      await fsService.updateAdmins(
        flightSchoolId: fs.id,
        adminUserIds: updated,
      );
      if (!mounted) return;
      context.read<FlightSchoolProvider>().reloadFlightSchoolInBackground();
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

    return Scaffold(
      appBar: AppBar(title: const Text("Admin-Nutzer verwalten")),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : () => _openAddAdminDialog(fs),
        icon: const Icon(Icons.person_add),
        label: const Text("Admin hinzufügen"),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 84),
                itemCount: fs.adminUserIds.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final adminId = fs.adminUserIds[index];
                  final member = _memberById(fs, adminId);
                  final isSelf = _isSelf(adminId, currentUser.id);
                  final name = member != null && member.name.isNotEmpty
                      ? member.name
                      : (isSelf ? currentUser.name : adminId);

                  return Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.admin_panel_settings),
                      ),
                      title: Text(
                        isSelf ? "$name (Du)" : name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(member?.mail ?? (isSelf ? currentUser.mail : "")),
                      trailing: isSelf
                          ? const Tooltip(
                              message: "Eigene Admin-Rechte sind geschützt",
                              child: Icon(Icons.lock_outline, color: Colors.grey),
                            )
                          : IconButton(
                              tooltip: "Admin-Rechte entfernen",
                              icon: const Icon(Icons.remove_circle_outline,
                                  color: Colors.red),
                              onPressed: _busy
                                  ? null
                                  : () => _removeAdmin(
                                        fs: fs,
                                        adminId: adminId,
                                        currentUserId: currentUser.id,
                                      ),
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
