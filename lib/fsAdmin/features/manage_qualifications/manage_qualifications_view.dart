import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/core/data/models/team_role_model.dart';
import 'package:season_planner/core/services/qualification_service.dart';
import 'package:season_planner/fsAdmin/data/models/user_summary_flight_school_view.dart';
import 'package:season_planner/fsAdmin/flight_school_provider.dart';
import 'package:season_planner/fsAdmin/services/flight_school_service.dart';

/// Admin-Verwaltung für Qualifikationen (z. B. Fluglehrer, Sicherheitstrainer,
/// Anwärter, Tandempilot) inkl. Pflichtnachweisen UND eingehenden Qualifikations-Anfragen.
class ManageQualificationsView extends StatefulWidget {
  final int initialTab;

  const ManageQualificationsView({super.key, this.initialTab = 0});

  @override
  State<ManageQualificationsView> createState() =>
      _ManageQualificationsViewState();
}

class _ManageQualificationsViewState extends State<ManageQualificationsView> {
  final _service = QualificationService();
  bool _busy = false;

  Future<void> _reloadSchool() async {
    await context.read<FlightSchoolProvider>().reloadFlightSchool(
          FlightSchoolService().getFlightSchool,
        );
  }

  Future<void> _openQualificationDialog({Qualification? existing}) async {
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null) return;

    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final customDocCtrl = TextEditingController();
    final selectedDocs = <String>{...(existing?.requiredDocuments ?? const [])};
    final allCatalogDocs = <String>{
      ...kStandardDocumentTypes,
      ...selectedDocs,
    };

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final extraDocs = allCatalogDocs
              .where((d) => !kStandardDocumentTypes.contains(d))
              .toList()
            ..sort();
          final sortedCatalog = [...kStandardDocumentTypes, ...extraDocs];
          return AlertDialog(
            title: Text(
              existing == null
                  ? 'Neue Qualifikation anlegen'
                  : 'Qualifikation bearbeiten',
            ),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Bezeichnung *',
                        hintText: 'z. B. Sicherheitstrainer oder Bootsschein',
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Geforderte Dokumentennachweise für diese Qualifikation:',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    ...sortedCatalog.map((docType) {
                      return CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: selectedDocs.contains(docType),
                        title: Text(docType),
                        onChanged: (v) {
                          setLocal(() {
                            if (v == true) {
                              selectedDocs.add(docType);
                            } else {
                              selectedDocs.remove(docType);
                            }
                          });
                        },
                      );
                    }),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: customDocCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Eigenen Nachweis-Typ hinzufügen',
                              hintText: 'z. B. Windenfahrer-Schein',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          tooltip: 'Hinzufügen',
                          icon: const Icon(Icons.add),
                          onPressed: () {
                            final v = customDocCtrl.text.trim();
                            if (v.isEmpty) return;
                            setLocal(() {
                              allCatalogDocs.add(v);
                              selectedDocs.add(v);
                              customDocCtrl.clear();
                            });
                          },
                        ),
                      ],
                    ),
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

    final qualName = nameCtrl.text.trim();
    nameCtrl.dispose();
    customDocCtrl.dispose();

    if (ok != true || qualName.isEmpty) return;

    setState(() => _busy = true);
    try {
      if (existing == null) {
        await _service.createQualification(
          flightSchoolId: fs.id,
          name: qualName,
          requiredDocuments: selectedDocs.toList(),
        );
      } else {
        await _service.updateQualification(
          qualification: existing,
          name: qualName,
          requiredDocuments: selectedDocs.toList(),
        );
      }
      await _reloadSchool();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteQualification(Qualification q) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Qualifikation löschen?'),
        content: Text(
          'Möchtest du die Qualifikation „${q.name}“ wirklich löschen?',
        ),
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
    await _service.deleteQualification(q);
    await _reloadSchool();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _approveRequest(
    UserSummary member,
    Qualification qual,
  ) async {
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null) return;
    setState(() => _busy = true);
    try {
      await _service.approveQualificationRequest(
        membershipId: member.membershipId,
        flightSchoolId: fs.id,
        memberName: member.displayName,
        currentQualificationIds: member.qualificationIds,
        currentRequestedIds: member.requestedQualificationIds,
        qualificationId: qual.id,
        qualificationName: qual.name,
      );
      await _reloadSchool();
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              'Qualifikation „${qual.name}“ für ${member.displayName} eingetragen.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rejectRequest(
    UserSummary member,
    Qualification qual,
  ) async {
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null) return;
    setState(() => _busy = true);
    try {
      await _service.rejectQualificationRequest(
        membershipId: member.membershipId,
        flightSchoolId: fs.id,
        memberName: member.displayName,
        currentRequestedIds: member.requestedQualificationIds,
        qualificationId: qual.id,
        qualificationName: qual.name,
      );
      await _reloadSchool();
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              'Anfrage für „${qual.name}“ von ${member.displayName} abgelehnt.',
            ),
          ),
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

    final quals = fs.qualifications;
    final qualById = {for (final q in quals) q.id: q};

    // Alle offenen Qualifikations-Anfragen sammeln
    final openRequests = <({UserSummary member, Qualification qual})>[];
    for (final m in fs.members) {
      for (final reqId in m.requestedQualificationIds) {
        final q = qualById[reqId];
        if (q != null) {
          openRequests.add((member: m, qual: q));
        }
      }
    }

    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Qualifikationen verwalten'),
          bottom: TabBar(
            tabs: [
              Tab(text: 'Qualifikationen (${quals.length})'),
              Tab(
                text: openRequests.isEmpty
                    ? 'Anfragen'
                    : 'Anfragen (${openRequests.length})',
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _busy ? null : () => _openQualificationDialog(),
          icon: const Icon(Icons.add),
          label: const Text('Neue Qualifikation'),
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (_busy) const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: TabBarView(
                  children: [
                    // TAB 1: Qualifikationen & ihre Pflichtnachweise
                    quals.isEmpty
                        ? const Center(
                            child: Text('Noch keine Qualifikationen vorhanden.'),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                            itemCount: quals.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final q = quals[index];
                              return Card(
                                clipBehavior: Clip.antiAlias,
                                child: ListTile(
                                  onTap: _busy
                                      ? null
                                      : () =>
                                          _openQualificationDialog(existing: q),
                                  leading: CircleAvatar(
                                    backgroundColor: Theme.of(context)
                                        .colorScheme
                                        .primaryContainer,
                                    child: Icon(
                                      Icons.workspace_premium_outlined,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          q.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      if (q.isDefault)
                                        const Chip(
                                          label: Text(
                                            'Standard',
                                            style: TextStyle(fontSize: 11),
                                          ),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                    ],
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      q.requiredDocuments.isEmpty
                                          ? 'Keine Pflichtnachweise definiert'
                                          : 'Pflichtnachweise: ${q.requiredDocuments.join(', ')}',
                                      style: const TextStyle(fontSize: 12.5),
                                    ),
                                  ),
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (v) {
                                      if (v == 'edit') {
                                        _openQualificationDialog(existing: q);
                                      }
                                      if (v == 'delete') {
                                        _deleteQualification(q);
                                      }
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(
                                        value: 'edit',
                                        child: Text('Bearbeiten'),
                                      ),
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Text('Löschen'),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),

                    // TAB 2: Eingehende Qualifikations-Anfragen
                    openRequests.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'Keine offenen Qualifikations-Anfragen.\nWenn ein Teammitglied eine Qualifikation anfragt, erscheint sie hier zur Freigabe.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.black54),
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                            itemCount: openRequests.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final item = openRequests[index];
                              return Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.workspace_premium,
                                            color: Colors.orange,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              '${item.member.displayName} möchte „${item.qual.name}“ eintragen lassen',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 14.5,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (item
                                          .qual.requiredDocuments.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          'Erforderliche Nachweise: ${item.qual.requiredDocuments.join(', ')}',
                                          style: const TextStyle(
                                            fontSize: 12.5,
                                            color: Colors.black54,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          FilledButton.icon(
                                            onPressed: _busy
                                                ? null
                                                : () => _approveRequest(
                                                      item.member,
                                                      item.qual,
                                                    ),
                                            icon: const Icon(Icons.check,
                                                size: 18),
                                            label: const Text('Zuteilen'),
                                          ),
                                          const SizedBox(width: 8),
                                          OutlinedButton.icon(
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: Colors.red,
                                            ),
                                            onPressed: _busy
                                                ? null
                                                : () => _rejectRequest(
                                                      item.member,
                                                      item.qual,
                                                    ),
                                            icon: const Icon(Icons.close,
                                                size: 18),
                                            label: const Text('Ablehnen'),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
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
      ),
    );
  }
}
