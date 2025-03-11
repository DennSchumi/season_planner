import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:season_planer/core/appwrite_config.dart';

class AuthService {
  final Client client = Client()
      .setEndpoint(AppwriteConfig().appwriteEnpoint)
      .setProject(AppwriteConfig().projectId);

  late final Account _account;

  AuthService() {
    _account = Account(client);
  }

  /// Registers a new user with email, password, and name
  Future<models.User?> signUp(String email, String password, String name) async {
    try {
      return await _account.create(
        userId: ID.unique(),
        email: email,
        password: password,
        name: name,
      );
    } catch (e) {
      print("Error during registration: $e");
      return null;
    }
  }

  /// Logs in a user with email and password
  Future<bool> login(String email, String password) async {
    try {
      await _account.createEmailPasswordSession(email: email, password: password);
      return true;
    } catch (e) {
      print("Error during login: $e");
      return false;
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

  /// Retrieves the currently logged-in user's details
  Future<models.User?> getCurrentUser() async {
    try {
      return await _account.get();
    } catch (e) {
      print("Error retrieving user: $e");
      return null;
    }
  }

  /// Checks if the user has an active session
  Future<bool> isLoggedIn() async {
    try {
      final sessionList = await _account.listSessions();
      return sessionList.sessions.isNotEmpty;
    } catch (e) {
      print("Error checking session: $e");
      return false;
    }
  }

  /// Sends a password reset email to the user
  Future<bool> resetPassword(String email) async {
    try {
      await _account.createRecovery(email: email, url: "https://your-app.com/reset-password");
      return true;
    } catch (e) {
      print("Error resetting password: $e");
      return false;
    }
  }
}
