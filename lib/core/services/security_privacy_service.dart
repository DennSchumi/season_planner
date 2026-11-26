import 'dart:convert';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/enums.dart' as aw_enums;
import 'package:flutter/foundation.dart';
import 'package:season_planner/core/appwrite_config.dart';
import 'package:season_planner/core/services/auth_service.dart';

/// Zentrale Schnittstelle zur serverseitigen Appwrite Function `tragegurt_security`:
/// - Phase 2: Appwrite-Team-Synchronisierung, Dokumenten-Dateirechte (`fileSecurity`),
///   Freigabe-Entzug bei Austritt, datensparsame Team-Profile & serverseitig
///   geprüfte Admin-Aktionen.
/// - Phase 3: DSGVO-Betroffenenrechte (Art. 15/20 Datenexport & Art. 17 Kontolöschung).
class SecurityPrivacyService {
  static final SecurityPrivacyService _instance =
      SecurityPrivacyService._internal();
  factory SecurityPrivacyService() => _instance;
  SecurityPrivacyService._internal();

  Client get _client => AuthService().client;
  late final Functions _functions = Functions(_client);

  Future<Map<String, dynamic>> _call(Map<String, dynamic> payload) async {
    final cfg = AppwriteConfig();
    final exec = await _functions.createExecution(
      functionId: cfg.securityFunctionId,
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
        (decoded['error'] ?? 'Aktion fehlgeschlagen (${exec.responseStatusCode}).')
            .toString(),
      );
    }
    return decoded;
  }

  /// Synchronisiert das Appwrite-Team (`team:<flightSchoolId>`) sowie die
  /// Profil-Leserechte der Mitglieder dieser Flugschule.
  Future<void> syncSchoolTeam(String flightSchoolId) async {
    if (flightSchoolId.trim().isEmpty) return;
    try {
      await _call({
        'action': 'syncSchoolTeam',
        'flightSchoolId': flightSchoolId.trim(),
      });
    } catch (e) {
      debugPrint('SecurityPrivacyService.syncSchoolTeam warning: $e');
    }
  }

  /// Synchronisiert DB-Row- UND Storage-File-Permissions eines Qualifikationsdokuments
  /// exakt auf den Besitzer + explizit freigegebene Flugschul-Admins.
  Future<void> syncDocumentPermissions(String documentId) async {
    if (documentId.trim().isEmpty) return;
    try {
      await _call({
        'action': 'syncDocumentPermissions',
        'documentId': documentId.trim(),
      });
    } catch (e) {
      debugPrint('SecurityPrivacyService.syncDocumentPermissions warning: $e');
    }
  }

  /// Entzieht beim Austritt / Entfernen sofort alle Dokument-Freigaben,
  /// Team-Rechte und Profil-Leserechte für die betroffene Flugschule.
  Future<void> revokeSchoolAccess({
    required String flightSchoolId,
    String? targetUserId,
  }) async {
    if (flightSchoolId.trim().isEmpty) return;
    try {
      await _call({
        'action': 'revokeSchoolAccess',
        'flightSchoolId': flightSchoolId.trim(),
        if (targetUserId != null && targetUserId.trim().isNotEmpty)
          'targetUserId': targetUserId.trim(),
      });
    } catch (e) {
      debugPrint('SecurityPrivacyService.revokeSchoolAccess warning: $e');
    }
  }

  /// Lädt datensparsam ausschließlich Name + Avatar-URL von aktiven Kollegen
  /// der eigenen Flugschulen (ohne Adresse, Geburtsdatum, Notfallkontakt etc.).
  Future<Map<String, ({String name, String avatarUrl})>> getTeamPublicProfiles(
    List<String> flightSchoolIds,
  ) async {
    final ids = flightSchoolIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return const {};
    try {
      final res = await _call({
        'action': 'getTeamPublicProfiles',
        'flightSchoolIds': ids,
      });
      final rawProfiles = res['profiles'];
      if (rawProfiles is! Map) return const {};
      final out = <String, ({String name, String avatarUrl})>{};
      for (final entry in rawProfiles.entries) {
        final v = entry.value;
        if (v is Map) {
          out[entry.key.toString()] = (
            name: (v['name'] ?? '').toString(),
            avatarUrl: (v['avatarUrl'] ?? '').toString(),
          );
        }
      }
      return out;
    } catch (e) {
      debugPrint('SecurityPrivacyService.getTeamPublicProfiles warning: $e');
      return const {};
    }
  }

  /// Führt eine serverseitig rollengeprüfte Admin-Aktion inkl. fälschungssicherem
  /// Audit-Log aus.
  Future<bool> runAdminAction({
    required String flightSchoolId,
    required String operation,
    Map<String, dynamic> params = const {},
  }) async {
    try {
      await _call({
        'action': 'adminAction',
        'flightSchoolId': flightSchoolId.trim(),
        'operation': operation,
        ...params,
      });
      return true;
    } catch (e) {
      debugPrint('SecurityPrivacyService.runAdminAction($operation) error: $e');
      return false;
    }
  }

  /// Prüft serverseitig & DSGVO-datensparsam Doppelbesetzungen über ALLE
  /// Flugschulen hinweg (Events & Tandem-Dienste).
  /// - Für Admins (`otherSchoolsOnly: true`): liefert neutrale Konflikthinweise
  ///   für fremde Flugschulen ohne Preisgabe fremder Event-/Schulnamen.
  /// - Für Nutzer-Selbstprüfung (`userIds: [ownUserId]`, `otherSchoolsOnly: false`):
  ///   prüft alle eigenen Einsätze über alle Flugschulen hinweg.
  Future<Map<String, List<String>>> checkCrossSchoolConflicts({
    String flightSchoolId = '',
    required List<String> userIds,
    required DateTime startTime,
    required DateTime endTime,
    String? ignoreEventId,
    String? ignoreDutyId,
    bool otherSchoolsOnly = true,
  }) async {
    final cleaned = userIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (cleaned.isEmpty) return const {};
    try {
      final res = await _call({
        'action': 'checkCrossSchoolConflicts',
        if (flightSchoolId.trim().isNotEmpty)
          'flightSchoolId': flightSchoolId.trim(),
        'userIds': cleaned,
        'startTime': startTime.toUtc().toIso8601String(),
        'endTime': endTime.toUtc().toIso8601String(),
        if (ignoreEventId != null && ignoreEventId.trim().isNotEmpty)
          'ignoreEventId': ignoreEventId.trim(),
        if (ignoreDutyId != null && ignoreDutyId.trim().isNotEmpty)
          'ignoreDutyId': ignoreDutyId.trim(),
        'otherSchoolsOnly': otherSchoolsOnly,
      });
      final rawMap = res['conflictsByUserId'];
      if (rawMap is! Map) return const {};
      final out = <String, List<String>>{};
      for (final entry in rawMap.entries) {
        final v = entry.value;
        if (v is List) {
          final list = v
              .map((x) => x.toString().trim())
              .where((x) => x.isNotEmpty)
              .toList();
          if (list.isNotEmpty) {
            out[entry.key.toString()] = list;
          }
        }
      }
      return out;
    } catch (e) {
      debugPrint('SecurityPrivacyService.checkCrossSchoolConflicts warning: $e');
      return const {};
    }
  }

  /// Prüft serverseitig, ob beendete Events alle erforderlichen Checklisten und
  /// Stundenzettel vollständig haben, und setzt deren Status automatisch auf `done`.
  Future<List<String>> checkEventCompletion({
    required String flightSchoolId,
    String? eventId,
  }) async {
    if (flightSchoolId.trim().isEmpty) return const [];
    try {
      final res = await _call({
        'action': 'checkEventCompletion',
        'flightSchoolId': flightSchoolId.trim(),
        if (eventId != null && eventId.trim().isNotEmpty)
          'eventId': eventId.trim(),
      });
      final raw = res['completedEventIds'];
      if (raw is List) {
        return raw
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
      return const [];
    } catch (e) {
      debugPrint('SecurityPrivacyService.checkEventCompletion warning: $e');
      return const [];
    }
  }

  /// Legt serverseitig Beitrittsanfragen (`status: requested`) für eine oder
  /// mehrere Flugschulen an – inkl. korrekter Admin-Team-Permissions (da der
  /// anfragende Nutzer clientseitig noch kein Mitglied des Ziel-Teams ist).
  Future<int> requestJoinFlightSchools(List<String> flightSchoolIds) async {
    final ids = flightSchoolIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return 0;
    final res = await _call({
      'action': 'requestJoinFlightSchools',
      'flightSchoolIds': ids,
    });
    final count = res['createdCount'];
    if (count is int) return count;
    return int.tryParse(count?.toString() ?? '') ?? 0;
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

  // ==================== STANDARD-PERMISSION-HELPER ====================

  static List<String> schoolReadAdminWritePerms(String flightSchoolId) => [
        Permission.read(Role.team(flightSchoolId)),
        Permission.update(Role.team(flightSchoolId, 'admin')),
        Permission.delete(Role.team(flightSchoolId, 'admin')),
      ];

  static List<String> schoolMemberUpdatePerms(String flightSchoolId) => [
        Permission.read(Role.team(flightSchoolId)),
        Permission.update(Role.team(flightSchoolId)),
        Permission.delete(Role.team(flightSchoolId, 'admin')),
      ];

  static List<String> ownerAndSchoolAdminPerms({
    required String userId,
    required String flightSchoolId,
    bool allowOwnerDelete = false,
  }) =>
      [
        Permission.read(Role.user(userId)),
        Permission.update(Role.user(userId)),
        if (allowOwnerDelete) Permission.delete(Role.user(userId)),
        Permission.read(Role.team(flightSchoolId, 'admin')),
        Permission.update(Role.team(flightSchoolId, 'admin')),
        Permission.delete(Role.team(flightSchoolId, 'admin')),
      ];

  static List<String> ownerOnlyPerms(String userId) => [
        Permission.read(Role.user(userId)),
        Permission.update(Role.user(userId)),
        Permission.delete(Role.user(userId)),
      ];
}
