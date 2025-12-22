import 'package:season_planer/data/models/event_model.dart';
import 'package:season_planer/data/models/user_models/flight_school_model_user_view.dart';

class UserModelUserView {
  final String id;
  final String name;
  final String mail;
  final String phone;
  final List<FlightSchoolUserView> flightSchools;
  final List<Event> events;

  // Constructor
  UserModelUserView({
    required this.id,
    required this.name,
    required this.mail,
    required this.phone,
    required this.flightSchools,
    required this.events,
  });

  // Factory method to create an instance from a JSON object
  factory UserModelUserView.fromJson(Map<String, dynamic> json) {
    return UserModelUserView(
      id: json['id'] as String,
      name: json['name'] as String,
      mail: json['mail'] as String,
      phone: json['phone'] as String,
      flightSchools: (json['flightSchools'] as List)
          .map((fs) => FlightSchoolUserView.fromJson(fs))
          .toList(),
      events: (json['events'] as List)
          .map((e) => Event.fromJson(e))
          .toList(),
    );
  }

  // Convert object to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'mail': mail,
      'phone': phone,
      'flightSchools': flightSchools.map((fs) => fs.toJson()).toList(),
      'events': events.map((e) => e.toJson()).toList(),
    };
  }

  // Copy method to update specific fields
  UserModelUserView copyWith({
    String? id,
    String? name,
    String? mail,
    String? phone,
    List<FlightSchoolUserView>? flightSchools,
    List<Event>? events,
  }) {
    return UserModelUserView(
      id: id ?? this.id,
      name: name ?? this.name,
      mail: mail ?? this.mail,
      phone: phone ?? this.phone,
      flightSchools: flightSchools ?? this.flightSchools,
      events: events ?? this.events,
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
