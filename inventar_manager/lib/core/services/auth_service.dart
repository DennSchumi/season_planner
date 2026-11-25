import 'dart:convert';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/enums.dart' as enums;
import 'package:appwrite/models.dart' as models;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:inventar_manager/core/appwrite_config.dart';

class AuthService {
  final Client client = Client()
      .setEndpoint(AppwriteConfig.endpoint)
      .setProject(AppwriteConfig.projectId);

  static final AuthService _instance = AuthService._internal();

  factory AuthService() {
    return _instance;
  }
  AuthService._internal();

  late final Account _account;
  late final TablesDB _tablesDB;
  late final Storage _storage;
  bool _initialized = false;

  void init() {
    if (_initialized) return;
    _account = Account(client);
    _tablesDB = TablesDB(client);
    _storage = Storage(client);
    _initialized = true;
  }

  Account get account {
    if (!_initialized) init();
    return _account;
  }

  TablesDB get tablesDB {
    if (!_initialized) init();
    return _tablesDB;
  }

  Storage get storage {
    if (!_initialized) init();
    return _storage;
  }

  models.User? _currentUser;
  models.User? get currentUser => _currentUser;

  /// Startet eine E-Mail-Registrierung per 6-stelligem Einmal-Code (Email OTP).
  /// Sendet den Code über Appwrite an [email] und gibt die zugehörige `userId` zurück.
  Future<String> startEmailOtpRegistration(String email) async {
    try {
      try {
        await account.deleteSession(sessionId: 'current');
      } catch (_) {}

      final token = await account.createEmailToken(
        userId: ID.unique(),
        email: email.trim(),
      );
      return token.userId;
    } on AppwriteException catch (e) {
      debugPrint(
        "Appwrite startEmailOtpRegistration failed: ${e.type} (${e.code}) ${e.message}",
      );
      rethrow;
    }
  }

  /// Schließt die E-Mail-OTP-Registrierung ab: prüft den 6-stelligen [otpCode],
  /// startet die Session, setzt Passwort + Name (nur bei neuem Konto) und legt
  /// erst danach die Profil-Zeile in `core_db.users` an.
  Future<({models.User user, bool alreadyExisted})>
      completeEmailOtpRegistration({
    required String userId,
    required String otpCode,
    required String password,
    required String name,
    String phone = '',
    bool legalAccepted = false,
  }) async {
    try {
      try {
        await account.deleteSession(sessionId: 'current');
      } catch (_) {}

      await account.createSession(
        userId: userId.trim(),
        secret: otpCode.trim(),
      );

      var user = await account.get();
      final alreadyHasPassword = user.passwordUpdate.trim().isNotEmpty;

      if (!alreadyHasPassword) {
        user = await account.updatePassword(password: password);
        if (name.trim().isNotEmpty) {
          user = await account.updateName(name: name.trim());
        }
      } else if (user.name.trim().isEmpty && name.trim().isNotEmpty) {
        try {
          user = await account.updateName(name: name.trim());
        } catch (_) {}
      }

      if (phone.trim().isNotEmpty || legalAccepted) {
        try {
          final mergedPrefs = Map<String, dynamic>.from(user.prefs.data);
          if (phone.trim().isNotEmpty) {
            mergedPrefs['phone'] = phone.trim();
          }
          if (legalAccepted) {
            mergedPrefs['legal_accepted_at'] = DateTime.now().toIso8601String();
            mergedPrefs['legal_version'] = '2026-11';
          }
          await account.updatePrefs(prefs: mergedPrefs);
        } catch (_) {}
      }

      _currentUser = user;
      await ensureUserProfileRow(
        user: user,
        phoneOverride: phone.trim(),
      );

      return (user: user, alreadyExisted: alreadyHasPassword);
    } on AppwriteException catch (e) {
      debugPrint(
        "Appwrite completeEmailOtpRegistration failed: ${e.type} (${e.code}) ${e.message}",
      );
      rethrow;
    }
  }

  /// Spiegelt das Google-OAuth-Profilbild DSGVO-konform in den eigenen
  /// Appwrite-Bucket `user_avatars`, damit beim Anzeigen keine externen
  /// Anfragen an Google-Server ausgelöst werden.
  Future<({String url, String fileId})?> _mirrorOAuthAvatarToOwnStorage() async {
    try {
      final session = await account.getSession(sessionId: 'current');
      final provider = session.provider.toLowerCase();
      final token = session.providerAccessToken;
      if (token.isEmpty) return null;

      if (provider == 'google') {
        final res = await http.get(
          Uri.parse('https://www.googleapis.com/oauth2/v3/userinfo'),
          headers: {'Authorization': 'Bearer $token'},
        );
        if (res.statusCode == 200) {
          final json = jsonDecode(res.body);
          if (json is Map && json['picture'] is String) {
            final pic = (json['picture'] as String).trim();
            if (pic.isEmpty) return null;
            final imgRes = await http.get(Uri.parse(pic));
            if (imgRes.statusCode != 200 || imgRes.bodyBytes.isEmpty) {
              return null;
            }
            if (imgRes.bodyBytes.length > 5 * 1024 * 1024) return null;

            final contentType =
                (imgRes.headers['content-type'] ?? '').toLowerCase();
            final ext = contentType.contains('png')
                ? 'png'
                : contentType.contains('webp')
                    ? 'webp'
                    : 'jpg';
            final uploaded = await storage.createFile(
              bucketId: AppwriteConfig.userAvatarsBucketId,
              fileId: ID.unique(),
              file: InputFile.fromBytes(
                bytes: imgRes.bodyBytes,
                filename: 'oauth_avatar.$ext',
              ),
              permissions: [
                Permission.read(Role.users()),
                Permission.update(Role.user(session.userId)),
                Permission.delete(Role.user(session.userId)),
              ],
            );
            return (
              url: AppwriteConfig.fileViewUrl(
                AppwriteConfig.userAvatarsBucketId,
                uploaded.$id,
              ),
              fileId: uploaded.$id,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('_mirrorOAuthAvatarToOwnStorage error: $e');
    }
    return null;
  }

  /// Registriert einen neuen Tragegurt-Account direkt (Legacy-Fallback).
  Future<models.User> signUp(
    String email,
    String password,
    String name, {
    String phone = '',
  }) async {
    try {
      final user = await account.create(
        userId: ID.unique(),
        email: email,
        password: password,
        name: name,
      );

      try {
        await account.deleteSession(sessionId: 'current');
      } catch (_) {}

      await account.createEmailPasswordSession(
        email: email,
        password: password,
      );

      if (phone.trim().isNotEmpty) {
        try {
          await account.updatePrefs(prefs: {'phone': phone.trim()});
        } catch (_) {}
      }

      _currentUser = await account.get();
      await ensureUserProfileRow(
        user: _currentUser ?? user,
        phoneOverride: phone.trim(),
      );

      return _currentUser ?? user;
    } on AppwriteException catch (e) {
      debugPrint("Appwrite signUp failed: ${e.type} (${e.code}) ${e.message}");
      rethrow;
    } catch (e) {
      debugPrint("Unknown signUp error: $e");
      rethrow;
    }
  }

  /// Stellt sicher, dass für den angemeldeten Appwrite-User eine Zeile
  /// in `core_db.users` existiert.
  Future<models.Row?> ensureUserProfileRow({
    models.User? user,
    String? phoneOverride,
  }) async {
    final current = user ?? await getCurrentUser();
    if (current == null) return null;

    final phone = (phoneOverride != null && phoneOverride.isNotEmpty)
        ? phoneOverride
        : (current.phone.isNotEmpty
            ? current.phone
            : (current.prefs.data['phone'] ?? '').toString());

    try {
      final existing = await tablesDB.listRows(
        databaseId: AppwriteConfig.coreDatabaseId,
        tableId: AppwriteConfig.spUsersCollectionId,
        queries: [
          Query.or([
            Query.equal('\$id', current.$id),
            Query.equal('auth_id', current.$id),
          ]),
          Query.limit(1),
        ],
      );

      if (existing.rows.isEmpty) {
        final mirroredAvatar = await _mirrorOAuthAvatarToOwnStorage();
        return await tablesDB.createRow(
          databaseId: AppwriteConfig.coreDatabaseId,
          tableId: AppwriteConfig.spUsersCollectionId,
          rowId: current.$id,
          data: {
            'auth_id': current.$id,
            'name': current.name,
            'email': current.email,
            'phone': phone,
            if (mirroredAvatar != null) ...{
              'avatar_url': mirroredAvatar.url,
              'avatar_file_id': mirroredAvatar.fileId,
            },
          },
          permissions: [
            Permission.read(Role.user(current.$id)),
            Permission.update(Role.user(current.$id)),
          ],
        );
      } else {
        final row = existing.rows.first;
        final updates = <String, dynamic>{};
        if ((row.data['auth_id'] ?? '').toString().isEmpty) {
          updates['auth_id'] = current.$id;
        }
        if ((row.data['name'] ?? '').toString().isEmpty &&
            current.name.isNotEmpty) {
          updates['name'] = current.name;
        }
        if ((row.data['email'] ?? '').toString().isEmpty &&
            current.email.isNotEmpty) {
          updates['email'] = current.email;
        }
        final existingAvatar =
            (row.data['avatar_url'] ?? '').toString().trim();
        final isExternalGoogleAvatar =
            existingAvatar.contains('googleusercontent.com');
        if (existingAvatar.isEmpty || isExternalGoogleAvatar) {
          final mirroredAvatar = await _mirrorOAuthAvatarToOwnStorage();
          if (mirroredAvatar != null) {
            updates['avatar_url'] = mirroredAvatar.url;
            updates['avatar_file_id'] = mirroredAvatar.fileId;
          }
        }
        if (updates.isNotEmpty) {
          return await tablesDB.updateRow(
            databaseId: AppwriteConfig.coreDatabaseId,
            tableId: AppwriteConfig.spUsersCollectionId,
            rowId: row.$id,
            data: updates,
          );
        }
        return row;
      }
    } catch (e) {
      debugPrint('ensureUserProfileRow error: $e');
      return null;
    }
  }

  /// Meldet einen Benutzer per E-Mail und Passwort an.
  /// Gibt `""` bei Erfolg oder eine verständliche Fehlermeldung zurück.
  Future<String> login(String email, String password) async {
    try {
      try {
        await account.deleteSession(sessionId: 'current');
      } catch (_) {}

      await account.createEmailPasswordSession(
        email: email.trim(),
        password: password,
      );
      _currentUser = await account.get();
      await ensureUserProfileRow(user: _currentUser);
      return "";
    } on AppwriteException catch (e) {
      if (e.code == 401) {
        return "E-Mail oder Passwort ist falsch.";
      }
      return formatAuthError(e);
    } catch (e) {
      return "Ein unerwarteter Fehler ist aufgetreten: $e";
    }
  }

  /// Meldet einen Benutzer per OAuth2 (Google oder Apple) über Appwrite an
  /// bzw. registriert ihn automatisch beim ersten Login.
  Future<bool> loginWithOAuth(enums.OAuthProvider provider) async {
    try {
      final successUrl = kIsWeb ? '${Uri.base.origin}/' : null;
      final failureUrl = kIsWeb ? '${Uri.base.origin}/?oauth=failed' : null;

      await account.createOAuth2Session(
        provider: provider,
        success: successUrl,
        failure: failureUrl,
      );

      final user = await getCurrentUser();
      if (user != null) {
        await ensureUserProfileRow(user: user);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("Error during OAuth (${provider.value}): $e");
      rethrow;
    }
  }

  /// Sendet eine Passwort-Zurücksetzen-E-Mail über Appwrite Auth Recovery.
  Future<void> resetPassword(String email) async {
    final baseUrl = kIsWeb && Uri.base.origin.startsWith('http')
        ? Uri.base.origin
        : AppwriteConfig.webBaseUrl;
    final cleanBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    await account.createRecovery(
      email: email.trim(),
      url: "$cleanBase/reset-password",
    );
  }

  /// Schließt das Zurücksetzen des Passworts mit dem Link-Token ab.
  Future<void> completePasswordRecovery({
    required String userId,
    required String secret,
    required String newPassword,
  }) async {
    await account.updateRecovery(
      userId: userId.trim(),
      secret: secret.trim(),
      password: newPassword,
    );
  }

  /// Meldet den aktuellen Benutzer ab.
  Future<void> logout() async {
    try {
      await account.deleteSession(sessionId: 'current');
      _currentUser = null;
    } catch (e) {
      debugPrint("Error during logout: $e");
    }
  }

  /// Gibt den aktuell eingeloggten Appwrite-Auth-Benutzer zurück.
  Future<models.User?> getCurrentUser() async {
    try {
      _currentUser = await account.get();
      return _currentUser;
    } catch (e) {
      debugPrint("Error retrieving user: $e");
      return null;
    }
  }

  /// Erzeugt ein JWT für den aktuell authentifizierten Benutzer.
  Future<String?> getJWT() async {
    try {
      final jwt = await account.createJWT();
      return jwt.jwt;
    } catch (e) {
      debugPrint("Error creating JWT: $e");
      return null;
    }
  }

  /// Prüft, ob eine aktive Session vorliegt (und pflegt ggf. das Profil nach).
  Future<bool> isLoggedIn() async {
    try {
      final sessionList = await account.listSessions();
      if (sessionList.sessions.isNotEmpty) {
        _currentUser = await account.get();
        await ensureUserProfileRow(user: _currentUser);
        return true;
      }
      return false;
    } on AppwriteException catch (e) {
      // HTTP 401 = einfach noch nicht angemeldet (normal beim Start).
      if (e.code != 401) {
        debugPrint("Error checking session: $e");
      }
      return false;
    } catch (e) {
      debugPrint("Error checking session: $e");
      return false;
    }
  }

  /// Übersetzt häufige Appwrite-Auth-Fehler in verständliche deutsche Hinweise.
  static String formatAuthError(Object error) {
    if (error is AppwriteException) {
      final type = (error.type ?? '').toLowerCase();
      final msg = (error.message ?? '').toLowerCase();
      if (type.contains('smtp_disabled') || msg.contains('smtp')) {
        return 'Der E-Mail-Versand (SMTP) ist auf dem Server noch nicht aktiv eingerichtet.';
      }
      if (type.contains('auth_method_disabled') ||
          (msg.contains('auth method') && msg.contains('disabled'))) {
        return 'Die E-Mail-Code-Anmeldung (Email OTP) ist in Appwrite noch nicht aktiviert.';
      }
      if (type.contains('rate_limit')) {
        return 'Zu viele Versuche in kurzer Zeit. Bitte warte einen Moment und versuche es erneut.';
      }
      if (type.contains('user_not_found')) {
        return 'Für diese E-Mail-Adresse wurde kein Benutzerkonto gefunden.';
      }
      if (type.contains('invalid_token') ||
          type.contains('expired') ||
          msg.contains('invalid token') ||
          msg.contains('expired')) {
        return 'Der Code bzw. Link ist ungültig oder abgelaufen. Bitte fordere einen neuen an.';
      }
      if (msg.contains('password') && msg.contains('8')) {
        return 'Das neue Passwort muss mindestens 8 Zeichen lang sein.';
      }
      if (msg.contains('invalid `url`') || type.contains('argument_invalid')) {
        return 'Die Ziel-URL für den Reset-Link ist in Appwrite nicht als erlaubte Web-Plattform hinterlegt.';
      }
      if (error.message != null && error.message!.trim().isNotEmpty) {
        return error.message!.trim();
      }
    }
    return error.toString();
  }
}
