import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:season_planner/core/appwrite_config.dart';
import 'package:season_planner/core/data/models/qualification_model.dart';
import 'package:season_planner/core/services/qualification_service.dart';
import 'package:season_planner/core/theme.dart';
import 'package:season_planner/core/widgets/embedded_pdf_view.dart';
import 'package:season_planner/core/widgets/ux_components.dart';
import 'package:url_launcher/url_launcher.dart';

/// Öffnet ein Qualifikationsdokument direkt in einem In-App-Popup (Bilder mit
/// Zoom/Pan, PDFs im eingebetteten Viewer). Im Admin-Prüfmodus (`canReview: true`)
/// können dort direkt das Ablaufdatum („Gültig bis“) angepasst sowie der Nachweis
/// bestätigt oder abgelehnt werden.
///
/// Gibt `true` zurück, falls am Dokument oder an der Freigabe eine Änderung
/// vorgenommen wurde (so dass die aufrufende Liste aktualisieren kann).
Future<bool> showQualificationDocumentPopup({
  required BuildContext context,
  required QualificationDocument document,
  QualificationApproval? approval,
  String? ownerName,
  String? flightSchoolId,
  bool canReview = false,
}) async {
  final changed = await showDialog<bool>(
    context: context,
    builder: (ctx) => _QualificationDocumentDialog(
      initialDocument: document,
      initialApproval: approval,
      ownerName: ownerName,
      flightSchoolId: flightSchoolId,
      canReview: canReview,
    ),
  );
  return changed == true;
}

class _QualificationDocumentDialog extends StatefulWidget {
  final QualificationDocument initialDocument;
  final QualificationApproval? initialApproval;
  final String? ownerName;
  final String? flightSchoolId;
  final bool canReview;

  const _QualificationDocumentDialog({
    required this.initialDocument,
    this.initialApproval,
    this.ownerName,
    this.flightSchoolId,
    required this.canReview,
  });

  @override
  State<_QualificationDocumentDialog> createState() =>
      _QualificationDocumentDialogState();
}

class _QualificationDocumentDialogState
    extends State<_QualificationDocumentDialog> {
  final _service = QualificationService();
  late QualificationDocument _doc;
  QualificationApproval? _approval;

  bool _loadingBytes = true;
  Uint8List? _bytes;
  bool _busy = false;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _doc = widget.initialDocument;
    _approval = widget.initialApproval;
    _loadBytes();
  }

  Future<void> _loadBytes() async {
    final data = await _service.loadDocumentBytes(_doc.fileId);
    if (!mounted) return;
    setState(() {
      _bytes = data;
      _loadingBytes = false;
    });
  }

  bool get _isImage {
    final lower = _doc.fileName.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp');
  }

  bool get _isPdf => _doc.fileName.toLowerCase().endsWith('.pdf');

  String get _externalUrl {
    final cfg = AppwriteConfig();
    return cfg.fileViewUrl(cfg.qualificationDocumentsBucketId, _doc.fileId);
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  Future<void> _openExternal() async {
    if (_externalUrl.isEmpty) return;
    await launchUrl(
      Uri.parse(_externalUrl),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _editExpiry() async {
    final schoolId = widget.flightSchoolId ?? _approval?.flightSchoolId ?? '';
    if (schoolId.isEmpty) return;

    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _doc.expiresAt ?? now.add(const Duration(days: 365)),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Gültig bis anpassen (${_doc.documentType})',
    );
    if (picked == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final updated = await _service.updateDocumentExpiry(
        doc: _doc,
        expiresAt: picked,
        flightSchoolId: schoolId,
      );
      if (!mounted) return;
      if (updated != null) {
        setState(() {
          _doc = updated;
          _hasChanges = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gültig bis auf ${_fmtDate(picked)} aktualisiert.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decide(ApprovalStatusEnum decision) async {
    final approval = _approval;
    if (approval == null) return;

    String comment = '';
    if (decision == ApprovalStatusEnum.rejected) {
      final ctrl = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Nachweis ablehnen'),
          content: TextField(
            controller: ctrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Begründung (optional)',
              hintText: 'z. B. Dokument unleserlich oder abgelaufen',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.dangerColor,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ablehnen'),
            ),
          ],
        ),
      );
      comment = ctrl.text.trim();
      ctrl.dispose();
      if (ok != true || !mounted) return;
    }

    setState(() => _busy = true);
    try {
      await _service.reviewApproval(
        approval: approval,
        decision: decision,
        comment: comment,
      );
      if (!mounted) return;
      _hasChanges = true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            decision == ApprovalStatusEnum.approved
                ? 'Nachweis „${_doc.documentType}“ bestätigt.'
                : 'Nachweis „${_doc.documentType}“ abgelehnt.',
          ),
        ),
      );
      Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;
    final approval = _approval;
    final isExpired = _doc.isExpired;

    final (Color? statusFg, Color? statusBg, String? statusLabel) =
        approval != null
            ? switch (approval.status) {
                ApprovalStatusEnum.approved => (
                  isExpired ? AppTheme.dangerColor : AppTheme.successColor,
                  isExpired ? AppTheme.dangerBg : AppTheme.successBg,
                  isExpired ? 'Abgelaufen' : approval.status.label,
                ),
                ApprovalStatusEnum.rejected => (
                  AppTheme.dangerColor,
                  AppTheme.dangerBg,
                  approval.status.label,
                ),
                ApprovalStatusEnum.submitted => (
                  AppTheme.warningColor,
                  AppTheme.warningBg,
                  approval.status.label,
                ),
              }
            : (
                isExpired ? AppTheme.dangerColor : null,
                isExpired ? AppTheme.dangerBg : null,
                isExpired ? 'Abgelaufen' : null,
              );

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 920,
          maxHeight: size.height * 0.90,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Kopfzeile
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
              child: Row(
                children: [
                  TintedIconBadge(
                    icon: _isImage
                        ? Icons.image_outlined
                        : Icons.picture_as_pdf_outlined,
                    iconColor: AppTheme.primaryColor,
                    backgroundColor: AppTheme.primaryTint,
                    size: 40,
                    iconSize: 21,
                    radius: 12,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                widget.ownerName != null &&
                                        widget.ownerName!.trim().isNotEmpty
                                    ? '${widget.ownerName} · ${_doc.documentType}'
                                    : _doc.documentType,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15.5,
                                ),
                              ),
                            ),
                            if (statusLabel != null &&
                                statusFg != null &&
                                statusBg != null) ...[
                              const SizedBox(width: 8),
                              StatusPill(
                                label: statusLabel,
                                foreground: statusFg,
                                background: statusBg,
                                fontSize: 10.5,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_doc.fileName} · Ausgestellt: ${_fmtDate(_doc.issuedAt)} · Gültig bis: ${_fmtDate(_doc.expiresAt)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: isExpired
                                ? AppTheme.dangerColor
                                : cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'In neuem Tab öffnen',
                    onPressed: _openExternal,
                    icon: const Icon(Icons.open_in_new_rounded, size: 20),
                  ),
                  IconButton(
                    tooltip: 'Schließen',
                    onPressed: () => Navigator.pop(context, _hasChanges),
                    icon: const Icon(Icons.close_rounded, size: 22),
                  ),
                ],
              ),
            ),
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            const Divider(height: 1),

            // Dokument-Vorschau
            Expanded(
              child: Container(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                padding: const EdgeInsets.all(12),
                child: _loadingBytes
                    ? const Center(child: CircularProgressIndicator())
                    : _bytes == null
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.broken_image_outlined,
                                  size: 42,
                                  color: cs.onSurfaceVariant,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Vorschau konnte nicht geladen werden.',
                                  style: TextStyle(color: cs.onSurfaceVariant),
                                ),
                                const SizedBox(height: 12),
                                FilledButton.tonalIcon(
                                  onPressed: _openExternal,
                                  icon: const Icon(Icons.open_in_new, size: 18),
                                  label: const Text('Extern öffnen'),
                                ),
                              ],
                            ),
                          )
                        : _isImage
                            ? Stack(
                                children: [
                                  Positioned.fill(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: InteractiveViewer(
                                        minScale: 0.75,
                                        maxScale: 5.0,
                                        child: Center(
                                          child: Image.memory(
                                            _bytes!,
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    right: 8,
                                    bottom: 8,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black
                                            .withValues(alpha: 0.58),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.zoom_in_rounded,
                                            size: 14,
                                            color: Colors.white,
                                          ),
                                          SizedBox(width: 4),
                                          Text(
                                            'Zoomen & Verschieben',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : _isPdf
                                ? EmbeddedPdfView(
                                    bytes: _bytes!,
                                    fileName: _doc.fileName,
                                    onOpenExternal: _openExternal,
                                  )
                                : Center(
                                    child: FilledButton.tonalIcon(
                                      onPressed: _openExternal,
                                      icon: const Icon(
                                        Icons.open_in_new,
                                        size: 18,
                                      ),
                                      label: const Text('Datei extern öffnen'),
                                    ),
                                  ),
              ),
            ),

            // Aktionsleiste (für Admin-Prüfung: Gültig bis ändern + Bestätigen / Ablehnen)
            if (widget.canReview) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.event_available_outlined,
                          size: 17,
                          color: isExpired
                              ? AppTheme.dangerColor
                              : cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Gültig bis: ${_fmtDate(_doc.expiresAt)}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isExpired
                                ? AppTheme.dangerColor
                                : cs.onSurface,
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _editExpiry,
                          icon: const Icon(
                            Icons.edit_calendar_outlined,
                            size: 16,
                          ),
                          label: const Text('Ändern'),
                        ),
                      ],
                    ),
                    if (approval != null)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.dangerColor,
                            ),
                            onPressed: _busy ||
                                    approval.status ==
                                        ApprovalStatusEnum.rejected
                                ? null
                                : () => _decide(ApprovalStatusEnum.rejected),
                            icon: const Icon(Icons.close, size: 17),
                            label: const Text('Ablehnen'),
                          ),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.successColor,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: _busy ||
                                    approval.status ==
                                        ApprovalStatusEnum.approved
                                ? null
                                : () => _decide(ApprovalStatusEnum.approved),
                            icon: const Icon(Icons.check, size: 17),
                            label: const Text('Bestätigen'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
