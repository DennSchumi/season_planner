import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:season_planner/core/appwrite_config.dart';
import 'package:season_planner/core/data/enums/event_role_enum.dart';
import 'package:season_planner/core/data/models/qualification_model.dart';
import 'package:season_planner/core/data/models/team_role_model.dart';
import 'package:season_planner/core/services/audit_log_service.dart';
import 'package:season_planner/core/services/auth_service.dart';
import 'package:season_planner/core/services/security_privacy_service.dart';

class QualificationService {
  static final QualificationService _instance =
      QualificationService._internal();
  factory QualificationService() => _instance;
  QualificationService._internal();

  Client get _client => AuthService().client;

  late final TablesDB _tablesDB = TablesDB(_client);
  late final Storage _storage = Storage(_client);

  // ==================== QUALIFIKATIONEN (CRUD) ====================

  Future<List<Qualification>> listQualifications(String flightSchoolId) async {
    try {
      final cfg = AppwriteConfig();
      final res = await _tablesDB.listRows(
        databaseId: cfg.mainDatabaseId,
        tableId: cfg.qualificationsTableId,
        queries: [
          Query.equal('flight_school_id', flightSchoolId),
          Query.limit(100),
        ],
      );
      return res.rows.map((r) => Qualification.fromMap(r.$id, r.data)).toList();
    } catch (e) {
      debugPrint('listQualifications error: $e');
      return [];
    }
  }

  /// Legt die 4 Standard-Qualifikationen an, falls eine Flugschule noch keine hat.
  Future<List<Qualification>> ensureDefaultQualifications(
    String flightSchoolId,
  ) async {
    final existing = await listQualifications(flightSchoolId);
    if (existing.isNotEmpty) return existing;

    final created = <Qualification>[];
    final cfg = AppwriteConfig();
    for (final qualName in kDefaultQualificationNames) {
      try {
        final row = await _tablesDB.createRow(
          databaseId: cfg.mainDatabaseId,
          tableId: cfg.qualificationsTableId,
          rowId: ID.unique(),
          data: {
            'flight_school_id': flightSchoolId,
            'name': qualName,
            'is_default': true,
            'required_documents': <String>[],
          },
          permissions: SecurityPrivacyService.schoolReadAdminWritePerms(
            flightSchoolId,
          ),
        );
        created.add(Qualification.fromMap(row.$id, row.data));
      } catch (e) {
        debugPrint('ensureDefaultQualifications($qualName) error: $e');
      }
    }
    return created;
  }

  Future<Qualification?> createQualification({
    required String flightSchoolId,
    required String name,
    List<String> requiredDocuments = const [],
    bool isDefault = false,
  }) async {
    try {
      final cfg = AppwriteConfig();
      final row = await _tablesDB.createRow(
        databaseId: cfg.mainDatabaseId,
        tableId: cfg.qualificationsTableId,
        rowId: ID.unique(),
        data: {
          'flight_school_id': flightSchoolId,
          'name': name.trim(),
          'is_default': isDefault,
          'required_documents': requiredDocuments,
        },
        permissions: SecurityPrivacyService.schoolReadAdminWritePerms(
          flightSchoolId,
        ),
      );
      await AuditLogService().log(
        flightSchoolId: flightSchoolId,
        action: 'Qualifikation erstellt',
        details:
            'Qualifikation „${name.trim()}“ (Nachweise: ${requiredDocuments.isEmpty ? "keine" : requiredDocuments.join(', ')})',
      );
      return Qualification.fromMap(row.$id, row.data);
    } catch (e) {
      debugPrint('createQualification error: $e');
      return null;
    }
  }

  Future<bool> updateQualification({
    required Qualification qualification,
    required String name,
    required List<String> requiredDocuments,
  }) async {
    try {
      final cfg = AppwriteConfig();
      await _tablesDB.updateRow(
        databaseId: cfg.mainDatabaseId,
        tableId: cfg.qualificationsTableId,
        rowId: qualification.id,
        data: {
          'name': name.trim(),
          'required_documents': requiredDocuments,
        },
      );
      await AuditLogService().log(
        flightSchoolId: qualification.flightSchoolId,
        action: 'Qualifikation aktualisiert',
        details:
            'Qualifikation „${name.trim()}“ (Nachweise: ${requiredDocuments.isEmpty ? "keine" : requiredDocuments.join(', ')})',
      );
      return true;
    } catch (e) {
      debugPrint('updateQualification error: $e');
      return false;
    }
  }

  Future<bool> deleteQualification(Qualification qualification) async {
    try {
      final cfg = AppwriteConfig();
      await _tablesDB.deleteRow(
        databaseId: cfg.mainDatabaseId,
        tableId: cfg.qualificationsTableId,
        rowId: qualification.id,
      );
      await AuditLogService().log(
        flightSchoolId: qualification.flightSchoolId,
        action: 'Qualifikation gelöscht',
        details: 'Qualifikation „${qualification.name}“ entfernt',
      );
      return true;
    } catch (e) {
      debugPrint('deleteQualification error: $e');
      return false;
    }
  }

  // ==================== QUALIFIKATIONS-ANFRAGEN (NUTZER & ADMIN) ====================

  /// Nutzer fragt eine Qualifikation bei der Flugschule an.
  Future<bool> requestQualification({
    required String membershipId,
    required String flightSchoolId,
    required List<String> currentRequestedIds,
    required String qualificationId,
    required String qualificationName,
  }) async {
    try {
      final cfg = AppwriteConfig();
      final next = {...currentRequestedIds, qualificationId}.toList();
      await _tablesDB.updateRow(
        databaseId: cfg.mainDatabaseId,
        tableId: cfg.membershipsId,
        rowId: membershipId,
        data: {'requested_qualifications': next},
      );
      await AuditLogService().log(
        flightSchoolId: flightSchoolId,
        action: 'Qualifikation angefragt',
        details: 'Qualifikation „$qualificationName“ zur Eintragung angefragt',
      );
      return true;
    } catch (e) {
      debugPrint('requestQualification error: $e');
      return false;
    }
  }

  /// Nutzer zieht eine offene Qualifikations-Anfrage zurück.
  Future<bool> withdrawQualificationRequest({
    required String membershipId,
    required List<String> currentRequestedIds,
    required String qualificationId,
  }) async {
    try {
      final cfg = AppwriteConfig();
      final next =
          currentRequestedIds.where((id) => id != qualificationId).toList();
      await _tablesDB.updateRow(
        databaseId: cfg.mainDatabaseId,
        tableId: cfg.membershipsId,
        rowId: membershipId,
        data: {'requested_qualifications': next},
      );
      return true;
    } catch (e) {
      debugPrint('withdrawQualificationRequest error: $e');
      return false;
    }
  }

  /// Admin genehmigt eine angefragte Qualifikation (verschiebt sie in `qualifications`).
  Future<bool> approveQualificationRequest({
    required String membershipId,
    required String flightSchoolId,
    required String memberName,
    required List<String> currentQualificationIds,
    required List<String> currentRequestedIds,
    required String qualificationId,
    required String qualificationName,
  }) async {
    try {
      final cfg = AppwriteConfig();
      final nextQuals = {...currentQualificationIds, qualificationId}.toList();
      final nextReqs =
          currentRequestedIds.where((id) => id != qualificationId).toList();
      await _tablesDB.updateRow(
        databaseId: cfg.mainDatabaseId,
        tableId: cfg.membershipsId,
        rowId: membershipId,
        data: {
          'qualifications': nextQuals,
          'requested_qualifications': nextReqs,
        },
      );
      await AuditLogService().log(
        flightSchoolId: flightSchoolId,
        action: 'Qualifikation zugeteilt',
        details: '$memberName → Qualifikation „$qualificationName“ bestätigt',
      );
      return true;
    } catch (e) {
      debugPrint('approveQualificationRequest error: $e');
      return false;
    }
  }

  /// Admin lehnt eine angefragte Qualifikation ab.
  Future<bool> rejectQualificationRequest({
    required String membershipId,
    required String flightSchoolId,
    required String memberName,
    required List<String> currentRequestedIds,
    required String qualificationId,
    required String qualificationName,
  }) async {
    try {
      final cfg = AppwriteConfig();
      final nextReqs =
          currentRequestedIds.where((id) => id != qualificationId).toList();
      await _tablesDB.updateRow(
        databaseId: cfg.mainDatabaseId,
        tableId: cfg.membershipsId,
        rowId: membershipId,
        data: {'requested_qualifications': nextReqs},
      );
      await AuditLogService().log(
        flightSchoolId: flightSchoolId,
        action: 'Qualifikationsanfrage abgelehnt',
        details: '$memberName → Anfrage für „$qualificationName“ abgelehnt',
      );
      return true;
    } catch (e) {
      debugPrint('rejectQualificationRequest error: $e');
      return false;
    }
  }

  // ==================== TEAM-ROLLEN / EINSATZPOSITIONEN (CRUD) ====================

  Future<List<TeamRole>> listTeamRoles(String flightSchoolId) async {
    try {
      final cfg = AppwriteConfig();
      final res = await _tablesDB.listRows(
        databaseId: cfg.mainDatabaseId,
        tableId: cfg.teamRolesTableId,
        queries: [
          Query.equal('flight_school_id', flightSchoolId),
          Query.limit(100),
        ],
      );
      return res.rows.map((r) => TeamRole.fromMap(r.$id, r.data)).toList();
    } catch (e) {
      debugPrint('listTeamRoles error: $e');
      return [];
    }
  }

  /// Legt die 5 Standard-Einsatzrollen an, falls eine Flugschule noch keine Rollen hat.
  Future<List<TeamRole>> ensureDefaultRoles(String flightSchoolId) async {
    final existing = await listTeamRoles(flightSchoolId);
    if (existing.isNotEmpty) return existing;

    final created = <TeamRole>[];
    final cfg = AppwriteConfig();
    for (final roleName in kDefaultTeamRoleNames) {
      try {
        final row = await _tablesDB.createRow(
          databaseId: cfg.mainDatabaseId,
          tableId: cfg.teamRolesTableId,
          rowId: ID.unique(),
          data: {
            'flight_school_id': flightSchoolId,
            'name': roleName,
            'is_default': true,
            'required_qualification_ids': <String>[],
            'require_all_qualifications': true,
            'checklist_id': '',
            'instruction_ids': <String>[],
          },
          permissions: SecurityPrivacyService.schoolReadAdminWritePerms(
            flightSchoolId,
          ),
        );
        created.add(TeamRole.fromMap(row.$id, row.data));
      } catch (e) {
        debugPrint('ensureDefaultRoles($roleName) error: $e');
      }
    }
    return created;
  }

  Future<TeamRole?> createTeamRole({
    required String flightSchoolId,
    required String name,
    List<String> requiredQualificationIds = const [],
    bool requireAllQualifications = true,
    String? checklistId,
    List<String> instructionIds = const [],
    bool isDefault = false,
  }) async {
    try {
      final cfg = AppwriteConfig();
      final row = await _tablesDB.createRow(
        databaseId: cfg.mainDatabaseId,
        tableId: cfg.teamRolesTableId,
        rowId: ID.unique(),
        data: {
          'flight_school_id': flightSchoolId,
          'name': name.trim(),
          'is_default': isDefault,
          'required_qualification_ids': requiredQualificationIds,
          'require_all_qualifications': requireAllQualifications,
          'checklist_id': checklistId ?? '',
          'instruction_ids': instructionIds,
        },
        permissions: SecurityPrivacyService.schoolReadAdminWritePerms(
          flightSchoolId,
        ),
      );
      await AuditLogService().log(
        flightSchoolId: flightSchoolId,
        action: 'Teamrolle erstellt',
        details: 'Einsatzrolle „${name.trim()}“ angelegt',
      );
      return TeamRole.fromMap(row.$id, row.data);
    } catch (e) {
      debugPrint('createTeamRole error: $e');
      return null;
    }
  }

  Future<bool> updateTeamRole({
    required TeamRole role,
    required String name,
    List<String> requiredQualificationIds = const [],
    bool requireAllQualifications = true,
    String? checklistId,
    List<String> instructionIds = const [],
  }) async {
    try {
      final cfg = AppwriteConfig();
      await _tablesDB.updateRow(
        databaseId: cfg.mainDatabaseId,
        tableId: cfg.teamRolesTableId,
        rowId: role.id,
        data: {
          'name': name.trim(),
          'required_qualification_ids': requiredQualificationIds,
          'require_all_qualifications': requireAllQualifications,
          'checklist_id': checklistId ?? '',
          'instruction_ids': instructionIds,
        },
      );
      await AuditLogService().log(
        flightSchoolId: role.flightSchoolId,
        action: 'Teamrolle aktualisiert',
        details: 'Einsatzrolle „${name.trim()}“ bearbeitet',
      );
      return true;
    } catch (e) {
      debugPrint('updateTeamRole error: $e');
      return false;
    }
  }

  Future<bool> deleteTeamRole(TeamRole role) async {
    try {
      final cfg = AppwriteConfig();
      await _tablesDB.deleteRow(
        databaseId: cfg.mainDatabaseId,
        tableId: cfg.teamRolesTableId,
        rowId: role.id,
      );
      await AuditLogService().log(
        flightSchoolId: role.flightSchoolId,
        action: 'Teamrolle gelöscht',
        details: 'Rolle „${role.name}“ entfernt',
      );
      return true;
    } catch (e) {
      debugPrint('deleteTeamRole error: $e');
      return false;
    }
  }

  // ==================== QUALIFIKATIONSDOKUMENTE ====================

  Future<List<QualificationDocument>> listUserDocuments(String userId) async {
    try {
      final cfg = AppwriteConfig();
      final res = await _tablesDB.listRows(
        databaseId: cfg.mainDatabaseId,
        tableId: cfg.qualificationDocumentsTableId,
        queries: [
          Query.equal('user_id', userId),
          Query.limit(200),
        ],
      );
      return res.rows
          .map((r) => QualificationDocument.fromMap(r.$id, r.data))
          .toList();
    } catch (e) {
      debugPrint('listUserDocuments error: $e');
      return [];
    }
  }

  static const Set<String> _allowedDocumentExtensions = {
    'pdf',
    'png',
    'jpg',
    'jpeg',
    'webp',
  };
  static const int _maxDocumentBytes = 10 * 1024 * 1024; // 10 MB

  Future<QualificationDocument?> uploadDocument({
    required String userId,
    required String documentType,
    required String title,
    required Uint8List fileBytes,
    required String fileName,
    DateTime? issuedAt,
    DateTime? expiresAt,
    List<String> submitToFlightSchoolIds = const [],
  }) async {
    final extIdx = fileName.lastIndexOf('.');
    final ext = extIdx >= 0 ? fileName.substring(extIdx + 1).toLowerCase() : '';
    if (!_allowedDocumentExtensions.contains(ext)) {
      throw Exception(
        'Dateityp „.$ext“ nicht erlaubt. Unterstützt werden: PDF, PNG, JPG, JPEG, WEBP.',
      );
    }
    if (fileBytes.isEmpty) {
      throw Exception('Die ausgewählte Datei ist leer.');
    }
    if (fileBytes.length > _maxDocumentBytes) {
      throw Exception('Die Datei darf maximal 10 MB groß sein.');
    }

    final cfg = AppwriteConfig();
    String? uploadedFileId;
    try {
      final ownerPerms = SecurityPrivacyService.ownerOnlyPerms(userId);
      final uploaded = await _storage.createFile(
        bucketId: cfg.qualificationDocumentsBucketId,
        fileId: ID.unique(),
        file: InputFile.fromBytes(bytes: fileBytes, filename: fileName),
        permissions: ownerPerms,
      );
      uploadedFileId = uploaded.$id;

      final row = await _tablesDB.createRow(
        databaseId: cfg.mainDatabaseId,
        tableId: cfg.qualificationDocumentsTableId,
        rowId: ID.unique(),
        data: {
          'user_id': userId,
          'document_type': documentType.trim(),
          'title': title.trim().isEmpty ? documentType.trim() : title.trim(),
          'file_id': uploaded.$id,
          'file_name': fileName,
          if (issuedAt != null) 'issued_at': issuedAt.toIso8601String(),
          if (expiresAt != null) 'expires_at': expiresAt.toIso8601String(),
        },
        permissions: ownerPerms,
      );

      final doc = QualificationDocument.fromMap(row.$id, row.data);

      for (final schoolId in submitToFlightSchoolIds) {
        await submitDocumentToSchool(
          document: doc,
          flightSchoolId: schoolId,
        );
      }

      return doc;
    } catch (e) {
      // Verwaiste Storage-Datei bei fehlgeschlagenem DB-Eintrag wieder aufräumen
      if (uploadedFileId != null) {
        try {
          await _storage.deleteFile(
            bucketId: cfg.qualificationDocumentsBucketId,
            fileId: uploadedFileId,
          );
        } catch (_) {}
      }
      debugPrint('uploadDocument error: $e');
      rethrow;
    }
  }

  /// Lädt die Rohdaten (PDF / Bild) eines Qualifikationsdokuments über den
  /// authentifizierten Appwrite-Storage-Client für die In-App-Vorschau.
  Future<Uint8List?> loadDocumentBytes(String fileId) async {
    if (fileId.trim().isEmpty) return null;
    try {
      final cfg = AppwriteConfig();
      return await _storage.getFileView(
        bucketId: cfg.qualificationDocumentsBucketId,
        fileId: fileId,
      );
    } catch (e) {
      debugPrint('loadDocumentBytes error: $e');
      return null;
    }
  }

  /// Aktualisiert das Ablaufdatum („Gültig bis“) eines Nachweis-Dokuments
  /// (z. B. durch einen Flugschul-Admin bei der Dokumentenprüfung).
  Future<QualificationDocument?> updateDocumentExpiry({
    required QualificationDocument doc,
    required DateTime expiresAt,
    required String flightSchoolId,
  }) async {
    try {
      final cfg = AppwriteConfig();
      final row = await _tablesDB.updateRow(
        databaseId: cfg.mainDatabaseId,
        tableId: cfg.qualificationDocumentsTableId,
        rowId: doc.id,
        data: {
          'expires_at': expiresAt.toIso8601String(),
        },
      );
      final updated = QualificationDocument.fromMap(row.$id, row.data);
      final fmt =
          '${expiresAt.day.toString().padLeft(2, '0')}.${expiresAt.month.toString().padLeft(2, '0')}.${expiresAt.year}';
      await AuditLogService().log(
        flightSchoolId: flightSchoolId,
        action: 'Dokument-Gültigkeit geändert',
        details: '„${doc.documentType}“ (${doc.fileName}) · Gültig bis: $fmt',
      );
      return updated;
    } catch (e) {
      debugPrint('updateDocumentExpiry error: $e');
      return null;
    }
  }

  Future<bool> deleteDocument(QualificationDocument doc) async {
    try {
      final cfg = AppwriteConfig();
      // zugehörige Freigaben löschen
      final approvals = await _tablesDB.listRows(
        databaseId: cfg.mainDatabaseId,
        tableId: cfg.qualificationApprovalsTableId,
        queries: [Query.equal('document_id', doc.id), Query.limit(100)],
      );
      for (final a in approvals.rows) {
        await _tablesDB.deleteRow(
          databaseId: cfg.mainDatabaseId,
          tableId: cfg.qualificationApprovalsTableId,
          rowId: a.$id,
        );
      }
      await _tablesDB.deleteRow(
        databaseId: cfg.mainDatabaseId,
        tableId: cfg.qualificationDocumentsTableId,
        rowId: doc.id,
      );
      try {
        await _storage.deleteFile(
          bucketId: cfg.qualificationDocumentsBucketId,
          fileId: doc.fileId,
        );
      } catch (_) {}
      return true;
    } catch (e) {
      debugPrint('deleteDocument error: $e');
      return false;
    }
  }

  // ==================== FREIGABEN (APPROVALS) ====================

  Future<QualificationApproval?> submitDocumentToSchool({
    required QualificationDocument document,
    required String flightSchoolId,
  }) async {
    try {
      final cfg = AppwriteConfig();
      // Prüfen, ob schon eine Freigabe für dieses Dokument + diese Schule existiert
      final existing = await _tablesDB.listRows(
        databaseId: cfg.mainDatabaseId,
        tableId: cfg.qualificationApprovalsTableId,
        queries: [
          Query.equal('document_id', document.id),
          Query.equal('flight_school_id', flightSchoolId),
          Query.limit(1),
        ],
      );
      if (existing.rows.isNotEmpty) {
        final row = await _tablesDB.updateRow(
          databaseId: cfg.mainDatabaseId,
          tableId: cfg.qualificationApprovalsTableId,
          rowId: existing.rows.first.$id,
          data: {
            'status': ApprovalStatusEnum.submitted.name,
            'comment': '',
          },
        );
        await SecurityPrivacyService().syncDocumentPermissions(document.id);
        return QualificationApproval.fromMap(row.$id, row.data);
      }

      final row = await _tablesDB.createRow(
        databaseId: cfg.mainDatabaseId,
        tableId: cfg.qualificationApprovalsTableId,
        rowId: ID.unique(),
        data: {
          'document_id': document.id,
          'user_id': document.userId,
          'flight_school_id': flightSchoolId,
          'document_type': document.documentType,
          'status': ApprovalStatusEnum.submitted.name,
        },
        permissions: SecurityPrivacyService.ownerAndSchoolAdminPerms(
          userId: document.userId,
          flightSchoolId: flightSchoolId,
          allowOwnerDelete: true,
        ),
      );
      await SecurityPrivacyService().syncDocumentPermissions(document.id);
      return QualificationApproval.fromMap(row.$id, row.data);
    } catch (e) {
      debugPrint('submitDocumentToSchool error: $e');
      return null;
    }
  }

  Future<List<QualificationApproval>> listUserApprovals(String userId) async {
    try {
      final cfg = AppwriteConfig();
      final res = await _tablesDB.listRows(
        databaseId: cfg.mainDatabaseId,
        tableId: cfg.qualificationApprovalsTableId,
        queries: [
          Query.equal('user_id', userId),
          Query.limit(200),
        ],
      );
      return res.rows
          .map((r) => QualificationApproval.fromMap(r.$id, r.data))
          .toList();
    } catch (e) {
      debugPrint('listUserApprovals error: $e');
      return [];
    }
  }

  Future<List<QualificationApproval>> listSchoolApprovals(
    String flightSchoolId, {
    ApprovalStatusEnum? status,
  }) async {
    try {
      final cfg = AppwriteConfig();
      final queries = <String>[
        Query.equal('flight_school_id', flightSchoolId),
        if (status != null) Query.equal('status', status.name),
        Query.limit(200),
      ];
      final res = await _tablesDB.listRows(
        databaseId: cfg.mainDatabaseId,
        tableId: cfg.qualificationApprovalsTableId,
        queries: queries,
      );
      return res.rows
          .map((r) => QualificationApproval.fromMap(r.$id, r.data))
          .toList();
    } catch (e) {
      debugPrint('listSchoolApprovals error: $e');
      return [];
    }
  }

  Future<QualificationDocument?> getDocumentById(String documentId) async {
    try {
      final cfg = AppwriteConfig();
      final row = await _tablesDB.getRow(
        databaseId: cfg.mainDatabaseId,
        tableId: cfg.qualificationDocumentsTableId,
        rowId: documentId,
      );
      return QualificationDocument.fromMap(row.$id, row.data);
    } catch (e) {
      debugPrint('getDocumentById error: $e');
      return null;
    }
  }

  Future<bool> reviewApproval({
    required QualificationApproval approval,
    required ApprovalStatusEnum decision,
    String comment = '',
  }) async {
    return SecurityPrivacyService().runAdminAction(
      flightSchoolId: approval.flightSchoolId,
      operation: 'reviewApproval',
      params: {
        'approvalId': approval.id,
        'decision': decision.name,
        'comment': comment.trim(),
      },
    );
  }

  /// Prüft für Warnhinweise (Soft-Warning), ob ein Mitglied für eine Teamrolle:
  /// 1) die geforderten Qualifikationen (UND / ODER) vom Admin zugeteilt bekommen hat, und
  /// 2) die zugehörigen Pflichtnachweise dieser Qualifikationen gültig & bestätigt vorliegen hat.
  Future<QualificationCheckResult> checkQualification({
    required String userId,
    required String flightSchoolId,
    required String roleName,
    required List<TeamRole> schoolRoles,
    required List<Qualification> schoolQualifications,
    required List<String> memberQualificationIds,
  }) async {
    final normalized = EventRoleEnum.displayLabel(roleName).toLowerCase();
    final matchingRoles = schoolRoles.where((r) =>
        r.name.toLowerCase() == roleName.toLowerCase() ||
        r.name.toLowerCase() == normalized);
    if (matchingRoles.isEmpty) {
      return const QualificationCheckResult(isFullyQualified: true);
    }
    final role = matchingRoles.first;
    if (role.requiredQualificationIds.isEmpty) {
      return const QualificationCheckResult(isFullyQualified: true);
    }

    final qualById = {for (final q in schoolQualifications) q.id: q};
    final reqQuals = role.requiredQualificationIds
        .map((id) => qualById[id])
        .whereType<Qualification>()
        .toList();
    if (reqQuals.isEmpty) {
      return const QualificationCheckResult(isFullyQualified: true);
    }

    final ownedQuals = reqQuals
        .where((q) => memberQualificationIds.contains(q.id))
        .toList();
    final missingQuals = reqQuals
        .where((q) => !memberQualificationIds.contains(q.id))
        .toList();

    final List<String> missingQualNames;
    final List<Qualification> qualsToCheckDocsFor;

    if (role.requireAllQualifications) {
      missingQualNames = missingQuals.map((q) => q.name).toList();
      qualsToCheckDocsFor = reqQuals;
    } else {
      final satisfied = ownedQuals.isNotEmpty;
      missingQualNames =
          satisfied ? const [] : reqQuals.map((q) => q.name).toList();
      qualsToCheckDocsFor = satisfied ? ownedQuals : reqQuals;
    }

    // Alle geforderten Dokumenttypen aus den relevanten Qualifikationen sammeln
    final requiredDocs = <String>{};
    for (final q in qualsToCheckDocsFor) {
      requiredDocs.addAll(q.requiredDocuments);
    }

    if (requiredDocs.isEmpty) {
      return QualificationCheckResult(
        isFullyQualified: missingQualNames.isEmpty,
        missingQualifications: missingQualNames,
        requireAllQualifications: role.requireAllQualifications,
      );
    }

    final parallelData = await Future.wait([
      listUserDocuments(userId),
      listUserApprovals(userId),
    ]);
    final docs = parallelData[0] as List<QualificationDocument>;
    final approvals = (parallelData[1] as List<QualificationApproval>)
        .where((a) => a.flightSchoolId == flightSchoolId)
        .toList();
    final docsById = {for (final d in docs) d.id: d};

    final missing = <String>[];
    final pending = <String>[];
    final expired = <String>[];

    for (final reqType in requiredDocs) {
      final matchingApprovals = approvals
          .where((a) => a.documentType.toLowerCase() == reqType.toLowerCase())
          .toList();

      if (matchingApprovals.isEmpty) {
        missing.add(reqType);
        continue;
      }

      final approvedOnes = matchingApprovals
          .where((a) => a.status == ApprovalStatusEnum.approved)
          .toList();

      if (approvedOnes.isEmpty) {
        final hasSubmitted = matchingApprovals
            .any((a) => a.status == ApprovalStatusEnum.submitted);
        if (hasSubmitted) {
          pending.add(reqType);
        } else {
          missing.add(reqType);
        }
        continue;
      }

      final hasValidUnexpired = approvedOnes.any((a) {
        final doc = docsById[a.documentId];
        return doc != null && !doc.isExpired;
      });
      if (!hasValidUnexpired) {
        expired.add(reqType);
      }
    }

    return QualificationCheckResult(
      isFullyQualified: missingQualNames.isEmpty &&
          missing.isEmpty &&
          pending.isEmpty &&
          expired.isEmpty,
      missingQualifications: missingQualNames,
      requireAllQualifications: role.requireAllQualifications,
      missingDocuments: missing,
      pendingDocuments: pending,
      expiredDocuments: expired,
    );
  }
}
