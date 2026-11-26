import 'package:season_planner/core/data/models/event_model.dart';
import 'package:season_planner/core/data/models/tandem_model.dart';
import 'package:season_planner/user/data/models/flight_school_model_user_view.dart';

class UserModelUserView {
  final String id;
  final String name;
  final String mail;
  final String phone;
  final String avatarUrl;
  final String avatarFileId;
  final String emergencyContactName;
  final String emergencyContactRelation;
  final String emergencyContactPhone;
  final String birthDate;
  final String address;
  final String licenseNumber;
  final String licenseRatings;
  final String employmentType;
  final String activeSince;
  final List<FlightSchoolUserView> flightSchools;
  final List<FlightSchoolUserView> adminOnlyFlightSchools;
  final List<Event> events;
  final List<TandemDuty> tandemDuties;
  final List<TandemDemand> tandemDemands;
  final Map<String, String> tandemPilotNamesById;
  final bool hasLoadedArchive;

  UserModelUserView({
    required this.id,
    required this.name,
    required this.mail,
    required this.phone,
    this.avatarUrl = '',
    this.avatarFileId = '',
    this.emergencyContactName = '',
    this.emergencyContactRelation = '',
    this.emergencyContactPhone = '',
    this.birthDate = '',
    this.address = '',
    this.licenseNumber = '',
    this.licenseRatings = '',
    this.employmentType = '',
    this.activeSince = '',
    required this.flightSchools,
    this.adminOnlyFlightSchools = const [],
    required this.events,
    this.tandemDuties = const [],
    this.tandemDemands = const [],
    this.tandemPilotNamesById = const {},
    this.hasLoadedArchive = false,
  });

  /// Alle Flugschulen, bei denen der Nutzer als Administrator eingetragen ist
  /// (inkl. Schulen ohne reguläre Team-Mitgliedschaft).
  List<FlightSchoolUserView> get adminFlightSchools {
    final byId = <String, FlightSchoolUserView>{};
    for (final fs in flightSchools) {
      if (fs.adminUserIds.contains(id)) {
        byId[fs.id] = fs;
      }
    }
    for (final fs in adminOnlyFlightSchools) {
      byId.putIfAbsent(fs.id, () => fs);
    }
    final list = byId.values.toList()
      ..sort(
        (a, b) => a.displayName.toLowerCase().compareTo(
              b.displayName.toLowerCase(),
            ),
      );
    return list;
  }

  bool get isAdmin => adminFlightSchools.isNotEmpty;

  bool get hasEmergencyContact =>
      emergencyContactName.trim().isNotEmpty ||
      emergencyContactPhone.trim().isNotEmpty;

  String resolveTandemPilotName(String userId) {
    if (userId == id) return name.isNotEmpty ? name : mail;
    return tandemPilotNamesById[userId] ?? 'Tandempilot';
  }

  factory UserModelUserView.fromJson(Map<String, dynamic> json) {
    return UserModelUserView(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      mail: (json['mail'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      avatarUrl: (json['avatarUrl'] ?? '').toString(),
      avatarFileId: (json['avatarFileId'] ?? '').toString(),
      emergencyContactName: (json['emergencyContactName'] ?? '').toString(),
      emergencyContactRelation:
          (json['emergencyContactRelation'] ?? '').toString(),
      emergencyContactPhone: (json['emergencyContactPhone'] ?? '').toString(),
      birthDate: (json['birthDate'] ?? '').toString(),
      address: (json['address'] ?? '').toString(),
      licenseNumber: (json['licenseNumber'] ?? '').toString(),
      licenseRatings: (json['licenseRatings'] ?? '').toString(),
      employmentType: (json['employmentType'] ?? '').toString(),
      activeSince: (json['activeSince'] ?? '').toString(),
      flightSchools: (json['flightSchools'] as List? ?? const [])
          .map((fs) => FlightSchoolUserView.fromJson(fs))
          .toList(),
      adminOnlyFlightSchools:
          (json['adminOnlyFlightSchools'] as List? ?? const [])
              .map((fs) => FlightSchoolUserView.fromJson(fs))
              .toList(),
      events: (json['events'] as List? ?? const [])
          .map((e) => Event.fromJson(e))
          .toList(),
      tandemDuties: (json['tandemDuties'] as List? ?? const [])
          .map((d) => TandemDuty.fromJson(Map<String, dynamic>.from(d)))
          .toList(),
      tandemDemands: (json['tandemDemands'] as List? ?? const [])
          .map((d) => TandemDemand.fromJson(Map<String, dynamic>.from(d)))
          .toList(),
      tandemPilotNamesById:
          Map<String, String>.from(json['tandemPilotNamesById'] ?? const {}),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'mail': mail,
      'phone': phone,
      'avatarUrl': avatarUrl,
      'avatarFileId': avatarFileId,
      'emergencyContactName': emergencyContactName,
      'emergencyContactRelation': emergencyContactRelation,
      'emergencyContactPhone': emergencyContactPhone,
      'birthDate': birthDate,
      'address': address,
      'licenseNumber': licenseNumber,
      'licenseRatings': licenseRatings,
      'employmentType': employmentType,
      'activeSince': activeSince,
      'flightSchools': flightSchools.map((fs) => fs.toJson()).toList(),
      'adminOnlyFlightSchools':
          adminOnlyFlightSchools.map((fs) => fs.toJson()).toList(),
      'events': events.map((e) => e.toJson()).toList(),
      'tandemDuties': tandemDuties.map((d) => d.toJson()).toList(),
      'tandemDemands': tandemDemands.map((d) => d.toJson()).toList(),
      'tandemPilotNamesById': tandemPilotNamesById,
    };
  }

  UserModelUserView copyWith({
    String? id,
    String? name,
    String? mail,
    String? phone,
    String? avatarUrl,
    String? avatarFileId,
    String? emergencyContactName,
    String? emergencyContactRelation,
    String? emergencyContactPhone,
    String? birthDate,
    String? address,
    String? licenseNumber,
    String? licenseRatings,
    String? employmentType,
    String? activeSince,
    List<FlightSchoolUserView>? flightSchools,
    List<FlightSchoolUserView>? adminOnlyFlightSchools,
    List<Event>? events,
    List<TandemDuty>? tandemDuties,
    List<TandemDemand>? tandemDemands,
    Map<String, String>? tandemPilotNamesById,
    bool? hasLoadedArchive,
  }) {
    return UserModelUserView(
      id: id ?? this.id,
      name: name ?? this.name,
      mail: mail ?? this.mail,
      phone: phone ?? this.phone,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      avatarFileId: avatarFileId ?? this.avatarFileId,
      emergencyContactName: emergencyContactName ?? this.emergencyContactName,
      emergencyContactRelation:
          emergencyContactRelation ?? this.emergencyContactRelation,
      emergencyContactPhone:
          emergencyContactPhone ?? this.emergencyContactPhone,
      birthDate: birthDate ?? this.birthDate,
      address: address ?? this.address,
      licenseNumber: licenseNumber ?? this.licenseNumber,
      licenseRatings: licenseRatings ?? this.licenseRatings,
      employmentType: employmentType ?? this.employmentType,
      activeSince: activeSince ?? this.activeSince,
      flightSchools: flightSchools ?? this.flightSchools,
      adminOnlyFlightSchools:
          adminOnlyFlightSchools ?? this.adminOnlyFlightSchools,
      events: events ?? this.events,
      tandemDuties: tandemDuties ?? this.tandemDuties,
      tandemDemands: tandemDemands ?? this.tandemDemands,
      tandemPilotNamesById:
          tandemPilotNamesById ?? this.tandemPilotNamesById,
      hasLoadedArchive: hasLoadedArchive ?? this.hasLoadedArchive,
    );
  }

  static UserModelUserView empty() {
    return UserModelUserView(
      id: '',
      name: '',
      mail: '',
      phone: '',
      flightSchools: [],
      events: [],
    );
  }

  @override
  String toString() {
    return 'UserModel(id: $id, name: $name, mail: $mail, phone: $phone, '
        'flightSchools: $flightSchools, events: $events)';
  }
}
