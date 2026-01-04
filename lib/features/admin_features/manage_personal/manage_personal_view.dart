import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planer/data/enums/event_role_enum.dart';
import 'package:season_planer/services/flight_school_provider.dart';
import 'package:season_planer/data/models/admin_models/user_summary_flight_school_view.dart';

// TODO: später deinen DatabaseService importieren
// import 'package:season_planer/services/database_service.dart';

class ManagePersonalView extends StatefulWidget {
  const ManagePersonalView({super.key});

  @override
  State<ManagePersonalView> createState() => _ManagePersonalViewState();
}

class _ManagePersonalViewState extends State<ManagePersonalView> {
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
      final name = (m.name).toLowerCase();
      final mail = (m.mail).toLowerCase();
      final phone = (m.phone).toLowerCase();
      return name.contains(q) || mail.contains(q) || phone.contains(q);
    }).toList();
  }

  // ---------------- Invite Dialog ----------------
  Future<void> _openInviteDialog() async {
    final emailCtrl = TextEditingController();
    final Set<EventRoleEnum> selectedRoles = {EventRoleEnum.values.first};

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text("Invite user"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: "E-mail",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _MultiRolePicker(
                      value: selectedRoles,
                      onChanged: (newSet) => setLocal(() {
                        selectedRoles
                          ..clear()
                          ..addAll(newSet);
                      }),
                    ),
                    const SizedBox(height: 8),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "This will send an invitation e-mail.",
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text("Invite"),
                ),
              ],
            );
          },
        );
      },
    );

    final email = emailCtrl.text.trim();
    emailCtrl.dispose();

    if (ok != true) return;

    if (email.isEmpty || !email.contains("@")) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a valid e-mail address.")),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      // TODO: Backend Call
      // final db = DatabaseService();
      // await db.inviteUserToFlightSchool(
      //   context: context,
      //   email: email,
      //   roles: selectedRoles.map((r) => r.name).toList(),
      // );

      // TODO: Provider reload (damit neue Invites/Members angezeigt werden)
      // await context.read<FlightSchoolProvider>().reloadFlightSchool();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Invitation sent to $email (roles: ${selectedRoles.map((e) => e.label).join(", ")}).",
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Invite failed: $e")),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------- Change Roles (direkt speichern) ----------------
  Future<void> _editRolesForUser(UserSummary user) async {
    final Set<EventRoleEnum> working =
    user.roles.isEmpty ? {EventRoleEnum.values.first} : {...user.roles};

    final res = await showDialog<Set<EventRoleEnum>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text("Roles for ${user.name.isEmpty ? user.mail : user.name}"),
              content: SingleChildScrollView(
                child: _MultiRolePicker(
                  value: working,
                  onChanged: (newSet) => setLocal(() {
                    working
                      ..clear()
                      ..addAll(newSet);
                  }),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (working.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Please select at least one role.")),
                      );
                      return;
                    }
                    Navigator.pop(ctx, working);
                  },
                  child: const Text("Save"),
                ),
              ],
            );
          },
        );
      },
    );

    if (res == null) return;

    setState(() => _busy = true);
    try {
      // TODO: Backend Update – Membership roles updaten
      // final db = DatabaseService();
      // await db.updateMembershipRoles(
      //   context: context,
      //   userId: user.id,
      //   roles: res.map((r) => r.name).toList(),
      // );

      // TODO: Provider reload – damit UI die echten Rollen aus Backend zeigt
      // await context.read<FlightSchoolProvider>().reloadFlightSchool();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Roles updated: ${res.map((e) => e.label).join(", ")}")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Role update failed: $e")),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------- Remove member ----------------
  Future<void> _removeMember({required UserSummary user}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Remove member?"),
        content: Text("Remove ${user.name.isEmpty ? user.mail : user.name}?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Remove"),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _busy = true);
    try {
      // TODO: Backend call
      // final db = DatabaseService();
      // await db.removeMemberFromFlightSchool(context: context, userId: user.id);

      // TODO: Provider reload
      // await context.read<FlightSchoolProvider>().reloadFlightSchool();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Member removed.")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Remove failed: $e")),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    final fs = context.watch<FlightSchoolProvider>().flightSchool;

    if (fs == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final members = _filteredMembers(fs.members);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Manage Personnel"),
        actions: [
          IconButton(
            tooltip: "Invite user",
            onPressed: _busy ? null : _openInviteDialog,
            icon: const Icon(Icons.person_add_alt_1),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: "Search (name / mail / phone)",
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
                  border: const OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: members.isEmpty
                  ? const Center(child: Text("No members found."))
                  : ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                itemCount: members.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final m = members[index];
                  final roles = m.roles.toSet();

                  return Card(
                    elevation: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const CircleAvatar(child: Icon(Icons.person)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      m.name.isEmpty ? "Unnamed user" : m.name,
                                      style: const TextStyle(fontWeight: FontWeight.w700),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      m.mail.isEmpty ? "—" : m.mail,
                                      style: const TextStyle(color: Colors.black54),
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuButton<String>(
                                tooltip: "Actions",
                                onSelected: (value) {
                                  if (value == "remove") _removeMember(user: m);
                                  if (value == "roles") _editRolesForUser(m);
                                },
                                itemBuilder: (ctx) => const [
                                  PopupMenuItem(value: "roles", child: Text("Edit roles")),
                                  PopupMenuItem(value: "remove", child: Text("Remove")),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (m.phone.isNotEmpty)
                            Text("Phone: ${m.phone}",
                                style: const TextStyle(color: Colors.black54)),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: roles.isEmpty
                                      ? const [Chip(label: Text("No roles set"))]
                                      : roles.map((r) => Chip(label: Text(r.label))).toList(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                onPressed: _busy ? null : () => _editRolesForUser(m),
                                icon: const Icon(Icons.edit),
                                label: const Text("Edit"),
                              ),
                            ],
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _openInviteDialog,
        icon: const Icon(Icons.mail_outline),
        label: const Text("Invite"),
      ),
    );
  }
}

class _MultiRolePicker extends StatelessWidget {
  final Set<EventRoleEnum> value;
  final ValueChanged<Set<EventRoleEnum>> onChanged;

  const _MultiRolePicker({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: EventRoleEnum.values.map((role) {
        final checked = value.contains(role);
        return CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: checked,
          title: Text(role.label),
          onChanged: (v) {
            final next = {...value};
            if (v == true) {
              next.add(role);
            } else {
              next.remove(role);
            }
            onChanged(next);
          },
        );
      }).toList(),
    );
  }
}
