import 'dart:convert';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/enums.dart' as aw_enums;
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:season_planner/core/appwrite_config.dart';
import 'package:season_planner/core/data/enums/event_role_enum.dart';
import 'package:season_planner/core/data/enums/event_status_enum.dart';
import 'package:season_planner/core/data/enums/event_user_status_enum.dart';
import 'package:season_planner/core/data/models/audit_export_model.dart';
import 'package:season_planner/core/data/models/qualification_model.dart';
import 'package:season_planner/core/data/models/tandem_model.dart';
import 'package:season_planner/core/data/models/team_role_model.dart';
import 'package:season_planner/core/services/audit_log_service.dart';
import 'package:season_planner/core/services/auth_service.dart';
import 'package:season_planner/core/services/qualification_service.dart';
import 'package:season_planner/fsAdmin/data/models/flight_school_model_flight_school_view.dart';
import 'package:season_planner/fsAdmin/data/models/user_summary_flight_school_view.dart';

class AuditPdfExportResult {
  final Uint8List pdfBytes;
  final int attachedDocumentCount;
  final List<String> warnings;
  final bool mergedViaServer;

  const AuditPdfExportResult({
    required this.pdfBytes,
    required this.attachedDocumentCount,
    required this.warnings,
    required this.mergedViaServer,
  });
}

class AuditExportService {
  static final AuditExportService _instance = AuditExportService._internal();
  factory AuditExportService() => _instance;
  AuditExportService._internal();

  Client get _client => AuthService().client;
  late final TablesDB _tablesDB = TablesDB(_client);
  late final Functions _functions = Functions(_client);
  late final Storage _storage = Storage(_client);

  // ==================== SCHOOL AUDIT CONFIG ====================

  Future<bool> setAuditExportsEnabled({
    required String flightSchoolId,
    required bool enabled,
  }) async {
    try {
      final cfg = AppwriteConfig();
      await _tablesDB.updateRow(
        databaseId: cfg.mainDatabaseId,
        tableId: cfg.flightSchoolsCollectionId,
        rowId: flightSchoolId,
        data: {'audit_exports_enabled': enabled},
      );
      await AuditLogService().log(
        flightSchoolId: flightSchoolId,
        action: enabled ? 'audit_exports_enabled' : 'audit_exports_disabled',
        details: enabled
            ? 'Audit Exports für Flugschule aktiviert'
            : 'Audit Exports für Flugschule deaktiviert',
      );
      return true;
    } catch (e) {
      debugPrint('AuditExportService.setAuditExportsEnabled error: $e');
      return false;
    }
  }

  Future<bool> saveSchoolAuditProfile({
    required String flightSchoolId,
    required FlightSchoolAuditProfile profile,
  }) async {
    try {
      final cfg = AppwriteConfig();
      await _tablesDB.updateRow(
        databaseId: cfg.mainDatabaseId,
        tableId: cfg.flightSchoolsCollectionId,
        rowId: flightSchoolId,
        data: {'audit_profile_json': profile.toJsonString()},
      );
      await AuditLogService().log(
        flightSchoolId: flightSchoolId,
        action: 'audit_profile_updated',
        details: 'ÖAeC Audit-Stammdaten der Flugschule aktualisiert',
      );
      return true;
    } catch (e) {
      debugPrint('AuditExportService.saveSchoolAuditProfile error: $e');
      return false;
    }
  }

  // ==================== COMPLIANCE & YEAR DATA ====================

  /// Zählt bestätigte Einsätze (Events + Tandem) je Mitglied in [year].
  Map<String, int> countConfirmedAssignmentsForYear(
    FlightSchoolModelFlightSchoolView fs,
    int year,
  ) {
    final counts = <String, int>{};

    for (final ev in fs.events) {
      if (ev.status == EventStatusEnum.canceled) continue;
      final inYear = ev.startTime.year == year || ev.endTime.year == year;
      if (!inYear) continue;

      for (final tm in ev.team) {
        if (tm.isSlot) continue;
        final st = tm.statusEnum;
        final confirmed = st == EventUserStatusEnum.accepted_user ||
            st == EventUserStatusEnum.accepted_flight_school;
        if (!confirmed) continue;
        final member = fs.findMemberByAnyId(tm.userId);
        final key = member?.id ?? tm.userId;
        counts[key] = (counts[key] ?? 0) + 1;
      }
    }

    if (fs.tandemEnabled) {
      for (final duty in fs.tandemDuties) {
        if (duty.status != TandemDutyStatus.confirmed) continue;
        final inYear = duty.startDay.year == year || duty.endDay.year == year;
        if (!inYear) continue;
        final member = fs.findMemberByAnyId(duty.userId);
        final key = member?.id ?? duty.userId;
        counts[key] = (counts[key] ?? 0) + 1;
      }
    }

    return counts;
  }

  /// Lädt alle freigegebenen & gültigen Nachweise sowie Audit-Warnungen pro Mitglied.
  Future<Map<String, AuditMemberCompliance>> loadComplianceForSchool({
    required FlightSchoolModelFlightSchoolView fs,
    required int year,
  }) async {
    final qualService = QualificationService();
    final counts = countConfirmedAssignmentsForYear(fs, year);
    final approvals = await qualService.listSchoolApprovals(
      fs.id,
      status: ApprovalStatusEnum.approved,
    );

    final approvalsByUser = <String, List<QualificationApproval>>{};
    for (final a in approvals) {
      final canonical = fs.findMemberByAnyId(a.userId)?.id ?? a.userId;
      approvalsByUser.putIfAbsent(canonical, () => []).add(a);
    }

    // Dokumente aller Mitglieder parallel laden
    final docsFutures = fs.members.map((m) async {
      final docs = await qualService.listUserDocuments(m.id);
      return MapEntry(m.id, docs);
    });
    final docsByUser = Map<String, List<QualificationDocument>>.fromEntries(
      await Future.wait(docsFutures),
    );

    final result = <String, AuditMemberCompliance>{};
    for (final m in fs.members) {
      final memberDocs = docsByUser[m.id] ?? const <QualificationDocument>[];
      final docById = {for (final d in memberDocs) d.id: d};
      final memberApprovals =
          approvalsByUser[m.id] ?? const <QualificationApproval>[];

      // Alle freigegebenen & gültigen Dokumente (dedupliziert pro Dokument-ID)
      final validDocsById = <String, QualificationDocument>{};
      final approvedTypes = <String>{};
      final validTypes = <String>{};

      for (final a in memberApprovals) {
        final doc = docById[a.documentId];
        if (doc == null) continue;
        approvedTypes.add(a.documentType.toLowerCase());
        if (!doc.isExpired) {
          validDocsById[doc.id] = doc;
          validTypes.add(a.documentType.toLowerCase());
        }
      }

      // Pflichtdokumente aus Qualifikationen des Mitglieds prüfen
      final requiredTypes = <String>{};
      for (final qId in m.qualificationIds) {
        final q = fs.findQualificationById(qId);
        if (q != null) requiredTypes.addAll(q.requiredDocuments);
      }

      final missingDocTypes = <String>[];
      final expiredDocTypes = <String>[];
      for (final req in requiredTypes) {
        final lower = req.toLowerCase();
        if (validTypes.contains(lower)) continue;
        if (approvedTypes.contains(lower)) {
          expiredDocTypes.add(req);
        } else {
          missingDocTypes.add(req);
        }
      }

      final missingProfile = <String>[];
      if (m.address.trim().isEmpty) missingProfile.add('Anschrift');
      if (m.birthDate.trim().isEmpty) missingProfile.add('Geburtsdatum');
      if (m.licenseNumber.trim().isEmpty && m.qualificationIds.isNotEmpty) {
        missingProfile.add('Scheinnummer');
      }

      final validDocs = validDocsById.values.toList()
        ..sort((a, b) => a.documentType.compareTo(b.documentType));

      result[m.id] = AuditMemberCompliance(
        member: m,
        confirmedAssignmentsInYear: counts[m.id] ?? 0,
        validApprovedDocs: validDocs,
        missingDocTypes: missingDocTypes,
        expiredDocTypes: expiredDocTypes,
        missingProfileFields: missingProfile,
      );
    }

    return result;
  }

  // ==================== PDF GENERATION & MERGE ====================

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  /// Erzeugt das vollständige ÖAeC-Stellenbesetzungsplan-Gesamt-PDF inkl. aller
  /// freigegebenen & gültigen Nachweis-Dokumente (PDF + Bilder) als nummerierte Anhänge.
  Future<AuditPdfExportResult> buildStellenbesetzungsplanPdf({
    required FlightSchoolModelFlightSchoolView fs,
    required FlightSchoolAuditProfile profile,
    required int year,
    required List<UserSummary> includedMembers,
    required Map<String, AuditMemberCompliance> complianceByMemberId,
  }) async {
    final now = DateTime.now();
    final exportDateStr = _fmtDate(now);
    final schoolName = profile.officialName.trim().isNotEmpty
        ? profile.officialName.trim()
        : fs.displayName;

    // 1) Qualifikations-Sektionen nach ÖAeC-Reihenfolge (Mehrfachnennung erlaubt!)
    final sortedQuals = List<Qualification>.from(fs.qualifications)
      ..sort((a, b) {
        final c = oeAeCQualificationSortOrder(a.name)
            .compareTo(oeAeCQualificationSortOrder(b.name));
        if (c != 0) return c;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    final sections = <({String title, bool isTandem, List<UserSummary> people})>[];
    final placedMemberIds = <String>{};

    for (final q in sortedQuals) {
      final matching = includedMembers
          .where((m) => m.qualificationIds.contains(q.id))
          .toList()
        ..sort(
          (a, b) =>
              a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
        );
      if (matching.isEmpty) continue;
      for (final m in matching) {
        placedMemberIds.add(m.id);
      }
      sections.add((
        title: oeAeCSectionTitleForQualification(q.name),
        isTandem: q.name.toLowerCase().contains('tandem'),
        people: matching,
      ));
    }

    // Büro-Sektion (wie Ausbildungsleiter explizit auswählbar)
    final officeSet = profile.officeMemberIds.toSet();
    final officePeople = includedMembers
        .where((m) => officeSet.contains(m.id))
        .toList()
      ..sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
    if (officePeople.isNotEmpty) {
      for (final m in officePeople) {
        placedMemberIds.add(m.id);
      }
      sections.add((title: 'Büro', isTandem: false, people: officePeople));
    }

    // Sonstige eingeplante Mitarbeiter ohne zugeordnete Qualifikation / Büro
    final unplaced = includedMembers
        .where((m) => !placedMemberIds.contains(m.id))
        .toList()
      ..sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
    if (unplaced.isNotEmpty) {
      sections.add(
        (title: 'Weiteres Personal', isTandem: false, people: unplaced),
      );
    }

    // 2) Anhangsliste aufbauen (alphabetisch nach Person, inkl. Ausbildungsleiter falls ausgewählt)
    final allAppendixMembers = <UserSummary>[];
    final seenIds = <String>{};
    if (profile.trainingDirectorUserId.isNotEmpty) {
      final dir = fs.findMemberByAnyId(profile.trainingDirectorUserId);
      if (dir != null && seenIds.add(dir.id)) {
        allAppendixMembers.add(dir);
      }
    }
    final sortedIncluded = List<UserSummary>.from(includedMembers)
      ..sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
    for (final m in sortedIncluded) {
      if (seenIds.add(m.id)) allAppendixMembers.add(m);
    }

    final appendixEntries =
        <({int number, UserSummary member, List<QualificationDocument> docs})>[];
    int nextAppNr = 1;
    for (final m in allAppendixMembers) {
      final docs =
          complianceByMemberId[m.id]?.validApprovedDocs ??
          const <QualificationDocument>[];
      if (docs.isEmpty) continue;
      appendixEntries.add((number: nextAppNr++, member: m, docs: docs));
    }

    // 3) Basis-PDF (ÖAeC-Stellenbesetzungsplan-Layout, ohne Versionsverzeichnis)
    final basePdfBytes = await _renderBasePdf(
      fs: fs,
      profile: profile,
      schoolName: schoolName,
      year: year,
      exportDateStr: exportDateStr,
      sections: sections,
      appendixEntries: appendixEntries,
      complianceByMemberId: complianceByMemberId,
    );

    if (appendixEntries.isEmpty) {
      return AuditPdfExportResult(
        pdfBytes: basePdfBytes,
        attachedDocumentCount: 0,
        warnings: const [],
        mergedViaServer: true,
      );
    }

    // 4) Anhänge (PDFs + Bilder) über Appwrite Function `audit_pdf_merger` zu 1 Gesamt-PDF zusammenführen
    final cfg = AppwriteConfig();
    final attachmentsPayload = appendixEntries.map((entry) {
      return {
        'appendixNumber': entry.number,
        'memberName': entry.member.displayName,
        'files': entry.docs.map((d) {
          return {
            'fileId': d.fileId,
            'bucketId': cfg.qualificationDocumentsBucketId,
            'documentType': d.documentType,
            'title': d.title,
            'fileName': d.fileName,
            'expiresAt': d.expiresAt != null ? _fmtDate(d.expiresAt!) : '',
          };
        }).toList(),
      };
    }).toList();

    try {
      final execution = await _functions.createExecution(
        functionId: cfg.auditPdfMergerFunctionId,
        body: jsonEncode({
          'basePdfBase64': base64Encode(basePdfBytes),
          'attachments': attachmentsPayload,
        }),
        xasync: false,
        method: aw_enums.ExecutionMethod.pOST,
      );

      if (execution.responseStatusCode == 200 &&
          execution.responseBody.isNotEmpty) {
        final decoded = jsonDecode(execution.responseBody);
        if (decoded is Map &&
            decoded['ok'] == true &&
            decoded['pdfBase64'] is String) {
          final mergedBytes = base64Decode(decoded['pdfBase64'] as String);
          final serverWarnings = (decoded['warnings'] as List? ?? const [])
              .map((w) => w.toString())
              .toList();
          final count = decoded['attachedCount'] is int
              ? decoded['attachedCount'] as int
              : 0;
          return AuditPdfExportResult(
            pdfBytes: mergedBytes,
            attachedDocumentCount: count,
            warnings: serverWarnings,
            mergedViaServer: true,
          );
        }
      }
      debugPrint(
        'audit_pdf_merger unexpected response: status=${execution.responseStatusCode} body=${execution.responseBody}',
      );
    } catch (e) {
      debugPrint('audit_pdf_merger call failed, using client fallback: $e');
    }

    // Fallback: Bilder direkt im Client-PDF einbetten, PDF-Anhänge als Warnung ausgeben
    return _fallbackClientEmbedImages(
      fs: fs,
      profile: profile,
      schoolName: schoolName,
      year: year,
      exportDateStr: exportDateStr,
      sections: sections,
      appendixEntries: appendixEntries,
      complianceByMemberId: complianceByMemberId,
    );
  }

  Future<Uint8List> _renderBasePdf({
    required FlightSchoolModelFlightSchoolView fs,
    required FlightSchoolAuditProfile profile,
    required String schoolName,
    required int year,
    required String exportDateStr,
    required List<({String title, bool isTandem, List<UserSummary> people})>
        sections,
    required List<
            ({int number, UserSummary member, List<QualificationDocument> docs})>
        appendixEntries,
    required Map<String, AuditMemberCompliance> complianceByMemberId,
    List<pw.Widget>? fallbackImagePages,
  }) async {
    final doc = pw.Document(
      title: 'Stellenbesetzungsplan $schoolName ($year)',
      author: schoolName,
    );

    final accent = PdfColor.fromHex('#5B3DF5');
    final lightBg = PdfColor.fromHex('#F4F4F6');
    final border = PdfColor.fromHex('#D8DCE3');
    final muted = PdfColor.fromHex('#5B6270');

    String pdfSafe(String input) {
      final replaced = input
          .replaceAll('\u2013', '-')
          .replaceAll('\u2014', '-')
          .replaceAll('\u2212', '-')
          .replaceAll('\u2018', "'")
          .replaceAll('\u2019', "'")
          .replaceAll('\u201C', '"')
          .replaceAll('\u201D', '"')
          .replaceAll('\u201E', '"')
          .replaceAll('\u2026', '...')
          .replaceAll('\u2022', '-')
          .replaceAll('\u00A0', ' ');
      final buf = StringBuffer();
      for (final rune in replaced.runes) {
        if (rune == 0x0A || rune == 0x0D || (rune >= 0x20 && rune <= 0xFF)) {
          buf.writeCharCode(rune);
        }
      }
      return buf.toString();
    }

    String val(String s) => s.trim().isEmpty ? '-' : pdfSafe(s.trim());

    // Ausbildungsleiter auflösen (aus Team-Mitglied + Profil-Overrides)
    final dirMember = profile.trainingDirectorUserId.isNotEmpty
        ? fs.findMemberByAnyId(profile.trainingDirectorUserId)
        : null;
    final dirName = profile.trainingDirectorName.trim().isNotEmpty
        ? profile.trainingDirectorName.trim()
        : (dirMember?.displayName ?? '');
    final dirAddress = profile.trainingDirectorAddress.trim().isNotEmpty
        ? profile.trainingDirectorAddress.trim()
        : (dirMember?.address ?? '');
    final dirEmail = profile.trainingDirectorEmail.trim().isNotEmpty
        ? profile.trainingDirectorEmail.trim()
        : (dirMember?.mail ?? '');
    final dirPhone = profile.trainingDirectorPhone.trim().isNotEmpty
        ? profile.trainingDirectorPhone.trim()
        : (dirMember?.phone ?? '');
    final dirBirth = profile.trainingDirectorBirthDate.trim().isNotEmpty
        ? profile.trainingDirectorBirthDate.trim()
        : (dirMember?.birthDate ?? '');

    pw.Widget kvRow(String label, String value) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 130,
              child: pw.Text(
                label,
                style: pw.TextStyle(
                  fontSize: 9.5,
                  fontWeight: pw.FontWeight.bold,
                  color: muted,
                ),
              ),
            ),
            pw.Expanded(
              child: pw.Text(
                val(value),
                style: const pw.TextStyle(fontSize: 9.5),
              ),
            ),
          ],
        ),
      );
    }

    pw.Widget memberBlock(
      int index,
      UserSummary m, {
      required bool isTandem,
    }) {
      final comp = complianceByMemberId[m.id];
      final roleLabels = m.roles
          .map(EventRoleEnum.displayLabel)
          .where((r) => r.trim().isNotEmpty)
          .toList();
      final periodStr = [
        if (m.activeSince.trim().isNotEmpty) '${m.activeSince.trim()} bis aktuell',
        if (m.employmentType.trim().isNotEmpty) '(${m.employmentType.trim()})',
      ].join(' ');

      final headerParts = <String>[
        '($index) ${m.displayName}',
        if (m.licenseNumber.trim().isNotEmpty)
          'Scheinnummer ${m.licenseNumber.trim()}',
        if (m.birthDate.trim().isNotEmpty) 'geb. ${m.birthDate.trim()}',
      ];

      final tandemDoc = isTandem ? comp?.findValidDocByKeyword('tandem') : null;
      final medicalDoc =
          isTandem ? comp?.findValidDocByKeyword('medical') : null;

      return pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 10),
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          borderRadius: pw.BorderRadius.circular(6),
          border: pw.Border.all(color: border, width: 0.7),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              pdfSafe(headerParts.join(', ')),
              style: pw.TextStyle(
                fontSize: 10.5,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 4),
            kvRow(
              'Tätigkeitsbereich:',
              roleLabels.isEmpty ? '-' : roleLabels.join(', '),
            ),
            kvRow('Anschrift:', m.address),
            kvRow('E-Mail:', m.mail),
            kvRow('Telefon:', m.phone),
            kvRow(
              'Tätigkeitszeitraum:',
              periodStr.isEmpty ? 'Saison $year' : periodStr,
            ),
            kvRow('Berechtigungen:', m.licenseRatings),
            if (isTandem) ...[
              kvRow(
                'Tandemlizenz gültig:',
                tandemDoc?.expiresAt != null
                    ? 'gültig bis ${_fmtDate(tandemDoc!.expiresAt!)}'
                    : (tandemDoc != null ? 'Nachweis im Anhang' : '-'),
              ),
              kvRow(
                'Medical:',
                medicalDoc?.expiresAt != null
                    ? 'gültig bis ${_fmtDate(medicalDoc!.expiresAt!)}'
                    : (medicalDoc != null ? 'Nachweis im Anhang' : '-'),
              ),
            ],
          ],
        ),
      );
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 40),
        footer: (ctx) => pw.Container(
          margin: const pw.EdgeInsets.only(top: 10),
          padding: const pw.EdgeInsets.only(top: 6),
          decoration: pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: border, width: 0.5)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Stellenbesetzungsplan · $schoolName · Exportiert am $exportDateStr',
                style: pw.TextStyle(fontSize: 8, color: muted),
              ),
              pw.Text(
                'Seite ${ctx.pageNumber} von ${ctx.pagesCount}',
                style: pw.TextStyle(fontSize: 8, color: muted),
              ),
            ],
          ),
        ),
        build: (ctx) => [
          // Titelblock (ÖAeC-Struktur)
          pw.Center(
            child: pw.Column(
              children: [
                pw.Text(
                  'Stellenbesetzungsplan der Zivilluftfahrerschule',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: accent,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  schoolName,
                  style: pw.TextStyle(
                    fontSize: 13.5,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Jahr $year · Stand / Exportdatum: $exportDateStr',
                  style: pw.TextStyle(fontSize: 9.5, color: muted),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),

          // Geltungsbereich / Flugschuldaten
          pw.Text(
            'Geltungsbereich',
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: accent,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Der Stellenbesetzungsplan gibt eine Übersicht über die Besetzung des Personals in folgender Flugschule zum Zeitpunkt $exportDateStr (Saison $year):',
            style: const pw.TextStyle(fontSize: 9.5),
          ),
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: lightBg,
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(color: border, width: 0.7),
            ),
            child: pw.Column(
              children: [
                kvRow('Flugschulname:', schoolName),
                kvRow('Eigentümer:', profile.ownerName),
                kvRow('Anschrift:', profile.address),
                kvRow('E-Mail:', profile.email),
                kvRow('Telefon:', profile.phone),
              ],
            ),
          ),
          pw.SizedBox(height: 14),

          // Verantwortliche/r GeschäftsführerIn / Ausbildungsleiter
          pw.Text(
            'Verantwortliche/r GeschäftsführerIn / Ausbildungsleiter',
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: accent,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Nach geltendem Bescheid mit der Nummer ${val(profile.bescheidNumber)} ist folgender Ausbildungsleiter für $schoolName${profile.trainingDirectorSince.trim().isNotEmpty ? ' seit ${profile.trainingDirectorSince.trim()}' : ''} nominiert:',
            style: const pw.TextStyle(fontSize: 9.5),
          ),
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: lightBg,
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(color: border, width: 0.7),
            ),
            child: pw.Column(
              children: [
                kvRow('Ausbildungsleiter:', dirName),
                kvRow('Anschrift:', dirAddress),
                kvRow('E-Mail:', dirEmail),
                kvRow('Telefon:', dirPhone),
                kvRow('Geboren am:', dirBirth),
              ],
            ),
          ),
          pw.SizedBox(height: 16),

          // Personal-Abschnitte sortiert nach Qualifikation
          for (final sec in sections) ...[
            pw.Container(
              width: double.infinity,
              margin: const pw.EdgeInsets.only(top: 6, bottom: 8),
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              decoration: pw.BoxDecoration(
                color: accent,
                borderRadius: pw.BorderRadius.circular(5),
              ),
              child: pw.Text(
                '${sec.title} (${sec.people.length})',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
              ),
            ),
            for (int i = 0; i < sec.people.length; i++)
              memberBlock(i + 1, sec.people[i], isTandem: sec.isTandem),
          ],

          // Anhangsverzeichnis (wie Seite 11 des ÖAeC-Musters)
          pw.NewPage(),
          pw.Text(
            'Anhangsverzeichnis',
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: accent,
            ),
          ),
          pw.SizedBox(height: 8),
          if (appendixEntries.isEmpty)
            pw.Text(
              'Keine freigegebenen und gültigen Nachweisdokumente vorhanden.',
              style: pw.TextStyle(fontSize: 10, color: muted),
            )
          else
            pw.TableHelper.fromTextArray(
              headers: const ['Anhang Nr.', 'Name', 'Dokumente'],
              data: appendixEntries.map((entry) {
                final docLines = entry.docs.map((d) {
                  final exp =
                      d.expiresAt != null ? ' (bis ${_fmtDate(d.expiresAt!)})' : '';
                  return '- ${d.documentType}$exp';
                }).join('\n');
                return [
                  'Anhang ${entry.number}',
                  entry.member.displayName,
                  docLines,
                ];
              }).toList(),
              headerStyle: pw.TextStyle(
                fontSize: 9.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: pw.BoxDecoration(color: accent),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 6,
              ),
              border: pw.TableBorder.all(color: border, width: 0.6),
              oddRowDecoration: pw.BoxDecoration(color: lightBg),
              columnWidths: const {
                0: pw.FixedColumnWidth(80),
                1: pw.FixedColumnWidth(150),
                2: pw.FlexColumnWidth(),
              },
            ),
          pw.SizedBox(height: 14),
          pw.Text(
            'Hinweise',
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              decoration: pw.TextDecoration.underline,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Alle relevanten, freigegebenen und gültigen Dokumente der Personen im Stellenbesetzungsplan befinden sich direkt im Anschluss als Kopie im Anhang dieses Dokuments.',
            style: pw.TextStyle(
              fontSize: 9.5,
              fontStyle: pw.FontStyle.italic,
              color: muted,
            ),
          ),
        ],
      ),
    );

    if (fallbackImagePages != null) {
      for (final pageWidget in fallbackImagePages) {
        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(28),
            build: (_) => pageWidget,
          ),
        );
      }
    }

    return doc.save();
  }

  Future<AuditPdfExportResult> _fallbackClientEmbedImages({
    required FlightSchoolModelFlightSchoolView fs,
    required FlightSchoolAuditProfile profile,
    required String schoolName,
    required int year,
    required String exportDateStr,
    required List<({String title, bool isTandem, List<UserSummary> people})>
        sections,
    required List<
            ({int number, UserSummary member, List<QualificationDocument> docs})>
        appendixEntries,
    required Map<String, AuditMemberCompliance> complianceByMemberId,
  }) async {
    final cfg = AppwriteConfig();
    final imagePages = <pw.Widget>[];
    final warnings = <String>[];
    int attachedCount = 0;

    for (final entry in appendixEntries) {
      for (final d in entry.docs) {
        try {
          final bytes = await _storage.getFileView(
            bucketId: cfg.qualificationDocumentsBucketId,
            fileId: d.fileId,
          );
          final lower = d.fileName.toLowerCase();
          final isImg = lower.endsWith('.png') ||
              lower.endsWith('.jpg') ||
              lower.endsWith('.jpeg');
          if (!isImg) {
            warnings.add(
              '${entry.member.displayName} (${d.documentType}): PDF-Anhang konnte im Offline-Fallback nicht eingebettet werden.',
            );
            continue;
          }
          imagePages.add(
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Text(
                  'Anhang ${entry.number} · ${entry.member.displayName} · ${d.documentType}',
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Expanded(
                  child: pw.Center(
                    child: pw.Image(
                      pw.MemoryImage(bytes),
                      fit: pw.BoxFit.contain,
                    ),
                  ),
                ),
              ],
            ),
          );
          attachedCount++;
        } catch (_) {
          warnings.add(
            '${entry.member.displayName} (${d.documentType}): Datei konnte nicht geladen werden.',
          );
        }
      }
    }

    final pdfBytes = await _renderBasePdf(
      fs: fs,
      profile: profile,
      schoolName: schoolName,
      year: year,
      exportDateStr: exportDateStr,
      sections: sections,
      appendixEntries: appendixEntries,
      complianceByMemberId: complianceByMemberId,
      fallbackImagePages: imagePages,
    );

    return AuditPdfExportResult(
      pdfBytes: pdfBytes,
      attachedDocumentCount: attachedCount,
      warnings: warnings,
      mergedViaServer: false,
    );
  }
}
