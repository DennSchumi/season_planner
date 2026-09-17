import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:inventar_manager/core/appwrite_config.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  final Client client = Client()
      .setEndpoint(AppwriteConfig.endpoint)
      .setProject(AppwriteConfig.projectId)
      .setSelfSigned(status: kDebugMode);

  static final AuthService _instance = AuthService._internal();

  factory AuthService() {
    return _instance;
  }
  AuthService._internal();

  late final Account _account;

  void init() {
    _account = Account(client);
  }

  /// Logs in a user with email and password
  Future<Object> login(String email, String password) async {
    try {
      await _account.createEmailPasswordSession(email: email, password: password);
      _currentUser = await _account.get();
      return "";
    } on AppwriteException catch (e) {
      if (e.code == 401) {
        return "E-Mail oder Passwort ist falsch.";
      }
      return "Login fehlgeschlagen: ${e.message ?? e.toString()}";
    } catch (e) {
      return "Ein unerwarteter Fehler ist aufgetreten: $e";
    }
  }

  /// Logs out the current user by deleting the active session
  Future<void> logout() async {
    try {
      await _account.deleteSession(sessionId: 'current');
    } catch (e) {
      print("Error during logout: $e");
    }
  }

  models.User? _currentUser;
  models.User? get currentUser => _currentUser;

  /// Retrieves the currently logged-in user's details
  Future<models.User?> getCurrentUser() async {
    try {
      _currentUser = await _account.get();
      return _currentUser;
    } catch (e) {
      print("Error retrieving user: $e");
      return null;
    }
  }

  /// Creates a JWT token for the current authenticated user
  Future<String?> getJWT() async {
    try {
      final jwt = await _account.createJWT();
      return jwt.jwt;
    } catch (e) {
      print("Error creating JWT: $e");
      return null;
    }
  }

  /// Checks if the user has an active session
  Future<bool> isLoggedIn() async {
    try {
      final sessionList = await _account.listSessions();
      if (sessionList.sessions.isNotEmpty) {
        _currentUser = await _account.get();
        return true;
      }
      return false;
    } catch (e) {
      print("Error checking session: $e");
      return false;
    }
  }
}
