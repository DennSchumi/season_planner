import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/core/data/models/audit_export_model.dart';
import 'package:season_planner/core/services/audit_export_service.dart';
import 'package:season_planner/core/services/data_window.dart';
import 'package:season_planner/core/services/file_download_helper.dart';
import 'package:season_planner/core/theme.dart';
import 'package:season_planner/core/widgets/user_avatar.dart';
import 'package:season_planner/core/widgets/ux_components.dart';
import 'package:season_planner/fsAdmin/data/models/flight_school_model_flight_school_view.dart';
import 'package:season_planner/fsAdmin/data/models/user_summary_flight_school_view.dart';
import 'package:season_planner/fsAdmin/flight_school_provider.dart';
import 'package:season_planner/fsAdmin/services/flight_school_service.dart';

class StellenbesetzungsplanView extends StatefulWidget {
  const StellenbesetzungsplanView({super.key});

  @override
  State<StellenbesetzungsplanView> createState() =>
      _StellenbesetzungsplanViewState();
}

class _StellenbesetzungsplanViewState extends State<StellenbesetzungsplanView> {
  final _service = AuditExportService();
  final _fsService = FlightSchoolService();

  int _selectedYear = DateTime.now().year;
  bool _loading = true;
  bool _exporting = false;

  Map<String, AuditMemberCompliance> _complianceByMemberId = {};
  Set<String> _selectedMemberIds = {};
  String _directorUserId = '';
  Set<String> _officeMemberIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadForYear());
  }

  Future<void> _loadForYear() async {
    final fsProvider = context.read<FlightSchoolProvider>();
    final initialFs = fsProvider.flightSchool;
    if (initialFs == null || initialFs.id.isEmpty) return;
    var fs = initialFs;

    setState(() => _loading = true);

    // Für Audit-Exports des gewählten Jahres stets alle Events/Tandem-Dienste
    // laden, falls das gewählte Jahr außerhalb des 3-Monate-Standardfensters liegt.
    if (!fs.hasLoadedArchive &&
        DataWindow.isYearOutsideDefaultWindow(_selectedYear)) {
      fsProvider.setIncludeArchive(true);
      final results = await Future.wait([
        _fsService.refreshEventsOnly(fs, includeArchive: true),
        _fsService.refreshTandemOnly(fs, includeArchive: true),
      ]);
      if (!mounted) return;
      var updated = fs.copyWith(hasLoadedArchive: true);
      if (results[0] != null) {
        updated = updated.copyWith(events: results[0]!.events);
      }
      if (results[1] != null) {
        updated = updated.copyWith(
          tandemDuties: results[1]!.tandemDuties,
          tandemDemands: results[1]!.tandemDemands,
        );
      }
      fsProvider.applyPartialUpdate(updated);
      fs = updated;
    }

    final compliance = await _service.loadComplianceForSchool(
      fs: fs,
      year: _selectedYear,
    );
    if (!mounted) return;

    // Standard-Vorauswahl: Alle Mitarbeiter mit mind. 1 bestätigtem Einsatz im gewählten Jahr
    // sowie konfigurierter Ausbildungsleiter & Büro-Personal
    final autoSelected = <String>{};
    for (final entry in compliance.entries) {
      if (entry.value.confirmedAssignmentsInYear > 0) {
        autoSelected.add(entry.key);
      }
    }
    final dirId = fs.auditProfile.trainingDirectorUserId;
    if (dirId.isNotEmpty && fs.members.any((m) => m.id == dirId)) {
      autoSelected.add(dirId);
    }
    for (final offId in fs.auditProfile.officeMemberIds) {
      if (fs.members.any((m) => m.id == offId)) {
        autoSelected.add(offId);
      }
    }

    setState(() {
      _complianceByMemberId = compliance;
      _selectedMemberIds = autoSelected;
      _directorUserId = dirId;
      _officeMemberIds = Set<String>.from(fs.auditProfile.officeMemberIds);
      _loading = false;
    });
  }

  Future<void> _exportPdf(FlightSchoolModelFlightSchoolView fs) async {
    if (_exporting) return;
    final included =
        fs.members.where((m) => _selectedMemberIds.contains(m.id)).toList();
    if (included.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte wähle mindestens einen Mitarbeiter aus.'),
        ),
      );
      return;
    }

    setState(() => _exporting = true);
    try {
      // Aktuelle Auswahl für Ausbildungsleiter & Büro ggf. übernehmen
      final effectiveProfile = fs.auditProfile.copyWith(
        trainingDirectorUserId: _directorUserId,
        officeMemberIds: _officeMemberIds.toList(),
      );

      // Änderungen an Ausbildungsleiter/Büro direkt in der Schule mitpersistieren
      if (_directorUserId != fs.auditProfile.trainingDirectorUserId ||
          _officeMemberIds.length != fs.auditProfile.officeMemberIds.length ||
          !_officeMemberIds.containsAll(fs.auditProfile.officeMemberIds)) {
        await _service.saveSchoolAuditProfile(
          flightSchoolId: fs.id,
          profile: effectiveProfile,
        );
        if (mounted) {
          context.read<FlightSchoolProvider>().reloadFlightSchoolInBackground(
            _fsService.getFlightSchool,
          );
        }
      }

      final result = await _service.buildStellenbesetzungsplanPdf(
        fs: fs,
        profile: effectiveProfile,
        year: _selectedYear,
        includedMembers: included,
        complianceByMemberId: _complianceByMemberId,
      );

      final now = DateTime.now();
      final dateStamp =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final safeSchool = (fs.displayShortName.isNotEmpty
              ? fs.displayShortName
              : fs.displayName)
          .replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_');
      final filename =
          'Stellenbesetzungsplan_${safeSchool}_${_selectedYear}_$dateStamp.pdf';

      final saved = await downloadBytesFile(
        bytes: result.pdfBytes,
        filename: filename,
        mimeType: 'application/pdf',
      );
      if (!mounted) return;

      if (saved) {
        final warningSuffix =
            result.warnings.isNotEmpty
                ? ' (${result.warnings.length} Hinweis(e) bei Anhängen)'
                : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'PDF „$filename“ erstellt (${result.attachedDocumentCount} Nachweise angehängt)$warningSuffix.',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF-Download abgebrochen.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export fehlgeschlagen: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fs = context.watch<FlightSchoolProvider>().flightSchool;
    if (fs == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final cs = Theme.of(context).colorScheme;
    final currentYear = DateTime.now().year;
    final availableYears =
        <int>{
            currentYear,
            currentYear - 1,
            currentYear + 1,
            ...fs.events.map((e) => e.startTime.year),
            ...fs.tandemDuties.map((d) => d.startDay.year),
          }.toList()
          ..sort((a, b) => b.compareTo(a));

    final selectedMembers =
        fs.members.where((m) => _selectedMemberIds.contains(m.id)).toList();
    final totalDocsToAttach = selectedMembers.fold<int>(
      0,
      (sum, m) =>
          sum + (_complianceByMemberId[m.id]?.validApprovedDocs.length ?? 0),
    );
    final membersWithDocWarnings =
        selectedMembers
            .where((m) => _complianceByMemberId[m.id]?.hasDocWarnings == true)
            .length;

    // Sortierung in der Auswahl: aktiv eingeplante Mitarbeiter ganz oben
    final sortedMembers = List<UserSummary>.from(fs.members)..sort((a, b) {
      final aCount =
          _complianceByMemberId[a.id]?.confirmedAssignmentsInYear ?? 0;
      final bCount =
          _complianceByMemberId[b.id]?.confirmedAssignmentsInYear ?? 0;
      final aActive = aCount > 0 ? 0 : 1;
      final bActive = bCount > 0 ? 0 : 1;
      if (aActive != bActive) return aActive.compareTo(bActive);
      if (aCount != bCount) return bCount.compareTo(aCount);
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });

    final dirDropdownVal =
        fs.members.any((m) => m.id == _directorUserId) ? _directorUserId : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Stellenbesetzungsplan (ÖAeC)')),
      body: SafeArea(
        child: Column(
          children: [
            if (_loading || _exporting)
              const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadForYear,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    // 1) Jahr, Ausbildungsleiter & Kennzahlen
                    SoftCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<int>(
                                  initialValue: _selectedYear,
                                  decoration: const InputDecoration(
                                    labelText: 'Bezugsjahr',
                                  ),
                                  items:
                                      availableYears
                                          .map(
                                            (y) => DropdownMenuItem<int>(
                                              value: y,
                                              child: Text('Jahr $y'),
                                            ),
                                          )
                                          .toList(),
                                  onChanged:
                                      _loading || _exporting
                                          ? null
                                          : (y) {
                                            if (y != null &&
                                                y != _selectedYear) {
                                              setState(() => _selectedYear = y);
                                              _loadForYear();
                                            }
                                          },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: 2,
                                child: DropdownButtonFormField<String?>(
                                  initialValue: dirDropdownVal,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Ausbildungsleiter',
                                  ),
                                  items: [
                                    const DropdownMenuItem<String?>(
                                      value: null,
                                      child: Text('Aus Audit-Stammdaten'),
                                    ),
                                    ...fs.members.map(
                                      (m) => DropdownMenuItem<String?>(
                                        value: m.id,
                                        child: Text(m.displayName),
                                      ),
                                    ),
                                  ],
                                  onChanged:
                                      _exporting
                                          ? null
                                          : (v) {
                                            setState(() {
                                              _directorUserId = v ?? '';
                                              if (v != null && v.isNotEmpty) {
                                                _selectedMemberIds.add(v);
                                              }
                                            });
                                          },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: KpiMetricCard(
                                  label: 'Ausgewählt',
                                  value: '${selectedMembers.length} Pers.',
                                  icon: Icons.people_outline_rounded,
                                  iconColor: AppTheme.primaryColor,
                                  iconBg: AppTheme.primaryTint,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: KpiMetricCard(
                                  label: 'Nachweise im PDF',
                                  value: '$totalDocsToAttach Dok.',
                                  icon: Icons.attach_file_rounded,
                                  iconColor: AppTheme.successColor,
                                  iconBg: AppTheme.successBg,
                                ),
                              ),
                            ],
                          ),
                          if (membersWithDocWarnings > 0) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppTheme.warningBg,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.warning_amber_rounded,
                                    size: 18,
                                    color: AppTheme.warningColor,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Audit-Hinweis: Bei $membersWithDocWarnings ausgewählten ${membersWithDocWarnings == 1 ? "Mitarbeiter" : "Mitarbeitern"} fehlen noch Pflichtnachweise oder sind abgelaufen. Es werden nur freigegebene & gültige Dokumente angehängt.',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.warningColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 2) Büro-Personal Schnellauswahl
                    SoftCard(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'BÜRO-PERSONAL (EIGENER ABSCHNITT IM PLAN)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.7,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children:
                                fs.members.map((m) {
                                  final isOffice = _officeMemberIds.contains(
                                    m.id,
                                  );
                                  return FilterChip(
                                    label: Text(m.displayName),
                                    selected: isOffice,
                                    visualDensity: VisualDensity.compact,
                                    onSelected:
                                        _exporting
                                            ? null
                                            : (v) {
                                              setState(() {
                                                if (v) {
                                                  _officeMemberIds.add(m.id);
                                                  _selectedMemberIds.add(m.id);
                                                } else {
                                                  _officeMemberIds.remove(m.id);
                                                }
                                              });
                                            },
                                  );
                                }).toList(),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    // 3) Mitarbeiter-Auswahl & Vorab-Check
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'MITARBEITER & NACHWEIS-CHECK ($_selectedYear)',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.7,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed:
                              _exporting
                                  ? null
                                  : () {
                                    setState(() {
                                      if (_selectedMemberIds.length ==
                                          fs.members.length) {
                                        _selectedMemberIds.clear();
                                      } else {
                                        _selectedMemberIds =
                                            fs.members.map((m) => m.id).toSet();
                                      }
                                    });
                                  },
                          child: Text(
                            _selectedMemberIds.length == fs.members.length
                                ? 'Alle abwählen'
                                : 'Alle wählen',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    for (final m in sortedMembers) ...[
                      _buildMemberCheckCard(context, fs, m),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
            ),

            // Sticky Export-Button unten
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                border: Border(top: BorderSide(color: cs.outlineVariant)),
              ),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed:
                    _loading || _exporting || selectedMembers.isEmpty
                        ? null
                        : () => _exportPdf(fs),
                icon:
                    _exporting
                        ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                        : const Icon(Icons.picture_as_pdf_outlined, size: 20),
                label: Text(
                  _exporting
                      ? 'Gesamt-PDF inkl. Anhänge wird erstellt…'
                      : 'Stellenbesetzungsplan als Gesamt-PDF exportieren',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberCheckCard(
    BuildContext context,
    FlightSchoolModelFlightSchoolView fs,
    UserSummary m,
  ) {
    final cs = Theme.of(context).colorScheme;
    final selected = _selectedMemberIds.contains(m.id);
    final comp = _complianceByMemberId[m.id];
    final assignments = comp?.confirmedAssignmentsInYear ?? 0;
    final validDocs = comp?.validApprovedDocs ?? const [];
    final qualNames =
        m.qualificationIds
            .map(fs.qualificationName)
            .where((s) => s.trim().isNotEmpty)
            .toList();

    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border:
          selected && comp?.hasDocWarnings == true
              ? Border.all(color: AppTheme.warningColor.withValues(alpha: 0.45))
              : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(
                value: selected,
                onChanged:
                    _exporting
                        ? null
                        : (v) {
                          setState(() {
                            if (v == true) {
                              _selectedMemberIds.add(m.id);
                            } else {
                              _selectedMemberIds.remove(m.id);
                            }
                          });
                        },
              ),
              UserAvatar(
                avatarUrl: m.avatarUrl,
                name: m.displayName,
                radius: 17,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      [
                        if (qualNames.isNotEmpty) qualNames.join(', '),
                        assignments > 0
                            ? '$assignments best. Einsatz${assignments == 1 ? "" : "e"} ($_selectedYear)'
                            : 'Keine Einsätze in $_selectedYear',
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              StatusPill(
                label: '${validDocs.length} Dok.',
                foreground:
                    validDocs.isNotEmpty
                        ? AppTheme.successColor
                        : cs.onSurfaceVariant,
                background:
                    validDocs.isNotEmpty
                        ? AppTheme.successBg
                        : AppTheme.backgroundColor,
                fontSize: 11,
              ),
            ],
          ),
          if (selected && comp != null && comp.hasAnyWarning) ...[
            Padding(
              padding: const EdgeInsets.only(left: 48, top: 6, right: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final exp in comp.expiredDocTypes)
                    StatusPill(
                      label: 'Abgelaufen: $exp',
                      foreground: AppTheme.dangerColor,
                      background: AppTheme.dangerBg,
                      fontSize: 10.5,
                    ),
                  for (final miss in comp.missingDocTypes)
                    StatusPill(
                      label: 'Fehlt: $miss',
                      foreground: AppTheme.warningColor,
                      background: AppTheme.warningBg,
                      fontSize: 10.5,
                    ),
                  if (comp.missingProfileFields.isNotEmpty)
                    StatusPill(
                      label:
                          'Profil offen: ${comp.missingProfileFields.join(", ")}',
                      foreground: AppTheme.infoColor,
                      background: AppTheme.infoBg,
                      fontSize: 10.5,
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
