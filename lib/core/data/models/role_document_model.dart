import 'dart:convert';

enum RoleDocumentType {
  instruction('Arbeitsanweisung'),
  checklist('Checkliste');

  final String label;
  const RoleDocumentType(this.label);

  static RoleDocumentType parse(dynamic raw) {
    final s = (raw ?? '').toString().trim().toLowerCase();
    return s == 'checklist'
        ? RoleDocumentType.checklist
        : RoleDocumentType.instruction;
  }
}

class RoleDocument {
  final String id;
  final String flightSchoolId;
  final RoleDocumentType docType;
  final String title;
  final String contentMd;
  final List<String> assetFileIds;
  final int version;
  final DateTime? updatedAt;

  const RoleDocument({
    required this.id,
    required this.flightSchoolId,
    required this.docType,
    required this.title,
    required this.contentMd,
    this.assetFileIds = const [],
    this.version = 1,
    this.updatedAt,
  });

  factory RoleDocument.fromMap(String id, Map<String, dynamic> map) {
    return RoleDocument(
      id: id,
      flightSchoolId: (map['flight_school_id'] ?? '').toString(),
      docType: RoleDocumentType.parse(map['doc_type']),
      title: (map['title'] ?? 'Dokument').toString(),
      contentMd: (map['content_md'] ?? '').toString(),
      assetFileIds: (map['asset_file_ids'] as List? ?? const [])
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList(),
      version: (map['version'] is int)
          ? map['version'] as int
          : int.tryParse('${map['version']}') ?? 1,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'].toString())
          : null,
    );
  }

  List<ChecklistItem> parseChecklistItems() =>
      parseChecklistMarkdown(contentMd);
}

class ChecklistItem {
  final String id;
  final String section;
  final String text;
  final bool checked;

  const ChecklistItem({
    required this.id,
    required this.section,
    required this.text,
    this.checked = false,
  });

  ChecklistItem copyWith({
    String? id,
    String? section,
    String? text,
    bool? checked,
  }) {
    return ChecklistItem(
      id: id ?? this.id,
      section: section ?? this.section,
      text: text ?? this.text,
      checked: checked ?? this.checked,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'section': section,
        'text': text,
        'checked': checked,
      };

  factory ChecklistItem.fromJson(Map<String, dynamic> json) {
    return ChecklistItem(
      id: (json['id'] ?? '').toString(),
      section: (json['section'] ?? '').toString(),
      text: (json['text'] ?? '').toString(),
      checked: json['checked'] == true,
    );
  }
}

/// Parst eine Markdown-Checkliste (`## Abschnitt` + `- [ ] Aufgabe`)
/// in strukturierte, interaktiv abhakbare Einträge.
/// Falls keine `- [ ]`-Checkboxen vorhanden sind, werden normale Listenpunkte (`- ` / `* ` / `1. `) genutzt.
List<ChecklistItem> parseChecklistMarkdown(String markdown) {
  final lines = const LineSplitter().convert(markdown);
  final taskItems = <ChecklistItem>[];
  final fallbackBulletItems = <ChecklistItem>[];

  String currentSection = '';
  int taskIdx = 0;
  int bulletIdx = 0;

  final headingRegex = RegExp(r'^\s{0,3}#{1,6}\s+(.+?)\s*#*\s*$');
  final taskRegex = RegExp(r'^\s*[-*+]\s+\[([ xX])\]\s+(.+)$');
  final bulletRegex = RegExp(r'^\s*(?:[-*+]|\d+[.)])\s+(.+)$');

  for (final rawLine in lines) {
    final line = rawLine.trimRight();
    if (line.trim().isEmpty) continue;

    final hMatch = headingRegex.firstMatch(line);
    if (hMatch != null) {
      final heading = hMatch.group(1)!.trim();
      // H1 ist meist der Dokumenttitel; ab H2 als Abschnittsüberschrift nutzen
      if (line.trimLeft().startsWith('##')) {
        currentSection = heading;
      }
      continue;
    }

    final tMatch = taskRegex.firstMatch(line);
    if (tMatch != null) {
      final checked = tMatch.group(1)!.toLowerCase() == 'x';
      final text = tMatch.group(2)!.trim();
      if (text.isNotEmpty) {
        taskItems.add(ChecklistItem(
          id: 'item_${taskIdx++}',
          section: currentSection,
          text: text,
          checked: checked,
        ));
      }
      continue;
    }

    final bMatch = bulletRegex.firstMatch(line);
    if (bMatch != null) {
      final text = bMatch.group(1)!.trim();
      if (text.isNotEmpty) {
        fallbackBulletItems.add(ChecklistItem(
          id: 'item_${bulletIdx++}',
          section: currentSection,
          text: text,
          checked: false,
        ));
      }
    }
  }

  return taskItems.isNotEmpty ? taskItems : fallbackBulletItems;
}

enum ChecklistCompletionStatus {
  inProgress('in_progress', 'In Bearbeitung'),
  signed('signed', 'Unterschrieben');

  final String dbValue;
  final String label;
  const ChecklistCompletionStatus(this.dbValue, this.label);

  static ChecklistCompletionStatus parse(dynamic raw) {
    final s = (raw ?? '').toString().trim().toLowerCase();
    return s == 'signed'
        ? ChecklistCompletionStatus.signed
        : ChecklistCompletionStatus.inProgress;
  }
}

class ChecklistCompletion {
  final String id;
  final String flightSchoolId;
  final String eventId;
  final String assignmentId;
  final String userId;
  final String roleName;
  final String checklistId;
  final String checklistTitle;
  final int checklistVersion;
  final List<ChecklistItem> items;
  final int totalCount;
  final int checkedCount;
  final bool isComplete;
  final ChecklistCompletionStatus status;
  final String notes;
  final String? signatureFileId;
  final DateTime? signedAt;
  final DateTime? updatedAt;

  const ChecklistCompletion({
    required this.id,
    required this.flightSchoolId,
    required this.eventId,
    required this.assignmentId,
    required this.userId,
    required this.roleName,
    required this.checklistId,
    required this.checklistTitle,
    this.checklistVersion = 1,
    this.items = const [],
    this.totalCount = 0,
    this.checkedCount = 0,
    this.isComplete = false,
    this.status = ChecklistCompletionStatus.inProgress,
    this.notes = '',
    this.signatureFileId,
    this.signedAt,
    this.updatedAt,
  });

  bool get isSigned => status == ChecklistCompletionStatus.signed;

  factory ChecklistCompletion.fromMap(String id, Map<String, dynamic> map) {
    final rawJson = (map['items_snapshot_json'] ?? '[]').toString();
    List<ChecklistItem> parsedItems = const [];
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is List) {
        parsedItems = decoded
            .whereType<Map>()
            .map((e) => ChecklistItem.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}

    final sigId = (map['signature_file_id'] ?? '').toString().trim();
    final total = (map['total_count'] is int)
        ? map['total_count'] as int
        : parsedItems.length;
    final checked = (map['checked_count'] is int)
        ? map['checked_count'] as int
        : parsedItems.where((i) => i.checked).length;

    return ChecklistCompletion(
      id: id,
      flightSchoolId: (map['flight_school_id'] ?? '').toString(),
      eventId: (map['event_id'] ?? '').toString(),
      assignmentId: (map['assignment_id'] ?? '').toString(),
      userId: (map['user_id'] ?? '').toString(),
      roleName: (map['role_name'] ?? '').toString(),
      checklistId: (map['checklist_id'] ?? '').toString(),
      checklistTitle: (map['checklist_title'] ?? 'Checkliste').toString(),
      checklistVersion: (map['checklist_version'] is int)
          ? map['checklist_version'] as int
          : int.tryParse('${map['checklist_version']}') ?? 1,
      items: parsedItems,
      totalCount: total,
      checkedCount: checked,
      isComplete: map['is_complete'] == true || (total > 0 && checked >= total),
      status: ChecklistCompletionStatus.parse(map['status']),
      notes: (map['notes'] ?? '').toString(),
      signatureFileId: sigId.isEmpty ? null : sigId,
      signedAt: map['signed_at'] != null
          ? DateTime.tryParse(map['signed_at'].toString())
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'].toString())
          : null,
    );
  }
}
