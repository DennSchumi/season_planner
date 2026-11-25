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
import 'package:season_planner/core/widgets/ux_components.dart';
import 'package:season_planner/user/data/models/flight_school_model_user_view.dart';
import 'package:season_planner/user/services/user_badge_state_service.dart';
import 'package:season_planner/user/user_provider.dart';

class MyTimesheetsView extends StatefulWidget {
  const MyTimesheetsView({super.key});

  @override
  State<MyTimesheetsView> createState() => _MyTimesheetsViewState();
}

class _MyTimesheetsViewState extends State<MyTimesheetsView> {
  final _service = TimesheetService();
  bool _loading = true;
  bool _exporting = false;
  List<EventTimesheet> _sheets = [];

  late DateTime _fromDate;
  late DateTime _toDate;
  String? _selectedSchoolId; // null = alle Flugschulen

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _fromDate = DateTime(now.year, 1, 1);
    _toDate = DateTime(now.year, 12, 31);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final user = context.read<UserProvider>().user;
    if (user == null || user.id.isEmpty) return;
    setState(() => _loading = true);
    final list = await _service.listTimesheetsForUser(user.id);
    if (!mounted) return;
    setState(() {
      _sheets = list;
      _loading = false;
    });
    UserBadgeStateService().refreshFromUser(user);
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  String _fmtFileDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _applyPreset(String preset) {
    final now = DateTime.now();
    setState(() {
      if (preset == 'this_year') {
        _fromDate = DateTime(now.year, 1, 1);
        _toDate = DateTime(now.year, 12, 31);
      } else if (preset == 'last_year') {
        _fromDate = DateTime(now.year - 1, 1, 1);
        _toDate = DateTime(now.year - 1, 12, 31);
      } else if (preset == 'last_12m') {
        _fromDate = DateTime(now.year - 1, now.month, now.day);
        _toDate = DateTime(now.year, now.month, now.day);
      }
    });
  }

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
    required List<EventTimesheet> filteredSheets,
    required Map<String, FlightSchoolUserView> fsById,
    required String userName,
  }) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final rows = TimesheetExportService.flattenRows(
        sheets: filteredSheets,
        from: _fromDate,
        to: _toDate,
        resolveSchoolName: (sid) => fsById[sid]?.displayName ?? 'Flugschule',
        resolveMemberName: (_) => userName,
        onlySubmitted: true,
      );
      if (rows.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Keine abgesendeten Stundenzettel im gewählten Zeitraum für den Export.',
              ),
            ),
          );
        }
        return;
      }

      final rangeTag = '${_fmtFileDate(_fromDate)}_bis_${_fmtFileDate(_toDate)}';
      Uint8List bytes;
      String filename;
      String mimeType;

      if (isPdf) {
        // Neueste vorhandene Unterschrift des Nutzers für das PDF laden
        Uint8List? sigBytes;
        for (final s in filteredSheets) {
          if (s.isSubmitted && s.signatureFileId != null) {
            sigBytes = await _service.loadSignatureBytes(s.signatureFileId);
            if (sigBytes != null) break;
          }
        }
        bytes = await TimesheetExportService.buildPdfBytes(
          rows: rows,
          title: 'Nachweis über Lehrtätigkeit',
          subtitle: userName,
          from: _fromDate,
          to: _toDate,
          includeMemberColumn: false,
          latestSignatureBytes: sigBytes,
          signerName: userName,
        );
        filename = 'Lehrtaetigkeit_$rangeTag.pdf';
        mimeType = 'application/pdf';
      } else {
        bytes = TimesheetExportService.buildCsvBytes(
          rows: rows,
          includeMemberColumn: false,
        );
        filename = 'Lehrtaetigkeit_$rangeTag.csv';
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
    final user = context.watch<UserProvider>().user;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final cs = Theme.of(context).colorScheme;
    final fsById = {for (final fs in user.flightSchools) fs.id: fs};
    final now = DateTime.now();

    final sheetByAssignmentId = {for (final s in _sheets) s.assignmentId: s};

    // Offene (noch nicht abgesendete) pflichtige Events ermitteln
    final openEvents = user.events.where((ev) {
      if (!ev.isOwnBindingAssignment || ev.status == EventStatusEnum.canceled) {
        return false;
      }
      if (ev.startTime.isAfter(now)) return false;
      if (_selectedSchoolId != null && ev.flightSchoolId != _selectedSchoolId) {
        return false;
      }
      final fs = fsById[ev.flightSchoolId];
      if (fs == null || !fs.userRequiresTimesheet) return false;
      final existing = sheetByAssignmentId[ev.id];
      return existing == null || !existing.isSubmitted;
    }).toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));

    // Abgesendete Stundenzettel im gewählten Filter
    final filteredSheets = _sheets.where((s) {
      if (_selectedSchoolId != null && s.flightSchoolId != _selectedSchoolId) {
        return false;
      }
      return true;
    }).toList();

    final userName = user.name.trim().isNotEmpty ? user.name.trim() : user.mail;
    final rowsInRange = TimesheetExportService.flattenRows(
      sheets: filteredSheets,
      from: _fromDate,
      to: _toDate,
      resolveSchoolName: (sid) => fsById[sid]?.displayName ?? 'Flugschule',
      resolveMemberName: (_) => userName,
      onlySubmitted: true,
    );

    final totalMinutes =
        rowsInRange.fold<int>(0, (sum, r) => sum + r.netMinutes);
    final uniqueDays = rowsInRange.map((r) => r.dateLabel).toSet().length;

    final submittedInRange = filteredSheets.where((s) {
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
      appBar: AppBar(title: const Text('Meine Stundenzettel')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              if (_loading || _exporting)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: LinearProgressIndicator(minHeight: 2),
                ),

              // Zeitraum- & Schul-Filter + Export
              SoftCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Auswertung & Nachweis-Export',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ActionChip(
                          label: Text('Jahr ${now.year}'),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _applyPreset('this_year'),
                        ),
                        ActionChip(
                          label: Text('Jahr ${now.year - 1}'),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _applyPreset('last_year'),
                        ),
                        ActionChip(
                          label: const Text('Letzte 12 Monate'),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _applyPreset('last_12m'),
                        ),
                      ],
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
                    if (user.flightSchools.length > 1) ...[
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String?>(
                        initialValue: _selectedSchoolId,
                        decoration: const InputDecoration(
                          labelText: 'Flugschule',
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Alle Flugschulen'),
                          ),
                          ...user.flightSchools.map(
                            (fs) => DropdownMenuItem<String?>(
                              value: fs.id,
                              child: Text(fs.displayName),
                            ),
                          ),
                        ],
                        onChanged: (v) => setState(() => _selectedSchoolId = v),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: KpiMetricCard(
                            label: 'Gesamtstunden',
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
                            value: '$uniqueDays',
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
                                      filteredSheets: filteredSheets,
                                      fsById: fsById,
                                      userName: userName,
                                    ),
                            icon: const Icon(Icons.picture_as_pdf_outlined,
                                size: 18),
                            label: const Text('PDF-Nachweis'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _exporting
                                ? null
                                : () => _export(
                                      isPdf: false,
                                      filteredSheets: filteredSheets,
                                      fsById: fsById,
                                      userName: userName,
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

              if (openEvents.isNotEmpty) ...[
                const SizedBox(height: 18),
                _buildPortraitSectionContainer(
                  context: context,
                  icon: Icons.access_time_filled_rounded,
                  iconColor: AppTheme.dangerColor,
                  title: 'Offene Stundenzettel',
                  subtitle: 'Bitte ausfüllen und digital unterschreiben',
                  count: openEvents.length,
                  tintColor: AppTheme.dangerColor,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final w = constraints.maxWidth;
                      final cols = w >= 820 ? 4 : (w >= 540 ? 3 : 2);
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: openEvents.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 0.70,
                        ),
                        itemBuilder: (context, idx) => _buildOpenEventCard(
                          context,
                          openEvents[idx],
                          sheetByAssignmentId[openEvents[idx].id],
                          fsById[openEvents[idx].flightSchoolId],
                          user.id,
                        ),
                      );
                    },
                  ),
                ),
              ],

              const SizedBox(height: 18),
              _buildPortraitSectionContainer(
                context: context,
                icon: Icons.verified_outlined,
                iconColor: AppTheme.successColor,
                title: 'Abgesendete Stundenzettel',
                subtitle: 'Nachweise im gewählten Zeitraum',
                count: submittedInRange.length,
                child: submittedInRange.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 28,
                          horizontal: 12,
                        ),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(
                                Icons.access_time_outlined,
                                size: 34,
                                color:
                                    cs.onSurfaceVariant.withValues(alpha: 0.6),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Im gewählten Zeitraum wurden noch keine Stundenzettel eingereicht.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final w = constraints.maxWidth;
                          final cols = w >= 820 ? 4 : (w >= 540 ? 3 : 2);
                          return GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: submittedInRange.length,
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: cols,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              childAspectRatio: 0.70,
                            ),
                            itemBuilder: (context, idx) => _buildSubmittedCard(
                              context,
                              submittedInRange[idx],
                              fsById[submittedInRange[idx].flightSchoolId],
                              user.id,
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPortraitSectionContainer({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required int count,
    Color? tintColor,
    required Widget child,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final containerBg = tintColor != null
        ? (isDark
            ? tintColor.withValues(alpha: 0.10)
            : tintColor.withValues(alpha: 0.06))
        : (isDark ? AppTheme.darkCardElevated : const Color(0xFFE7E7E2));
    final borderColor = tintColor != null
        ? tintColor.withValues(alpha: 0.28)
        : cs.outlineVariant.withValues(alpha: isDark ? 0.5 : 0.7);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: containerBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TintedIconBadge(
                icon: icon,
                iconColor: iconColor,
                backgroundColor: isDark ? cs.primaryContainer : Colors.white,
                size: 36,
                iconSize: 19,
                radius: 11,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15.5,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              StatusPill(
                label: '$count',
                foreground: iconColor,
                background: isDark ? cs.primaryContainer : Colors.white,
                fontSize: 11.5,
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _buildOpenEventCard(
    BuildContext context,
    Event ev,
    EventTimesheet? draft,
    FlightSchoolUserView? fs,
    String userId,
  ) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEnded = ev.endTime.isBefore(DateTime.now());
    final color = isEnded ? AppTheme.dangerColor : AppTheme.warningColor;
    final previewBg = isDark
        ? color.withValues(alpha: 0.18)
        : color.withValues(alpha: 0.12);
    final schoolLabel = fs == null
        ? ''
        : (fs.displayShortName.isNotEmpty
            ? fs.displayShortName
            : fs.displayName);
    final statusLabel = draft != null
        ? 'Entwurf'
        : (isEnded ? 'Fällig' : 'Laufend');

    return SoftCard(
      radius: 16,
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TimesheetRunnerView(
              event: ev,
              userId: userId,
              initialTimesheet: draft,
            ),
          ),
        );
        if (mounted) _load();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 74,
            color: previewBg,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: StatusPill(
                    label: statusLabel,
                    foreground: color,
                    background: Colors.white.withValues(
                      alpha: isDark ? 0.18 : 0.92,
                    ),
                    fontSize: 10,
                  ),
                ),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Icon(
                      Icons.access_time_filled_rounded,
                      size: 30,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ev.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      height: 1.2,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_fmtDate(ev.startTime)} - ${_fmtDate(ev.endTime)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      if (schoolLabel.isNotEmpty)
                        StatusPill(
                          label: schoolLabel,
                          foreground: AppTheme.primaryColor,
                          background: AppTheme.primaryTint,
                          fontSize: 10,
                        ),
                      if (ev.roleLabel.isNotEmpty)
                        StatusPill(
                          label: ev.roleLabel,
                          foreground: cs.onSurfaceVariant,
                          background: cs.surfaceContainerHighest,
                          fontSize: 10,
                        ),
                    ],
                  ),
                  const Spacer(),
                  const Divider(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.edit_note_rounded, size: 15, color: color),
                      const SizedBox(width: 4),
                      Text(
                        draft != null ? 'Weiter ausfüllen' : 'Ausfüllen',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmittedCard(
    BuildContext context,
    EventTimesheet sheet,
    FlightSchoolUserView? fs,
    String userId,
  ) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final schoolLabel = fs == null
        ? ''
        : (fs.displayShortName.isNotEmpty
            ? fs.displayShortName
            : fs.displayName);
    final previewBg = isDark
        ? AppTheme.successColor.withValues(alpha: 0.16)
        : AppTheme.successBg;

    return SoftCard(
      radius: 16,
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
              userId: userId,
              initialTimesheet: sheet,
              readOnlyOverride: true,
            ),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Oberer Kopf mit Gesamtstunden-Hervorhebung
          Container(
            height: 76,
            color: previewBg,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.verified_rounded,
                      size: 14,
                      color: AppTheme.successColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${sheet.activeDays} ${sheet.activeDays == 1 ? "Tag" : "Tage"}',
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.successColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  sheet.formattedTotalHours,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: AppTheme.successColor,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sheet.eventName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      height: 1.2,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.event_outlined,
                        size: 12.5,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '${_fmtDate(sheet.eventStart)} - ${_fmtDate(sheet.eventEnd)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      if (schoolLabel.isNotEmpty)
                        StatusPill(
                          label: schoolLabel,
                          foreground: AppTheme.primaryColor,
                          background: AppTheme.primaryTint,
                          fontSize: 10,
                        ),
                      if (sheet.roleName.trim().isNotEmpty)
                        StatusPill(
                          label: sheet.roleName.trim(),
                          foreground: cs.onSurfaceVariant,
                          background: cs.surfaceContainerHighest,
                          fontSize: 10,
                        ),
                    ],
                  ),
                  const Spacer(),
                  const Divider(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.visibility_outlined,
                        size: 14,
                        color: cs.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Ansehen',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: cs.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
