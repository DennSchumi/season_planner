import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planer/data/enums/event_role_enum.dart';
import 'package:season_planer/services/flight_school_service.dart';
import 'package:season_planer/services/providers/flight_school_provider.dart' hide FlightSchoolService;
import 'package:season_planer/data/models/admin_models/user_summary_flight_school_view.dart';

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
      final name = (m.name).toLowerCase();
      final mail = (m.mail).toLowerCase();
      final phone = (m.phone).toLowerCase();
      return name.contains(q) || mail.contains(q) || phone.contains(q);
    }).toList();
  }

  String _rolesLabel(Set<EventRoleEnum> roles) {
    if (roles.isEmpty) return "no role selected";
    return roles.map((e) => e.label).join(", ");
  }

  Future<void> _openInviteDialog() async {
    final emailCtrl = TextEditingController();
    final Set<EventRoleEnum> selectedRoles = {};

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
                    const SizedBox(height: 8),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "This will send an invitation to the User.",
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

    final fs = context
        .read<FlightSchoolProvider>()
        .flightSchool;
    if (fs == null) return;

    setState(() => _busy = true);
    try {
      await _flightSchoolService.inviteMember(
        flightSchoolId: fs.id,
        email: email,
      );

      context.read<FlightSchoolProvider>().reloadFlightSchoolInBackground(
        _flightSchoolService.getFlightSchool,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Invitation sent to $email (roles: ${_rolesLabel(selectedRoles)}).",
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

  Future<void> _editRolesForUser(UserSummary user) async {
    final Set<EventRoleEnum> working = {...user.roles};

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
                  onPressed: () => Navigator.pop(ctx, working),
                  child: const Text("Save"),
                ),
              ],
            );
          },
        );
      },
    );

    if (res == null) return;

    if (user.membershipId == null || user.membershipId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Missing membershipId for this user.")),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      await _flightSchoolService.updateRolesInMemberOfFlightSchool(
        user.membershipId!,
        res.map((r) => r.name).toList(),
      );

      context.read<FlightSchoolProvider>().reloadFlightSchoolInBackground(
        _flightSchoolService.getFlightSchool,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Roles updated: ${_rolesLabel(res)}")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Role update failed: $e")),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeMember({required UserSummary user}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Remove member?"),
        content: Text("Remove ${user.name.isEmpty ? user.mail : user.name}?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Remove"),
          ),
        ],
      ),
    );

    if (ok != true) return;

    if (user.membershipId == null || user.membershipId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Missing membershipId for this user.")),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      await FlightSchoolService().removeMemberOfFlightSchool(user.membershipId!);

      context.read<FlightSchoolProvider>().reloadFlightSchoolInBackground(
        _flightSchoolService.getFlightSchool,
      );

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
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: widget.isLoading
                ? const Icon(Icons.sync, color: Colors.blue)
                : widget.hasConnection
                ? const Icon(Icons.check_circle, color: Colors.green)
                : const Icon(Icons.error, color: Colors.red),
            onPressed: () {
              if (widget.lastUpdated == null) return;

              final time = '${widget.lastUpdated!.hour.toString().padLeft(2, '0')}:${widget.lastUpdated!.minute.toString().padLeft(2, '0')}';

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    widget.hasConnection
                        ? 'Last update: $time'
                        : 'Offline · Last update: $time',
                  ),
                ),
              );
            },
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
                      child:Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const CircleAvatar(child: Icon(Icons.person)),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        m.name.isEmpty ? "Unnamed user" : m.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.w700),
                                      ),
                                      if (m.mail.isNotEmpty)
                                        Text(
                                          "E-Mail: ${m.mail}",
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: Colors.black54),
                                        ),
                                      if (m.phone.isNotEmpty)
                                        Text(
                                          "Phone: ${m.phone}",
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: Colors.black54),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(width: 10),

                          Flexible(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Wrap(
                                alignment: WrapAlignment.end,
                                spacing: 8,
                                runSpacing: 6,
                                children: roles.isEmpty
                                    ? const [Chip(label: Text("No roles set"))]
                                    : roles.map((r) => Chip(label: Text(r.label))).toList(),
                              ),
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
                      )

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
