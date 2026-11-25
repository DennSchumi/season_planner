import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:season_planner/core/data/models/event_model.dart';
import 'package:season_planner/core/data/models/timesheet_model.dart';
import 'package:season_planner/core/services/timesheet_service.dart';
import 'package:season_planner/core/theme.dart';
import 'package:season_planner/core/widgets/ux_components.dart';
import 'package:signature/signature.dart';

/// Interaktiver Stundenzettel für ein Event-Teammitglied:
/// - Vorkonfigurierte Tage des Events (Ein-/Ausschalten pro Tag: Im Einsatz / Kein Einsatz)
/// - Arbeitsbeginn, Arbeitsende & Pausenzeit je Tag mit Live-Netto-Berechnung
/// - Zwischenspeichern als Entwurf ab Event-Beginn
/// - Verbindliches Absenden mit digitaler Unterschrift -> anschließend schreibgeschützt
class TimesheetRunnerView extends StatefulWidget {
  final Event event;
  final String userId;
  final EventTimesheet? initialTimesheet;
  final bool readOnlyOverride;

  const TimesheetRunnerView({
    super.key,
    required this.event,
    required this.userId,
    this.initialTimesheet,
    this.readOnlyOverride = false,
  });

  @override
  State<TimesheetRunnerView> createState() => _TimesheetRunnerViewState();
}

class _TimesheetRunnerViewState extends State<TimesheetRunnerView> {
  final _service = TimesheetService();

  EventTimesheet? _sheet;
  late List<TimesheetDayEntry> _entries;
  bool _saving = false;
  bool _submitting = false;
  Future<Uint8List?>? _signatureFuture;

  bool get _isSubmitted => _sheet?.isSubmitted == true;
  bool get _isReadOnly => _isSubmitted || widget.readOnlyOverride;

  int get _totalMinutes => _entries.fold<int>(0, (s, e) => s + e.netMinutes);
  int get _activeDays =>
      _entries.where((e) => e.active && e.netMinutes > 0).length;
  bool get _hasInvalidDay => _entries.any((e) => e.hasInvalidRange);

  @override
  void initState() {
    super.initState();
    _sheet = widget.initialTimesheet;
    if (_sheet != null && _sheet!.entries.isNotEmpty) {
      _entries = List<TimesheetDayEntry>.from(_sheet!.entries);
    } else {
      _entries = buildDefaultTimesheetEntriesForEvent(widget.event);
    }
    if (_sheet?.signatureFileId != null) {
      _signatureFuture = _service.loadSignatureBytes(_sheet!.signatureFileId);
    }
  }

  EventTimesheet _buildCurrentSheet() {
    final existing = _sheet;
    if (existing != null) {
      return existing.copyWith(
        entries: _entries,
        updatedAt: DateTime.now(),
      );
    }
    return EventTimesheet(
      id: '',
      flightSchoolId: widget.event.flightSchoolId,
      eventId: widget.event.eventDocId ?? widget.event.id,
      assignmentId: widget.event.id,
      userId: widget.userId,
      eventName: widget.event.displayName,
      roleName: widget.event.roleLabel,
      eventStart: widget.event.startTime,
      eventEnd: widget.event.endTime,
      entries: _entries,
      status: TimesheetStatus.draft,
      updatedAt: DateTime.now(),
    );
  }

  Future<void> _saveDraft({bool showFeedback = true}) async {
    if (_isReadOnly || _saving || _submitting) return;
    setState(() => _saving = true);
    try {
      final saved = await _service.saveDraft(_buildCurrentSheet());
      if (!mounted) return;
      if (saved != null) {
        setState(() {
          _sheet = saved;
          _entries = List<TimesheetDayEntry>.from(saved.entries);
        });
        if (showFeedback) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Entwurf gespeichert.')),
          );
        }
      } else if (showFeedback) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Zwischenspeichern fehlgeschlagen.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openSignatureAndSubmit() async {
    if (_isReadOnly || _submitting) return;
    if (_hasInvalidDay) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bitte prüfe die Zeiten: Das Arbeitsende muss nach dem Beginn liegen und länger als die Pause sein.',
          ),
        ),
      );
      return;
    }

    final controller = SignatureController(
      penStrokeWidth: 2.8,
      penColor: const Color(0xFF11131A),
      exportBackgroundColor: Colors.white,
    );

    final pngBytes = await showModalBottomSheet<Uint8List>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return StatefulBuilder(
          builder: (ctx, setLocal) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Stundenzettel unterschreiben',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Gesamt: ${formatMinutesAsHours(_totalMinutes)} ($_activeDays ${_activeDays == 1 ? "Einsatztag" : "Einsatztage"}) · Nach dem Absenden ist der Stundenzettel schreibgeschützt.',
                    style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    height: 190,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: cs.outlineVariant, width: 1.5),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Signature(
                      controller: controller,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          controller.clear();
                          setLocal(() {});
                        },
                        icon: const Icon(Icons.refresh, size: 17),
                        label: const Text('Leeren'),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Abbrechen'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () async {
                          if (controller.isEmpty) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Bitte zuerst im Feld unterschreiben.',
                                ),
                              ),
                            );
                            return;
                          }
                          final bytes = await controller.toPngBytes();
                          if (ctx.mounted && bytes != null) {
                            Navigator.pop(ctx, bytes);
                          }
                        },
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text('Absenden'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    controller.dispose();
    if (pngBytes == null || !mounted) return;

    setState(() => _submitting = true);
    try {
      final submitted = await _service.submitWithSignature(
        sheet: _buildCurrentSheet(),
        signaturePng: pngBytes,
      );
      if (!mounted) return;
      if (submitted != null) {
        setState(() {
          _sheet = submitted;
          _entries = List<TimesheetDayEntry>.from(submitted.entries);
          _signatureFuture = Future<Uint8List?>.value(pngBytes);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Stundenzettel erfolgreich unterschrieben & abgesendet.',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Stundenzettel konnte nicht abgesendet werden.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _pickTime(int idx, {required bool isStart}) async {
    if (_isReadOnly) return;
    final current = _entries[idx];
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? current.startTime : current.endTime,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _entries[idx] = isStart
          ? current.copyWith(startHour: picked.hour, startMinute: picked.minute)
          : current.copyWith(endHour: picked.hour, endMinute: picked.minute);
    });
  }

  Future<void> _pickCustomBreak(int idx) async {
    if (_isReadOnly) return;
    final current = _entries[idx];
    final ctrl = TextEditingController(text: '${current.breakMinutes}');
    final res = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pausenzeit (Minuten)'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Minuten',
            suffixText: 'Min.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () {
              final val = int.tryParse(ctrl.text.trim());
              if (val != null && val >= 0 && val <= 600) {
                Navigator.pop(ctx, val);
              }
            },
            child: const Text('Übernehmen'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (res != null && mounted) {
      setState(() => _entries[idx] = current.copyWith(breakMinutes: res));
    }
  }

  String _fmtDateTime(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stundenzettel'),
        actions: [
          if (!_isReadOnly)
            TextButton.icon(
              onPressed: _saving || _submitting ? null : () => _saveDraft(),
              icon: _saving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined, size: 18),
              label: const Text('Speichern'),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_saving || _submitting)
              const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  // Kopf- & Summenkarte
                  SoftCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            TintedIconBadge(
                              icon: _isSubmitted
                                  ? Icons.verified_outlined
                                  : Icons.access_time_rounded,
                              iconColor: _isSubmitted
                                  ? AppTheme.successColor
                                  : AppTheme.primaryColor,
                              backgroundColor: _isSubmitted
                                  ? AppTheme.successBg
                                  : AppTheme.primaryTint,
                              size: 40,
                              iconSize: 21,
                              radius: 12,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.event.displayName,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    widget.event.roleLabel,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            StatusPill(
                              label: _isSubmitted
                                  ? 'Abgesendet'
                                  : (_sheet != null ? 'Entwurf' : 'Offen'),
                              foreground: _isSubmitted
                                  ? AppTheme.successColor
                                  : AppTheme.primaryColor,
                              background: _isSubmitted
                                  ? AppTheme.successBg
                                  : AppTheme.primaryTint,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 11,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppTheme.darkCardElevated
                                : AppTheme.backgroundColor,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'GESAMTARBEITSZEIT',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.6,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      formatMinutesAsHours(_totalMinutes),
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.primaryColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '$_activeDays von ${_entries.length} Tagen',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                  Text(
                                    '${formatMinutesAsDecimal(_totalMinutes)} Std. dezimal',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                    child: Text(
                      'TAGE DES EVENTS (${_entries.length})',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.7,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),

                  // Tages-Karten
                  for (int i = 0; i < _entries.length; i++) ...[
                    _buildDayCard(context, i),
                    if (i != _entries.length - 1) const SizedBox(height: 10),
                  ],

                  // Unterschrifts-Protokoll nach Absenden
                  if (_isSubmitted) ...[
                    const SizedBox(height: 16),
                    SoftCard(
                      padding: const EdgeInsets.all(16),
                      border: Border.all(
                        color: AppTheme.successColor.withValues(alpha: 0.35),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.lock_outline_rounded,
                                size: 18,
                                color: AppTheme.successColor,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _sheet?.submittedAt != null
                                      ? 'Abgesendet am ${_fmtDateTime(_sheet!.submittedAt!)}'
                                      : 'Verbindlich abgesendet (schreibgeschützt)',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5,
                                    color: AppTheme.successColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_signatureFuture != null) ...[
                            const SizedBox(height: 10),
                            FutureBuilder<Uint8List?>(
                              future: _signatureFuture,
                              builder: (ctx, snap) {
                                final bytes = snap.data;
                                if (bytes == null) {
                                  return const SizedBox.shrink();
                                }
                                return Container(
                                  height: 110,
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: cs.outlineVariant,
                                    ),
                                  ),
                                  child: Image.memory(
                                    bytes,
                                    fit: BoxFit.contain,
                                  ),
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (!_isReadOnly)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  border: Border(
                    top: BorderSide(color: cs.outlineVariant),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed:
                            _saving || _submitting ? null : () => _saveDraft(),
                        icon: const Icon(Icons.save_outlined, size: 18),
                        label: const Text('Entwurf'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: _saving || _submitting || _hasInvalidDay
                            ? null
                            : _openSignatureAndSubmit,
                        icon: const Icon(Icons.draw_outlined, size: 18),
                        label: const Text('Unterschreiben & absenden'),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayCard(BuildContext context, int index) {
    final entry = _entries[index];
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final invalid = entry.hasInvalidRange;

    return SoftCard(
      padding: const EdgeInsets.all(14),
      border: invalid
          ? Border.all(color: AppTheme.dangerColor, width: 1.4)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${entry.weekdayShort}, ${entry.formattedDate}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                        color: entry.active ? cs.onSurface : cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.active
                          ? (invalid
                              ? 'Ungültiger Zeitraum'
                              : 'Netto: ${entry.formattedNetHours}')
                          : 'Kein Einsatz · 0:00 Std.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: invalid
                            ? AppTheme.dangerColor
                            : (entry.active
                                ? AppTheme.successColor
                                : cs.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
              if (!_isReadOnly) ...[
                Text(
                  entry.active ? 'Im Einsatz' : 'Kein Einsatz',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 4),
                Switch.adaptive(
                  value: entry.active,
                  onChanged: (v) {
                    setState(() => _entries[index] = entry.copyWith(active: v));
                  },
                ),
              ] else
                StatusPill(
                  label: entry.active ? entry.formattedNetHours : 'Kein Einsatz',
                  foreground:
                      entry.active ? AppTheme.successColor : cs.onSurfaceVariant,
                  background: entry.active
                      ? AppTheme.successBg
                      : (isDark
                          ? AppTheme.darkCardElevated
                          : AppTheme.backgroundColor),
                ),
            ],
          ),
          if (entry.active) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _TimeBox(
                    label: 'Beginn',
                    value: '${entry.startLabel} Uhr',
                    enabled: !_isReadOnly,
                    onTap: () => _pickTime(index, isStart: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _TimeBox(
                    label: 'Ende',
                    value: '${entry.endLabel} Uhr',
                    enabled: !_isReadOnly,
                    onTap: () => _pickTime(index, isStart: false),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _TimeBox(
                    label: 'Pause',
                    value: '${entry.breakMinutes} Min.',
                    enabled: !_isReadOnly,
                    onTap: () => _pickCustomBreak(index),
                  ),
                ),
              ],
            ),
            if (!_isReadOnly) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Pause:',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  for (final mins in const [0, 30, 45, 60])
                    ChoiceChip(
                      label: Text('$mins Min.', style: const TextStyle(fontSize: 11.5)),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      selected: entry.breakMinutes == mins,
                      onSelected: (_) {
                        setState(
                          () => _entries[index] =
                              entry.copyWith(breakMinutes: mins),
                        );
                      },
                    ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _TimeBox extends StatelessWidget {
  final String label;
  final String value;
  final bool enabled;
  final VoidCallback onTap;

  const _TimeBox({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark ? AppTheme.darkCardElevated : AppTheme.backgroundColor,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
