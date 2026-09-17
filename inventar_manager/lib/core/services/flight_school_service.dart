import 'package:flutter/foundation.dart';
import 'package:inventar_manager/core/services/database_service.dart';
import 'package:inventar_manager/core/appwrite_config.dart';
import 'package:appwrite/appwrite.dart';

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
      final docs = await DatabaseService().getDocuments(
        AppwriteConfig.flightSchoolsCollectionId, 
        queries: [Query.limit(100)]
      );
      _schools = docs.map((d) => FlightSchoolModel(
        id: d.$id,
        name: d.data['name'] ?? 'Unbekannt',
      )).toList();

      if (_schools.isNotEmpty) {
        _selectedSchool = _schools.first;
      }
    } catch (e) {
      debugPrint("Error loading schools: $e");
      errorMessage = "Netzwerkfehler: Flugschulen konnten nicht geladen werden.";
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
