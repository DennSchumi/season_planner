import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:season_planner/core/data/models/event_model.dart';
import 'package:season_planner/core/data/models/role_document_model.dart';
import 'package:season_planner/core/services/role_document_service.dart';
import 'package:season_planner/core/theme.dart';
import 'package:season_planner/core/widgets/markdown_document_view.dart';
import 'package:signature/signature.dart';

/// Interaktive Checklisten-Ansicht für ein Event-Teammitglied:
/// - Abhaken aller Punkte mit automatischer Zwischenspeicherung
/// - Abschließen & Unterschreiben im aufploppenden Unterschriftsfenster
///   (auch wenn noch Punkte offen sind, mit optionaler Begründung)
/// - Nach der Unterschrift schreibgeschütztes Abnahme-Protokoll inkl. Unterschrift
class ChecklistRunnerView extends StatefulWidget {
  final Event event;
  final String userId;
  final RoleDocument checklist;
  final ChecklistCompletion? initialCompletion;

  const ChecklistRunnerView({
    super.key,
    required this.event,
    required this.userId,
    required this.checklist,
    this.initialCompletion,
  });

  @override
  State<ChecklistRunnerView> createState() => _ChecklistRunnerViewState();
}

class _ChecklistRunnerViewState extends State<ChecklistRunnerView> {
  final _service = RoleDocumentService();
  ChecklistCompletion? _completion;
  late List<ChecklistItem> _items;
  bool _savingProgress = false;
  bool _signing = false;
  Future<Uint8List?>? _signatureFuture;

  @override
  void initState() {
    super.initState();
    _completion = widget.initialCompletion;
    _items = _buildInitialItems();
    if (_completion?.signatureFileId != null) {
      _signatureFuture =
          _service.loadSignatureBytes(_completion!.signatureFileId);
    }
  }

  List<ChecklistItem> _buildInitialItems() {
    final comp = _completion;
    // Wenn bereits unterschrieben: exakten Snapshot unverändert anzeigen!
    if (comp != null && comp.isSigned) {
      return List<ChecklistItem>.from(comp.items);
    }

    // Aktuelle Vorlage parsen und ggf. gespeicherten Zwischenstand übernehmen
    final templateItems = widget.checklist.parseChecklistItems();
    if (comp == null || comp.items.isEmpty) {
      return templateItems;
    }

    final checkedByText = <String, bool>{
      for (final item in comp.items)
        '${item.section}||${item.text}': item.checked,
    };
    return templateItems.map((item) {
      final key = '${item.section}||${item.text}';
      return item.copyWith(checked: checkedByText[key] ?? item.checked);
    }).toList();
  }

  bool get _isSigned => _completion?.isSigned == true;
  int get _checkedCount => _items.where((i) => i.checked).length;
  int get _totalCount => _items.length;

  /// Abhaken ist frühestens 24 Stunden vor Event-Beginn erlaubt.
  DateTime get _editUnlockTime =>
      widget.event.startTime.subtract(const Duration(hours: 24));

  /// Unterschreiben ist erst ab Event-Beginn erlaubt.
  DateTime get _signUnlockTime => widget.event.startTime;

  bool get _canEdit => !_isSigned && !DateTime.now().isBefore(_editUnlockTime);
  bool get _canSign => !_isSigned && !DateTime.now().isBefore(_signUnlockTime);

  Future<void> _toggleItem(int index, bool value) async {
    if (!_canEdit || _signing) return;
    setState(() {
      _items[index] = _items[index].copyWith(checked: value);
      _savingProgress = true;
    });

    try {
      final saved = await _service.saveProgress(
        existing: _completion,
        flightSchoolId: widget.event.flightSchoolId,
        eventId: widget.event.eventDocId ?? widget.event.id,
        assignmentId: widget.event.id,
        userId: widget.userId,
        roleName: widget.event.roleLabel,
        checklist: widget.checklist,
        items: _items,
        notes: _completion?.notes ?? '',
      );
      if (!mounted) return;
      setState(() => _completion = saved);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Zwischenstand konnte nicht gespeichert werden: $e')),
      );
    } finally {
      if (mounted) setState(() => _savingProgress = false);
    }
  }

  Future<void> _openSignatureDialog() async {
    if (!_canSign || _signing) return;

    final result = await showDialog<({Uint8List pngBytes, String notes})>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _SignatureDialog(
        checklistTitle: widget.checklist.title,
        checkedCount: _checkedCount,
        totalCount: _totalCount,
        initialNotes: _completion?.notes ?? '',
      ),
    );

    if (result == null || !mounted) return;

    setState(() => _signing = true);
    try {
      final signed = await _service.signCompletion(
        existing: _completion,
        flightSchoolId: widget.event.flightSchoolId,
        eventId: widget.event.eventDocId ?? widget.event.id,
        eventName: widget.event.displayName,
        assignmentId: widget.event.id,
        userId: widget.userId,
        roleName: widget.event.roleLabel,
        checklist: widget.checklist,
        items: _items,
        signaturePngBytes: result.pngBytes,
        notes: result.notes,
      );
      if (!mounted) return;
      setState(() {
        _completion = signed;
        _items = List<ChecklistItem>.from(signed.items);
        _signatureFuture = Future.value(result.pngBytes);
      });
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Checkliste erfolgreich unterschrieben und abgeschlossen.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Unterschrift konnte nicht gespeichert werden: $e')),
      );
    } finally {
      if (mounted) setState(() => _signing = false);
    }
  }

  String _fmtDateTime(DateTime? d) {
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final progress = _totalCount == 0 ? 0.0 : _checkedCount / _totalCount;

    // Einträge nach Abschnitten gruppieren (in Originalreihenfolge)
    final sections = <({String title, List<int> indices})>[];
    for (int i = 0; i < _items.length; i++) {
      final sec = _items[i].section;
      if (sections.isEmpty || sections.last.title != sec) {
        sections.add((title: sec, indices: [i]));
      } else {
        sections.last.indices.add(i);
      }
    }

    return PopScope(
      canPop: !_signing,
      onPopInvokedWithResult: (didPop, _) {},
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.checklist.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (_savingProgress)
              const Padding(
                padding: EdgeInsets.only(right: 14),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
        bottomNavigationBar: _isSigned
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                  child: FilledButton.icon(
                    onPressed: (_signing || !_canSign)
                        ? null
                        : _openSignatureDialog,
                    icon: _signing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            _canSign
                                ? Icons.draw_outlined
                                : Icons.lock_clock_outlined,
                          ),
                    label: Text(
                      !_canSign
                          ? 'Unterschreiben ab ${_fmtDateTime(_signUnlockTime)} Uhr'
                          : (_checkedCount >= _totalCount && _totalCount > 0
                              ? 'Abschließen & unterschreiben'
                              : 'Abschließen & unterschreiben ($_checkedCount/$_totalCount)'),
                    ),
                  ),
                ),
              ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
                children: [
                  // Status- & Fortschrittskarte
                  Card(
                    elevation: 0,
                    color: _isSigned
                        ? (_completion!.isComplete
                            ? Colors.green.withValues(alpha: 0.10)
                            : Colors.orange.withValues(alpha: 0.12))
                        : cs.surfaceContainerHighest.withValues(alpha: 0.55),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: _isSigned
                            ? (_completion!.isComplete
                                ? Colors.green.withValues(alpha: 0.4)
                                : Colors.orange.withValues(alpha: 0.45))
                            : cs.outlineVariant,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _isSigned
                                    ? (_completion!.isComplete
                                        ? Icons.verified
                                        : Icons.warning_amber_rounded)
                                    : Icons.checklist,
                                color: _isSigned
                                    ? (_completion!.isComplete
                                        ? Colors.green
                                        : Colors.orange.shade800)
                                    : cs.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _isSigned
                                      ? (_completion!.isComplete
                                          ? 'Vollständig abgeschlossen & unterschrieben'
                                          : 'Mit offenen Punkten unterschrieben')
                                      : '${widget.event.displayName} · ${widget.event.roleLabel}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14.5,
                                  ),
                                ),
                              ),
                              Text(
                                '$_checkedCount / $_totalCount',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 7,
                              color: _isSigned
                                  ? (_completion!.isComplete
                                      ? Colors.green
                                      : Colors.orange)
                                  : cs.primary,
                            ),
                          ),
                          if (_isSigned) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Unterschrieben am ${_fmtDateTime(_completion?.signedAt)} · Vorlage v${_completion?.checklistVersion ?? widget.checklist.version}',
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (!_isSigned && (!_canEdit || !_canSign)) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: (!_canEdit
                                ? AppTheme.infoColor
                                : AppTheme.warningColor)
                            .withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: (!_canEdit
                                  ? AppTheme.infoColor
                                  : AppTheme.warningColor)
                              .withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            !_canEdit
                                ? Icons.visibility_outlined
                                : Icons.lock_clock_outlined,
                            size: 20,
                            color: !_canEdit
                                ? AppTheme.infoColor
                                : AppTheme.warningColor,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              !_canEdit
                                  ? 'Vorschau-Modus: Du kannst alle Punkte vorab einsehen. Die Bearbeitung (Abhaken) wird ab ${_fmtDateTime(_editUnlockTime)} Uhr (24 Std. vor Beginn) freigeschaltet, das Unterschreiben ab Event-Beginn (${_fmtDateTime(_signUnlockTime)} Uhr).'
                                  : 'Vorbereitungs-Modus: Du kannst Punkte bereits abhaken. Das verbindliche Unterschreiben wird ab Event-Beginn (${_fmtDateTime(_signUnlockTime)} Uhr) freigeschaltet.',
                              style: const TextStyle(fontSize: 12.5, height: 1.35),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),

                  if (_items.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'Diese Checkliste enthält noch keine abhakbaren Punkte (- [ ] Aufgabe).',
                          style: TextStyle(color: Colors.black54),
                        ),
                      ),
                    )
                  else
                    ...sections.map((sec) {
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: cs.outlineVariant),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (sec.title.isNotEmpty)
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(8, 2, 8, 6),
                                  child: Text(
                                    sec.title,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14.5,
                                      color: cs.primary,
                                    ),
                                  ),
                                ),
                              ...sec.indices.map((idx) {
                                final item = _items[idx];
                                return CheckboxListTile(
                                  dense: true,
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                  value: item.checked,
                                  onChanged: _canEdit
                                      ? (v) => _toggleItem(idx, v ?? false)
                                      : null,
                                  title: Text(
                                    item.text,
                                    style: TextStyle(
                                      decoration: item.checked
                                          ? TextDecoration.lineThrough
                                          : null,
                                      color: item.checked
                                          ? cs.onSurfaceVariant
                                          : cs.onSurface,
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      );
                    }),

                  if (_isSigned) ...[
                    const SizedBox(height: 6),
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: cs.outlineVariant),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Unterschrift & Bemerkung',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                            if ((_completion?.notes ?? '').isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Bemerkung: ${_completion!.notes}',
                                style: const TextStyle(fontSize: 13.5),
                              ),
                            ],
                            const SizedBox(height: 10),
                            if (_signatureFuture != null)
                              SignaturePreviewBox(
                                bytesFuture: _signatureFuture!,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SignatureDialog extends StatefulWidget {
  final String checklistTitle;
  final int checkedCount;
  final int totalCount;
  final String initialNotes;

  const _SignatureDialog({
    required this.checklistTitle,
    required this.checkedCount,
    required this.totalCount,
    this.initialNotes = '',
  });

  @override
  State<_SignatureDialog> createState() => _SignatureDialogState();
}

class _SignatureDialogState extends State<_SignatureDialog> {
  late final SignatureController _sigCtrl;
  late final TextEditingController _notesCtrl;
  String? _error;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _sigCtrl = SignatureController(
      penStrokeWidth: 2.8,
      penColor: Colors.black87,
      exportBackgroundColor: Colors.white,
    );
    _notesCtrl = TextEditingController(text: widget.initialNotes);
  }

  @override
  void dispose() {
    _sigCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final openCount = widget.totalCount - widget.checkedCount;
    final isComplete = openCount <= 0 && widget.totalCount > 0;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.draw_outlined),
          SizedBox(width: 8),
          Expanded(child: Text('Checkliste unterschreiben')),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (isComplete ? Colors.green : Colors.orange)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: (isComplete ? Colors.green : Colors.orange)
                        .withValues(alpha: 0.45),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      isComplete
                          ? Icons.check_circle_outline
                          : Icons.warning_amber_rounded,
                      size: 20,
                      color: isComplete
                          ? Colors.green.shade700
                          : Colors.orange.shade800,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isComplete
                            ? 'Alle ${widget.totalCount} Punkte der Checkliste „${widget.checklistTitle}“ sind abgehakt. Mit deiner Unterschrift bestätigst du die vollständige Erledigung.'
                            : 'Hinweis: Es sind noch $openCount von ${widget.totalCount} Punkten offen. Du kannst die Checkliste trotzdem abschließen – gib bei Bedarf unten kurz den Grund an.',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notesCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: isComplete
                      ? 'Bemerkung (optional)'
                      : 'Begründung / Bemerkung zu offenen Punkten (optional)',
                  hintText: isComplete
                      ? 'z. B. Alles vollständig & einsatzbereit'
                      : 'z. B. Wetterbedingt ausgefallen / Akku defekt',
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Unterschrift (mit Finger oder Maus zeichnen):',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _exporting
                        ? null
                        : () {
                            _sigCtrl.clear();
                            setState(() => _error = null);
                          },
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Löschen'),
                  ),
                ],
              ),
              Container(
                height: 170,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _error != null ? cs.error : cs.outlineVariant,
                    width: _error != null ? 1.5 : 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: Signature(
                    controller: _sigCtrl,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(
                    color: cs.error,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _exporting ? null : () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton.icon(
          onPressed: _exporting
              ? null
              : () async {
                  if (_sigCtrl.isEmpty) {
                    setState(() => _error = 'Bitte zuerst im Feld unterschreiben.');
                    return;
                  }
                  setState(() {
                    _exporting = true;
                    _error = null;
                  });
                  final png = await _sigCtrl.toPngBytes();
                  if (!context.mounted) return;
                  if (png == null || png.isEmpty) {
                    setState(() {
                      _exporting = false;
                      _error = 'Unterschrift konnte nicht erfasst werden.';
                    });
                    return;
                  }
                  Navigator.pop(
                    context,
                    (pngBytes: png, notes: _notesCtrl.text.trim()),
                  );
                },
          icon: const Icon(Icons.check),
          label: const Text('Verbindlich abschließen'),
        ),
      ],
    );
  }
}

/// Admin-Dialog zur Einsicht eines Checklisten-Protokolls inkl. abgehakter/offener
/// Punkte, Bemerkung und gespeicherter Unterschrift.
Future<void> showChecklistProtocolDialog({
  required BuildContext context,
  required ChecklistCompletion completion,
  required String memberName,
}) async {
  final sigFuture = completion.signatureFileId != null
      ? RoleDocumentService().loadSignatureBytes(completion.signatureFileId)
      : null;

  String fmt(DateTime? d) {
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          Icon(
            completion.isSigned
                ? (completion.isComplete
                    ? Icons.verified
                    : Icons.warning_amber_rounded)
                : Icons.checklist,
            color: completion.isSigned
                ? (completion.isComplete ? Colors.green : Colors.orange)
                : Theme.of(ctx).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              completion.checklistTitle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$memberName · ${completion.roleName}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                completion.isSigned
                    ? '${completion.isComplete ? "Vollständig" : "Mit offenen Punkten"} unterschrieben am ${fmt(completion.signedAt)} (${completion.checkedCount}/${completion.totalCount} erledigt · v${completion.checklistVersion})'
                    : 'In Bearbeitung (${completion.checkedCount}/${completion.totalCount} erledigt · Stand: ${fmt(completion.updatedAt)})',
                style: const TextStyle(fontSize: 12.5, color: Colors.black54),
              ),
              const Divider(height: 20),
              ...completion.items.map((item) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        item.checked
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        size: 18,
                        color: item.checked ? Colors.green : Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.section.isNotEmpty
                              ? '${item.section}: ${item.text}'
                              : item.text,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              if (completion.notes.isNotEmpty) ...[
                const Divider(height: 20),
                Text(
                  'Bemerkung:\n${completion.notes}',
                  style: const TextStyle(fontSize: 13),
                ),
              ],
              if (sigFuture != null) ...[
                const Divider(height: 20),
                const Text(
                  'Unterschrift:',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 8),
                SignaturePreviewBox(bytesFuture: sigFuture),
              ],
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Schließen'),
        ),
      ],
    ),
  );
}
