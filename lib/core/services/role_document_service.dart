import 'dart:convert';
import 'package:appwrite/appwrite.dart';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:season_planner/core/appwrite_config.dart';
import 'package:season_planner/core/data/models/role_document_model.dart';
import 'package:season_planner/core/services/appwrite_pagination.dart';
import 'package:season_planner/core/services/audit_log_service.dart';
import 'package:season_planner/core/services/auth_service.dart';
import 'package:season_planner/core/services/security_privacy_service.dart';

class MarkdownImportResult {
  final String suggestedTitle;
  final String processedMd;
  final List<String> assetFileIds;
  final int uploadedImageCount;
  final List<String> missingImageRefs;

  const MarkdownImportResult({
    required this.suggestedTitle,
    required this.processedMd,
    required this.assetFileIds,
    required this.uploadedImageCount,
    required this.missingImageRefs,
  });
}

class RoleDocumentService {
  static final RoleDocumentService _instance = RoleDocumentService._internal();
  factory RoleDocumentService() => _instance;
  RoleDocumentService._internal();

  Client get _client => AuthService().client;

  late final TablesDB _tablesDB = TablesDB(_client);
  late final Storage _storage = Storage(_client);

  static const _imageExtensions = {'png', 'jpg', 'jpeg', 'webp', 'gif', 'svg'};

  // ==================== BIBLIOTHEK (ANWEISUNGEN & CHECKLISTEN) ====================

  Future<List<RoleDocument>> listSchoolDocuments(
    String flightSchoolId, {
    RoleDocumentType? type,
  }) async {
    try {
      final cfg = AppwriteConfig();
      final res = await _tablesDB.listRows(
        databaseId: cfg.seasonPlannerDatabaseId,
        tableId: cfg.roleDocumentsTableId,
        queries: [
          Query.equal('flight_school_id', flightSchoolId),
          if (type != null) Query.equal('doc_type', type.name),
          Query.limit(200),
        ],
      );
      final list = res.rows
          .map((r) => RoleDocument.fromMap(r.$id, r.data))
          .toList()
        ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      return list;
    } catch (e) {
      debugPrint('listSchoolDocuments error: $e');
      return [];
    }
  }

  Future<RoleDocument?> getDocumentById(String id) async {
    if (id.trim().isEmpty) return null;
    try {
      final cfg = AppwriteConfig();
      final row = await _tablesDB.getRow(
        databaseId: cfg.seasonPlannerDatabaseId,
        tableId: cfg.roleDocumentsTableId,
        rowId: id,
      );
      return RoleDocument.fromMap(row.$id, row.data);
    } catch (e) {
      debugPrint('getDocumentById($id) error: $e');
      return null;
    }
  }

  Future<List<RoleDocument>> getDocumentsByIds(List<String> ids) async {
    final cleaned = ids.where((e) => e.trim().isNotEmpty).toSet().toList();
    if (cleaned.isEmpty) return [];
    try {
      final cfg = AppwriteConfig();
      final byId = <String, RoleDocument>{};
      for (final chunk in chunkList(cleaned, size: 100)) {
        final res = await _tablesDB.listRows(
          databaseId: cfg.seasonPlannerDatabaseId,
          tableId: cfg.roleDocumentsTableId,
          queries: [
            Query.equal('\$id', chunk),
            Query.limit(chunk.length),
          ],
        );
        for (final row in res.rows) {
          byId[row.$id] = RoleDocument.fromMap(row.$id, row.data);
        }
      }
      return cleaned
          .map((id) => byId[id])
          .whereType<RoleDocument>()
          .toList();
    } catch (e) {
      debugPrint('getDocumentsByIds error: $e');
      return [];
    }
  }

  /// Importiert eine `.md`-Datei (einzeln, zusammen mit Bilddateien oder als `.zip`-Paket).
  /// Alle lokalen Bilder werden automatisch nach `instruction_assets` hochgeladen und
  /// die Bildpfade im Markdown direkt durch Appwrite-URLs ersetzt.
  Future<MarkdownImportResult> importMarkdownBundle({
    required List<({String name, Uint8List bytes})> pickedFiles,
  }) async {
    if (pickedFiles.isEmpty) {
      throw Exception('Keine Dateien ausgewählt.');
    }

    String? mdFileName;
    Uint8List? mdBytes;

    // Zuordnung: normalisierter relativer Pfad & Dateiname -> (filename, bytes)
    final imageByExactPath = <String, ({String name, Uint8List bytes})>{};
    final imageByBaseName = <String, ({String name, Uint8List bytes})>{};

    void registerAsset(String rawPath, Uint8List bytes) {
      final normalized = _normalizePath(rawPath);
      if (normalized.isEmpty) return;
      final baseName = _baseName(normalized);
      if (baseName.startsWith('.') || normalized.contains('__macosx/')) return;
      final ext = _extension(baseName);
      if (ext == 'md' || ext == 'markdown') {
        // Erste gefundene Markdown-Datei übernehmen (bevorzugt Root-Level)
        if (mdBytes == null ||
            (!normalized.contains('/') && (mdFileName?.contains('/') ?? false))) {
          mdFileName = normalized;
          mdBytes = bytes;
        }
      } else if (_imageExtensions.contains(ext)) {
        final item = (name: baseName, bytes: bytes);
        imageByExactPath[normalized.toLowerCase()] = item;
        imageByBaseName[baseName.toLowerCase()] = item;
      }
    }

    for (final f in pickedFiles) {
      final ext = _extension(f.name);
      if (ext == 'zip') {
        final archive = ZipDecoder().decodeBytes(f.bytes);
        for (final entry in archive.files) {
          if (!entry.isFile) continue;
          registerAsset(entry.name, Uint8List.fromList(entry.content));
        }
      } else {
        registerAsset(f.name, f.bytes);
      }
    }

    if (mdBytes == null) {
      throw Exception(
        'Keine Markdown-Datei (.md) gefunden. Bitte wähle eine .md-Datei oder eine .zip mit enthaltener .md-Datei aus.',
      );
    }

    // UTF-8 (mit Fallback auf Latin-1) dekodieren
    String content;
    try {
      content = utf8.decode(mdBytes!, allowMalformed: false);
    } catch (_) {
      content = latin1.decode(mdBytes!);
    }
    // UTF-8 BOM entfernen
    if (content.startsWith('\uFEFF')) {
      content = content.substring(1);
    }

    final cfg = AppwriteConfig();
    final uploadedUrlByKey = <String, String>{};
    final assetFileIds = <String>[];
    final missingImageRefs = <String>[];

    Future<String?> resolveAndUploadImage(String rawRef) async {
      final trimmed = rawRef.trim();
      if (trimmed.isEmpty) return null;
      final lower = trimmed.toLowerCase();
      if (lower.startsWith('http://') ||
          lower.startsWith('https://') ||
          lower.startsWith('data:')) {
        return null; // Bereits extern oder Base64
      }

      // URL-Encoding (z. B. %20) und Query/Fragment entfernen
      final withoutFrag = trimmed.split('#').first.split('?').first;
      String decodedPath;
      try {
        decodedPath = Uri.decodeFull(withoutFrag);
      } catch (_) {
        decodedPath = withoutFrag;
      }

      final normalized = _normalizePath(decodedPath).toLowerCase();
      final baseName = _baseName(normalized).toLowerCase();

      // Schon hochgeladen?
      if (uploadedUrlByKey.containsKey(normalized)) {
        return uploadedUrlByKey[normalized];
      }
      if (uploadedUrlByKey.containsKey(baseName)) {
        return uploadedUrlByKey[baseName];
      }

      final match =
          imageByExactPath[normalized] ?? imageByBaseName[baseName];
      if (match == null) {
        if (!missingImageRefs.contains(trimmed)) {
          missingImageRefs.add(trimmed);
        }
        return null;
      }

      final uploaded = await _storage.createFile(
        bucketId: cfg.instructionAssetsBucketId,
        fileId: ID.unique(),
        file: InputFile.fromBytes(bytes: match.bytes, filename: match.name),
      );
      assetFileIds.add(uploaded.$id);
      final url = cfg.fileViewUrl(cfg.instructionAssetsBucketId, uploaded.$id);
      uploadedUrlByKey[normalized] = url;
      uploadedUrlByKey[baseName] = url;
      return url;
    }

    // 1) Obsidian Wiki-Embeds: ![[bild.png]] oder ![[images/bild.png|400]]
    final obsidianImgRegex = RegExp(r'!\[\[([^\]|]+)(?:\|([^\]]+))?\]\]');
    final obsidianMatches = obsidianImgRegex.allMatches(content).toList();
    for (final m in obsidianMatches.reversed) {
      final rawTarget = m.group(1)!.trim();
      final altText = (m.group(2) ?? _baseName(rawTarget)).trim();
      final url = await resolveAndUploadImage(rawTarget);
      if (url != null) {
        content = content.replaceRange(m.start, m.end, '![$altText]($url)');
      }
    }

    // 2) Standard Markdown-Bilder: ![Alt](pfad/bild.png "optionaler Titel")
    final mdImgRegex = RegExp(
      r'!\[([^\]]*)\]\(\s*<?([^)\s>]+)>?(\s+"[^"]*")?\s*\)',
    );
    final mdMatches = mdImgRegex.allMatches(content).toList();
    for (final m in mdMatches.reversed) {
      final alt = m.group(1) ?? '';
      final rawTarget = m.group(2) ?? '';
      final titlePart = m.group(3) ?? '';
      final url = await resolveAndUploadImage(rawTarget);
      if (url != null) {
        content = content.replaceRange(
          m.start,
          m.end,
          '![$alt]($url$titlePart)',
        );
      }
    }

    // 3) HTML <img src="pfad/bild.png" ...> in reines Markdown umwandeln
    final htmlImgRegex = RegExp(
      r'''<img\b[^>]*\bsrc\s*=\s*["']([^"']+)["'][^>]*>''',
      caseSensitive: false,
    );
    final htmlAltRegex = RegExp(
      r'''\balt\s*=\s*["']([^"']*)["']''',
      caseSensitive: false,
    );
    final htmlMatches = htmlImgRegex.allMatches(content).toList();
    for (final m in htmlMatches.reversed) {
      final fullTag = m.group(0)!;
      final rawTarget = m.group(1)!;
      final alt = htmlAltRegex.firstMatch(fullTag)?.group(1) ?? '';
      final url = await resolveAndUploadImage(rawTarget);
      if (url != null) {
        content = content.replaceRange(m.start, m.end, '![$alt]($url)');
      }
    }

    // Potenziell unsichere HTML-Tags (<script>, <iframe>, <object>, <embed>) entfernen
    content = content.replaceAll(
      RegExp(
        r'<(script|iframe|object|embed|style)\b[^>]*>[\s\S]*?<\/\1>',
        caseSensitive: false,
      ),
      '',
    );
    content = content.replaceAll(
      RegExp(r'<(script|iframe|object|embed)\b[^>]*\/?>', caseSensitive: false),
      '',
    );

    // Titel aus erstem H1 oder Dateinamen ableiten
    String suggestedTitle = _stripExtension(_baseName(mdFileName ?? 'Dokument'));
    final h1Match =
        RegExp(r'^\s*#\s+(.+?)\s*#*\s*$', multiLine: true).firstMatch(content);
    if (h1Match != null && h1Match.group(1)!.trim().isNotEmpty) {
      suggestedTitle = h1Match.group(1)!.trim();
    }

    return MarkdownImportResult(
      suggestedTitle: suggestedTitle,
      processedMd: content,
      assetFileIds: assetFileIds,
      uploadedImageCount: assetFileIds.length,
      missingImageRefs: missingImageRefs,
    );
  }

  Future<RoleDocument?> createDocument({
    required String flightSchoolId,
    required RoleDocumentType docType,
    required String title,
    required String contentMd,
    List<String> assetFileIds = const [],
  }) async {
    final cfg = AppwriteConfig();
    final row = await _tablesDB.createRow(
      databaseId: cfg.seasonPlannerDatabaseId,
      tableId: cfg.roleDocumentsTableId,
      rowId: ID.unique(),
      data: {
        'flight_school_id': flightSchoolId,
        'doc_type': docType.name,
        'title': title.trim(),
        'content_md': contentMd,
        'asset_file_ids': assetFileIds,
        'version': 1,
        'updated_at': DateTime.now().toIso8601String(),
      },
      permissions: SecurityPrivacyService.schoolReadAdminWritePerms(
        flightSchoolId,
      ),
    );

    await AuditLogService().log(
      flightSchoolId: flightSchoolId,
      action: '${docType.label} angelegt',
      details: '„${title.trim()}“ (Version 1)',
    );

    return RoleDocument.fromMap(row.$id, row.data);
  }

  Future<RoleDocument?> updateDocument({
    required RoleDocument existing,
    required String title,
    required String contentMd,
    List<String>? newAssetFileIds,
  }) async {
    final cfg = AppwriteConfig();
    final nextVersion = existing.version + 1;
    final finalAssets = newAssetFileIds ?? existing.assetFileIds;

    final row = await _tablesDB.updateRow(
      databaseId: cfg.seasonPlannerDatabaseId,
      tableId: cfg.roleDocumentsTableId,
      rowId: existing.id,
      data: {
        'title': title.trim(),
        'content_md': contentMd,
        'asset_file_ids': finalAssets,
        'version': nextVersion,
        'updated_at': DateTime.now().toIso8601String(),
      },
    );

    // Falls neue Assets hochgeladen wurden, nicht mehr referenzierte alte Assets aufräumen
    if (newAssetFileIds != null) {
      for (final oldId in existing.assetFileIds) {
        if (!finalAssets.contains(oldId) && !contentMd.contains(oldId)) {
          try {
            await _storage.deleteFile(
              bucketId: cfg.instructionAssetsBucketId,
              fileId: oldId,
            );
          } catch (_) {}
        }
      }
    }

    await AuditLogService().log(
      flightSchoolId: existing.flightSchoolId,
      action: '${existing.docType.label} aktualisiert',
      details: '„${title.trim()}“ (Version $nextVersion)',
    );

    return RoleDocument.fromMap(row.$id, row.data);
  }

  Future<bool> deleteDocument(RoleDocument doc) async {
    try {
      final cfg = AppwriteConfig();
      await _tablesDB.deleteRow(
        databaseId: cfg.seasonPlannerDatabaseId,
        tableId: cfg.roleDocumentsTableId,
        rowId: doc.id,
      );

      for (final fileId in doc.assetFileIds) {
        try {
          await _storage.deleteFile(
            bucketId: cfg.instructionAssetsBucketId,
            fileId: fileId,
          );
        } catch (_) {}
      }

      await AuditLogService().log(
        flightSchoolId: doc.flightSchoolId,
        action: '${doc.docType.label} gelöscht',
        details: '„${doc.title}“ entfernt',
      );
      return true;
    } catch (e) {
      debugPrint('deleteDocument error: $e');
      return false;
    }
  }

  // ==================== CHECKLISTEN-DURCHFÜHRUNG & UNTERSCHRIFT ====================

  Future<ChecklistCompletion?> getCompletionForAssignment(
    String assignmentId,
  ) async {
    if (assignmentId.trim().isEmpty) return null;
    try {
      final cfg = AppwriteConfig();
      final res = await _tablesDB.listRows(
        databaseId: cfg.seasonPlannerDatabaseId,
        tableId: cfg.checklistCompletionsTableId,
        queries: [
          Query.equal('assignment_id', assignmentId),
          Query.limit(1),
        ],
      );
      if (res.rows.isEmpty) return null;
      return ChecklistCompletion.fromMap(res.rows.first.$id, res.rows.first.data);
    } catch (e) {
      debugPrint('getCompletionForAssignment error: $e');
      return null;
    }
  }

  Future<List<ChecklistCompletion>> listCompletionsForUser(
    String userId,
  ) async {
    if (userId.trim().isEmpty) return [];
    try {
      final cfg = AppwriteConfig();
      final rows = await listAllRows(
        _tablesDB,
        databaseId: cfg.seasonPlannerDatabaseId,
        tableId: cfg.checklistCompletionsTableId,
        queries: [Query.equal('user_id', userId)],
      );
      return rows
          .map((r) => ChecklistCompletion.fromMap(r.$id, r.data))
          .toList();
    } catch (e) {
      debugPrint('listCompletionsForUser error: $e');
      return [];
    }
  }

  Future<List<ChecklistCompletion>> listCompletionsForEvent(
    String eventId,
  ) async {
    if (eventId.trim().isEmpty) return [];
    try {
      final cfg = AppwriteConfig();
      final rows = await listAllRows(
        _tablesDB,
        databaseId: cfg.seasonPlannerDatabaseId,
        tableId: cfg.checklistCompletionsTableId,
        queries: [Query.equal('event_id', eventId)],
      );
      return rows
          .map((r) => ChecklistCompletion.fromMap(r.$id, r.data))
          .toList();
    } catch (e) {
      debugPrint('listCompletionsForEvent error: $e');
      return [];
    }
  }

  Future<List<ChecklistCompletion>> listCompletionsForSchool(
    String flightSchoolId,
  ) async {
    if (flightSchoolId.trim().isEmpty) return [];
    try {
      final cfg = AppwriteConfig();
      final rows = await listAllRows(
        _tablesDB,
        databaseId: cfg.seasonPlannerDatabaseId,
        tableId: cfg.checklistCompletionsTableId,
        queries: [Query.equal('flight_school_id', flightSchoolId)],
      );
      return rows
          .map((r) => ChecklistCompletion.fromMap(r.$id, r.data))
          .toList();
    } catch (e) {
      debugPrint('listCompletionsForSchool error: $e');
      return [];
    }
  }

  /// Speichert den laufenden Zwischenstand der abgehakten Punkte für eine Zuweisung.
  Future<ChecklistCompletion> saveProgress({
    ChecklistCompletion? existing,
    required String flightSchoolId,
    required String eventId,
    required String assignmentId,
    required String userId,
    required String roleName,
    required RoleDocument checklist,
    required List<ChecklistItem> items,
    String notes = '',
  }) async {
    final cfg = AppwriteConfig();
    final total = items.length;
    final checked = items.where((i) => i.checked).length;
    final data = {
      'flight_school_id': flightSchoolId,
      'event_id': eventId,
      'assignment_id': assignmentId,
      'user_id': userId,
      'role_name': roleName,
      'checklist_id': checklist.id,
      'checklist_title': checklist.title,
      'checklist_version': checklist.version,
      'items_snapshot_json':
          jsonEncode(items.map((e) => e.toJson()).toList()),
      'total_count': total,
      'checked_count': checked,
      'is_complete': total > 0 && checked >= total,
      'status': ChecklistCompletionStatus.inProgress.dbValue,
      'notes': notes.trim(),
      'updated_at': DateTime.now().toIso8601String(),
    };

    if (existing != null) {
      final row = await _tablesDB.updateRow(
        databaseId: cfg.seasonPlannerDatabaseId,
        tableId: cfg.checklistCompletionsTableId,
        rowId: existing.id,
        data: data,
      );
      return ChecklistCompletion.fromMap(row.$id, row.data);
    }

    final row = await _tablesDB.createRow(
      databaseId: cfg.seasonPlannerDatabaseId,
      tableId: cfg.checklistCompletionsTableId,
      rowId: ID.unique(),
      data: data,
      permissions: SecurityPrivacyService.ownerAndSchoolAdminPerms(
        userId: userId,
        flightSchoolId: flightSchoolId,
      ),
    );
    return ChecklistCompletion.fromMap(row.$id, row.data);
  }

  /// Lädt die PNG-Unterschrift hoch und schließt die Checkliste mit einem
  /// unveränderlichen Snapshot aller (abgehakten & offenen) Punkte ab.
  Future<ChecklistCompletion> signCompletion({
    ChecklistCompletion? existing,
    required String flightSchoolId,
    required String eventId,
    required String eventName,
    required String assignmentId,
    required String userId,
    required String roleName,
    required RoleDocument checklist,
    required List<ChecklistItem> items,
    required Uint8List signaturePngBytes,
    String notes = '',
  }) async {
    final cfg = AppwriteConfig();
    final sigFile = await _storage.createFile(
      bucketId: cfg.checklistSignaturesBucketId,
      fileId: ID.unique(),
      file: InputFile.fromBytes(
        bytes: signaturePngBytes,
        filename: 'signature_${assignmentId}_${DateTime.now().millisecondsSinceEpoch}.png',
      ),
      permissions: [
        Permission.read(Role.user(userId)),
        Permission.delete(Role.user(userId)),
        Permission.read(Role.team(flightSchoolId, 'admin')),
        Permission.delete(Role.team(flightSchoolId, 'admin')),
      ],
    );

    final total = items.length;
    final checked = items.where((i) => i.checked).length;
    final isComplete = total > 0 && checked >= total;
    final nowIso = DateTime.now().toIso8601String();

    final data = {
      'flight_school_id': flightSchoolId,
      'event_id': eventId,
      'assignment_id': assignmentId,
      'user_id': userId,
      'role_name': roleName,
      'checklist_id': checklist.id,
      'checklist_title': checklist.title,
      'checklist_version': checklist.version,
      'items_snapshot_json':
          jsonEncode(items.map((e) => e.toJson()).toList()),
      'total_count': total,
      'checked_count': checked,
      'is_complete': isComplete,
      'status': ChecklistCompletionStatus.signed.dbValue,
      'notes': notes.trim(),
      'signature_file_id': sigFile.$id,
      'signed_at': nowIso,
      'updated_at': nowIso,
    };

    try {
      final row = existing != null
          ? await _tablesDB.updateRow(
              databaseId: cfg.seasonPlannerDatabaseId,
              tableId: cfg.checklistCompletionsTableId,
              rowId: existing.id,
              data: data,
            )
          : await _tablesDB.createRow(
              databaseId: cfg.seasonPlannerDatabaseId,
              tableId: cfg.checklistCompletionsTableId,
              rowId: ID.unique(),
              data: data,
              permissions: SecurityPrivacyService.ownerAndSchoolAdminPerms(
                userId: userId,
                flightSchoolId: flightSchoolId,
              ),
            );

      await AuditLogService().log(
        flightSchoolId: flightSchoolId,
        userId: userId,
        action: isComplete
            ? 'Checkliste vollständig unterschrieben'
            : 'Checkliste mit offenen Punkten unterschrieben',
        details:
            'Event „$eventName“ ($roleName): ${checklist.title} – $checked/$total erledigt'
            '${notes.trim().isNotEmpty ? ' · Bemerkung: ${notes.trim()}' : ''}',
      );

      // Prüfe automatisch, ob das Event nun vollständig abgeschlossen werden kann
      SecurityPrivacyService().checkEventCompletion(
        flightSchoolId: flightSchoolId,
        eventId: eventId,
      );

      return ChecklistCompletion.fromMap(row.$id, row.data);
    } catch (e) {
      // Verwaiste Unterschrift-Datei bei DB-Fehler aufräumen
      try {
        await _storage.deleteFile(
          bucketId: cfg.checklistSignaturesBucketId,
          fileId: sigFile.$id,
        );
      } catch (_) {}
      rethrow;
    }
  }

  Future<Uint8List?> loadSignatureBytes(String? signatureFileId) async {
    if (signatureFileId == null || signatureFileId.trim().isEmpty) return null;
    try {
      final cfg = AppwriteConfig();
      return await _storage.getFileView(
        bucketId: cfg.checklistSignaturesBucketId,
        fileId: signatureFileId,
      );
    } catch (e) {
      debugPrint('loadSignatureBytes error: $e');
      return null;
    }
  }

  // ==================== HILFSFUNKTIONEN ====================

  static String _normalizePath(String path) {
    var p = path.replaceAll('\\', '/').trim();
    while (p.startsWith('./')) {
      p = p.substring(2);
    }
    while (p.startsWith('/')) {
      p = p.substring(1);
    }
    return p;
  }

  static String _baseName(String path) {
    final norm = _normalizePath(path);
    final idx = norm.lastIndexOf('/');
    return idx >= 0 ? norm.substring(idx + 1) : norm;
  }

  static String _extension(String filename) {
    final base = _baseName(filename);
    final idx = base.lastIndexOf('.');
    if (idx < 0 || idx == base.length - 1) return '';
    return base.substring(idx + 1).toLowerCase();
  }

  static String _stripExtension(String filename) {
    final idx = filename.lastIndexOf('.');
    return idx > 0 ? filename.substring(0, idx) : filename;
  }
}
