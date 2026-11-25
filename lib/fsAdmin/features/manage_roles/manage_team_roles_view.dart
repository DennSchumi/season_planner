import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/core/data/models/role_document_model.dart';
import 'package:season_planner/core/data/models/team_role_model.dart';
import 'package:season_planner/core/services/qualification_service.dart';
import 'package:season_planner/core/services/role_document_service.dart';
import 'package:season_planner/core/theme.dart';
import 'package:season_planner/core/widgets/ux_components.dart';
import 'package:season_planner/fsAdmin/features/manage_documents/manage_role_documents_view.dart';
import 'package:season_planner/fsAdmin/flight_school_provider.dart';
import 'package:season_planner/fsAdmin/services/flight_school_service.dart';

/// Admin-Verwaltung für Teamrollen / Einsatzpositionen (z. B. Startplatz,
/// Trainingsleiter, Kamera, Busfahrer, Bootshelfer) mit Zuordnung von
/// Pflicht-Qualifikationen (UND/ODER), Checkliste (max. 1) und Arbeitsanweisungen.
class ManageTeamRolesView extends StatefulWidget {
  const ManageTeamRolesView({super.key});

  @override
  State<ManageTeamRolesView> createState() => _ManageTeamRolesViewState();
}

class _ManageTeamRolesViewState extends State<ManageTeamRolesView> {
  final _service = QualificationService();
  final _docService = RoleDocumentService();
  List<RoleDocument> _schoolDocs = [];
  bool _busy = false;
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    _loadDocs();
  }

  Future<void> _loadDocs() async {
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null) return;
    final list = await _docService.listSchoolDocuments(fs.id);
    if (!mounted) return;
    setState(() => _schoolDocs = list);
  }

  Future<void> _reloadSchool() async {
    await context.read<FlightSchoolProvider>().reloadFlightSchool(
          FlightSchoolService().getFlightSchool,
        );
    await _loadDocs();
  }

  Future<void> _openRoleDialog({TeamRole? existing}) async {
    if (_dialogOpen || _busy) return;
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null) return;
    _dialogOpen = true;

    final checklists = _schoolDocs
        .where((d) => d.docType == RoleDocumentType.checklist)
        .toList();
    final instructions = _schoolDocs
        .where((d) => d.docType == RoleDocumentType.instruction)
        .toList();
    final qualifications = fs.qualifications;

    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final selectedQualIds = <String>{
      ...(existing?.requiredQualificationIds ?? const [])
          .where((id) => qualifications.any((q) => q.id == id)),
    };
    bool requireAllQuals = existing?.requireAllQualifications ?? true;

    String? selectedChecklistId = (existing?.checklistId != null &&
            checklists.any((c) => c.id == existing!.checklistId))
        ? existing!.checklistId
        : null;
    final selectedInstructionIds = <String>{
      ...(existing?.instructionIds ?? const [])
          .where((id) => instructions.any((i) => i.id == id)),
    };

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            title: Text(
              existing == null
                  ? 'Neue Teamrolle anlegen'
                  : 'Teamrolle bearbeiten',
            ),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Bezeichnung der Einsatzrolle *',
                        hintText: 'z. B. Startplatz, Trainingsleiter, Kamera',
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Verpflichtende Qualifikationen (optional):',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    if (qualifications.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          'Noch keine Qualifikationen angelegt.',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      )
                    else
                      ...qualifications.map((q) {
                        return CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: selectedQualIds.contains(q.id),
                          title: Text(q.name),
                          subtitle: q.requiredDocuments.isEmpty
                              ? null
                              : Text(
                                  'Nachweise: ${q.requiredDocuments.join(', ')}',
                                  style: const TextStyle(fontSize: 11.5),
                                ),
                          onChanged: (v) {
                            setLocal(() {
                              if (v == true) {
                                selectedQualIds.add(q.id);
                              } else {
                                selectedQualIds.remove(q.id);
                              }
                            });
                          },
                        );
                      }),
                    if (selectedQualIds.length >= 2) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Verknüpfung bei mehreren Qualifikationen:',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(
                            value: true,
                            label: Text('Alle (UND)'),
                          ),
                          ButtonSegment(
                            value: false,
                            label: Text('Mind. eine (ODER)'),
                          ),
                        ],
                        selected: {requireAllQuals},
                        onSelectionChanged: (set) =>
                            setLocal(() => requireAllQuals = set.first),
                      ),
                    ],
                    const Divider(height: 24),
                    const Text(
                      'Checkliste für diese Einsatzrolle (max. 1):',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String?>(
                      initialValue: selectedChecklistId,
                      decoration: const InputDecoration(
                        labelText: 'Zugeordnete Checkliste',
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Keine Checkliste'),
                        ),
                        ...checklists.map(
                          (c) => DropdownMenuItem<String?>(
                            value: c.id,
                            child: Text(
                              '${c.title} (${c.parseChecklistItems().length} Punkte)',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (v) => setLocal(() => selectedChecklistId = v),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Arbeitsanweisungen für diese Einsatzrolle:',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    if (instructions.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          'Noch keine Arbeitsanweisungen hochgeladen (über „Anweisungen & Checklisten“ anlegen).',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      )
                    else
                      ...instructions.map((doc) {
                        return CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: selectedInstructionIds.contains(doc.id),
                          title: Text(doc.title),
                          onChanged: (v) {
                            setLocal(() {
                              if (v == true) {
                                selectedInstructionIds.add(doc.id);
                              } else {
                                selectedInstructionIds.remove(doc.id);
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
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                onPressed: () {
                  if (nameCtrl.text.trim().isEmpty) return;
                  Navigator.pop(ctx, true);
                },
                child: const Text('Speichern'),
              ),
            ],
          );
        },
      ),
    );

    final roleName = nameCtrl.text.trim();
    _dialogOpen = false;
    Future<void>.delayed(const Duration(milliseconds: 300), nameCtrl.dispose);

    if (ok != true || roleName.isEmpty) return;

    setState(() => _busy = true);
    try {
      if (existing == null) {
        await _service.createTeamRole(
          flightSchoolId: fs.id,
          name: roleName,
          requiredQualificationIds: selectedQualIds.toList(),
          requireAllQualifications: requireAllQuals,
          checklistId: selectedChecklistId,
          instructionIds: selectedInstructionIds.toList(),
        );
      } else {
        await _service.updateTeamRole(
          role: existing,
          name: roleName,
          requiredQualificationIds: selectedQualIds.toList(),
          requireAllQualifications: requireAllQuals,
          checklistId: selectedChecklistId,
          instructionIds: selectedInstructionIds.toList(),
        );
      }
      await _reloadSchool();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteRole(TeamRole role) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Teamrolle löschen?'),
        content: Text('Möchtest du die Rolle „${role.name}“ wirklich löschen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    await _service.deleteTeamRole(role);
    await _reloadSchool();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final fs = context.watch<FlightSchoolProvider>().flightSchool;
    if (fs == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final roles = fs.teamRoles;
    final docTitleById = {for (final d in _schoolDocs) d.id: d.title};
    final qualNameById = {for (final q in fs.qualifications) q.id: q.name};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Teamrollen (Einsatzpositionen)'),
        actions: [
          IconButton(
            tooltip: 'Anweisungen & Checklisten verwalten',
            icon: const Icon(Icons.menu_book_outlined),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ManageRoleDocumentsView(),
                ),
              );
              if (mounted) _loadDocs();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : () => _openRoleDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Neue Rolle'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: roles.isEmpty
                  ? EmptyStateView(
                      icon: Icons.badge_outlined,
                      title: 'Noch keine Teamrollen vorhanden',
                      subtitle:
                          'Lege Einsatzpositionen wie Startplatz, Trainingsleiter oder Kamera an und verknüpfe Qualifikationen & Checklisten.',
                      actionLabel: 'Neue Rolle anlegen',
                      actionIcon: Icons.add,
                      onAction: _busy ? null : () => _openRoleDialog(),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                      itemCount: roles.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final r = roles[index];
                        final reqQualNames = r.requiredQualificationIds
                            .map((id) => qualNameById[id])
                            .whereType<String>()
                            .toList();
                        final checklistTitle = r.checklistId != null
                            ? docTitleById[r.checklistId!]
                            : null;
                        final instructionTitles = r.instructionIds
                            .map((id) => docTitleById[id])
                            .whereType<String>()
                            .toList();

                        final qualConnector =
                            r.requireAllQualifications ? ' & ' : ' ODER ';

                        final detailLines = <String>[
                          reqQualNames.isEmpty
                              ? 'Pflicht-Qualifikation: Keine'
                              : 'Pflicht-Qualifikation: ${reqQualNames.join(qualConnector)}',
                          if (checklistTitle != null)
                            'Checkliste: $checklistTitle',
                          if (instructionTitles.isNotEmpty)
                            'Anweisungen: ${instructionTitles.join(', ')}',
                        ];

                        return Card(
                          clipBehavior: Clip.antiAlias,
                          child: ListTile(
                            onTap: _busy
                                ? null
                                : () => _openRoleDialog(existing: r),
                            leading: CircleAvatar(
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer,
                              child: Icon(
                                Icons.badge_outlined,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    r.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                                if (r.isDefault)
                                  const Chip(
                                    label: Text('Standard',
                                        style: TextStyle(fontSize: 11)),
                                    visualDensity: VisualDensity.compact,
                                  ),
                              ],
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                detailLines.join('\n'),
                                style: const TextStyle(fontSize: 12.5),
                              ),
                            ),
                            trailing: PopupMenuButton<String>(
                              tooltip: 'Rollen-Aktionen',
                              onSelected: (v) {
                                if (v == 'edit') _openRoleDialog(existing: r);
                                if (v == 'delete') _deleteRole(r);
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit_outlined, size: 20),
                                      SizedBox(width: 12),
                                      Text('Bearbeiten'),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.delete_outline,
                                        size: 20,
                                        color: AppTheme.dangerColor,
                                      ),
                                      SizedBox(width: 12),
                                      Text(
                                        'Löschen',
                                        style: TextStyle(
                                          color: AppTheme.dangerColor,
                                        ),
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
