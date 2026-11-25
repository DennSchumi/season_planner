import 'package:season_planner/core/data/enums/membership_status_enum.dart';
import 'package:season_planner/core/data/enums/team_tier_enum.dart';

class UserSummary {
  /// Bevorzugt die Appwrite Auth-ID (`auth_id`), Fallback auf DB-Row-ID (`$id`).
  final String id;

  /// Optionale Zeilen-ID aus `core_db.users` (`$id`), falls abweichend von `auth_id`.
  final String userRowId;

  final String name;
  final String mail;
  final String phone;
  final String avatarUrl;
  final String emergencyContactName;
  final String emergencyContactRelation;
  final String emergencyContactPhone;
  final String birthDate;
  final String address;
  final String licenseNumber;
  final String licenseRatings;
  final String employmentType;
  final String activeSince;
  final List<String> roles;
  final List<String> qualificationIds;
  final List<String> requestedQualificationIds;
  final String membershipId;
  final MembershipStatusEnum membershipStatus;
  final TeamTierEnum teamTier;

  UserSummary({
    required this.id,
    this.userRowId = '',
    required this.name,
    required this.mail,
    required this.phone,
    this.avatarUrl = '',
    this.emergencyContactName = '',
    this.emergencyContactRelation = '',
    this.emergencyContactPhone = '',
    this.birthDate = '',
    this.address = '',
    this.licenseNumber = '',
    this.licenseRatings = '',
    this.employmentType = '',
    this.activeSince = '',
    required this.roles,
    this.qualificationIds = const [],
    this.requestedQualificationIds = const [],
    required this.membershipId,
    this.membershipStatus = MembershipStatusEnum.active,
    this.teamTier = TeamTierEnum.core,
  });

  bool get isExtendedTeam => teamTier == TeamTierEnum.extended;

  String get displayName => name.trim().isNotEmpty
      ? name.trim()
      : (mail.trim().isNotEmpty ? mail.trim() : id);

  bool get hasEmergencyContact =>
      emergencyContactName.trim().isNotEmpty ||
      emergencyContactPhone.trim().isNotEmpty;

  bool matchesId(String uid) =>
      uid.isNotEmpty &&
      (uid == id || (userRowId.isNotEmpty && uid == userRowId));

  factory UserSummary.fromJson(Map<String, dynamic> json) {
    return UserSummary(
      id: (json['id'] ?? '').toString(),
      userRowId: (json['userRowId'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      mail: (json['mail'] ?? json['email'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      avatarUrl: (json['avatarUrl'] ?? json['avatar_url'] ?? '').toString(),
      emergencyContactName: (json['emergencyContactName'] ??
              json['emergency_contact_name'] ??
              '')
          .toString(),
      emergencyContactRelation: (json['emergencyContactRelation'] ??
              json['emergency_contact_relation'] ??
              '')
          .toString(),
      emergencyContactPhone: (json['emergencyContactPhone'] ??
              json['emergency_contact_phone'] ??
              '')
          .toString(),
      birthDate: (json['birthDate'] ?? json['birth_date'] ?? '').toString(),
      address: (json['address'] ?? '').toString(),
      licenseNumber:
          (json['licenseNumber'] ?? json['license_number'] ?? '').toString(),
      licenseRatings:
          (json['licenseRatings'] ?? json['license_ratings'] ?? '').toString(),
      employmentType:
          (json['employmentType'] ?? json['employment_type'] ?? '').toString(),
      activeSince:
          (json['activeSince'] ?? json['active_since'] ?? '').toString(),
      membershipId: (json['membershipId'] ?? '').toString(),
      roles: parseRoles(json['roles']),
      qualificationIds:
          parseRoles(json['qualificationIds'] ?? json['qualifications']),
      requestedQualificationIds: parseRoles(
        json['requestedQualificationIds'] ?? json['requested_qualifications'],
      ),
      membershipStatus: MembershipStatusEnumX.parse(json['membershipStatus']),
      teamTier: TeamTierEnum.parse(json['teamTier'] ?? json['team_tier']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'userRowId': userRowId,
        'name': name,
        'mail': mail,
        'phone': phone,
        'avatarUrl': avatarUrl,
        'emergencyContactName': emergencyContactName,
        'emergencyContactRelation': emergencyContactRelation,
        'emergencyContactPhone': emergencyContactPhone,
        'birthDate': birthDate,
        'address': address,
        'licenseNumber': licenseNumber,
        'licenseRatings': licenseRatings,
        'employmentType': employmentType,
        'activeSince': activeSince,
        'membershipId': membershipId,
        'roles': roles,
        'qualificationIds': qualificationIds,
        'requestedQualificationIds': requestedQualificationIds,
        'membershipStatus': membershipStatus.name,
        'teamTier': teamTier.wireValue,
      };

  static List<String> parseRoles(dynamic raw) {
    if (raw is! List) return [];
    return raw
        .map((e) => e?.toString().trim() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
  }
}
