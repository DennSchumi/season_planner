import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/core/data/models/audit_export_model.dart';
import 'package:season_planner/core/services/audit_export_service.dart';
import 'package:season_planner/core/theme.dart';
import 'package:season_planner/core/widgets/ux_components.dart';
import 'package:season_planner/fsAdmin/data/models/flight_school_model_flight_school_view.dart';
import 'package:season_planner/fsAdmin/features/audit_exports/stellenbesetzungsplan_view.dart';
import 'package:season_planner/fsAdmin/flight_school_provider.dart';
import 'package:season_planner/fsAdmin/services/flight_school_service.dart';

/// Erweiterbarer Bereich „Audit Exports“ für ÖAeC-Flugschulaudits:
/// - Ein-/Ausschalter pro Flugschule
/// - Zentrale Pflege der ÖAeC-Flugschuldaten, Ausbildungsleiter & Büro-Personal
/// - Modulare Liste der verfügbaren Audit-Dokumente (Start: Stellenbesetzungsplan)
class AuditExportsView extends StatefulWidget {
  const AuditExportsView({super.key});

  @override
  State<AuditExportsView> createState() => _AuditExportsViewState();
}

class _AuditExportsViewState extends State<AuditExportsView> {
  final _service = AuditExportService();
  final _fsService = FlightSchoolService();

  bool _busy = false;
  bool _schoolFormExpanded = false;
  String? _loadedSchoolId;

  final _officialNameCtrl = TextEditingController();
  final _ownerNameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _bescheidCtrl = TextEditingController();
  final _directorSinceCtrl = TextEditingController();
  final _directorNameCtrl = TextEditingController();
  final _directorAddressCtrl = TextEditingController();
  final _directorEmailCtrl = TextEditingController();
  final _directorPhoneCtrl = TextEditingController();
  final _directorBirthCtrl = TextEditingController();

  String _directorUserId = '';
  Set<String> _officeMemberIds = {};

  @override
  void dispose() {
    _officialNameCtrl.dispose();
    _ownerNameCtrl.dispose();
    _addressCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _bescheidCtrl.dispose();
    _directorSinceCtrl.dispose();
    _directorNameCtrl.dispose();
    _directorAddressCtrl.dispose();
    _directorEmailCtrl.dispose();
    _directorPhoneCtrl.dispose();
    _directorBirthCtrl.dispose();
    super.dispose();
  }

  void _syncFromSchool(FlightSchoolModelFlightSchoolView fs) {
    final p = fs.auditProfile;
    _loadedSchoolId = fs.id;
    _officialNameCtrl.text =
        p.officialName.isNotEmpty ? p.officialName : fs.displayName;
    _ownerNameCtrl.text = p.ownerName;
    _addressCtrl.text = p.address;
    _emailCtrl.text = p.email;
    _phoneCtrl.text = p.phone;
    _bescheidCtrl.text = p.bescheidNumber;
    _directorUserId = p.trainingDirectorUserId;
    _directorSinceCtrl.text = p.trainingDirectorSince;
    _directorNameCtrl.text = p.trainingDirectorName;
    _directorAddressCtrl.text = p.trainingDirectorAddress;
    _directorEmailCtrl.text = p.trainingDirectorEmail;
    _directorPhoneCtrl.text = p.trainingDirectorPhone;
    _directorBirthCtrl.text = p.trainingDirectorBirthDate;
    _officeMemberIds = Set<String>.from(p.officeMemberIds);
    if (!p.hasBasicSchoolInfo) {
      _schoolFormExpanded = true;
    }
  }

  Future<void> _reloadSchool() async {
    await context
        .read<FlightSchoolProvider>()
        .reloadFlightSchool(_fsService.getFlightSchool);
  }

  Future<void> _toggleEnabled(
    FlightSchoolModelFlightSchoolView fs,
    bool enabled,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ok = await _service.setAuditExportsEnabled(
        flightSchoolId: fs.id,
        enabled: enabled,
      );
      if (!mounted) return;
      if (ok) {
        await _reloadSchool();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                enabled
                    ? 'Audit Exports aktiviert.'
                    : 'Audit Exports für ${fs.displayName} deaktiviert.',
              ),
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveAuditProfile(FlightSchoolModelFlightSchoolView fs) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final nextProfile = FlightSchoolAuditProfile(
        officialName: _officialNameCtrl.text,
        ownerName: _ownerNameCtrl.text,
        address: _addressCtrl.text,
        email: _emailCtrl.text,
        phone: _phoneCtrl.text,
        bescheidNumber: _bescheidCtrl.text,
        trainingDirectorUserId: _directorUserId,
        trainingDirectorName: _directorNameCtrl.text,
        trainingDirectorAddress: _directorAddressCtrl.text,
        trainingDirectorEmail: _directorEmailCtrl.text,
        trainingDirectorPhone: _directorPhoneCtrl.text,
        trainingDirectorBirthDate: _directorBirthCtrl.text,
        trainingDirectorSince: _directorSinceCtrl.text,
        officeMemberIds: _officeMemberIds.toList(),
      );
      final ok = await _service.saveSchoolAuditProfile(
        flightSchoolId: fs.id,
        profile: nextProfile,
      );
      if (!mounted) return;
      if (ok) {
        await _reloadSchool();
        if (mounted) {
          setState(() => _schoolFormExpanded = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Audit-Stammdaten der Flugschule gespeichert.'),
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Speichern fehlgeschlagen.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _applyDirectorMember(FlightSchoolModelFlightSchoolView fs, String? uid) {
    final selected = uid == null || uid.isEmpty ? null : fs.findMemberByAnyId(uid);
    setState(() {
      _directorUserId = selected?.id ?? '';
      if (selected != null) {
        _directorNameCtrl.text = selected.displayName;
        if (selected.address.isNotEmpty) {
          _directorAddressCtrl.text = selected.address;
        }
        if (selected.mail.isNotEmpty) _directorEmailCtrl.text = selected.mail;
        if (selected.phone.isNotEmpty) _directorPhoneCtrl.text = selected.phone;
        if (selected.birthDate.isNotEmpty) {
          _directorBirthCtrl.text = selected.birthDate;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final fs = context.watch<FlightSchoolProvider>().flightSchool;
    if (fs == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_loadedSchoolId != fs.id) {
      _syncFromSchool(fs);
    }

    final cs = Theme.of(context).colorScheme;
    final dirValue = fs.members.any((m) => m.id == _directorUserId)
        ? _directorUserId
        : null;

    // Erweiterbare Liste der ÖAeC-Audit-Dokumente
    final auditTemplates = <({
      IconData icon,
      Color color,
      Color bg,
      String code,
      String title,
      String subtitle,
      VoidCallback? onTap,
    })>[
      (
        icon: Icons.groups_outlined,
        color: AppTheme.primaryColor,
        bg: AppTheme.primaryTint,
        code: 'ÖAeC ORG 025',
        title: 'Stellenbesetzungsplan',
        subtitle:
            'Alle fest eingeplanten Mitarbeiter im gewählten Jahr, nach Qualifikation gruppiert inkl. aller freigegebenen Nachweise als 1 Gesamt-PDF.',
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const StellenbesetzungsplanView(),
            ),
          );
        },
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Audit Exports')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _reloadSchool,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: LinearProgressIndicator(minHeight: 2),
                ),

              // 1) Ein-/Ausschalter
              SoftCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                child: SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Audit Exports aktiv',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  subtitle: Text(
                    fs.auditExportsEnabled
                        ? 'ÖAeC-Audit-Dokumente inkl. Nachweis-Anhänge erstellen.'
                        : 'Für ${fs.displayName} deaktiviert.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  value: fs.auditExportsEnabled,
                  onChanged: _busy ? null : (v) => _toggleEnabled(fs, v),
                ),
              ),

              if (fs.auditExportsEnabled) ...[
                const SizedBox(height: 18),

                // 2) Verfügbare Audit-Dokumente (erweiterbar)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                  child: Text(
                    'VERFÜGBARE AUDIT-DOKUMENTE',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.7,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                for (final tpl in auditTemplates) ...[
                  SoftCard(
                    padding: const EdgeInsets.all(16),
                    onTap: tpl.onTap,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TintedIconBadge(
                          icon: tpl.icon,
                          iconColor: tpl.color,
                          backgroundColor: tpl.bg,
                          size: 44,
                          iconSize: 22,
                          radius: 13,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      tpl.title,
                                      style: const TextStyle(
                                        fontSize: 15.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  StatusPill(
                                    label: tpl.code,
                                    foreground: tpl.color,
                                    background: tpl.bg,
                                    fontSize: 10.5,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                tpl.subtitle,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: cs.onSurfaceVariant,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: cs.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                const SizedBox(height: 12),

                // 3) Flugschul-Auditdaten, Ausbildungsleiter & Büro
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                  child: Text(
                    'FLUGSCHULDATEN FÜR AUDIT-FORMBLÄTTER',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.7,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                SoftCard(
                  child: Column(
                    children: [
                      InkWell(
                        onTap: () => setState(
                          () => _schoolFormExpanded = !_schoolFormExpanded,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(15),
                          child: Row(
                            children: [
                              const TintedIconBadge(
                                icon: Icons.apartment_outlined,
                                iconColor: AppTheme.primaryColor,
                                backgroundColor: AppTheme.primaryTint,
                                size: 38,
                                iconSize: 20,
                                radius: 11,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Flugschule, Bescheid & Ausbildungsleiter',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14.5,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      fs.auditProfile.hasBasicSchoolInfo
                                          ? '${fs.auditProfile.ownerName.isNotEmpty ? fs.auditProfile.ownerName : fs.displayName} · Bescheid: ${fs.auditProfile.bescheidNumber.isNotEmpty ? fs.auditProfile.bescheidNumber : "–"}'
                                          : 'Noch nicht ausgefüllt – zum Bearbeiten tippen',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: fs.auditProfile.hasBasicSchoolInfo
                                            ? cs.onSurfaceVariant
                                            : AppTheme.warningColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                _schoolFormExpanded
                                    ? Icons.keyboard_arrow_up_rounded
                                    : Icons.keyboard_arrow_down_rounded,
                                color: cs.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_schoolFormExpanded) ...[
                        Divider(height: 1, color: cs.outlineVariant),
                        Padding(
                          padding: const EdgeInsets.all(15),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextField(
                                controller: _officialNameCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Name wie im Ausbildungsbescheid',
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _ownerNameCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Eigentümer (Name, Vorname)',
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _addressCtrl,
                                decoration: const InputDecoration(
                                  labelText:
                                      'Anschrift (Straße Nr., PLZ Ort)',
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _emailCtrl,
                                      keyboardType: TextInputType.emailAddress,
                                      decoration: const InputDecoration(
                                        labelText: 'Schul-E-Mail',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: _phoneCtrl,
                                      keyboardType: TextInputType.phone,
                                      decoration: const InputDecoration(
                                        labelText: 'Schul-Telefon',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'AUSBILDUNGSLEITER / GESCHÄFTSFÜHRER',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.7,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: TextField(
                                      controller: _bescheidCtrl,
                                      decoration: const InputDecoration(
                                        labelText: 'Bescheid-Nummer',
                                        hintText: 'AZ.2026/.../HGPG-Schul/...',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: _directorSinceCtrl,
                                      decoration: const InputDecoration(
                                        labelText: 'Nominiert seit',
                                        hintText: 'TT.MM.JJJJ',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              DropdownButtonFormField<String?>(
                                initialValue: dirValue,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText:
                                      'Ausbildungsleiter aus Team wählen (optional)',
                                ),
                                items: [
                                  const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('Manuelle Eingabe'),
                                  ),
                                  ...fs.members.map(
                                    (m) => DropdownMenuItem<String?>(
                                      value: m.id,
                                      child: Text(m.displayName),
                                    ),
                                  ),
                                ],
                                onChanged: (v) => _applyDirectorMember(fs, v),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: TextField(
                                      controller: _directorNameCtrl,
                                      decoration: const InputDecoration(
                                        labelText: 'Name Ausbildungsleiter',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: _directorBirthCtrl,
                                      decoration: const InputDecoration(
                                        labelText: 'Geboren am',
                                        hintText: 'TT.MM.JJJJ',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _directorAddressCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Anschrift Ausbildungsleiter',
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _directorEmailCtrl,
                                      keyboardType: TextInputType.emailAddress,
                                      decoration: const InputDecoration(
                                        labelText: 'E-Mail',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: _directorPhoneCtrl,
                                      keyboardType: TextInputType.phone,
                                      decoration: const InputDecoration(
                                        labelText: 'Telefon',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'BÜRO-PERSONAL (OPTIONAL)',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.7,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: fs.members.map((m) {
                                  final selected =
                                      _officeMemberIds.contains(m.id);
                                  return FilterChip(
                                    label: Text(m.displayName),
                                    selected: selected,
                                    onSelected: (v) {
                                      setState(() {
                                        if (v) {
                                          _officeMemberIds.add(m.id);
                                        } else {
                                          _officeMemberIds.remove(m.id);
                                        }
                                      });
                                    },
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 14),
                              FilledButton.icon(
                                onPressed:
                                    _busy ? null : () => _saveAuditProfile(fs),
                                icon: const Icon(Icons.save_outlined, size: 18),
                                label: const Text('Audit-Stammdaten speichern'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
