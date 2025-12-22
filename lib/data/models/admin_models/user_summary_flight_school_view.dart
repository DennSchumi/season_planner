class UserSummary {
  final String id;
  final String name;
  final String mail;
  final String phone;

  UserSummary({
    required this.id,
    required this.name,
    required this.mail,
    required this.phone,
  });

  factory UserSummary.fromJson(Map<String, dynamic> json) {
    return UserSummary(
      id: json['id'] as String,
      name: json['name'] as String,
      mail: json['mail'] as String,
      phone: json['phone'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'mail': mail,
    'phone': phone,
  };
}
