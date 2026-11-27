import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/core/data/enums/membership_status_enum.dart';
import 'package:season_planner/core/data/models/qualification_model.dart';
import 'package:season_planner/core/data/models/team_role_model.dart';
import 'package:season_planner/core/services/file_optimization_service.dart';
import 'package:season_planner/core/services/qualification_service.dart';
import 'package:season_planner/core/theme.dart';
import 'package:season_planner/core/widgets/document_preview_dialog.dart';
import 'package:season_planner/core/widgets/ux_components.dart';
import 'package:season_planner/user/data/models/flight_school_model_user_view.dart';
import 'package:season_planner/user/services/database_service.dart';
import 'package:season_planner/user/services/user_badge_state_service.dart';
import 'package:season_planner/user/user_provider.dart';

class _SchoolDocRequirement {
  final FlightSchoolUserView school;
  final List<String> qualifications;
  final QualificationDocument? approvedDoc;
  final QualificationDocument? submittedDoc;
  final QualificationDocument? renewalSubmittedDoc;
  final QualificationDocument? unsubmittedDoc;
  final bool hasExpired;
  final bool hasRejected;

  const _SchoolDocRequirement({
    required this.school,
    required this.qualifications,
    this.approvedDoc,
    this.submittedDoc,
    this.renewalSubmittedDoc,
    this.unsubmittedDoc,
    this.hasExpired = false,
    this.hasRejected = false,
  });

  bool get isApproved => approvedDoc != null;
  bool get isSubmitted => !isApproved && submittedDoc != null;
  bool get hasRenewalSubmitted => isApproved && renewalSubmittedDoc != null;
  bool get needsRenewal =>
      isApproved && (approvedDoc?.expiresSoon == true) && !hasRenewalSubmitted;
  bool get needsShare => !isApproved && !isSubmitted && unsubmittedDoc != null;
  bool get needsUpload => !isApproved && !isSubmitted && unsubmittedDoc == null;
}

class _GroupedRequiredDoc {
  final String docType;
  final List<_SchoolDocRequirement> schoolReqs;

  const _GroupedRequiredDoc({
    required this.docType,
    required this.schoolReqs,
  });

  List<_SchoolDocRequirement> get shareableReqs =>
      schoolReqs.where((r) => r.needsShare).toList();

  List<_SchoolDocRequirement> get uploadReqs =>
      schoolReqs.where((r) => r.needsUpload).toList();

  List<_SchoolDocRequirement> get submittedReqs =>
      schoolReqs.where((r) => r.isSubmitted).toList();

  List<_SchoolDocRequirement> get approvedReqs =>
      schoolReqs.where((r) => r.isApproved).toList();

  bool get allApproved =>
      schoolReqs.isNotEmpty && approvedReqs.length == schoolReqs.length;

  bool get anyExpiresSoon => approvedReqs.any((r) => r.needsRenewal);

  bool get hasRenewalSubmitted =>
      approvedReqs.any((r) => r.hasRenewalSubmitted);

  DateTime? get earliestExpiringDate {
    DateTime? earliest;
    for (final r in approvedReqs) {
      final exp = r.approvedDoc?.expiresAt;
      if (exp == null) continue;
      if (earliest == null || exp.isBefore(earliest)) {
        earliest = exp;
      }
    }
    return earliest;
  }

  bool get hasNeedsUpload => uploadReqs.isNotEmpty;
  bool get hasNeedsShare => !hasNeedsUpload && shareableReqs.isNotEmpty;
  bool get hasPendingReview =>
      !hasNeedsUpload && !hasNeedsShare && submittedReqs.isNotEmpty;

  int get sortPriority {
    if (hasNeedsUpload) return 0;
    if (hasNeedsShare) return 1;
    if (anyExpiresSoon) return 2;
    if (hasPendingReview) return 3;
    return 4;
  }
}

class MyQualificationsView extends StatefulWidget {
  const MyQualificationsView({super.key});

  @override
  State<MyQualificationsView> createState() => _MyQualificationsViewState();
}

class _MyQualificationsViewState extends State<MyQualificationsView> {
  final _service = QualificationService();
  List<QualificationDocument> _docs = [];
  List<QualificationApproval> _approvals = [];
  bool _loading = true;
  bool _busy = false;
  bool _showExpiredDocs = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = context.read<UserProvider>().user;
    if (user == null) return;
    setState(() => _loading = true);
    final docs = await _service.listUserDocuments(user.id);
    final approvals = await _service.listUserApprovals(user.id);
    if (!mounted) return;
    setState(() {
      _docs = docs;
      _approvals = approvals;
      _loading = false;
    });
    UserBadgeStateService().refreshFromUser(user);
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  String _schoolShortLabel(FlightSchoolUserView s) =>
      s.displayShortName.trim().isNotEmpty
          ? s.displayShortName.trim()
          : s.displayName;

  bool _isImageFile(String fileName) {
    final lower = fileName.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp');
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _openDocumentUrl(QualificationDocument doc) async {
    await showQualificationDocumentPopup(
      context: context,
      document: doc,
      canReview: false,
    );
  }

  Future<void> _openUploadDialog(
    List<FlightSchoolUserView> activeSchools, {
    String? preselectedType,
    Set<String>? preselectedSchoolIds,
  }) async {
    final user = context.read<UserProvider>().user;
    if (user == null) return;

    // Ausschließlich Dokumenttypen sammeln, die von den aktiven Flugschulen
    // des Mitarbeiters definiert wurden (eigene zugewiesene Qualifikationen zuerst).
    final schoolDefinedTypes = <String>[];
    final seenLower = <String>{};
    void addUnique(String raw) {
      final t = raw.trim();
      if (t.isEmpty) return;
      if (seenLower.add(t.toLowerCase())) {
        schoolDefinedTypes.add(t);
      }
    }

    for (final fs in activeSchools) {
      for (final q in fs.qualifications) {
        if (fs.hasQualification(q.id)) {
          for (final req in q.requiredDocuments) {
            addUnique(req);
          }
        }
      }
    }
    for (final fs in activeSchools) {
      for (final q in fs.qualifications) {
        for (final req in q.requiredDocuments) {
          addUnique(req);
        }
      }
    }
    if (preselectedType != null && preselectedType.trim().isNotEmpty) {
      addUnique(preselectedType.trim());
    }

    final Set<String> selectedTypes = {};
    if (preselectedType != null && preselectedType.trim().isNotEmpty) {
      final match = schoolDefinedTypes.firstWhere(
        (t) => t.toLowerCase() == preselectedType.trim().toLowerCase(),
        orElse: () => preselectedType.trim(),
      );
      selectedTypes.add(match);
    }

    final titleCtrl = TextEditingController();
    DateTime? issuedAt;
    DateTime? expiresAt;
    OptimizedFileResult? optimizedFile;
    bool optimizingFile = false;
    bool healthDataConsent = false;
    String? validationError;

    Future<void> openTypePickerPopup(
      BuildContext parentCtx,
      StateSetter setLocal,
    ) async {
      final draft = Set<String>.from(selectedTypes);
      final picked = await showDialog<Set<String>>(
        context: parentCtx,
        builder: (pCtx) {
          return StatefulBuilder(
            builder: (pCtx, setPopup) {
              final pcs = Theme.of(pCtx).colorScheme;
              return AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
                titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                contentPadding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Dokumenttyp(en) auswählen',
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Ein Dokument kann mehreren Nachweisen zugeordnet werden.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: pcs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                content: SizedBox(
                  width: 380,
                  child: schoolDefinedTypes.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'Deine Flugschule(n) haben aktuell keine Pflichtnachweise definiert.',
                            style: TextStyle(
                              fontSize: 13,
                              color: pcs.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 340),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: schoolDefinedTypes.length,
                            itemBuilder: (_, idx) {
                              final t = schoolDefinedTypes[idx];
                              final checked = draft.contains(t);
                              return CheckboxListTile(
                                value: checked,
                                dense: true,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                activeColor: AppTheme.primaryColor,
                                title: Text(
                                  t,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: checked
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                                onChanged: (v) {
                                  setPopup(() {
                                    if (v == true) {
                                      draft.add(t);
                                    } else {
                                      draft.remove(t);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                        ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(pCtx),
                    child: const Text('Abbrechen'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(pCtx, draft),
                    child: Text(
                      draft.isEmpty
                          ? 'Übernehmen'
                          : 'Übernehmen (${draft.length})',
                    ),
                  ),
                ],
              );
            },
          );
        },
      );

      if (picked != null) {
        setLocal(() {
          selectedTypes
            ..clear()
            ..addAll(picked);
          validationError = null;
        });
      }
    }

    bool isHealthRelatedType(String docType) {
      final lower = docType.toLowerCase();
      return lower.contains('tauglichkeit') ||
          lower.contains('medical') ||
          lower.contains('ärztlich') ||
          lower.contains('aerztlich') ||
          lower.contains('gesundheit') ||
          lower.contains('erste hilfe') ||
          lower.contains('erste-hilfe');
    }
    final Set<String> selectedSchools =
        (preselectedSchoolIds != null && preselectedSchoolIds.isNotEmpty)
            ? Set<String>.from(preselectedSchoolIds)
            : activeSchools.map((s) => s.id).toSet();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final cs = Theme.of(ctx).colorScheme;
            final isDark = Theme.of(ctx).brightness == Brightness.dark;
            final hasFile = optimizedFile != null;
            final fileMissing =
                validationError != null && !hasFile && !optimizingFile;
            final expiryMissing = validationError != null && expiresAt == null;

            Widget buildDateTile({
              required String label,
              required DateTime? value,
              required IconData icon,
              required VoidCallback onPick,
              VoidCallback? onClear,
              bool isRequired = false,
              bool hasError = false,
            }) {
              final hasVal = value != null;
              final bg = hasError
                  ? AppTheme.dangerBg
                  : hasVal
                      ? (isDark
                          ? cs.primaryContainer.withValues(alpha: 0.45)
                          : AppTheme.primaryTint.withValues(alpha: 0.7))
                      : cs.surfaceContainerHighest.withValues(alpha: 0.45);
              final borderCol = hasError
                  ? AppTheme.dangerColor
                  : hasVal
                      ? AppTheme.primaryColor.withValues(alpha: 0.45)
                      : cs.outlineVariant;

              return Material(
                color: bg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: borderCol,
                    width: hasError ? 1.4 : 1.0,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onPick,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          icon,
                          size: 17,
                          color: hasError
                              ? AppTheme.dangerColor
                              : hasVal
                                  ? AppTheme.primaryColor
                                  : cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                label,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: hasError
                                      ? AppTheme.dangerColor
                                      : cs.onSurfaceVariant,
                                ),
                              ),
                              Text(
                                hasVal
                                    ? _fmtDate(value)
                                    : (isRequired ? 'Pflichtfeld' : 'Optional'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: hasVal
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: hasError
                                      ? AppTheme.dangerColor
                                      : hasVal
                                          ? cs.onSurface
                                          : cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (hasVal && onClear != null)
                          InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: onClear,
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: Icon(
                                Icons.close_rounded,
                                size: 15,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              title: Row(
                children: [
                  const TintedIconBadge(
                    icon: Icons.upload_file_rounded,
                    iconColor: AppTheme.primaryColor,
                    backgroundColor: AppTheme.primaryTint,
                    size: 42,
                    iconSize: 22,
                    radius: 13,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Nachweis hochladen',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Einmal hochladen und direkt mit Flugschulen teilen',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 460,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 6),
                      // Interaktive Datei-Auswahl-Zone
                      Material(
                        color: fileMissing
                            ? AppTheme.dangerBg
                            : hasFile
                                ? (isDark
                                    ? AppTheme.successColor
                                        .withValues(alpha: 0.16)
                                    : AppTheme.successBg)
                                : (isDark
                                    ? cs.primaryContainer
                                        .withValues(alpha: 0.25)
                                    : AppTheme.primaryTint
                                        .withValues(alpha: 0.55)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            width: 1.4,
                            color: fileMissing
                                ? AppTheme.dangerColor
                                : hasFile
                                    ? AppTheme.successColor
                                        .withValues(alpha: 0.55)
                                    : AppTheme.primaryColor
                                        .withValues(alpha: 0.35),
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: optimizingFile
                              ? null
                              : () async {
                                  final result =
                                      await FilePicker.platform.pickFiles(
                                    type: FileType.custom,
                                    allowedExtensions: [
                                      'pdf',
                                      'jpg',
                                      'jpeg',
                                      'png',
                                      'webp',
                                    ],
                                    withData: true,
                                  );
                                  if (result == null || result.files.isEmpty) {
                                    return;
                                  }
                                  final rawFile = result.files.first;
                                  final rawBytes = rawFile.bytes;
                                  if (rawBytes == null || rawBytes.isEmpty) {
                                    setLocal(() {
                                      validationError =
                                          'Die ausgewählte Datei konnte nicht gelesen werden.';
                                    });
                                    return;
                                  }
                                  setLocal(() {
                                    optimizingFile = true;
                                    validationError = null;
                                  });
                                  try {
                                    final opt = await FileOptimizationService()
                                        .optimizeDocument(
                                      bytes: rawBytes,
                                      fileName: rawFile.name,
                                    );
                                    if (!ctx.mounted) return;
                                    setLocal(() {
                                      optimizedFile = opt;
                                      optimizingFile = false;
                                      validationError = null;
                                    });
                                  } catch (e) {
                                    if (!ctx.mounted) return;
                                    setLocal(() {
                                      optimizedFile = null;
                                      optimizingFile = false;
                                      validationError = e
                                          .toString()
                                          .replaceFirst('Exception: ', '');
                                    });
                                  }
                                },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 16,
                            ),
                            child: Row(
                              children: [
                                if (optimizingFile)
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: isDark ? 0.12 : 0.85,
                                      ),
                                      borderRadius: BorderRadius.circular(13),
                                    ),
                                    child: const Center(
                                      child: SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.2,
                                        ),
                                      ),
                                    ),
                                  )
                                else
                                  TintedIconBadge(
                                    icon: hasFile
                                        ? Icons.check_circle_rounded
                                        : Icons.cloud_upload_outlined,
                                    iconColor: fileMissing
                                        ? AppTheme.dangerColor
                                        : hasFile
                                            ? AppTheme.successColor
                                            : AppTheme.primaryColor,
                                    backgroundColor: Colors.white.withValues(
                                      alpha: isDark ? 0.12 : 0.85,
                                    ),
                                    size: 44,
                                    iconSize: 22,
                                    radius: 13,
                                  ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        optimizingFile
                                            ? 'Datei wird optimiert…'
                                            : hasFile
                                                ? optimizedFile!.fileName
                                                : 'Datei auswählen (PDF / Bild) *',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13.5,
                                          color: fileMissing
                                              ? AppTheme.dangerColor
                                              : hasFile
                                                  ? AppTheme.successColor
                                                  : cs.onSurface,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        optimizingFile
                                            ? 'Bild / PDF wird für schnellen Upload verkleinert'
                                            : hasFile
                                                ? (optimizedFile!.wasOptimized
                                                    ? '${_formatFileSize(optimizedFile!.finalBytes)} (von ${_formatFileSize(optimizedFile!.originalBytes)} optimiert) · Ändern'
                                                    : '${_formatFileSize(optimizedFile!.finalBytes)} · Tippen zum Ändern')
                                                : 'PDF, JPG, PNG oder WEBP (max. 4 MB nach Optimierung)',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  hasFile
                                      ? Icons.swap_horiz_rounded
                                      : Icons.add_circle_outline_rounded,
                                  size: 20,
                                  color: hasFile
                                      ? AppTheme.successColor
                                      : AppTheme.primaryColor,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      // Kompakte anklickbare Dokumenttyp-Pille -> öffnet Auswahl-Popup
                      Builder(
                        builder: (_) {
                          final typeMissing =
                              validationError != null && selectedTypes.isEmpty;
                          final orderedSelected = schoolDefinedTypes
                              .where((t) => selectedTypes.contains(t))
                              .toList();
                          final bg = typeMissing
                              ? AppTheme.dangerBg
                              : orderedSelected.isNotEmpty
                                  ? (isDark
                                      ? cs.primaryContainer
                                          .withValues(alpha: 0.45)
                                      : AppTheme.primaryTint
                                          .withValues(alpha: 0.65))
                                  : cs.surfaceContainerHighest
                                      .withValues(alpha: 0.45);
                          final borderCol = typeMissing
                              ? AppTheme.dangerColor
                              : orderedSelected.isNotEmpty
                                  ? AppTheme.primaryColor
                                      .withValues(alpha: 0.45)
                                  : cs.outlineVariant;

                          return Material(
                            color: bg,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(
                                color: borderCol,
                                width: typeMissing ? 1.4 : 1.0,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () => openTypePickerPopup(ctx, setLocal),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 11,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.category_outlined,
                                      size: 18,
                                      color: typeMissing
                                          ? AppTheme.dangerColor
                                          : orderedSelected.isNotEmpty
                                              ? AppTheme.primaryColor
                                              : cs.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Dokumenttyp *',
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w600,
                                              color: typeMissing
                                                  ? AppTheme.dangerColor
                                                  : cs.onSurfaceVariant,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          if (orderedSelected.isEmpty)
                                            Text(
                                              'Wähle Dokumententyp',
                                              style: TextStyle(
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w600,
                                                color: typeMissing
                                                    ? AppTheme.dangerColor
                                                    : cs.onSurfaceVariant,
                                              ),
                                            )
                                          else
                                            Wrap(
                                              spacing: 6,
                                              runSpacing: 5,
                                              children: orderedSelected
                                                  .map(
                                                    (t) => StatusPill(
                                                      label: t,
                                                      foreground:
                                                          AppTheme.primaryColor,
                                                      background: isDark
                                                          ? cs.surface
                                                          : Colors.white,
                                                      fontSize: 11.5,
                                                    ),
                                                  )
                                                  .toList(),
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Icon(
                                      Icons.tune_rounded,
                                      size: 18,
                                      color: orderedSelected.isNotEmpty
                                          ? AppTheme.primaryColor
                                          : cs.onSurfaceVariant,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: titleCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Bezeichnung (optional)',
                          hintText: 'z. B. Haftpflicht 2026',
                          prefixIcon: Icon(Icons.label_outline, size: 19),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: buildDateTile(
                              label: 'Ausgestellt am',
                              value: issuedAt,
                              icon: Icons.event_note_outlined,
                              onPick: () async {
                                final picked = await showDatePicker(
                                  context: ctx,
                                  initialDate: issuedAt ?? DateTime.now(),
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime(2100),
                                );
                                if (picked != null) {
                                  setLocal(() => issuedAt = picked);
                                }
                              },
                              onClear: () => setLocal(() => issuedAt = null),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: buildDateTile(
                              label: 'Gültig bis *',
                              value: expiresAt,
                              icon: Icons.event_available_outlined,
                              isRequired: true,
                              hasError: expiryMissing,
                              onPick: () async {
                                final now = DateTime.now();
                                final today =
                                    DateTime(now.year, now.month, now.day);
                                final picked = await showDatePicker(
                                  context: ctx,
                                  initialDate: expiresAt != null &&
                                          !expiresAt!.isBefore(today)
                                      ? expiresAt!
                                      : today.add(const Duration(days: 365)),
                                  firstDate: today,
                                  lastDate: DateTime(2100),
                                  helpText: 'Gültig bis (Pflichtfeld)',
                                );
                                if (picked != null) {
                                  setLocal(() {
                                    expiresAt = picked;
                                    validationError = null;
                                  });
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      if (validationError != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.dangerBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color:
                                  AppTheme.dangerColor.withValues(alpha: 0.45),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: AppTheme.dangerColor,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  validationError!,
                                  style: const TextStyle(
                                    color: AppTheme.dangerColor,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (activeSchools.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          'Direkt freigeben für Flugschule(n):',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: activeSchools.map((s) {
                            final isSelected = selectedSchools.contains(s.id);
                            return FilterChip(
                              label: Text(_schoolShortLabel(s)),
                              tooltip: s.displayName,
                              selected: isSelected,
                              selectedColor: AppTheme.primaryTint,
                              checkmarkColor: AppTheme.primaryColor,
                              labelStyle: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: isSelected
                                    ? AppTheme.primaryColor
                                    : cs.onSurface,
                              ),
                              side: BorderSide(
                                color: isSelected
                                    ? AppTheme.primaryColor
                                        .withValues(alpha: 0.45)
                                    : cs.outlineVariant,
                              ),
                              onSelected: (v) {
                                setLocal(() {
                                  if (v) {
                                    selectedSchools.add(s.id);
                                  } else {
                                    selectedSchools.remove(s.id);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Builder(
                        builder: (_) {
                          final needsHealthConsent =
                              selectedTypes.any(isHealthRelatedType);
                          if (needsHealthConsent) {
                            final consentMissing = validationError != null &&
                                !healthDataConsent;
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: consentMissing
                                    ? AppTheme.dangerBg
                                    : cs.surfaceContainerHighest
                                        .withValues(alpha: 0.45),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: consentMissing
                                      ? AppTheme.dangerColor
                                      : cs.outlineVariant,
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: Checkbox(
                                      value: healthDataConsent,
                                      visualDensity: VisualDensity.compact,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      onChanged: (v) {
                                        setLocal(() {
                                          healthDataConsent = v ?? false;
                                          if (healthDataConsent) {
                                            validationError = null;
                                          }
                                        });
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () {
                                        setLocal(() {
                                          healthDataConsent =
                                              !healthDataConsent;
                                          if (healthDataConsent) {
                                            validationError = null;
                                          }
                                        });
                                      },
                                      child: Text(
                                        'Ich willige ausdrücklich ein, dass dieser Gesundheits-/Tauglichkeitsnachweis gespeichert und nur für die von mir freigegebenen Flugschulen sichtbar ist (Art. 9 Abs. 2 lit. a DSGVO, jederzeit widerrufbar).',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          height: 1.35,
                                          color: consentMissing
                                              ? AppTheme.dangerColor
                                              : cs.onSurface,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.lock_outline_rounded,
                                size: 14,
                                color: cs.onSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Dein Nachweis ist nur für dich und von dir freigegebene Flugschulen sichtbar.',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
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
                FilledButton.icon(
                  onPressed: optimizingFile
                      ? null
                      : () {
                          if (selectedTypes.isEmpty) {
                            setLocal(
                              () => validationError =
                                  'Bitte wähle mindestens einen Dokumenttyp aus.',
                            );
                            return;
                          }
                          if (optimizedFile == null) {
                            setLocal(
                              () => validationError =
                                  'Bitte wähle zuerst eine Datei (PDF oder Bild) aus.',
                            );
                            return;
                          }
                          if (expiresAt == null) {
                            setLocal(
                              () => validationError =
                                  'Bitte gib das Ablaufdatum („Gültig bis“) an.',
                            );
                            return;
                          }
                          if (selectedTypes.any(isHealthRelatedType) &&
                              !healthDataConsent) {
                            setLocal(
                              () => validationError =
                                  'Bitte bestätige die Datenschutz-Einwilligung für Gesundheits-/Tauglichkeitsnachweise.',
                            );
                            return;
                          }
                          Navigator.pop(ctx, true);
                        },
                  icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                  label: Text(
                    selectedTypes.length > 1
                        ? 'Für ${selectedTypes.length} Nachweise hochladen'
                        : 'Hochladen',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    final finalTypes = selectedTypes.toList();
    final finalTitle = titleCtrl.text.trim();
    titleCtrl.dispose();

    if (ok != true || optimizedFile == null || finalTypes.isEmpty) return;

    setState(() => _busy = true);
    try {
      await _service.uploadDocumentForTypes(
        userId: user.id,
        documentTypes: finalTypes,
        title: finalTitle,
        fileBytes: optimizedFile!.bytes,
        fileName: optimizedFile!.fileName,
        issuedAt: issuedAt,
        expiresAt: expiresAt,
        submitToFlightSchoolIds: selectedSchools.toList(),
        alreadyOptimized: true,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              finalTypes.length > 1
                  ? 'Dokument für ${finalTypes.length} Nachweise hochgeladen und zur Prüfung eingereicht.'
                  : 'Dokument hochgeladen und zur Prüfung eingereicht.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Upload fehlgeschlagen: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareToMoreSchools(
    QualificationDocument doc,
    List<FlightSchoolUserView> activeSchools,
  ) async {
    final existingSchoolIds = _approvals
        .where((a) => a.documentId == doc.id)
        .map((a) => a.flightSchoolId)
        .toSet();
    final selected = activeSchools
        .where((s) => !existingSchoolIds.contains(s.id))
        .map((s) => s.id)
        .toSet();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final cs = Theme.of(ctx).colorScheme;
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: Row(
              children: [
                const TintedIconBadge(
                  icon: Icons.share_outlined,
                  iconColor: AppTheme.primaryColor,
                  backgroundColor: AppTheme.primaryTint,
                  size: 38,
                  iconSize: 19,
                  radius: 12,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '„${doc.customTitle.isNotEmpty ? doc.customTitle : doc.documentTypes.join(', ')}“ freigeben',
                    style: const TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Wähle die Flugschule(n), an die dieses Dokument übermittelt werden soll:',
                    style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: activeSchools.map((s) {
                      final already = existingSchoolIds.contains(s.id);
                      final isSelected = selected.contains(s.id);
                      return FilterChip(
                        label: Text(
                          already
                              ? '${_schoolShortLabel(s)} (bereits geteilt)'
                              : _schoolShortLabel(s),
                        ),
                        tooltip: s.displayName,
                        selected: isSelected,
                        selectedColor: AppTheme.primaryTint,
                        checkmarkColor: AppTheme.primaryColor,
                        onSelected: (v) {
                          setLocal(() {
                            if (v) {
                              selected.add(s.id);
                            } else {
                              selected.remove(s.id);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Abbrechen'),
              ),
              FilledButton.icon(
                onPressed:
                    selected.isEmpty ? null : () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.send_rounded, size: 17),
                label: const Text('Freigeben'),
              ),
            ],
          );
        },
      ),
    );

    if (ok != true || selected.isEmpty) return;
    setState(() => _busy = true);
    try {
      for (final sid in selected) {
        await _service.submitDocumentToSchool(
          document: doc,
          flightSchoolId: sid,
        );
      }
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dokument an Flugschule(n) übermittelt.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitExistingDocToSchools(
    List<_SchoolDocRequirement> shareReqs,
    String docType,
  ) async {
    if (shareReqs.isEmpty) return;
    setState(() => _busy = true);
    try {
      for (final req in shareReqs) {
        if (req.unsubmittedDoc == null) continue;
        await _service.submitDocumentToSchool(
          document: req.unsubmittedDoc!,
          flightSchoolId: req.school.id,
          documentTypeOverride: docType,
        );
      }
      await _load();
      if (mounted) {
        final names = shareReqs.map((r) => _schoolShortLabel(r.school)).join(', ');
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('„$docType“ für $names freigegeben.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteDoc(QualificationDocument doc) async {
    final displayTitle = doc.customTitle.isNotEmpty
        ? doc.customTitle
        : doc.documentTypes.join(', ');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dokument löschen?'),
        content: Text(
          'Soll „$displayTitle“ inkl. aller Flugschul-Freigaben entfernt werden?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.dangerColor),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    await _service.deleteDocument(doc);
    await _load();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _requestQualification(
    FlightSchoolUserView school,
    Qualification qual,
  ) async {
    if (school.membershipId.isEmpty) return;
    setState(() => _busy = true);
    try {
      final ok = await _service.requestQualification(
        membershipId: school.membershipId,
        flightSchoolId: school.id,
        currentRequestedIds: school.requestedQualificationIds,
        qualificationId: qual.id,
        qualificationName: qual.name,
      );
      if (ok) {
        final freshUser = await DatabaseService().getUserInformation();
        if (freshUser != null && mounted) {
          context.read<UserProvider>().setUser(freshUser);
        }
        if (mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: Text(
                'Qualifikation „${qual.name}“ bei ${school.displayName} angefragt.',
              ),
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _withdrawQualificationRequest(
    FlightSchoolUserView school,
    Qualification qual,
  ) async {
    if (school.membershipId.isEmpty) return;
    setState(() => _busy = true);
    try {
      final ok = await _service.withdrawQualificationRequest(
        membershipId: school.membershipId,
        currentRequestedIds: school.requestedQualificationIds,
        qualificationId: qual.id,
      );
      if (ok) {
        final freshUser = await DatabaseService().getUserInformation();
        if (freshUser != null && mounted) {
          context.read<UserProvider>().setUser(freshUser);
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<_GroupedRequiredDoc> _buildGroupedRequiredDocs(
    List<FlightSchoolUserView> activeSchools,
  ) {
    // Normalisierter Schlüssel -> (Anzeigename, Liste der Flugschul-Anforderungen)
    final displayByKey = <String, String>{};
    final reqsByKey = <String, List<_SchoolDocRequirement>>{};

    for (final s in activeSchools) {
      final qualsByDocKey = <String, List<String>>{};
      for (final qual in s.qualifications) {
        if (s.hasQualification(qual.id) && qual.requiredDocuments.isNotEmpty) {
          for (final reqDoc in qual.requiredDocuments) {
            final key = reqDoc.trim().toLowerCase();
            if (key.isEmpty) continue;
            displayByKey.putIfAbsent(key, () => reqDoc.trim());
            qualsByDocKey.putIfAbsent(key, () => []).add(qual.name);
          }
        }
      }

      for (final entry in qualsByDocKey.entries) {
        final key = entry.key;
        final qualNames = entry.value;
        final matchingDocs = _docs
            .where((d) => d.matchesType(key))
            .toList();

        bool isLaterExpiry(
          QualificationDocument candidate,
          QualificationDocument? current,
        ) {
          if (current == null) return true;
          if (candidate.expiresAt == null) return true;
          if (current.expiresAt == null) return false;
          return candidate.expiresAt!.isAfter(current.expiresAt!);
        }

        QualificationDocument? validApprovedDoc;
        QualificationDocument? validSubmittedDoc;
        QualificationDocument? validUnsubmittedDoc;
        bool hasExpired = false;
        bool hasRejected = false;

        for (final d in matchingDocs) {
          final schoolApprovals = _approvals
              .where(
                (a) =>
                    a.documentId == d.id &&
                    a.flightSchoolId == s.id &&
                    a.documentType.trim().toLowerCase() == key,
              )
              .toList();

          if (d.isExpired) {
            hasExpired = true;
            continue;
          }

          if (schoolApprovals.any(
            (a) => a.status == ApprovalStatusEnum.approved,
          )) {
            if (isLaterExpiry(d, validApprovedDoc)) {
              validApprovedDoc = d;
            }
          } else if (schoolApprovals.any(
            (a) => a.status == ApprovalStatusEnum.submitted,
          )) {
            if (isLaterExpiry(d, validSubmittedDoc)) {
              validSubmittedDoc = d;
            }
          } else if (schoolApprovals.any(
            (a) => a.status == ApprovalStatusEnum.rejected,
          )) {
            hasRejected = true;
          } else {
            if (isLaterExpiry(d, validUnsubmittedDoc)) {
              validUnsubmittedDoc = d;
            }
          }
        }

        // Folgedokument in Prüfung erkennen, wenn parallel bereits ein gültiges Dokument besteht
        QualificationDocument? renewalSubmittedDoc;
        if (validApprovedDoc != null && validSubmittedDoc != null) {
          final approvedExp = validApprovedDoc.expiresAt;
          final submittedExp = validSubmittedDoc.expiresAt;
          if (submittedExp == null ||
              (approvedExp != null && submittedExp.isAfter(approvedExp)) ||
              validApprovedDoc.expiresSoon) {
            renewalSubmittedDoc = validSubmittedDoc;
          }
        }

        reqsByKey.putIfAbsent(key, () => []).add(
              _SchoolDocRequirement(
                school: s,
                qualifications: qualNames,
                approvedDoc: validApprovedDoc,
                submittedDoc: validSubmittedDoc,
                renewalSubmittedDoc: renewalSubmittedDoc,
                unsubmittedDoc: validUnsubmittedDoc,
                hasExpired: hasExpired,
                hasRejected: hasRejected,
              ),
            );
      }
    }

    final grouped = reqsByKey.entries
        .map(
          (e) => _GroupedRequiredDoc(
            docType: displayByKey[e.key] ?? e.key,
            schoolReqs: e.value,
          ),
        )
        .toList()
      ..sort((a, b) {
        final p = a.sortPriority.compareTo(b.sortPriority);
        if (p != 0) return p;
        return a.docType.toLowerCase().compareTo(b.docType.toLowerCase());
      });

    return grouped;
  }

  Widget _buildRequiredRow(
    BuildContext context,
    _GroupedRequiredDoc group,
    List<FlightSchoolUserView> activeSchools,
  ) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Alle anfordernden Flugschulen + Qualifikationen in einer kompakten Zeile
    final schoolsSummary = group.schoolReqs
        .map((r) => '${r.school.displayName} (${r.qualifications.join(', ')})')
        .join(' · ');

    late final IconData icon;
    late final Color statusColor;
    late final String statusText;
    Color? rowBg;
    Color? rowBorder;

    if (group.hasNeedsUpload) {
      final anyRejected = group.uploadReqs.any((r) => r.hasRejected);
      final anyExpired = group.uploadReqs.any((r) => r.hasExpired);
      icon = anyRejected
          ? Icons.cancel_rounded
          : anyExpired
              ? Icons.event_busy_rounded
              : Icons.warning_amber_rounded;
      statusColor = AppTheme.dangerColor;
      statusText = anyRejected
          ? 'Abgelehnt – neu hochladen'
          : anyExpired
              ? 'Abgelaufen – erneuern'
              : 'Fehlt noch';
    } else if (group.hasNeedsShare) {
      icon = Icons.share_rounded;
      statusColor = AppTheme.warningColor;
      final missingShareNames = group.shareableReqs
          .map((r) => _schoolShortLabel(r.school))
          .join(', ');
      final okNames = [
        ...group.approvedReqs.map((r) => _schoolShortLabel(r.school)),
        ...group.submittedReqs.map((r) => _schoolShortLabel(r.school)),
      ];
      statusText = okNames.isNotEmpty
          ? 'Vorhanden (${okNames.join(', ')}) · Noch freizugeben für $missingShareNames'
          : 'Bereits hochgeladen · Noch freizugeben für $missingShareNames';
      rowBg = isDark
          ? AppTheme.warningColor.withValues(alpha: 0.14)
          : AppTheme.warningBg;
      rowBorder = AppTheme.warningColor.withValues(alpha: 0.35);
    } else if (group.hasPendingReview) {
      icon = Icons.hourglass_top_rounded;
      statusColor = AppTheme.warningColor;
      statusText = 'Prüfung offen';
    } else if (group.anyExpiresSoon) {
      icon = Icons.schedule_rounded;
      statusColor = AppTheme.warningColor;
      final exp = group.earliestExpiringDate;
      statusText = exp != null
          ? 'Bestätigt · läuft bald ab (bis ${_fmtDate(exp)})'
          : 'Bestätigt (läuft bald ab)';
      rowBg = isDark
          ? AppTheme.warningColor.withValues(alpha: 0.14)
          : AppTheme.warningBg;
      rowBorder = AppTheme.warningColor.withValues(alpha: 0.35);
    } else if (group.hasRenewalSubmitted) {
      icon = Icons.check_circle_rounded;
      statusColor = AppTheme.successColor;
      statusText = 'Bestätigt · Folgedokument eingereicht (Prüfung offen)';
    } else {
      icon = Icons.check_circle_rounded;
      statusColor = AppTheme.successColor;
      final exp = group.earliestExpiringDate;
      statusText = exp != null ? 'Bestätigt · gültig bis ${_fmtDate(exp)}' : 'Bestätigt';
    }

    final targetSchoolIds = group.schoolReqs.map((r) => r.school.id).toSet();
    Widget? trailingAction;
    if (group.hasNeedsUpload) {
      trailingAction = FilledButton.tonalIcon(
        onPressed: _busy
            ? null
            : () => _openUploadDialog(
                  activeSchools,
                  preselectedType: group.docType,
                  preselectedSchoolIds: targetSchoolIds,
                ),
        icon: const Icon(Icons.upload_file, size: 16),
        label: const Text('Hochladen'),
      );
    } else if (group.hasNeedsShare) {
      final shareReqs = group.shareableReqs;
      final buttonLabel = shareReqs.length == 1
          ? 'Für ${_schoolShortLabel(shareReqs.first.school)} freigeben'
          : 'Für ${shareReqs.length} Schulen freigeben';
      trailingAction = FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.warningColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        onPressed: _busy
            ? null
            : () => _submitExistingDocToSchools(shareReqs, group.docType),
        icon: const Icon(Icons.send_rounded, size: 15),
        label: Text(buttonLabel, style: const TextStyle(fontSize: 12.5)),
      );
    } else if (group.anyExpiresSoon) {
      trailingAction = FilledButton.tonalIcon(
        onPressed: _busy
            ? null
            : () => _openUploadDialog(
                  activeSchools,
                  preselectedType: group.docType,
                  preselectedSchoolIds: targetSchoolIds,
                ),
        icon: const Icon(Icons.upload_file, size: 16),
        label: const Text('Erneuern'),
      );
    } else if (group.allApproved) {
      // Auch während ein Dokument noch gültig ist, kann jederzeit vorab ein
      // zweites / Folgedokument hochgeladen und zur Prüfung eingereicht werden.
      trailingAction = IconButton(
        tooltip: 'Neues / Folgedokument hochladen',
        visualDensity: VisualDensity.compact,
        onPressed: _busy
            ? null
            : () => _openUploadDialog(
                  activeSchools,
                  preselectedType: group.docType,
                  preselectedSchoolIds: targetSchoolIds,
                ),
        icon: Icon(
          Icons.note_add_outlined,
          size: 20,
          color: cs.primary,
        ),
      );
    }

    final rowContent = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 19, color: statusColor),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                group.docType,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
              Text(
                schoolsSummary,
                style: TextStyle(
                  fontSize: 11.5,
                  color: cs.onSurfaceVariant,
                ),
              ),
              Text(
                statusText,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: statusColor,
                ),
              ),
            ],
          ),
        ),
        if (trailingAction != null) ...[
          const SizedBox(width: 8),
          trailingAction,
        ],
      ],
    );

    if (rowBg != null) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: rowBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: rowBorder ?? Colors.transparent),
        ),
        child: rowContent,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: rowContent,
    );
  }

  String _fmtShortDate(DateTime? d) {
    if (d == null) return '–';
    final yy = (d.year % 100).toString().padLeft(2, '0');
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.$yy';
  }

  Widget _buildDocumentPortraitCard({
    required BuildContext context,
    required QualificationDocument doc,
    required List<FlightSchoolUserView> activeSchools,
    required Map<String, FlightSchoolUserView> schoolById,
    bool compact = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final docApprovals =
        _approvals.where((a) => a.documentId == doc.id).toList();
    final isImg = _isImageFile(doc.fileName);

    final Color accentColor = doc.isExpired
        ? AppTheme.dangerColor
        : doc.expiresSoon
            ? AppTheme.warningColor
            : AppTheme.primaryColor;
    final Color previewBg = doc.isExpired
        ? (isDark
            ? AppTheme.dangerColor.withValues(alpha: 0.16)
            : AppTheme.dangerBg)
        : doc.expiresSoon
            ? (isDark
                ? AppTheme.warningColor.withValues(alpha: 0.16)
                : AppTheme.warningBg)
            : (isDark
                ? cs.primaryContainer.withValues(alpha: 0.35)
                : AppTheme.primaryTint.withValues(alpha: 0.65));

    final customTitle = doc.customTitle;
    final hasCustomTitle = customTitle.isNotEmpty;
    final assignedTypes = doc.documentTypes;

    // Freigaben pro Flugschule bündeln (bei Dokumenten mit mehreren Nachweisen
    // gibt es mehrere Approval-Zeilen je Schule -> genau 1 Pill pro Flugschule).
    final approvalsBySchool = <String, List<QualificationApproval>>{};
    for (final a in docApprovals) {
      approvalsBySchool.putIfAbsent(a.flightSchoolId, () => []).add(a);
    }

    return SoftCard(
      radius: compact ? 13 : 16,
      onTap: () => _openDocumentUrl(doc),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Oberer Dokument-Vorschau-Bereich (Icon + optionale Bezeichnung)
          Container(
            height: hasCustomTitle ? (compact ? 60 : 76) : (compact ? 48 : 64),
            color: previewBg,
            padding: compact
                ? const EdgeInsets.fromLTRB(5, 4, 2, 4)
                : const EdgeInsets.fromLTRB(9, 6, 4, 6),
            child: Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isImg
                            ? Icons.image_outlined
                            : Icons.picture_as_pdf_outlined,
                        size: compact ? 22 : 28,
                        color: accentColor,
                      ),
                      if (hasCustomTitle) ...[
                        const SizedBox(height: 3),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            customTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: compact ? 9.5 : 10.5,
                              fontWeight: FontWeight.w800,
                              color: accentColor,
                              height: 1.15,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (doc.isExpired || doc.expiresSoon)
                  Align(
                    alignment: Alignment.topLeft,
                    child: compact
                        ? Tooltip(
                            message:
                                doc.isExpired ? 'Abgelaufen' : 'Bald fällig',
                            child: Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(
                                  alpha: isDark ? 0.18 : 0.92,
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                doc.isExpired
                                    ? Icons.error_outline
                                    : Icons.schedule_rounded,
                                size: 12,
                                color: doc.isExpired
                                    ? AppTheme.dangerColor
                                    : AppTheme.warningColor,
                              ),
                            ),
                          )
                        : StatusPill(
                            label:
                                doc.isExpired ? 'Abgelaufen' : 'Bald fällig',
                            foreground: doc.isExpired
                                ? AppTheme.dangerColor
                                : AppTheme.warningColor,
                            background: Colors.white.withValues(
                              alpha: isDark ? 0.18 : 0.92,
                            ),
                            fontSize: 9,
                          ),
                  ),
                Align(
                  alignment: Alignment.topRight,
                  child: PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    constraints: compact
                        ? const BoxConstraints(minWidth: 24, minHeight: 24)
                        : null,
                    iconSize: compact ? 16 : 18,
                    tooltip: 'Aktionen',
                    onSelected: (v) {
                      if (v == 'view') _openDocumentUrl(doc);
                      if (v == 'share') {
                        _shareToMoreSchools(doc, activeSchools);
                      }
                      if (v == 'delete') _deleteDoc(doc);
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'view',
                        child: Row(
                          children: [
                            Icon(Icons.open_in_new, size: 17),
                            SizedBox(width: 8),
                            Text('Ansehen'),
                          ],
                        ),
                      ),
                      if (activeSchools.isNotEmpty)
                        const PopupMenuItem(
                          value: 'share',
                          child: Row(
                            children: [
                              Icon(Icons.share_outlined, size: 17),
                              SizedBox(width: 8),
                              Text('Teilen'),
                            ],
                          ),
                        ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline,
                              size: 17,
                              color: AppTheme.dangerColor,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Löschen',
                              style: TextStyle(color: AppTheme.dangerColor),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Inhalt der Hochkant-Kachel
          Expanded(
            child: Padding(
              padding: compact
                  ? const EdgeInsets.fromLTRB(7, 6, 7, 5)
                  : const EdgeInsets.fromLTRB(9, 8, 9, 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.event_outlined,
                        size: compact ? 10.5 : 12,
                        color: doc.isExpired
                            ? AppTheme.dangerColor
                            : cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          doc.expiresAt != null
                              ? (compact
                                  ? _fmtShortDate(doc.expiresAt)
                                  : 'Bis ${_fmtDate(doc.expiresAt)}')
                              : 'Unbefr.',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: compact ? 9.5 : 10.5,
                            fontWeight: FontWeight.w700,
                            color: doc.isExpired
                                ? AppTheme.dangerColor
                                : cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: compact ? 4 : 6),
                  // Flugschul-Freigabe-Pills (1 Pill pro Flugschule)
                  if (approvalsBySchool.isEmpty)
                    Text(
                      compact ? 'Nicht geteilt' : 'Noch nicht geteilt',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 9 : 10,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.warningColor,
                      ),
                    )
                  else
                    Wrap(
                      spacing: compact ? 3 : 4,
                      runSpacing: compact ? 3 : 4,
                      children: approvalsBySchool.entries.map((entry) {
                        final schoolId = entry.key;
                        final list = entry.value;
                        final fs = schoolById[schoolId];
                        final short = fs != null ? _schoolShortLabel(fs) : 'FS';

                        final ApprovalStatusEnum aggStatus = list.any(
                          (a) => a.status == ApprovalStatusEnum.rejected,
                        )
                            ? ApprovalStatusEnum.rejected
                            : list.every(
                                (a) => a.status == ApprovalStatusEnum.approved,
                              )
                                ? ApprovalStatusEnum.approved
                                : ApprovalStatusEnum.submitted;

                        final (fg, bg, stIcon) = switch (aggStatus) {
                          ApprovalStatusEnum.approved => (
                            AppTheme.successColor,
                            AppTheme.successBg,
                            Icons.check_circle,
                          ),
                          ApprovalStatusEnum.rejected => (
                            AppTheme.dangerColor,
                            AppTheme.dangerBg,
                            Icons.cancel,
                          ),
                          ApprovalStatusEnum.submitted => (
                            AppTheme.warningColor,
                            AppTheme.warningBg,
                            Icons.hourglass_top,
                          ),
                        };
                        final tooltipDetails = list
                            .map(
                              (a) =>
                                  '${a.documentType}: ${a.status.label}'
                                  '${(a.comment ?? '').isNotEmpty ? ' (${a.comment})' : ''}',
                            )
                            .join('\n');
                        return Tooltip(
                          message:
                              '${fs?.displayName ?? short}\n$tooltipDetails',
                          child: StatusPill(
                            label: short,
                            icon: compact ? null : stIcon,
                            foreground: fg,
                            background: bg,
                            fontSize: compact ? 8.5 : 9.5,
                          ),
                        );
                      }).toList(),
                    ),
                  SizedBox(height: compact ? 5 : 7),
                  // Zugeordnete Qualifikationsnachweise (unter den Schul-Pills)
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: assignedTypes.map((typeName) {
                          return Padding(
                            padding: EdgeInsets.only(bottom: compact ? 3 : 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (assignedTypes.length > 1) ...[
                                  Padding(
                                    padding: EdgeInsets.only(
                                      top: compact ? 4 : 5,
                                      right: 4,
                                    ),
                                    child: Container(
                                      width: compact ? 4 : 4.5,
                                      height: compact ? 4 : 4.5,
                                      decoration: BoxDecoration(
                                        color: accentColor,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                ],
                                Expanded(
                                  child: Text(
                                    typeName,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: compact ? 10 : 11.5,
                                      height: 1.2,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  Divider(height: compact ? 7 : 9),
                  Row(
                    children: [
                      Expanded(
                        child: Tooltip(
                          message: 'Öffnen',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => _openDocumentUrl(doc),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.open_in_new_rounded,
                                    size: compact ? 14 : 14,
                                    color: cs.primary,
                                  ),
                                  if (!compact) ...[
                                    const SizedBox(width: 4),
                                    Text(
                                      'Öffnen',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: cs.primary,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (activeSchools.isNotEmpty) ...[
                        Container(
                          width: 1,
                          height: 13,
                          color: cs.outlineVariant,
                        ),
                        Expanded(
                          child: Tooltip(
                            message: 'Teilen',
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: _busy
                                  ? null
                                  : () =>
                                      _shareToMoreSchools(doc, activeSchools),
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 2),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.share_outlined,
                                      size: compact ? 14 : 14,
                                      color: cs.onSurfaceVariant,
                                    ),
                                    if (!compact) ...[
                                      const SizedBox(width: 4),
                                      Text(
                                        'Teilen',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
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

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserProvider>().user;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeSchools = user.flightSchools
        .where((s) => s.membershipStatus == MembershipStatusEnum.active)
        .toList();
    final schoolById = {for (final s in user.flightSchools) s.id: s};

    final groupedRequired = _buildGroupedRequiredDocs(activeSchools);
    final openRequiredCount = groupedRequired
        .where((g) => g.hasNeedsUpload || g.hasNeedsShare || g.anyExpiresSoon)
        .length;
    final activeDocs = _docs.where((d) => !d.isExpired).toList();
    final expiredDocs = _docs.where((d) => d.isExpired).toList();
    final visibleDocs =
        _showExpiredDocs ? [...activeDocs, ...expiredDocs] : activeDocs;

    return Scaffold(
      appBar: AppBar(title: const Text('Meine Qualifikationen')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : () => _openUploadDialog(activeSchools),
        icon: const Icon(Icons.upload_file),
        label: const Text('Nachweis hochladen'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                        children: [
                          // 1) Qualifikationen je Flugschule (Zugewiesen / Anfragen)
                          for (final s in activeSchools)
                            if (s.qualifications.isNotEmpty) ...[
                              SoftCard(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.workspace_premium_outlined,
                                          color: cs.primary,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Qualifikationen · ${s.displayName}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 15,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    ...s.qualifications.map((q) {
                                      final owned = s.hasQualification(q.id);
                                      final requested =
                                          s.hasRequestedQualification(q.id);
                                      return Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 6),
                                        child: Row(
                                          children: [
                                            Icon(
                                              owned
                                                  ? Icons.verified
                                                  : requested
                                                      ? Icons.hourglass_top
                                                      : Icons
                                                          .radio_button_unchecked,
                                              size: 18,
                                              color: owned
                                                  ? AppTheme.successColor
                                                  : requested
                                                      ? AppTheme.warningColor
                                                      : Colors.grey,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    q.name,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 13.5,
                                                    ),
                                                  ),
                                                  Text(
                                                    owned
                                                        ? 'Vom Admin zugeteilt'
                                                        : requested
                                                            ? 'Angefragt – warte auf Admin-Bestätigung'
                                                            : 'Nicht zugeteilt',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: owned
                                                          ? AppTheme
                                                              .successColor
                                                          : requested
                                                              ? AppTheme
                                                                  .warningColor
                                                              : cs
                                                                  .onSurfaceVariant,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (!owned && !requested)
                                              OutlinedButton(
                                                onPressed: _busy
                                                    ? null
                                                    : () =>
                                                        _requestQualification(
                                                          s,
                                                          q,
                                                        ),
                                                child: const Text('Anfragen'),
                                              )
                                            else if (requested && !owned)
                                              TextButton(
                                                onPressed: _busy
                                                    ? null
                                                    : () =>
                                                        _withdrawQualificationRequest(
                                                          s,
                                                          q,
                                                        ),
                                                child: const Text(
                                                  'Zurückziehen',
                                                ),
                                              ),
                                          ],
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],

                          // 2) Deduplizierte Pflichtnachweise über alle Flugschulen
                          if (groupedRequired.isNotEmpty) ...[
                            SoftCard(
                              color: openRequiredCount > 0
                                  ? (isDark
                                      ? AppTheme.dangerColor
                                          .withValues(alpha: 0.10)
                                      : AppTheme.dangerColor
                                          .withValues(alpha: 0.05))
                                  : (isDark
                                      ? AppTheme.successColor
                                          .withValues(alpha: 0.10)
                                      : AppTheme.successBg
                                          .withValues(alpha: 0.65)),
                              border: Border.all(
                                color: openRequiredCount > 0
                                    ? AppTheme.dangerColor
                                        .withValues(alpha: 0.28)
                                    : AppTheme.successColor
                                        .withValues(alpha: 0.28),
                              ),
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        openRequiredCount > 0
                                            ? Icons.warning_amber_rounded
                                            : Icons.verified_outlined,
                                        color: openRequiredCount > 0
                                            ? AppTheme.dangerColor
                                            : AppTheme.successColor,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          openRequiredCount > 0
                                              ? 'Pflichtnachweise ($openRequiredCount offen)'
                                              : 'Pflichtnachweise vollständig',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  ...groupedRequired.map(
                                    (group) => _buildRequiredRow(
                                      context,
                                      group,
                                      activeSchools,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          // 3) Optisch abgesetzter Bereich „Meine Dokumente“ mit 2:3 Hochformat-Kacheln
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? AppTheme.darkCardElevated
                                  : const Color(0xFFE7E7E2),
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: cs.outlineVariant.withValues(
                                  alpha: isDark ? 0.5 : 0.7,
                                ),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    TintedIconBadge(
                                      icon: Icons.folder_copy_outlined,
                                      iconColor: cs.primary,
                                      backgroundColor: isDark
                                          ? cs.primaryContainer
                                          : Colors.white,
                                      size: 36,
                                      iconSize: 19,
                                      radius: 11,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Meine Dokumente',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 15.5,
                                            ),
                                          ),
                                          Text(
                                            'Hochgeladene Lizenzen, Versicherungen & Nachweise',
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              color: cs.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    StatusPill(
                                      label: '${activeDocs.length}',
                                      foreground: cs.primary,
                                      background: isDark
                                          ? cs.primaryContainer
                                          : Colors.white,
                                      fontSize: 11.5,
                                    ),
                                  ],
                                ),
                                if (expiredDocs.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: ActionChip(
                                      avatar: Icon(
                                        _showExpiredDocs
                                            ? Icons.visibility_off_outlined
                                            : Icons.history_rounded,
                                        size: 16,
                                        color: _showExpiredDocs
                                            ? cs.primary
                                            : cs.onSurfaceVariant,
                                      ),
                                      label: Text(
                                        _showExpiredDocs
                                            ? 'Alte ausblenden (${expiredDocs.length})'
                                            : 'Alte anzeigen (${expiredDocs.length})',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: _showExpiredDocs
                                              ? cs.primary
                                              : cs.onSurface,
                                        ),
                                      ),
                                      backgroundColor: isDark
                                          ? cs.surface
                                          : Colors.white,
                                      side: BorderSide(
                                        color: _showExpiredDocs
                                            ? cs.primary.withValues(alpha: 0.4)
                                            : cs.outlineVariant,
                                      ),
                                      onPressed: () => setState(
                                        () => _showExpiredDocs =
                                            !_showExpiredDocs,
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 14),
                                if (visibleDocs.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 28,
                                      horizontal: 12,
                                    ),
                                    child: Center(
                                      child: Column(
                                        children: [
                                          Icon(
                                            expiredDocs.isNotEmpty
                                                ? Icons.history_rounded
                                                : Icons.upload_file_outlined,
                                            size: 36,
                                            color: cs.onSurfaceVariant
                                                .withValues(alpha: 0.6),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            expiredDocs.isNotEmpty
                                                ? 'Keine aktuell gültigen Dokumente vorhanden.\nAlle ${expiredDocs.length} bisherigen Dokumente sind abgelaufen.'
                                                : 'Noch keine Nachweise hochgeladen.\nLade ein Dokument einmal hoch und teile es mit mehreren Flugschulen.',
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
                                else
                                  LayoutBuilder(
                                    builder: (context, constraints) {
                                      final w = constraints.maxWidth;
                                      final crossAxisCount = w >= 920
                                          ? 5
                                          : w >= 660
                                              ? 4
                                              : w >= 290
                                                  ? 3
                                                  : 2;
                                      final tileWidth = (w -
                                              ((crossAxisCount - 1) * 8)) /
                                          crossAxisCount;
                                      final isCompactTile = tileWidth < 145;
                                      return GridView.builder(
                                        shrinkWrap: true,
                                        physics:
                                            const NeverScrollableScrollPhysics(),
                                        itemCount: visibleDocs.length,
                                        gridDelegate:
                                            SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: crossAxisCount,
                                          crossAxisSpacing: 8,
                                          mainAxisSpacing: 8,
                                          childAspectRatio:
                                              isCompactTile ? 0.62 : 0.68,
                                        ),
                                        itemBuilder: (context, idx) {
                                          final doc = visibleDocs[idx];
                                          final card =
                                              _buildDocumentPortraitCard(
                                            context: context,
                                            doc: doc,
                                            activeSchools: activeSchools,
                                            schoolById: schoolById,
                                            compact: isCompactTile,
                                          );
                                          return doc.isExpired
                                              ? Opacity(
                                                  opacity: 0.74,
                                                  child: card,
                                                )
                                              : card;
                                        },
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
          ],
        ),
      ),
    );
  }
}
