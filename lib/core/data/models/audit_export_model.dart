import 'dart:convert';
import 'package:season_planner/core/data/models/qualification_model.dart';
import 'package:season_planner/fsAdmin/data/models/user_summary_flight_school_view.dart';

/// Erweiterbare ÖAeC-Audit-Stammdaten einer Flugschule (gespeichert in
/// `core_db.flight_schools.audit_profile_json`).
class FlightSchoolAuditProfile {
  final String officialName;
  final String ownerName;
  final String address;
  final String email;
  final String phone;
  final String bescheidNumber;
  final String trainingDirectorUserId;
  final String trainingDirectorName;
  final String trainingDirectorAddress;
  final String trainingDirectorEmail;
  final String trainingDirectorPhone;
  final String trainingDirectorBirthDate;
  final String trainingDirectorSince;
  final List<String> officeMemberIds;

  const FlightSchoolAuditProfile({
    this.officialName = '',
    this.ownerName = '',
    this.address = '',
    this.email = '',
    this.phone = '',
    this.bescheidNumber = '',
    this.trainingDirectorUserId = '',
    this.trainingDirectorName = '',
    this.trainingDirectorAddress = '',
    this.trainingDirectorEmail = '',
    this.trainingDirectorPhone = '',
    this.trainingDirectorBirthDate = '',
    this.trainingDirectorSince = '',
    this.officeMemberIds = const [],
  });

  factory FlightSchoolAuditProfile.fromJsonString(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const FlightSchoolAuditProfile();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return FlightSchoolAuditProfile.fromMap(decoded);
      }
      if (decoded is Map) {
        return FlightSchoolAuditProfile.fromMap(
          Map<String, dynamic>.from(decoded),
        );
      }
    } catch (_) {}
    return const FlightSchoolAuditProfile();
  }

  factory FlightSchoolAuditProfile.fromMap(Map<String, dynamic> map) {
    return FlightSchoolAuditProfile(
      officialName: (map['officialName'] ?? '').toString(),
      ownerName: (map['ownerName'] ?? '').toString(),
      address: (map['address'] ?? '').toString(),
      email: (map['email'] ?? '').toString(),
      phone: (map['phone'] ?? '').toString(),
      bescheidNumber: (map['bescheidNumber'] ?? '').toString(),
      trainingDirectorUserId: (map['trainingDirectorUserId'] ?? '').toString(),
      trainingDirectorName: (map['trainingDirectorName'] ?? '').toString(),
      trainingDirectorAddress:
          (map['trainingDirectorAddress'] ?? '').toString(),
      trainingDirectorEmail: (map['trainingDirectorEmail'] ?? '').toString(),
      trainingDirectorPhone: (map['trainingDirectorPhone'] ?? '').toString(),
      trainingDirectorBirthDate:
          (map['trainingDirectorBirthDate'] ?? '').toString(),
      trainingDirectorSince: (map['trainingDirectorSince'] ?? '').toString(),
      officeMemberIds: (map['officeMemberIds'] as List? ?? const [])
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList(),
    );
  }

  Map<String, dynamic> toMap() => {
        'officialName': officialName.trim(),
        'ownerName': ownerName.trim(),
        'address': address.trim(),
        'email': email.trim(),
        'phone': phone.trim(),
        'bescheidNumber': bescheidNumber.trim(),
        'trainingDirectorUserId': trainingDirectorUserId.trim(),
        'trainingDirectorName': trainingDirectorName.trim(),
        'trainingDirectorAddress': trainingDirectorAddress.trim(),
        'trainingDirectorEmail': trainingDirectorEmail.trim(),
        'trainingDirectorPhone': trainingDirectorPhone.trim(),
        'trainingDirectorBirthDate': trainingDirectorBirthDate.trim(),
        'trainingDirectorSince': trainingDirectorSince.trim(),
        'officeMemberIds': officeMemberIds,
      };

  String toJsonString() => jsonEncode(toMap());

  bool get hasBasicSchoolInfo =>
      ownerName.trim().isNotEmpty ||
      address.trim().isNotEmpty ||
      bescheidNumber.trim().isNotEmpty;

  FlightSchoolAuditProfile copyWith({
    String? officialName,
    String? ownerName,
    String? address,
    String? email,
    String? phone,
    String? bescheidNumber,
    String? trainingDirectorUserId,
    String? trainingDirectorName,
    String? trainingDirectorAddress,
    String? trainingDirectorEmail,
    String? trainingDirectorPhone,
    String? trainingDirectorBirthDate,
    String? trainingDirectorSince,
    List<String>? officeMemberIds,
  }) {
    return FlightSchoolAuditProfile(
      officialName: officialName ?? this.officialName,
      ownerName: ownerName ?? this.ownerName,
      address: address ?? this.address,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      bescheidNumber: bescheidNumber ?? this.bescheidNumber,
      trainingDirectorUserId:
          trainingDirectorUserId ?? this.trainingDirectorUserId,
      trainingDirectorName: trainingDirectorName ?? this.trainingDirectorName,
      trainingDirectorAddress:
          trainingDirectorAddress ?? this.trainingDirectorAddress,
      trainingDirectorEmail:
          trainingDirectorEmail ?? this.trainingDirectorEmail,
      trainingDirectorPhone:
          trainingDirectorPhone ?? this.trainingDirectorPhone,
      trainingDirectorBirthDate:
          trainingDirectorBirthDate ?? this.trainingDirectorBirthDate,
      trainingDirectorSince:
          trainingDirectorSince ?? this.trainingDirectorSince,
      officeMemberIds: officeMemberIds ?? this.officeMemberIds,
    );
  }
}

/// Vorab-Prüfergebnis je Mitarbeiter für den ÖAeC-Stellenbesetzungsplan.
class AuditMemberCompliance {
  final UserSummary member;
  final int confirmedAssignmentsInYear;
  final List<QualificationDocument> validApprovedDocs;
  final List<String> missingDocTypes;
  final List<String> expiredDocTypes;
  final List<String> missingProfileFields;

  const AuditMemberCompliance({
    required this.member,
    required this.confirmedAssignmentsInYear,
    required this.validApprovedDocs,
    required this.missingDocTypes,
    required this.expiredDocTypes,
    required this.missingProfileFields,
  });

  bool get hasDocWarnings =>
      missingDocTypes.isNotEmpty || expiredDocTypes.isNotEmpty;

  bool get hasAnyWarning => hasDocWarnings || missingProfileFields.isNotEmpty;

  /// Sucht ein gültiges Dokument anhand eines Stichworts (z. B. `tandem`, `medical`).
  QualificationDocument? findValidDocByKeyword(String keyword) {
    final k = keyword.toLowerCase();
    for (final d in validApprovedDocs) {
      if (d.documentType.toLowerCase().contains(k) ||
          d.title.toLowerCase().contains(k)) {
        return d;
      }
    }
    return null;
  }
}

/// Sortierpriorität der Qualifikations-Sektionen gemäß ÖAeC-Muster:
/// 1. Fluglehrer, 2. Sicherheitstrainer, 3. Fluglehreranwärter,
/// 4. Tandempiloten, 5. sonstige Qualifikationen.
int oeAeCQualificationSortOrder(String qualName) {
  final n = qualName.trim().toLowerCase();
  if (n.contains('fluglehrer') && !n.contains('anwärter') && !n.contains('anwaerter')) {
    return 0;
  }
  if (n.contains('sicherheitstrainer') || n.contains('trainer')) return 1;
  if (n.contains('anwärter') || n.contains('anwaerter')) return 2;
  if (n.contains('tandem')) return 3;
  return 4;
}

String oeAeCSectionTitleForQualification(String qualName) {
  final n = qualName.trim().toLowerCase();
  if (n == 'fluglehrer') return 'FluglehrerInnen für Hänge- und Paragleiter';
  if (n == 'anwärter' || n == 'fluglehreranwärter') {
    return 'FluglehreranwärterInnen für Hänge- und Paragleiter';
  }
  if (n == 'sicherheitstrainer') return 'SicherheitstrainerInnen';
  if (n == 'tandempilot') return 'TandempilotInnen';
  return qualName;
}
