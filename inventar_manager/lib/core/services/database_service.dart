import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:inventar_manager/core/appwrite_config.dart';
import 'package:flutter/foundation.dart';

class DatabaseService {
  final Client client = Client()
      .setEndpoint(AppwriteConfig.endpoint)
      .setProject(AppwriteConfig.projectId)
      .setSelfSigned(status: kDebugMode);

  static final DatabaseService _instance = DatabaseService._internal();

  factory DatabaseService() {
    return _instance;
  }
  DatabaseService._internal();

  late final Databases _databases;
  late final Storage _storage;

  void init() {
    _databases = Databases(client);
    _storage = Storage(client);
  }

  // Generic method to fetch documents
  Future<List<models.Document>> getDocuments(String collectionId, {List<String>? queries}) async {
    try {
      final response = await _databases.listDocuments(
        databaseId: AppwriteConfig.inventoryDatabaseId,
        collectionId: collectionId,
        queries: queries,
      );
      return response.documents;
    } catch (e) {
      debugPrint("Error fetching documents from $collectionId: $e");
      rethrow;
    }
  }

  // Generic method to create document
  Future<models.Document?> createDocument(String collectionId, Map<String, dynamic> data) async {
    try {
      return await _databases.createDocument(
        databaseId: AppwriteConfig.inventoryDatabaseId,
        collectionId: collectionId,
        documentId: ID.unique(),
        data: data,
      );
    } catch (e) {
      print("Error creating document in $collectionId: $e");
      return null;
    }
  }

  // Generic method to update document
  Future<models.Document?> updateDocument(String collectionId, String documentId, Map<String, dynamic> data) async {
    try {
      return await _databases.updateDocument(
        databaseId: AppwriteConfig.inventoryDatabaseId,
        collectionId: collectionId,
        documentId: documentId,
        data: data,
      );
    } catch (e) {
      print("Error updating document $documentId in $collectionId: $e");
      return null;
    }
  }

  // Generic method to delete document
  Future<void> deleteDocument(String collectionId, String documentId) async {
    try {
      await _databases.deleteDocument(
        databaseId: AppwriteConfig.inventoryDatabaseId,
        collectionId: collectionId,
        documentId: documentId,
      );
    } catch (e) {
      debugPrint("Error deleting document $documentId in $collectionId: $e");
      rethrow;
    }
  }

  // Storage Methods
  Future<models.File?> uploadFile(String bucketId, String fileName, Uint8List fileBytes) async {
    try {
      return await _storage.createFile(
        bucketId: bucketId,
        fileId: ID.unique(),
        file: InputFile.fromBytes(bytes: fileBytes, filename: fileName),
      );
    } catch (e) {
      debugPrint("Error uploading file to bucket $bucketId: $e");
      return null;
    }
  }

  String getFileViewUrl(String bucketId, String fileId) {
    return "${AppwriteConfig.endpoint}/storage/buckets/$bucketId/files/$fileId/view?project=${AppwriteConfig.projectId}";
  }
}
