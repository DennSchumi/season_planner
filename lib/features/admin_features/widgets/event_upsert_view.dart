import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planer/data/models/event_model.dart';
import 'package:season_planer/data/enums/event_status_enum.dart';
import 'package:season_planer/data/enums/event_role_enum.dart';
import 'package:season_planer/data/enums/event_user_status_enum.dart';
import 'package:season_planer/services/flight_school_provider.dart';
import 'package:season_planer/data/models/admin_models/user_summary_flight_school_view.dart';

class EventUpsertView extends StatefulWidget {
  final Event? initialEvent;
  final Future<void> Function(Event event) onSave;

  const EventUpsertView({
    super.key,
    required this.initialEvent,
    required this.onSave,
  });

  @override
  State<EventUpsertView> createState() => _EventUpsertViewState();
}

class _EventUpsertViewState extends State<EventUpsertView> {
  static const List<EventUserStatusEnum> _allowedStatuses = [
    EventUserStatusEnum.open,
    EventUserStatusEnum.pending_user,
    EventUserStatusEnum.aceppted_flight_school,
  ];

  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _identifierCtrl;
  late final TextEditingController _locationCtrl;
  late final TextEditingController _notesCtrl;

  late DateTime _start;
  late DateTime _end;
  late EventStatusEnum _status;

  late List<TeamMember> _team;

  bool _saving = false;
  bool get isEdit => widget.initialEvent != null;

  @override
  void initState() {
    super.initState();
    final e = widget.initialEvent;

    _nameCtrl = TextEditingController(text: e?.displayName ?? "");
    _identifierCtrl = TextEditingController(text: e?.identifier ?? "");
    _locationCtrl = TextEditingController(text: e?.location ?? "");
    _notesCtrl = TextEditingController(text: e?.notes ?? "");

    _start = e?.startTime ?? DateTime.now().add(const Duration(hours: 1));
    _end = e?.endTime ?? DateTime.now().add(const Duration(hours: 3));
    _status = e?.status ?? EventStatusEnum.values.first;

    _team = List<TeamMember>.from(e?.team ?? const <TeamMember>[]);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _identifierCtrl.dispose();
    _locationCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  // ----------------- helpers -----------------
  EventUserStatusEnum _statusOf(TeamMember tm) {
    try {
      return EventUserStatusEnum.values.byName(tm.status);
    } catch (_) {
      return EventUserStatusEnum.open;
    }
  }

  bool _isDenied(EventUserStatusEnum s) =>
      s == EventUserStatusEnum.denied_user ||
          s == EventUserStatusEnum.denied_flight_school;

  bool _isAccepted(EventUserStatusEnum s) =>
      s == EventUserStatusEnum.aceppted_flight_school ||
          s == EventUserStatusEnum.accepted_user;

  bool _isPendingFs(EventUserStatusEnum s) =>
      s == EventUserStatusEnum.pending_flight_school;
  bool _isPendingUser(EventUserStatusEnum s) =>
      s == EventUserStatusEnum.pending_user;
  bool _isOpen(EventUserStatusEnum s) => s == EventUserStatusEnum.open;

  String _resolveName(TeamMember tm, List<UserSummary> members) {
    if (tm.name.trim().isNotEmpty) return tm.name.trim();
    if (tm.isSlot) return "Open Opportunity";

    final hit = members.where((m) => m.id == tm.userId).toList();
    if (hit.isNotEmpty && hit.first.name.trim().isNotEmpty) {
      return hit.first.name.trim();
    }
    return "User not yet Set";
  }

  void _removeTeamMember(int index) => setState(() => _team.removeAt(index));
  void _updateTeamMember(int index, TeamMember updated) =>
      setState(() => _team[index] = updated);

  // ----------------- discard -----------------
  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("Discard changes?"),
          content: const Text("All unsaved changes will be lost."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Discard"),
            ),
          ],
        );
      },
    );

    if (discard == true && mounted) Navigator.pop(context);
  }

  // ----------------- date/time -----------------
  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(2100, 12, 31),
    );
    if (date == null) return null;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return null;

    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _pickStart() async {
    final picked = await _pickDateTime(_start);
    if (!mounted || picked == null) return;
    setState(() {
      _start = picked;
      if (!_end.isAfter(_start)) _end = _start.add(const Duration(hours: 2));
    });
  }

  Future<void> _pickEnd() async {
    final picked = await _pickDateTime(_end);
    if (!mounted || picked == null) return;
    setState(() => _end = picked);
  }

  // ----------------- team add dialog -----------------
  Future<void> _addTeamMemberDialog() async {
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No FlightSchool in provider.")),
      );
      return;
    }

    final members = fs.members;

    UserSummary? selected = members.isNotEmpty
        ? members.firstWhere(
          (m) => !_team.any((t) => t.userId == m.id),
      orElse: () => members.first,
    )
        : null;

    // Default: allow Open Opportunity as "none"
    if (members.isNotEmpty) {
      // keep selected as first free member
    } else {
      selected = null;
    }

    EventRoleEnum role = EventRoleEnum.values.first;

    final result = await showDialog<TeamMember>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text("Add Team Entry"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<UserSummary?>(
                      initialValue: selected,
                      decoration: const InputDecoration(
                        labelText: "Member (optional)",
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<UserSummary?>(
                          value: null,
                          child: Text("Open Opportunity (no member)"),
                        ),
                        ...members.map((m) {
                          final alreadyInTeam = _team.any((t) => t.userId == m.id);
                          return DropdownMenuItem<UserSummary?>(
                            value: m,
                            enabled: !alreadyInTeam,
                            child: Text(
                              alreadyInTeam ? "${m.name} (already in team)" : m.name,
                            ),
                          );
                        }),
                      ],
                      onChanged: (v) => setLocal(() => selected = v),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<EventRoleEnum>(
                      initialValue: role,
                      decoration: const InputDecoration(
                        labelText: "Role",
                        border: OutlineInputBorder(),
                      ),
                      items: EventRoleEnum.values
                          .map((r) => DropdownMenuItem(
                        value: r,
                        child: Text(r.label),
                      ))
                          .toList(),
                      onChanged: (v) => setLocal(() => role = v ?? role),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () {
                    // ✅ If no user selected => Open Opportunity slot
                    if (selected == null) {
                      final slotId =
                          "slot_${DateTime.now().microsecondsSinceEpoch}";
                      Navigator.pop(
                        ctx,
                        TeamMember(
                          userId: slotId,
                          name: "Open Opportunity",
                          role: role.name,
                          status: EventUserStatusEnum.open.name,
                        ),
                      );
                      return;
                    }

                    Navigator.pop(
                      ctx,
                      TeamMember(
                        userId: selected!.id,
                        name: selected!.name,
                        role: role.name,
                        status: EventUserStatusEnum.pending_user.name,
                      ),
                    );
                  },
                  child: const Text("Add"),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) return;

    if (!result.isSlot && _team.any((t) => t.userId == result.userId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Member already in team.")),
      );
      return;
    }

    if (!isEdit) {
      final rs = EventUserStatusEnum.values.byName(result.status);
      if (!_allowedStatuses.contains(rs)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Invalid status for create.")),
        );
        return;
      }
    }

    setState(() => _team.add(result));
  }

  // ----------------- team edit popup -----------------
  Future<void> _openTeamEditDialog({
    required int index,
    required TeamMember tm,
    required List<UserSummary> members,
  }) async {
    final currentStatus = _statusOf(tm);

    if (_isDenied(currentStatus)) return;

    final open = _isOpen(currentStatus);
    final pendingFs = _isPendingFs(currentStatus);
    final pendingUser = _isPendingUser(currentStatus);
    final accepted = _isAccepted(currentStatus);

    // Rules:
    // - open: member optional (null => stay open/slot, selected => pending_user + real member), role editable
    // - pending_flight_school: can accept, no member change
    // - pending_user: role editable, no member change
    // - accepted_*: role editable, no member change (unless you later allow "edit mode")
    final canPickMember = open;
    final canChangeRole = open || pendingUser || accepted;
    final canAcceptPendingFs = pendingFs;

    EventRoleEnum role = EventRoleEnum.values.byName(tm.role);

    UserSummary? selectedUser = tm.isSlot
        ? null
        : members.where((m) => m.id == tm.userId).isNotEmpty
        ? members.firstWhere((m) => m.id == tm.userId)
        : null;

    final res = await showDialog<TeamMember?>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text(_resolveName(tm, members)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // accept button for pending_flight_school
                    if (canAcceptPendingFs)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(
                              ctx,
                              tm.copyWith(
                                status: EventUserStatusEnum
                                    .aceppted_flight_school.name,
                              ),
                            );
                          },
                          icon: const Icon(Icons.check),
                          label: const Text("Accept"),
                        ),
                      ),
                    if (canAcceptPendingFs) const SizedBox(height: 12),

                    // open: optional member selection (incl. None)
                    if (canPickMember) ...[
                      DropdownButtonFormField<UserSummary?>(
                        initialValue: selectedUser,
                        decoration: const InputDecoration(
                          labelText: "Member (optional)",
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem<UserSummary?>(
                            value: null,
                            child: Text("Open Opportunity (no member)"),
                          ),
                          ...members.map((m) {
                            final alreadyInTeam =
                            _team.any((t) => t.userId == m.id);
                            final enabled = !alreadyInTeam ||
                                (selectedUser?.id == m.id);
                            return DropdownMenuItem<UserSummary?>(
                              value: m,
                              enabled: enabled,
                              child: Text(
                                !enabled ? "${m.name} (already in team)" : m.name,
                              ),
                            );
                          }),
                        ],
                        onChanged: (v) => setLocal(() => selectedUser = v),
                      ),
                      const SizedBox(height: 12),
                    ],

                    DropdownButtonFormField<EventRoleEnum>(
                      initialValue: role,
                      decoration: InputDecoration(
                        labelText: "Role",
                        border: const OutlineInputBorder(),
                        helperText: canChangeRole
                            ? null
                            : "Role cannot be changed in this status.",
                      ),
                      items: EventRoleEnum.values
                          .map((r) => DropdownMenuItem(
                        value: r,
                        child: Text(r.label),
                      ))
                          .toList(),
                      onChanged: canChangeRole
                          ? (v) => setLocal(() => role = v ?? role)
                          : null,
                    ),

                    if (pendingUser)
                      const Padding(
                        padding: EdgeInsets.only(top: 10),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text("Waiting for user response…",
                              style: TextStyle(fontSize: 12)),
                        ),
                      ),
                    if (pendingFs)
                      const Padding(
                        padding: EdgeInsets.only(top: 10),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text("Waiting for flight school…",
                              style: TextStyle(fontSize: 12)),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text("Close"),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (open) {
                      if (selectedUser == null) {
                        Navigator.pop(
                          ctx,
                          tm.copyWith(
                            role: role.name,
                            status: EventUserStatusEnum.open.name,
                            // keep slot userId
                          ),
                        );
                        return;
                      }

                      Navigator.pop(
                        ctx,
                        tm.copyWith(
                          userId: selectedUser!.id,
                          name: selectedUser!.name,
                          role: role.name,
                          status: EventUserStatusEnum.pending_user.name,
                        ),
                      );
                      return;
                    }

                    if (pendingUser || accepted) {
                      Navigator.pop(ctx, tm.copyWith(role: role.name));
                      return;
                    }

                    Navigator.pop(ctx, null);
                  },
                  child: const Text("Apply"),
                ),
              ],
            );
          },
        );
      },
    );

    if (res != null) _updateTeamMember(index, res);
  }

  // ----------------- submit -----------------
  Future<void> _submit() async {
    if (_saving) return;

    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;

    if (!_end.isAfter(_start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("End time must be after start time.")),
      );
      return;
    }

    final fsFromProvider = context.read<FlightSchoolProvider>().flightSchool;
    final fsId = widget.initialEvent?.flightSchoolId ?? fsFromProvider?.id;

    if (fsId == null || fsId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("flightSchoolId missing (Provider not set?).")),
      );
      return;
    }

    // invariant: open must be slot, everything else must be real member
    for (final tm in _team) {
      final s = _statusOf(tm);
      if (s == EventUserStatusEnum.open) {
        if (!tm.isSlot) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Open must be a slot (no real member).")),
          );
          return;
        }
      } else {
        if (tm.isSlot) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("This status requires a real member.")),
          );
          return;
        }
      }
    }

    setState(() => _saving = true);

    final base = widget.initialEvent ??
        Event(
          id: "",
          flightSchoolId: fsId,
          identifier: "",
          status: EventStatusEnum.values.first,
          startTime: _start,
          endTime: _end,
          displayName: "",
          location: "",
          team: const <TeamMember>[],
          notes: "",
          role: EventRoleEnum.values.first,
          assignmentStatus: EventUserStatusEnum.values.first,
        );

    final updated = base.copyWith(
      flightSchoolId: fsId,
      displayName: _nameCtrl.text.trim(),
      identifier: _identifierCtrl.text.trim(),
      location: _locationCtrl.text.trim(),
      status: _status,
      startTime: _start,
      endTime: _end,
      notes: _notesCtrl.text.trim(),
      team: _team,
    );

    try {
      await widget.onSave(updated);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Save failed: $e")),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ----------------- UI -----------------
  @override
  Widget build(BuildContext context) {
    final fs = context.watch<FlightSchoolProvider>().flightSchool;
    if (fs == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final title = isEdit ? "Edit Event" : "Create Event";

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: "Discard changes",
          onPressed: _saving ? null : _confirmDiscard,
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : const Text("Save"),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: "Event Name",
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                (v == null || v.trim().isEmpty) ? "Please enter a name." : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _identifierCtrl,
                decoration: const InputDecoration(
                  labelText: "Identifier",
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? "Please enter an identifier."
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _locationCtrl,
                decoration: const InputDecoration(
                  labelText: "Location",
                  border: OutlineInputBorder(),
                  hintText: "e.g. Kössen – Unterberg",
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? "Please enter a location."
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<EventStatusEnum>(
                initialValue: _status,
                decoration: const InputDecoration(
                  labelText: "Status",
                  border: OutlineInputBorder(),
                ),
                items: EventStatusEnum.values
                    .map((s) => DropdownMenuItem(
                  value: s,
                  child: Text(s.label),
                ))
                    .toList(),
                onChanged: (v) => setState(() => _status = v ?? _status),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickStart,
                      icon: const Icon(Icons.schedule),
                      label: Text("Start: ${_fmt(_start)}"),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickEnd,
                      icon: const Icon(Icons.schedule),
                      label: Text("End: ${_fmt(_end)}"),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                "Team",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              if (_team.isEmpty)
                const Text("No team entries yet.")
              else
                ..._team.asMap().entries.map((entry) {
                  final index = entry.key;
                  final tm = entry.value;

                  final s = _statusOf(tm);
                  final denied = _isDenied(s);
                  final displayName = _resolveName(tm, fs.members);

                  return Opacity(
                    opacity: denied ? 0.5 : 1.0,
                    child: Card(
                      elevation: 1,
                      child: ListTile(
                        title: Text(displayName),
                        subtitle: Text(
                          "${EventRoleEnum.values.byName(tm.role).label} • "
                              "${EventUserStatusLabelForNewEvent(EventUserStatusEnum.values.byName(tm.status)).label}",
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: "Edit",
                              onPressed: denied
                                  ? null
                                  : () => _openTeamEditDialog(
                                index: index,
                                tm: tm,
                                members: fs.members,
                              ),
                              icon: const Icon(Icons.edit),
                            ),
                            IconButton(
                              tooltip: "Remove",
                              onPressed: denied || _isPendingFs(s) || _isPendingUser(s)
                                  ? null
                                  : () => _removeTeamMember(index),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                        onTap: denied
                            ? null
                            : () => _openTeamEditDialog(
                          index: index,
                          tm: tm,
                          members: fs.members,
                        ),
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _addTeamMemberDialog,
                icon: const Icon(Icons.person_add),
                label: const Text("Add Team Entry"),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _notesCtrl,
                maxLines: 4,
                maxLength: 250,
                decoration: const InputDecoration(
                  labelText: "Notes",
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                  hintText: "Max. 250 characters",
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _saving ? null : _submit,
                icon: const Icon(Icons.save),
                label: Text(isEdit ? "Save Changes" : "Create Event"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmt(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return "${two(dt.day)}.${two(dt.month)}.${dt.year} ${two(dt.hour)}:${two(dt.minute)}";
  }
}
