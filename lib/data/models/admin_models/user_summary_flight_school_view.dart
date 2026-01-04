import 'package:season_planer/data/enums/event_role_enum.dart';

class UserSummary {
  final String id;
  final String name;
  final String mail;
  final String phone;
  final List<EventRoleEnum> roles;

  UserSummary({
    required this.id,
    required this.name,
    required this.mail,
    required this.phone,
    required this.roles,
  });

  factory UserSummary.fromJson(Map<String, dynamic> json) {
    final rawRoles = json['roles'];

    return UserSummary(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      mail: (json['mail'] ?? json['email'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      roles: parseRoles(rawRoles),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'mail': mail,
    'phone': phone,
    'roles': roles.map((r) => r.name).toList(),
  };


  static List<EventRoleEnum> parseRoles(dynamic raw) {
    if (raw is! List) return [];

    return raw
        .map((e) {
      try {
        return EventRoleEnum.values.byName(e.toString());
      } catch (_) {
        return null;
      }
    })
        .whereType<EventRoleEnum>()
        .toList();
  }
}
