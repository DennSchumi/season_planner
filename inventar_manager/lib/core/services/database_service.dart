import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:flutter/foundation.dart';
import 'package:inventar_manager/core/appwrite_config.dart';
import 'package:inventar_manager/core/services/auth_service.dart';

class DatabaseService {
  Client get client => AuthService().client;

  static final DatabaseService _instance = DatabaseService._internal();

  factory DatabaseService() {
    return _instance;
  }
  DatabaseService._internal();

  late final TablesDB _tablesDB;
  late final Storage _storage;
  bool _initialized = false;

  void init() {
    if (_initialized) return;
    _tablesDB = TablesDB(client);
    _storage = Storage(client);
    _initialized = true;
  }

  TablesDB get tablesDB {
    if (!_initialized) init();
    return _tablesDB;
  }

  Storage get storage {
    if (!_initialized) init();
    return _storage;
  }

  // Generic method to fetch rows (Appwrite 2.x TablesDB)
  Future<List<models.Row>> getDocuments(
    String tableId, {
    List<String>? queries,
    String? databaseId,
  }) async {
    try {
      final response = await tablesDB.listRows(
        databaseId: databaseId ?? AppwriteConfig.inventoryDatabaseId,
        tableId: tableId,
        queries: queries,
      );
      return response.rows;
    } catch (e) {
      debugPrint("Error fetching rows from $tableId: $e");
      rethrow;
    }
  }

  // Generic method to create row
  Future<models.Row?> createDocument(
    String tableId,
    Map<String, dynamic> data, {
    String? databaseId,
    List<String>? permissions,
  }) async {
    try {
      return await tablesDB.createRow(
        databaseId: databaseId ?? AppwriteConfig.inventoryDatabaseId,
        tableId: tableId,
        rowId: ID.unique(),
        data: data,
        permissions: permissions,
      );
    } catch (e) {
      debugPrint("Error creating row in $tableId: $e");
      return null;
    }
  }

  // Generic method to update row
  Future<models.Row?> updateDocument(
    String tableId,
    String rowId,
    Map<String, dynamic> data, {
    String? databaseId,
  }) async {
    try {
      return await tablesDB.updateRow(
        databaseId: databaseId ?? AppwriteConfig.inventoryDatabaseId,
        tableId: tableId,
        rowId: rowId,
        data: data,
      );
    } catch (e) {
      debugPrint("Error updating row $rowId in $tableId: $e");
      return null;
    }
  }

  // Generic method to delete row
  Future<void> deleteDocument(
    String tableId,
    String rowId, {
    String? databaseId,
  }) async {
    try {
      await tablesDB.deleteRow(
        databaseId: databaseId ?? AppwriteConfig.inventoryDatabaseId,
        tableId: tableId,
        rowId: rowId,
      );
    } catch (e) {
      debugPrint("Error deleting row $rowId in $tableId: $e");
      rethrow;
    }
  }

  // Storage Methods
  Future<models.File?> uploadFile(
    String bucketId,
    String fileName,
    Uint8List fileBytes, {
    List<String>? permissions,
  }) async {
    try {
      return await storage.createFile(
        bucketId: bucketId,
        fileId: ID.unique(),
        file: InputFile.fromBytes(bytes: fileBytes, filename: fileName),
        permissions: permissions,
      );
    } catch (e) {
      debugPrint("Error uploading file to bucket $bucketId: $e");
      return null;
    }
  }

  String getFileViewUrl(String bucketId, String fileId) {
    return AppwriteConfig.fileViewUrl(bucketId, fileId);
  }
}
