/// Die 4 Standard-Qualifikationen, die bei jeder Flugschule automatisch angelegt werden.
const List<String> kDefaultQualificationNames = [
  'Fluglehrer',
  'Anwärter',
  'Sicherheitstrainer',
  'Tandempilot',
];

/// Die 6 Standard-Teamrollen (Einsatzpositionen), die bei jeder Flugschule
/// automatisch angelegt werden.
const List<String> kDefaultTeamRoleNames = [
  'Startplatz',
  'Trainingsleiter',
  'Kamera',
  'Busfahrer',
  'Bootshelfer',
  'Tandempilot',
];

/// Vordefinierter Standardkatalog für Qualifikations- und Versicherungsnachweise,
/// damit Dokumente schulübergreifend eindeutig zugeordnet werden können.
const List<String> kStandardDocumentTypes = [
  'Bootsführerschein',
  'Autoführerschein',
  'Tandemlizenz DE',
  'Tandemlizenz AT',
  'Fluglehrerlizenz DE',
  'Fluglehrerlizenz AT',
  'Anwärterbestätigung',
  'Sicherheitstrainingsleiter Urkunde',
  'Medical',
  'Fluglehrerhaftpflicht',
  'Tandemhaftpflicht',
  'Drittpacker Einweisung',
];

/// Fachliche / rechtliche Qualifikation je Flugschule (z. B. Fluglehrer,
/// Sicherheitstrainer, Anwärter) inkl. geforderter Dokumentennachweise.
class Qualification {
  final String id;
  final String flightSchoolId;
  final String name;
  final bool isDefault;
  final List<String> requiredDocuments;

  const Qualification({
    required this.id,
    required this.flightSchoolId,
    required this.name,
    this.isDefault = false,
    this.requiredDocuments = const [],
  });

  factory Qualification.fromMap(String id, Map<String, dynamic> map) {
    return Qualification(
      id: id,
      flightSchoolId: (map['flight_school_id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      isDefault: map['is_default'] == true,
      requiredDocuments: (map['required_documents'] as List? ?? const [])
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList(),
    );
  }

  Map<String, dynamic> toMap() => {
        'flight_school_id': flightSchoolId,
        'name': name,
        'is_default': isDefault,
        'required_documents': requiredDocuments,
      };

  Qualification copyWith({
    String? id,
    String? flightSchoolId,
    String? name,
    bool? isDefault,
    List<String>? requiredDocuments,
  }) {
    return Qualification(
      id: id ?? this.id,
      flightSchoolId: flightSchoolId ?? this.flightSchoolId,
      name: name ?? this.name,
      isDefault: isDefault ?? this.isDefault,
      requiredDocuments: requiredDocuments ?? this.requiredDocuments,
    );
  }
}

/// Einsatzposition / Teamrolle je Flugschule (z. B. Startplatz, Trainingsleiter,
/// Kamera, Busfahrer, Bootshelfer) mit Checkliste, Arbeitsanweisungen und
/// optionalen Pflicht-Qualifikationen (UND / ODER).
class TeamRole {
  final String id;
  final String flightSchoolId;
  final String name;
  final bool isDefault;
  final List<String> requiredQualificationIds;

  /// `true` = Mitglied muss ALLE gewählten Qualifikationen besitzen (UND).
  /// `false` = Mitglied muss MINDESTENS EINE der gewählten Qualifikationen besitzen (ODER).
  final bool requireAllQualifications;

  final String? checklistId;
  final List<String> instructionIds;

  const TeamRole({
    required this.id,
    required this.flightSchoolId,
    required this.name,
    this.isDefault = false,
    this.requiredQualificationIds = const [],
    this.requireAllQualifications = true,
    this.checklistId,
    this.instructionIds = const [],
  });

  factory TeamRole.fromMap(String id, Map<String, dynamic> map) {
    final rawChecklistId = (map['checklist_id'] ?? '').toString().trim();
    return TeamRole(
      id: id,
      flightSchoolId: (map['flight_school_id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      isDefault: map['is_default'] == true,
      requiredQualificationIds:
          (map['required_qualification_ids'] as List? ?? const [])
              .map((e) => e.toString())
              .where((e) => e.trim().isNotEmpty)
              .toList(),
      requireAllQualifications: map['require_all_qualifications'] != false,
      checklistId: rawChecklistId.isEmpty ? null : rawChecklistId,
      instructionIds: (map['instruction_ids'] as List? ?? const [])
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList(),
    );
  }

  Map<String, dynamic> toMap() => {
        'flight_school_id': flightSchoolId,
        'name': name,
        'is_default': isDefault,
        'required_qualification_ids': requiredQualificationIds,
        'require_all_qualifications': requireAllQualifications,
        'checklist_id': checklistId ?? '',
        'instruction_ids': instructionIds,
      };

  TeamRole copyWith({
    String? id,
    String? flightSchoolId,
    String? name,
    bool? isDefault,
    List<String>? requiredQualificationIds,
    bool? requireAllQualifications,
    String? checklistId,
    bool clearChecklistId = false,
    List<String>? instructionIds,
  }) {
    return TeamRole(
      id: id ?? this.id,
      flightSchoolId: flightSchoolId ?? this.flightSchoolId,
      name: name ?? this.name,
      isDefault: isDefault ?? this.isDefault,
      requiredQualificationIds:
          requiredQualificationIds ?? this.requiredQualificationIds,
      requireAllQualifications:
          requireAllQualifications ?? this.requireAllQualifications,
      checklistId:
          clearChecklistId ? null : (checklistId ?? this.checklistId),
      instructionIds: instructionIds ?? this.instructionIds,
    );
  }
}
