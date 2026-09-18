import 'package:flutter/foundation.dart';
import 'package:inventar_manager/core/services/database_service.dart';
import 'package:inventar_manager/core/appwrite_config.dart';
import 'package:appwrite/appwrite.dart';
import 'package:inventar_manager/core/services/auth_service.dart';

class FlightSchoolModel {
  final String id;
  final String name;

  FlightSchoolModel({required this.id, required this.name});
}

class FlightSchoolService extends ChangeNotifier {
  static final FlightSchoolService _instance = FlightSchoolService._internal();

  factory FlightSchoolService() {
    return _instance;
  }

  FlightSchoolService._internal();

  List<FlightSchoolModel> _schools = [];
  FlightSchoolModel? _selectedSchool;
  bool _isLoading = true;
  String? errorMessage;

  List<FlightSchoolModel> get schools => List.unmodifiable(_schools);
  FlightSchoolModel? get selectedSchool => _selectedSchool;
  bool get isLoading => _isLoading;

  Future<void> loadSchools() async {
    _isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final user = await AuthService().getCurrentUser();
      if (user == null) {
        throw Exception("Kein eingeloggter Nutzer gefunden.");
      }

      // 1. Fetch user profile from Season Planner DB to get memberships
      final userDocs = await DatabaseService().getDocuments(
        AppwriteConfig.spUsersCollectionId,
        databaseId: AppwriteConfig.seasonPlannerDatabaseId,
        queries: [Query.equal("auth_id", user.$id)],
      );

      Set<String> allowedSchoolIds = {};
      if (userDocs.isNotEmpty) {
        final userIdInDb = userDocs.first.$id;
        
        // Fetch memberships directly from the memberships collection
        final membershipsDocs = await DatabaseService().getDocuments(
          AppwriteConfig.spMembershipsCollectionId,
          databaseId: AppwriteConfig.seasonPlannerDatabaseId,
          queries: [Query.equal("users", userIdInDb)],
        );

        for (var mDoc in membershipsDocs) {
          final fs = mDoc.data["flightSchools"];
          if (fs != null) {
            if (fs is Map) {
              allowedSchoolIds.add(fs["\$id"] as String);
            } else if (fs is String) {
              allowedSchoolIds.add(fs);
            }
          }
        }
      }

      if (allowedSchoolIds.isEmpty) {
        _schools = [];
        errorMessage = "Du bist keiner Flugschule im Season Planner zugeordnet.\n(Debug: DB-User-ID: ${userDocs.isNotEmpty ? userDocs.first.$id : 'Nicht gefunden'} | Auth-ID: ${user.$id})";
      } else {
        // 2. Fetch flight schools from Season Planner DB
        try {
          final docs = await DatabaseService().getDocuments(
            AppwriteConfig.spFlightSchoolsCollectionId, 
            databaseId: AppwriteConfig.seasonPlannerDatabaseId,
            queries: [
              Query.equal("\$id", allowedSchoolIds.toList()),
              Query.limit(100)
            ]
          );
          
          _schools = docs.where((d) {
            final isEnabled = d.data['inventoryEnabled'];
            if (isEnabled != null && isEnabled == false) {
              return false;
            }
            return true;
          }).map((d) => FlightSchoolModel(
            id: d.$id,
            name: d.data['display_name'] ?? d.data['name'] ?? 'Unbekannt',
          )).toList();
        } catch (e) {
           errorMessage = "Fehler beim Laden der Flugschulen: $e";
           _schools = [];
        }
      }

      if (_schools.isNotEmpty) {
        // Keep the previously selected school if it's still in the allowed list
        if (_selectedSchool != null && _schools.any((s) => s.id == _selectedSchool!.id)) {
          // Keep it
        } else {
          _selectedSchool = _schools.first;
        }
      } else if (errorMessage == null) {
        errorMessage = "Keine aktiven Flugschulen gefunden. (Erlaubte IDs: ${allowedSchoolIds.join(', ')})";
        _selectedSchool = null;
      }
    } catch (e) {
      debugPrint("Error loading schools: $e");
      errorMessage = "Netzwerkfehler: Flugschulen konnten nicht geladen werden.";
      _schools = [];
      _selectedSchool = null;
    }

    _isLoading = false;
    notifyListeners();
  }

  void selectSchool(String id) {
    if (_schools.isEmpty) return;
    final newSchool = _schools.firstWhere((s) => s.id == id, orElse: () => _selectedSchool!);
    if (_selectedSchool == null || newSchool.id != _selectedSchool!.id) {
      _selectedSchool = newSchool;
      notifyListeners();
    }
  }
}
