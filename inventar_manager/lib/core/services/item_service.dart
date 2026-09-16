import 'package:appwrite/appwrite.dart';
import 'package:flutter/material.dart';
import 'package:inventar_manager/core/services/database_service.dart';
import 'package:inventar_manager/core/appwrite_config.dart';

class ItemModel {
  String id;
  String schoolId;
  String categoryId;
  String materialNumber;
  String name;
  String? serialNumber;
  String status;
  String? assignedTo;
  DateTime? lastServiceDate;
  DateTime? nextServiceDate;

  ItemModel({
    required this.id,
    required this.schoolId,
    required this.categoryId,
    required this.materialNumber,
    required this.name,
    this.serialNumber,
    this.status = 'in_stock',
    this.assignedTo,
    this.lastServiceDate,
    this.nextServiceDate,
  });

  factory ItemModel.fromDocument(dynamic doc) {
    return ItemModel(
      id: doc.$id,
      schoolId: doc.data['schoolId'],
      categoryId: doc.data['categoryId'],
      materialNumber: doc.data['materialNumber'],
      name: doc.data['name'],
      serialNumber: doc.data['serialNumber'],
      status: doc.data['status'] ?? 'in_stock',
      assignedTo: doc.data['assignedTo'],
      lastServiceDate: doc.data['lastServiceDate'] != null ? DateTime.parse(doc.data['lastServiceDate']) : null,
      nextServiceDate: doc.data['nextServiceDate'] != null ? DateTime.parse(doc.data['nextServiceDate']) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'schoolId': schoolId,
      'categoryId': categoryId,
      'materialNumber': materialNumber,
      'name': name,
      'serialNumber': serialNumber,
      'status': status,
      'assignedTo': assignedTo,
      'lastServiceDate': lastServiceDate?.toIso8601String(),
      'nextServiceDate': nextServiceDate?.toIso8601String(),
    };
  }
}

class ItemService extends ChangeNotifier {
  static final ItemService _instance = ItemService._internal();

  factory ItemService() {
    return _instance;
  }

  ItemService._internal();

  List<ItemModel> _items = [];
  bool _isLoading = false;

  List<ItemModel> get items => List.unmodifiable(_items);
  bool get isLoading => _isLoading;

  Future<void> loadItems(String schoolId) async {
    _isLoading = true;
    notifyListeners();

    try {
      final queries = [
        Query.equal('schoolId', schoolId),
        Query.limit(500) // Adjust as needed
      ];
      final docs = await DatabaseService().getDocuments(AppwriteConfig.itemsCollectionId, queries: queries);
      
      _items = docs.map((d) => ItemModel.fromDocument(d)).toList();
    } catch (e) {
      print("Error loading items: $e");
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<ItemModel?> addItem(ItemModel item) async {
    final doc = await DatabaseService().createDocument(AppwriteConfig.itemsCollectionId, item.toMap());
    if (doc != null) {
      item.id = doc.$id;
      _items.add(item);
      notifyListeners();
      return item;
    }
    return null;
  }

  Future<bool> updateItem(ItemModel item) async {
    final doc = await DatabaseService().updateDocument(AppwriteConfig.itemsCollectionId, item.id, item.toMap());
    if (doc != null) {
      final index = _items.indexWhere((c) => c.id == item.id);
      if (index != -1) {
        _items[index] = item;
        notifyListeners();
      }
      return true;
    }
    return false;
  }

  Future<bool> deleteItem(String id) async {
    try {
      await DatabaseService().deleteDocument(AppwriteConfig.itemsCollectionId, id);
      _items.removeWhere((item) => item.id == id);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint("Error deleting item: \$e");
      return false;
    }
  }
}
