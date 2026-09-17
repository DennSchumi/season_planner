import 'package:appwrite/appwrite.dart';
import 'package:flutter/material.dart';
import 'package:inventar_manager/core/services/database_service.dart';
import 'package:inventar_manager/core/appwrite_config.dart';

class CategoryModel {
  String id;
  String schoolId;
  String name;
  String prefix;
  int serviceIntervalMonths;
  bool serviceRequiresDocument;
  String iconData;

  CategoryModel({
    required this.id,
    required this.schoolId,
    required this.name,
    required this.prefix,
    required this.serviceIntervalMonths,
    required this.serviceRequiresDocument,
    required this.iconData,
  });

  factory CategoryModel.fromDocument(dynamic d) {
    return CategoryModel(
      id: d.$id,
      schoolId: d.data['schoolId'],
      name: d.data['name'],
      prefix: d.data['prefix'],
      serviceIntervalMonths: d.data['serviceIntervalMonths'],
      serviceRequiresDocument: d.data['serviceRequiresDoc'] ?? false,
      iconData: d.data['iconData'] ?? 'support',
    );
  }
  
  IconData get icon {
    switch (iconData) {
      case 'radio': return Icons.radio;
      case 'paragliding': return Icons.paragliding;
      case 'airline_seat_recline_normal': return Icons.airline_seat_recline_normal;
      case 'support':
      default: return Icons.support;
    }
  }
}

class CategoryService extends ChangeNotifier {
  static final CategoryService _instance = CategoryService._internal();

  factory CategoryService() {
    return _instance;
  }

  CategoryService._internal();

  List<CategoryModel> _categories = [];
  bool _isLoading = false;
  String? errorMessage;

  List<CategoryModel> get categories => List.unmodifiable(_categories);
  bool get isLoading => _isLoading;

  Future<void> loadCategories(String schoolId) async {
    _isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final queries = [
        Query.equal('schoolId', schoolId),
        Query.limit(100)
      ];
      final docs = await DatabaseService().getDocuments(AppwriteConfig.categoriesCollectionId, queries: queries);
      
      final loadedCats = <CategoryModel>[];
      for (var d in docs) {
        try {
          loadedCats.add(CategoryModel.fromDocument(d));
        } catch (e) {
          debugPrint("Failed to parse category: $e");
        }
      }
      _categories = loadedCats;
    } catch (e) {
      debugPrint("Error loading categories: $e");
      errorMessage = "Netzwerkfehler: Kategorien konnten nicht geladen werden.";
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> addCategory(CategoryModel category) async {
    final data = {
      'schoolId': category.schoolId,
      'name': category.name,
      'prefix': category.prefix,
      'serviceIntervalMonths': category.serviceIntervalMonths,
      'serviceRequiresDoc': category.serviceRequiresDocument,
      'iconData': category.iconData,
    };
    final doc = await DatabaseService().createDocument(AppwriteConfig.categoriesCollectionId, data);
    if (doc != null) {
      category.id = doc.$id;
      _categories.add(category);
      notifyListeners();
    }
  }

  Future<void> updateCategory(CategoryModel category) async {
    final data = {
      'name': category.name,
      'prefix': category.prefix,
      'serviceIntervalMonths': category.serviceIntervalMonths,
      'serviceRequiresDoc': category.serviceRequiresDocument,
      'iconData': category.iconData,
    };
    final doc = await DatabaseService().updateDocument(AppwriteConfig.categoriesCollectionId, category.id, data);
    if (doc != null) {
      final index = _categories.indexWhere((c) => c.id == category.id);
      if (index != -1) {
        _categories[index] = category;
        notifyListeners();
      }
    }
  }
}
