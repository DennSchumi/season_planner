import 'package:season_planner/core/data/models/event_application_model.dart';
import 'package:season_planner/user/data/models/flight_school_model_user_view.dart';

import '../../../core/data/models/event_assigment_model.dart';

class UserModelUserView {
  final String id;
  final String name;
  final String mail;
  final String phone;
  final List<FlightSchoolUserView> flightSchools;
  final List<EventAssignment> assignments;
  final List<PositionApplication> applications;

  const UserModelUserView({
    required this.id,
    required this.name,
    required this.mail,
    required this.phone,
    required this.flightSchools,
    required this.assignments,
    required this.applications,
  });

  factory UserModelUserView.fromJson(Map<String, dynamic> json) {
    return UserModelUserView(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      mail: (json['mail'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      flightSchools: (json['flightSchools'] as List? ?? const [])
          .map((fs) => FlightSchoolUserView.fromJson(
        Map<String, dynamic>.from(fs as Map),
      ))
          .toList(),
      assignments: (json['assignments'] as List? ?? const [])
          .map((a) => EventAssignment.fromJson(
        Map<String, dynamic>.from(a as Map),
      ))
          .toList(),
      applications: (json['applications'] as List? ?? const [])
          .map((a) => PositionApplication.fromMap(
        Map<String, dynamic>.from(a as Map),
      ))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'mail': mail,
      'phone': phone,
      'flightSchools': flightSchools.map((fs) => fs.toJson()).toList(),
      'assignments': assignments.map((a) => a.toJson()).toList(),
      'applications': applications.map((a) => a.toMap()).toList(),
    };
  }

  UserModelUserView copyWith({
    String? id,
    String? name,
    String? mail,
    String? phone,
    List<FlightSchoolUserView>? flightSchools,
    List<EventAssignment>? assignments,
    List<PositionApplication>? applications,
  }) {
    return UserModelUserView(
      id: id ?? this.id,
      name: name ?? this.name,
      mail: mail ?? this.mail,
      phone: phone ?? this.phone,
      flightSchools: flightSchools ?? this.flightSchools,
      assignments: assignments ?? this.assignments,
      applications: applications ?? this.applications,
    );
  }

  static UserModelUserView empty() {
    return const UserModelUserView(
      id: '',
      name: '',
      mail: '',
      phone: '',
      flightSchools: [],
      assignments: [],
      applications: [],
    );
  }

  @override
  String toString() {
    return 'UserModelUserView('
        'id: $id, '
        'name: $name, '
        'mail: $mail, '
        'phone: $phone, '
        'flightSchools: $flightSchools, '
        'assignments: $assignments, '
        'applications: $applications'
        ')';
  }
}