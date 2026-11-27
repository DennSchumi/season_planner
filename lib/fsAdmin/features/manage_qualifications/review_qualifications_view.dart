import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/core/data/models/qualification_model.dart';
import 'package:season_planner/core/services/qualification_service.dart';
import 'package:season_planner/core/widgets/document_preview_dialog.dart';
import 'package:season_planner/core/widgets/ux_components.dart';
import 'package:season_planner/fsAdmin/flight_school_provider.dart';
import 'package:season_planner/user/user_provider.dart';

class ReviewQualificationsView extends StatefulWidget {
  const ReviewQualificationsView({super.key});

  @override
  State<ReviewQualificationsView> createState() =>
      _ReviewQualificationsViewState();
}

class _ReviewQualificationsViewState extends State<ReviewQualificationsView> {
  final _service = QualificationService();
  List<QualificationApproval> _approvals = [];
  final Map<String, QualificationDocument?> _docsById = {};
  bool _onlyOpen = true;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null) return;
    setState(() => _loading = true);

    final list = await _service.listSchoolApprovals(fs.id);
    for (final a in list) {
      if (!_docsById.containsKey(a.documentId)) {
        _docsById[a.documentId] = await _service.getDocumentById(a.documentId);
      }
    }

    if (!mounted) return;
    setState(() {
      _approvals = list;
      _loading = false;
    });
  }

  Future<void> _decide(
    QualificationApproval approval,
    ApprovalStatusEnum decision,
  ) async {
    String comment = '';
    if (decision == ApprovalStatusEnum.rejected) {
      final ctrl = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder:
            (ctx) => AlertDialog(
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
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Ablehnen'),
                ),
              ],
            ),
      );
      comment = ctrl.text.trim();
      ctrl.dispose();
      if (ok != true) return;
    }

    setState(() => _busy = true);
    await _service.reviewApproval(
      approval: approval,
      decision: decision,
      comment: comment,
    );
    await _load();
    if (mounted) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            decision == ApprovalStatusEnum.approved
                ? 'Nachweis bestätigt.'
                : 'Nachweis abgelehnt.',
          ),
        ),
      );
    }
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  Future<void> _editExpiry(
    QualificationDocument doc,
    String flightSchoolId,
  ) async {
    final now = DateTime.now();
    final initial = doc.expiresAt ?? now.add(const Duration(days: 365));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Gültig bis anpassen (${doc.documentType})',
    );
    if (picked == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final updated = await _service.updateDocumentExpiry(
        doc: doc,
        expiresAt: picked,
        flightSchoolId: flightSchoolId,
      );
      if (!mounted) return;
      if (updated != null) {
        setState(() => _docsById[doc.id] = updated);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Gültig bis für „${doc.documentType}“ auf ${_fmtDate(picked)} aktualisiert.',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ablaufdatum konnte nicht gespeichert werden.'),
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
    final currentUser = context.watch<UserProvider>().user;
    if (fs == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final filtered =
        _onlyOpen
            ? _approvals
                .where((a) => a.status == ApprovalStatusEnum.submitted)
                .toList()
            : _approvals;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Qualifikationsprüfung'),
        actions: [
          FilterChip(
            label: Text(_onlyOpen ? 'Nur offen' : 'Alle'),
            selected: _onlyOpen,
            onSelected: (v) => setState(() => _onlyOpen = v),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child:
                  _loading
                      ? const Center(child: CircularProgressIndicator())
                      : filtered.isEmpty
                      ? EmptyStateView(
                        icon: Icons.verified_user_outlined,
                        title:
                            _onlyOpen
                                ? 'Keine offenen Nachweise zur Prüfung'
                                : 'Noch keine Nachweise eingereicht',
                        subtitle:
                            _onlyOpen
                                ? 'Alle eingereichten Qualifikationsnachweise deiner Teammitglieder wurden bereits geprüft.'
                                : 'Sobald Mitglieder Dokumente für ihre Qualifikationen hochladen, erscheinen sie hier zur Freigabe.',
                        actionLabel:
                            _onlyOpen && _approvals.isNotEmpty
                                ? 'Alle Nachweise anzeigen'
                                : null,
                        actionIcon: Icons.filter_list_off,
                        onAction:
                            _onlyOpen && _approvals.isNotEmpty
                                ? () => setState(() => _onlyOpen = false)
                                : null,
                      )
                      : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: filtered.length,
                          separatorBuilder:
                              (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final a = filtered[index];
                            final doc = _docsById[a.documentId];
                            final fallback =
                                currentUser != null &&
                                        a.userId == currentUser.id
                                    ? (currentUser.name.isNotEmpty
                                        ? currentUser.name
                                        : currentUser.mail)
                                    : null;
                            final userName = fs.resolveMemberName(
                              a.userId,
                              fallbackName: fallback,
                            );

                            Future<void> openReviewPopup() async {
                              if (doc == null) return;
                              final changed =
                                  await showQualificationDocumentPopup(
                                    context: context,
                                    document: doc,
                                    approval: a,
                                    ownerName: userName,
                                    flightSchoolId: fs.id,
                                    canReview: true,
                                  );
                              if (changed && mounted) {
                                await _load();
                              }
                            }

                            final isEarlyRenewal =
                                a.status == ApprovalStatusEnum.submitted &&
                                _approvals.any((other) {
                                  if (other.id == a.id) return false;
                                  if (other.userId != a.userId) return false;
                                  if (other.documentType.toLowerCase() !=
                                      a.documentType.toLowerCase()) {
                                    return false;
                                  }
                                  if (other.status !=
                                      ApprovalStatusEnum.approved) {
                                    return false;
                                  }
                                  final otherDoc = _docsById[other.documentId];
                                  return otherDoc != null &&
                                      !otherDoc.isExpired;
                                });

                            return Card(
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: doc == null ? null : openReviewPopup,
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '$userName · ${a.documentType}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 15,
                                              ),
                                            ),
                                          ),
                                          if (isEarlyRenewal) ...[
                                            const StatusPill(
                                              label: 'Folgedokument',
                                              foreground: Color(0xFF1570EF),
                                              background: Color(0xFFEFF6FF),
                                              fontSize: 11,
                                            ),
                                            const SizedBox(width: 6),
                                          ],
                                          Chip(
                                            label: Text(
                                              a.status.label,
                                              style: const TextStyle(
                                                fontSize: 12,
                                              ),
                                            ),
                                            backgroundColor: switch (a.status) {
                                              ApprovalStatusEnum.approved =>
                                                Colors.green.withValues(
                                                  alpha: 0.15,
                                                ),
                                              ApprovalStatusEnum.rejected =>
                                                Colors.red.withValues(
                                                  alpha: 0.15,
                                                ),
                                              ApprovalStatusEnum.submitted =>
                                                Colors.orange.withValues(
                                                  alpha: 0.15,
                                                ),
                                            },
                                          ),
                                        ],
                                      ),
                                      if (doc != null) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          'Datei: ${doc.fileName}  ·  Gültig bis: ${_fmtDate(doc.expiresAt)}'
                                          '${doc.isExpired ? " (ABGELAUFEN!)" : ""}',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            color:
                                                doc.isExpired
                                                    ? Colors.red
                                                    : Colors.black54,
                                          ),
                                        ),
                                      ],
                                      if ((a.comment ?? '').isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          'Kommentar: ${a.comment}',
                                          style: const TextStyle(
                                            fontSize: 12.5,
                                            color: Colors.black54,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 10),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          if (doc != null)
                                            OutlinedButton.icon(
                                              onPressed: openReviewPopup,
                                              icon: const Icon(
                                                Icons.visibility_outlined,
                                                size: 18,
                                              ),
                                              label: const Text(
                                                'Dokument prüfen',
                                              ),
                                            ),
                                          if (doc != null)
                                            OutlinedButton.icon(
                                              onPressed:
                                                  _busy
                                                      ? null
                                                      : () => _editExpiry(
                                                        doc,
                                                        fs.id,
                                                      ),
                                              icon: const Icon(
                                                Icons.edit_calendar_outlined,
                                                size: 18,
                                              ),
                                              label: const Text(
                                                'Gültig bis ändern',
                                              ),
                                            ),
                                          FilledButton.icon(
                                            onPressed:
                                                _busy ||
                                                        a.status ==
                                                            ApprovalStatusEnum
                                                                .approved
                                                    ? null
                                                    : () => _decide(
                                                      a,
                                                      ApprovalStatusEnum
                                                          .approved,
                                                    ),
                                            icon: const Icon(
                                              Icons.check,
                                              size: 18,
                                            ),
                                            label: const Text('Bestätigen'),
                                          ),
                                          OutlinedButton.icon(
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: Colors.red,
                                            ),
                                            onPressed:
                                                _busy ||
                                                        a.status ==
                                                            ApprovalStatusEnum
                                                                .rejected
                                                    ? null
                                                    : () => _decide(
                                                      a,
                                                      ApprovalStatusEnum
                                                          .rejected,
                                                    ),
                                            icon: const Icon(
                                              Icons.close,
                                              size: 18,
                                            ),
                                            label: const Text('Ablehnen'),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
            ),
          ],
        ),
      ),
    );
  }
}
