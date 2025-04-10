import 'package:season_planer/data/models/event_model.dart';
import 'package:season_planer/data/models/flight_school_model.dart';

class UserModel {
  final String id;
  final String name;
  final String mail;
  final String phone;
  final List<FlightSchool> flightSchools;
  final List<Event> events;

  // Constructor
  UserModel({
    required this.id,
    required this.name,
    required this.mail,
    required this.phone,
    required this.flightSchools,
    required this.events,
  });

  // Factory method to create an instance from a JSON object
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      name: json['name'] as String,
      mail: json['mail'] as String,
      phone: json['phone'] as String,
      flightSchools: (json['flightSchools'] as List)
          .map((fs) => FlightSchool.fromJson(fs))
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
  UserModel copyWith({
    String? id,
    String? name,
    String? mail,
    String? phone,
    List<FlightSchool>? flightSchools,
    List<Event>? events,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      mail: mail ?? this.mail,
      phone: phone ?? this.phone,
      flightSchools: flightSchools ?? this.flightSchools,
      events: events ?? this.events,
    );
  }

  // Leerer Benutzer (z. B. für Initialzustand)
  static UserModel empty() {
    return UserModel(
      id: '',
      name: '',
      mail: '',
      phone: '',
      flightSchools: [],
      events: [],
    );
  }
  // Debugging & Readable Output
  @override
  String toString() {
    return 'UserModel(id: $id, name: $name, mail: $mail, phone: $phone, '
        'flightSchools: $flightSchools, events: $events)';
  }
}
