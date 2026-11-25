enum ApprovalStatusEnum {
  submitted,
  approved,
  rejected,
}

extension ApprovalStatusEnumX on ApprovalStatusEnum {
  String get label {
    switch (this) {
      case ApprovalStatusEnum.submitted:
        return 'Eingereicht';
      case ApprovalStatusEnum.approved:
        return 'Bestätigt';
      case ApprovalStatusEnum.rejected:
        return 'Abgelehnt';
    }
  }

  static ApprovalStatusEnum parse(dynamic raw) {
    final s = (raw ?? 'submitted').toString();
    return ApprovalStatusEnum.values.firstWhere(
      (e) => e.name == s,
      orElse: () => ApprovalStatusEnum.submitted,
    );
  }
}

class QualificationDocument {
  final String id;
  final String userId;
  final String documentType;
  final String title;
  final String fileId;
  final String fileName;
  final DateTime? issuedAt;
  final DateTime? expiresAt;

  const QualificationDocument({
    required this.id,
    required this.userId,
    required this.documentType,
    required this.title,
    required this.fileId,
    required this.fileName,
    this.issuedAt,
    this.expiresAt,
  });

  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());

  bool get expiresSoon =>
      expiresAt != null &&
      !isExpired &&
      expiresAt!.isBefore(DateTime.now().add(const Duration(days: 30)));

  factory QualificationDocument.fromMap(String id, Map<String, dynamic> map) {
    return QualificationDocument(
      id: id,
      userId: (map['user_id'] ?? '').toString(),
      documentType: (map['document_type'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      fileId: (map['file_id'] ?? '').toString(),
      fileName: (map['file_name'] ?? '').toString(),
      issuedAt: map['issued_at'] != null && map['issued_at'].toString().isNotEmpty
          ? DateTime.tryParse(map['issued_at'].toString())
          : null,
      expiresAt: map['expires_at'] != null && map['expires_at'].toString().isNotEmpty
          ? DateTime.tryParse(map['expires_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'user_id': userId,
        'document_type': documentType,
        'title': title,
        'file_id': fileId,
        'file_name': fileName,
        'issued_at': issuedAt?.toIso8601String(),
        'expires_at': expiresAt?.toIso8601String(),
      };
}

class QualificationApproval {
  final String id;
  final String documentId;
  final String userId;
  final String flightSchoolId;
  final String documentType;
  final ApprovalStatusEnum status;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? comment;

  const QualificationApproval({
    required this.id,
    required this.documentId,
    required this.userId,
    required this.flightSchoolId,
    required this.documentType,
    required this.status,
    this.reviewedBy,
    this.reviewedAt,
    this.comment,
  });

  factory QualificationApproval.fromMap(String id, Map<String, dynamic> map) {
    return QualificationApproval(
      id: id,
      documentId: (map['document_id'] ?? '').toString(),
      userId: (map['user_id'] ?? '').toString(),
      flightSchoolId: (map['flight_school_id'] ?? '').toString(),
      documentType: (map['document_type'] ?? '').toString(),
      status: ApprovalStatusEnumX.parse(map['status']),
      reviewedBy: map['reviewed_by']?.toString(),
      reviewedAt: map['reviewed_at'] != null && map['reviewed_at'].toString().isNotEmpty
          ? DateTime.tryParse(map['reviewed_at'].toString())
          : null,
      comment: map['comment']?.toString(),
    );
  }
}

class QualificationCheckResult {
  final bool isFullyQualified;
  final List<String> missingQualifications;
  final bool requireAllQualifications;
  final List<String> missingDocuments;
  final List<String> pendingDocuments;
  final List<String> expiredDocuments;

  const QualificationCheckResult({
    required this.isFullyQualified,
    this.missingQualifications = const [],
    this.requireAllQualifications = true,
    this.missingDocuments = const [],
    this.pendingDocuments = const [],
    this.expiredDocuments = const [],
  });

  bool get hasMissingQualifications => missingQualifications.isNotEmpty;
  bool get hasOpenDocuments =>
      missingDocuments.isNotEmpty ||
      pendingDocuments.isNotEmpty ||
      expiredDocuments.isNotEmpty;

  String get summaryText {
    if (isFullyQualified) return 'Vollständig qualifiziert';
    final parts = <String>[];
    if (missingQualifications.isNotEmpty) {
      parts.add(
        requireAllQualifications || missingQualifications.length == 1
            ? 'Qualifikation fehlt: ${missingQualifications.join(', ')}'
            : 'Eine Qualifikation erforderlich: ${missingQualifications.join(' oder ')}',
      );
    }
    if (missingDocuments.isNotEmpty) {
      parts.add('Nachweis fehlt: ${missingDocuments.join(', ')}');
    }
    if (pendingDocuments.isNotEmpty) {
      parts.add('Prüfung offen: ${pendingDocuments.join(', ')}');
    }
    if (expiredDocuments.isNotEmpty) {
      parts.add('Abgelaufen: ${expiredDocuments.join(', ')}');
    }
    return parts.join(' · ');
  }
}
