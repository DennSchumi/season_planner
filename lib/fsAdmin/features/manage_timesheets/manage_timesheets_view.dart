import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/core/data/enums/event_status_enum.dart';
import 'package:season_planner/core/data/enums/event_user_status_enum.dart';
import 'package:season_planner/core/data/models/event_model.dart';
import 'package:season_planner/core/data/models/timesheet_model.dart';
import 'package:season_planner/core/services/file_download_helper.dart';
import 'package:season_planner/core/services/timesheet_export_service.dart';
import 'package:season_planner/core/services/timesheet_service.dart';
import 'package:season_planner/core/theme.dart';
import 'package:season_planner/core/widgets/timesheet_runner_view.dart';
import 'package:season_planner/core/widgets/user_avatar.dart';
import 'package:season_planner/core/widgets/ux_components.dart';
import 'package:season_planner/fsAdmin/data/models/flight_school_model_flight_school_view.dart';
import 'package:season_planner/fsAdmin/flight_school_provider.dart';
import 'package:season_planner/fsAdmin/services/flight_school_service.dart';

class ManageTimesheetsView extends StatefulWidget {
  const ManageTimesheetsView({super.key});

  @override
  State<ManageTimesheetsView> createState() => _ManageTimesheetsViewState();
}

class _ManageTimesheetsViewState extends State<ManageTimesheetsView> {
  final _service = TimesheetService();
  final _fsService = FlightSchoolService();

  bool _loading = true;
  bool _savingConfig = false;
  bool _exporting = false;
  List<EventTimesheet> _sheets = [];

  late DateTime _fromDate;
  late DateTime _toDate;
  String? _selectedMemberId; // null = alle Mitglieder

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _fromDate = DateTime(now.year, 1, 1);
    _toDate = DateTime(now.year, 12, 31);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null || fs.id.isEmpty) return;
    setState(() => _loading = true);
    final list = await _service.listTimesheetsForSchool(fs.id);
    if (!mounted) return;
    setState(() {
      _sheets = list;
      _loading = false;
    });
  }

  Future<void> _reloadSchool() async {
    await context
        .read<FlightSchoolProvider>()
        .reloadFlightSchool(_fsService.getFlightSchool);
    if (mounted) await _load();
  }

  Future<void> _saveConfig({
    required FlightSchoolModelFlightSchoolView fs,
    required bool enabled,
    required List<String> qualIds,
  }) async {
    if (_savingConfig) return;
    setState(() => _savingConfig = true);
    try {
      final ok = await _service.updateSchoolTimesheetConfig(
        flightSchoolId: fs.id,
        enabled: enabled,
        qualificationIds: qualIds,
      );
      if (!mounted) return;
      if (ok) {
        await _reloadSchool();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Stundenzettel-Einstellungen gespeichert.'),
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Speichern fehlgeschlagen.')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingConfig = false);
    }
  }

  Future<void> _reopenSheet(EventTimesheet sheet) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Zur Korrektur entsperren?'),
        content: const Text(
          'Der Stundenzettel wird wieder in den Entwurfsstatus gesetzt, damit der Mitarbeiter seine Zeiten anpassen und neu unterschreiben kann.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Entsperren'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final ok = await _service.reopenForCorrection(sheet);
    if (!mounted) return;
    if (ok) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Stundenzettel zur Korrektur wieder geöffnet.'),
          ),
        );
      }
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  String _fmtFileDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _fromDate : _toDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _fromDate = picked;
        if (_toDate.isBefore(_fromDate)) _toDate = _fromDate;
      } else {
        _toDate = picked;
        if (_fromDate.isAfter(_toDate)) _fromDate = _toDate;
      }
    });
  }

  Future<void> _export({
    required bool isPdf,
    required FlightSchoolModelFlightSchoolView fs,
    required List<EventTimesheet> filteredSheets,
  }) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final rows = TimesheetExportService.flattenRows(
        sheets: filteredSheets,
        from: _fromDate,
        to: _toDate,
        resolveSchoolName: (_) => fs.displayName,
        resolveMemberName: (uid) => fs.resolveMemberName(uid),
        onlySubmitted: true,
      );
      if (rows.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Keine abgesendeten Stundenzettel im gewählten Filter vorhanden.',
              ),
            ),
          );
        }
        return;
      }

      final includeMember = _selectedMemberId == null;
      final subtitle = _selectedMemberId != null
          ? '${fs.resolveMemberName(_selectedMemberId!)} · ${fs.displayName}'
          : fs.displayName;
      final rangeTag = '${_fmtFileDate(_fromDate)}_bis_${_fmtFileDate(_toDate)}';

      Uint8List bytes;
      String filename;
      String mimeType;

      if (isPdf) {
        Uint8List? sigBytes;
        String? signerName;
        if (_selectedMemberId != null) {
          signerName = fs.resolveMemberName(_selectedMemberId!);
          for (final s in filteredSheets) {
            if (s.isSubmitted && s.signatureFileId != null) {
              sigBytes = await _service.loadSignatureBytes(s.signatureFileId);
              if (sigBytes != null) break;
            }
          }
        }
        bytes = await TimesheetExportService.buildPdfBytes(
          rows: rows,
          title: 'Stundenzettel-Auswertung',
          subtitle: subtitle,
          from: _fromDate,
          to: _toDate,
          includeMemberColumn: includeMember,
          latestSignatureBytes: sigBytes,
          signerName: signerName,
        );
        filename = 'Stundenzettel_$rangeTag.pdf';
        mimeType = 'application/pdf';
      } else {
        bytes = TimesheetExportService.buildCsvBytes(
          rows: rows,
          includeMemberColumn: includeMember,
        );
        filename = 'Stundenzettel_$rangeTag.csv';
        mimeType = 'text/csv;charset=utf-8';
      }

      final ok = await downloadBytesFile(
        bytes: bytes,
        filename: filename,
        mimeType: mimeType,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? '${isPdf ? "PDF" : "CSV"} „$filename“ wurde exportiert.'
                : 'Export abgebrochen oder fehlgeschlagen.',
          ),
        ),
      );
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
    final effectiveQualIds = fs.effectiveTimesheetQualificationIds;

    final filteredSheets = _sheets.where((s) {
      if (_selectedMemberId == null) return true;
      final m = fs.findMemberByAnyId(_selectedMemberId!);
      return s.userId == _selectedMemberId ||
          (m != null && m.matchesId(s.userId));
    }).toList();

    final rowsInRange = TimesheetExportService.flattenRows(
      sheets: filteredSheets,
      from: _fromDate,
      to: _toDate,
      resolveSchoolName: (_) => fs.displayName,
      resolveMemberName: (uid) => fs.resolveMemberName(uid),
      onlySubmitted: true,
    );

    final totalMinutes =
        rowsInRange.fold<int>(0, (sum, r) => sum + r.netMinutes);
    final totalDays = rowsInRange.length;

    final submittedSheets = filteredSheets.where((s) {
      if (!s.isSubmitted) return false;
      return s.entries.any((e) {
        if (!e.active || e.netMinutes <= 0) return false;
        final d = e.date;
        return !d.isBefore(
              DateTime(_fromDate.year, _fromDate.month, _fromDate.day),
            ) &&
            !d.isAfter(DateTime(_toDate.year, _toDate.month, _toDate.day));
      });
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Stundenzettel')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _reloadSchool,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              if (_loading || _savingConfig || _exporting)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: LinearProgressIndicator(minHeight: 2),
                ),

              // 1) Ein-/Ausschalter & Pflicht-Qualifikationen
              SoftCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Stundenzettel-Funktion aktiv',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      subtitle: Text(
                        fs.timesheetEnabled
                            ? 'Lehrpersonal erfasst ab Event-Beginn tägliche Arbeitszeiten inkl. Unterschrift.'
                            : 'Für ${fs.displayName} deaktiviert.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      value: fs.timesheetEnabled,
                      onChanged: _savingConfig
                          ? null
                          : (v) => _saveConfig(
                                fs: fs,
                                enabled: v,
                                qualIds: fs.timesheetQualificationIds,
                              ),
                    ),
                    if (fs.timesheetEnabled && fs.qualifications.isNotEmpty) ...[
                      Divider(height: 20, color: cs.outlineVariant),
                      Text(
                        'PFLICHT-QUALIFIKATIONEN',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.7,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Mitarbeiter mit mindestens einer markierten Qualifikation müssen für Events Stundenzettel abgeben (Standard: Fluglehrer, Sicherheitstrainer, Anwärter).',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: fs.qualifications.map((q) {
                          final selected = effectiveQualIds.contains(q.id);
                          return FilterChip(
                            label: Text(q.name),
                            selected: selected,
                            onSelected: _savingConfig
                                ? null
                                : (val) {
                                    final next =
                                        Set<String>.from(effectiveQualIds);
                                    if (val) {
                                      next.add(q.id);
                                    } else {
                                      next.remove(q.id);
                                    }
                                    _saveConfig(
                                      fs: fs,
                                      enabled: fs.timesheetEnabled,
                                      qualIds: next.toList(),
                                    );
                                  },
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),

              if (fs.timesheetEnabled) ...[
                const SizedBox(height: 16),

                // 2) Team-Auswertung & Export
                SoftCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Team-Auswertung & Export',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _pickDate(isFrom: true),
                              icon: const Icon(Icons.calendar_today, size: 15),
                              label: Text('Von: ${_fmtDate(_fromDate)}'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _pickDate(isFrom: false),
                              icon: const Icon(Icons.event, size: 15),
                              label: Text('Bis: ${_fmtDate(_toDate)}'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String?>(
                        initialValue: _selectedMemberId,
                        decoration: const InputDecoration(
                          labelText: 'Mitarbeiter',
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Alle Mitarbeiter'),
                          ),
                          ...fs.members.map(
                            (m) => DropdownMenuItem<String?>(
                              value: m.id,
                              child: Text(m.displayName),
                            ),
                          ),
                        ],
                        onChanged: (v) => setState(() => _selectedMemberId = v),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: KpiMetricCard(
                              label: 'Erfasste Stunden',
                              value: formatMinutesAsHours(totalMinutes),
                              icon: Icons.access_time_rounded,
                              iconColor: AppTheme.primaryColor,
                              iconBg: AppTheme.primaryTint,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: KpiMetricCard(
                              label: 'Einsatztage',
                              value: '$totalDays',
                              icon: Icons.event_available_outlined,
                              iconColor: AppTheme.successColor,
                              iconBg: AppTheme.successBg,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _exporting
                                  ? null
                                  : () => _export(
                                        isPdf: true,
                                        fs: fs,
                                        filteredSheets: filteredSheets,
                                      ),
                              icon: const Icon(Icons.picture_as_pdf_outlined,
                                  size: 18),
                              label: const Text('PDF-Export'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _exporting
                                  ? null
                                  : () => _export(
                                        isPdf: false,
                                        fs: fs,
                                        filteredSheets: filteredSheets,
                                      ),
                              icon: const Icon(Icons.table_chart_outlined,
                                  size: 18),
                              label: const Text('CSV (Excel)'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                  child: Text(
                    'EINGEREICHTE STUNDENZETTEL (${submittedSheets.length})',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.7,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                if (submittedSheets.isEmpty)
                  const EmptyStateView(
                    icon: Icons.access_time_outlined,
                    title: 'Keine eingereichten Stundenzettel',
                    subtitle:
                        'Im gewählten Zeitraum wurden noch keine Stundenzettel abgegeben.',
                  )
                else
                  for (final sheet in submittedSheets) ...[
                    _buildAdminSheetTile(context, fs, sheet),
                    const SizedBox(height: 8),
                  ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdminSheetTile(
    BuildContext context,
    FlightSchoolModelFlightSchoolView fs,
    EventTimesheet sheet,
  ) {
    final cs = Theme.of(context).colorScheme;
    final memberName = fs.resolveMemberName(sheet.userId);
    final avatarUrl = fs.findMemberByAnyId(sheet.userId)?.avatarUrl ?? '';

    return SoftCard(
      padding: const EdgeInsets.all(12),
      onTap: () {
        final dummyEvent = Event(
          id: sheet.assignmentId,
          eventDocId: sheet.eventId,
          flightSchoolId: sheet.flightSchoolId,
          identifier: '',
          status: EventStatusEnum.done,
          startTime: sheet.eventStart,
          endTime: sheet.eventEnd,
          displayName: sheet.eventName,
          location: '',
          team: const [],
          notes: '',
          role: sheet.roleName,
          assignmentStatus: EventUserStatusEnum.accepted_user,
        );
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TimesheetRunnerView(
              event: dummyEvent,
              userId: sheet.userId,
              initialTimesheet: sheet,
              readOnlyOverride: true,
            ),
          ),
        );
      },
      child: Row(
        children: [
          UserAvatar(
            avatarUrl: avatarUrl,
            name: memberName,
            radius: 19,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$memberName · ${sheet.eventName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_fmtDate(sheet.eventStart)} – ${_fmtDate(sheet.eventEnd)} · ${sheet.activeDays} ${sheet.activeDays == 1 ? "Tag" : "Tage"}',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          StatusPill(
            label: sheet.formattedTotalHours,
            foreground: AppTheme.successColor,
            background: AppTheme.successBg,
          ),
          IconButton(
            tooltip: 'Zur Korrektur entsperren',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.lock_open_outlined,
              size: 18,
              color: cs.onSurfaceVariant,
            ),
            onPressed: () => _reopenSheet(sheet),
          ),
        ],
      ),
    );
  }
}
