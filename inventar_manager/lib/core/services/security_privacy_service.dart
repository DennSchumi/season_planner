import 'dart:convert';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/enums.dart' as aw_enums;
import 'package:inventar_manager/core/appwrite_config.dart';
import 'package:inventar_manager/core/services/auth_service.dart';

/// Zentrale Schnittstelle zur serverseitigen Appwrite Function `tragegurt_security`
/// (DSGVO Art. 15/20 Datenexport & Art. 17 Kontolöschung + Standard-Permissions).
class SecurityPrivacyService {
  static final SecurityPrivacyService _instance =
      SecurityPrivacyService._internal();
  factory SecurityPrivacyService() => _instance;
  SecurityPrivacyService._internal();

  Client get _client => AuthService().client;
  late final Functions _functions = Functions(_client);

  Future<Map<String, dynamic>> _call(Map<String, dynamic> payload) async {
    final exec = await _functions.createExecution(
      functionId: AppwriteConfig.securityFunctionId,
      body: jsonEncode(payload),
      xasync: false,
      method: aw_enums.ExecutionMethod.pOST,
      headers: const {'Content-Type': 'application/json'},
    );
    final raw = exec.responseBody.trim();
    if (raw.isEmpty) {
      throw Exception(
        'Leere Antwort vom Sicherheitsdienst (HTTP ${exec.responseStatusCode}).',
      );
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Ungültige Antwort vom Sicherheitsdienst.');
    }
    if (exec.responseStatusCode >= 400 || decoded['ok'] == false) {
      throw Exception(
        (decoded['error'] ??
                'Aktion fehlgeschlagen (${exec.responseStatusCode}).')
            .toString(),
      );
    }
    return decoded;
  }

  /// Art. 15 & Art. 20 DSGVO: Lädt alle eigenen personenbezogenen Daten als JSON.
  Future<Map<String, dynamic>> exportMyData() async {
    final res = await _call({'action': 'exportMyData'});
    final data = res['data'];
    if (data is Map<String, dynamic>) return data;
    return res;
  }

  /// Art. 17 DSGVO: Löscht das eigene Konto inkl. Profil, Dokumenten & Auth-User.
  Future<void> deleteMyAccount({required String confirmEmail}) async {
    await _call({
      'action': 'deleteMyAccount',
      'confirmEmail': confirmEmail.trim(),
    });
  }

  /// Standard-Row-/File-Permissions für Inventardaten einer Flugschule
  /// (`rowSecurity=true` / `fileSecurity=true`).
  static List<String> schoolMemberUpdatePerms(String flightSchoolId) => [
        Permission.read(Role.team(flightSchoolId)),
        Permission.update(Role.team(flightSchoolId)),
        Permission.delete(Role.team(flightSchoolId, 'admin')),
      ];

  static List<String> schoolReadAdminWritePerms(String flightSchoolId) => [
        Permission.read(Role.team(flightSchoolId)),
        Permission.update(Role.team(flightSchoolId, 'admin')),
        Permission.delete(Role.team(flightSchoolId, 'admin')),
      ];
}
