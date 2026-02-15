import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/data/models/event_model.dart';
import 'package:season_planner/data/enums/event_status_enum.dart';
import 'package:season_planner/data/enums/event_role_enum.dart';
import 'package:season_planner/data/enums/event_user_status_enum.dart';
import 'package:season_planner/services/providers/flight_school_provider.dart';
import 'package:season_planner/data/models/admin_models/user_summary_flight_school_view.dart';

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
    EventUserStatusEnum.accepted_flight_school,
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

  late final Set<String> _persistedTeamKeys;

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

    _persistedTeamKeys = _team.map(_teamKey).toSet();
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

  String _teamKey(TeamMember tm) => "${tm.userId}|${tm.role}|${tm.status}";

  bool _isPersisted(TeamMember tm) {
    return _persistedTeamKeys.contains(_teamKey(tm));
  }

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
      s == EventUserStatusEnum.accepted_flight_school ||
          s == EventUserStatusEnum.accepted_user;

  bool _isPendingFs(EventUserStatusEnum s) => s == EventUserStatusEnum.pending_flight_school;
  bool _isPendingUser(EventUserStatusEnum s) => s == EventUserStatusEnum.pending_user;
  bool _isOpen(EventUserStatusEnum s) => s == EventUserStatusEnum.open;

  bool _isOpenSlot(TeamMember tm) {
    return tm.userId.isEmpty || tm.userId.startsWith("slot_");
  }

  String _resolveName(TeamMember tm, List<UserSummary> members) {
    if (tm.name.trim().isNotEmpty) return tm.name.trim();
    if (_isOpenSlot(tm)) return "Open Opportunity";

    final hit = members.where((m) => m.id == tm.userId).toList();
    if (hit.isNotEmpty && hit.first.name.trim().isNotEmpty) return hit.first.name.trim();

    return "Member";
  }

  void _removeTeamMember(int index) => setState(() => _team.removeAt(index));
  void _updateTeamMember(int index, TeamMember updated) => setState(() => _team[index] = updated);

  // ----------------- discard -----------------

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("Discard changes?"),
          content: const Text("All unsaved changes will be lost."),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
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

  // ----------------- delete --------------------

  Future<void> _confirmDelete() async { //not yet used
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("Delete Event?"),
          content: const Text("The Project will be Deleted completly. Are you shure you dont want to change the Status?"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => {Navigator.pop(context)},
              child: const Text("Delete"),
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

    UserSummary? selected = null;
    EventRoleEnum role = EventRoleEnum.values.first;

    final result = await showDialog<TeamMember>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final availableMembers = members.where((m) {
              final alreadyInTeam = _team.any((t) => t.userId == m.id);
              return !alreadyInTeam;
            }).toList();

            return AlertDialog(
              title: const Text("Add Team Entry"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<UserSummary?>(
                      value: selected, // null = Open Opportunity
                      decoration: const InputDecoration(
                        labelText: "Member (optional)",
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<UserSummary?>(
                          value: null,
                          child: Text("Open Opportunity (no member)"),
                        ),
                        ...availableMembers.map(
                              (m) => DropdownMenuItem<UserSummary?>(
                            value: m,
                            child: Text(m.name),
                          ),
                        ),
                      ],
                      onChanged: (v) => setLocal(() => selected = v),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<EventRoleEnum>(
                      value: role,
                      decoration: const InputDecoration(
                        labelText: "Role",
                        border: OutlineInputBorder(),
                      ),
                      items: EventRoleEnum.values
                          .map((r) => DropdownMenuItem(value: r, child: Text(r.label)))
                          .toList(),
                      onChanged: (v) => setLocal(() => role = v ?? role),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
                ElevatedButton(
                  onPressed: () {
                    if (selected == null) {
                      final slotId = "slot_${DateTime.now().microsecondsSinceEpoch}";
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

    if (!result.userId.startsWith("slot_") && _team.any((t) => t.userId == result.userId)) {
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
    final persisted = _isPersisted(tm);

    if (_isDenied(currentStatus) && persisted) return;

    final open = _isOpen(currentStatus);
    final pendingFs = _isPendingFs(currentStatus);
    final pendingUser = _isPendingUser(currentStatus);
    final accepted = _isAccepted(currentStatus);
    final userReqChange =
        currentStatus == EventUserStatusEnum.user_requests_change;

    final canPickMember = open || !persisted || userReqChange;
    final canChangeRole =
        open || pendingUser || accepted || !persisted || userReqChange;
    final canAcceptPendingFs = pendingFs;

    EventRoleEnum role = EventRoleEnum.values.byName(tm.role);
    String? selectedUserId = _isOpenSlot(tm) ? null : tm.userId;

    final Map<String, UserSummary> uniqueMembers = {
      for (final m in members) m.id: m,
    };

    final res = await showDialog<TeamMember?>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final availableMembers = uniqueMembers.values.where((m) {
              final alreadyInTeam = _team.any((t) => t.userId == m.id);
              final isCurrentlySelected = selectedUserId == m.id;
              if (userReqChange && m.id == tm.userId) return false;
              return !alreadyInTeam || isCurrentlySelected;
            }).toList();

            final dropdownValues = <String?>{
              null,
              ...availableMembers.map((m) => m.id),
            };

            if (!dropdownValues.contains(selectedUserId)) {
              selectedUserId = null;
            }

            return AlertDialog(
              title: Text(
                userReqChange
                    ? "User requested change"
                    : _resolveName(tm, members),
              ),

              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (userReqChange) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: Theme.of(ctx)
                              .colorScheme
                              .surfaceContainerHighest,
                        ),
                        child: RichText(
                          text: TextSpan(
                            style: Theme.of(ctx)
                                .textTheme
                                .bodySmall
                                ?.copyWith(height: 1.4),
                            children: [
                              TextSpan(
                                text: "${_resolveName(tm, members)} ",
                                style:
                                const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const TextSpan(
                                text:
                                "requested a change to this assignment.\n\n",
                              ),
                              const TextSpan(
                                text:
                                "The user is asking to be replaced. You can either turn this position into an ",
                              ),
                              const TextSpan(
                                text: "open opportunity",
                                style:
                                TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const TextSpan(
                                text:
                                " or assign another member to this role.",
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    if (canAcceptPendingFs)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(
                              ctx,
                              tm.copyWith(
                                status: EventUserStatusEnum
                                    .accepted_flight_school
                                    .name,
                              ),
                            );
                          },
                          icon: const Icon(Icons.check),
                          label: const Text("Accept"),
                        ),
                      ),
                    if (canAcceptPendingFs) const SizedBox(height: 12),

                    if (canPickMember) ...[
                      DropdownButtonFormField<String?>(
                        value: selectedUserId,
                        decoration: const InputDecoration(
                          labelText: "Member",
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text("Open Opportunity (no member)"),
                          ),
                          ...availableMembers.map(
                                (m) => DropdownMenuItem<String?>(
                              value: m.id,
                              child: Text(m.name),
                            ),
                          ),
                        ],
                        onChanged: (v) =>
                            setLocal(() => selectedUserId = v),
                      ),
                      const SizedBox(height: 12),
                    ],

                    DropdownButtonFormField<EventRoleEnum>(
                      value: role,
                      decoration: InputDecoration(
                        labelText: "Role",
                        border: const OutlineInputBorder(),
                        helperText:
                        canChangeRole ? null : "Role cannot be changed.",
                      ),
                      items: EventRoleEnum.values
                          .map(
                            (r) =>
                            DropdownMenuItem(value: r, child: Text(r.label)),
                      )
                          .toList(),
                      onChanged: canChangeRole
                          ? (v) => setLocal(() => role = v ?? role)
                          : null,
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
                    if (selectedUserId == null) {
                      final newSlotId = _isOpenSlot(tm)
                          ? tm.userId
                          : "slot_${DateTime.now().microsecondsSinceEpoch}";

                      Navigator.pop(
                        ctx,
                        tm.copyWith(
                          userId: newSlotId,
                          name: "Open Opportunity",
                          status: EventUserStatusEnum.open.name,
                          role: role.name,
                        ),
                      );
                      return;
                    }

                    final picked = uniqueMembers[selectedUserId]!;

                    Navigator.pop(
                      ctx,
                      tm.copyWith(
                        userId: picked.id,
                        name: picked.name,
                        status: EventUserStatusEnum.pending_user.name,
                        role: role.name,
                      ),
                    );
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


    for (final tm in _team) {
      final s = _statusOf(tm);

      if (s == EventUserStatusEnum.open) {
        if (!_isOpenSlot(tm)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Open Opportunity must have no real member.")),
          );
          return;
        }
      } else {
        if (_isOpenSlot(tm)) {
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
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: "Event Name", border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? "Please enter a name." : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _identifierCtrl,
                decoration: const InputDecoration(labelText: "Identifier", border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? "Please enter an identifier." : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _locationCtrl,
                decoration: const InputDecoration(
                  labelText: "Location",
                  border: OutlineInputBorder(),
                  hintText: "e.g. Kössen – Unterberg",
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? "Please enter a location." : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<EventStatusEnum>(
                value: _status,
                decoration: const InputDecoration(labelText: "Status", border: OutlineInputBorder()),
                items: EventStatusEnum.values.map((s) => DropdownMenuItem(value: s, child: Text(s.label))).toList(),
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
              const Text("Team", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),

              if (_team.isEmpty)
                const Text("No team entries yet.")
              else
                ..._team.asMap().entries.map((entry) {
                  final index = entry.key;
                  final tm = entry.value;

                  final s = _statusOf(tm);
                  final denied = _isDenied(s);

                  final persisted = _isPersisted(tm);
                  final displayName = _resolveName(tm, fs.members);


                  return Opacity(
                    opacity: (denied && persisted) ? 0.5 : 1.0,
                    child: Card(
                      elevation: 1,
                      child: ListTile(
                        title: Text(displayName),
                        subtitle: Text(
                          "${EventRoleEnum.values.byName(tm.role).label} • "
                              "${EventUserStatusEnum.values.byName(tm.status).label(context: EventUserStatusLabelContext.defaultView)}",

                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: "Edit",
                              onPressed: (denied && persisted)
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
                              onPressed: () => _removeTeamMember(index),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                        onTap: (denied && persisted)
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
