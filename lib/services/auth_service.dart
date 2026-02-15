import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:season_planner/core/appwrite_config.dart';

class AuthService {
  final Client client = Client()
      .setEndpoint(AppwriteConfig().appwriteEnpoint)
      .setProject(AppwriteConfig().projectId)
      .setSelfSigned(status: true);


  static final AuthService _instance = AuthService._internal();

  factory AuthService() {
    return _instance;
  }
  AuthService._internal();

  late final Account _account;

  void init() {
    _account = Account(client);
  }

Future<void> testLogin() async {
  await _account.createEmailPasswordSession(email: "test@test.de", password: "testpass");
  }

  /// Registers a new user with email, password, and name
  Future<models.User> signUp(String email, String password, String name) async {
    try {
      final user = await _account.create(
        userId: ID.unique(),
        email: email,
        password: password,
        name: name,
      );

      return user;
    } on AppwriteException catch (e) {
      print("Appwrite signUp failed: ${e.type} (${e.code}) ${e.message}");
      rethrow;
    } catch (e) {
      print("Unknown signUp error: $e");
      rethrow;
    }
  }


  /// Logs in a user with email and password
  Future<Object> login(String email, String password) async {
    try {
      var result = await _account.createEmailPasswordSession(email: email, password: password);
      print(result);
      return "";
    } catch (e) {
      print("Error during login: $e");
      return e;
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
