import 'package:dart_appwrite/dart_appwrite.dart';
import 'dart:io';

const String endpoint = 'http://localhost/v1';
const String projectId = '6aa0f487000340aa9e05';
final String apiKey = Platform.environment['APPWRITE_API_KEY'] ?? '';
const String databaseId = 'inventory_db';

void main() async {
  if (apiKey.isEmpty) {
    print('FEHLER: Bitte setze die Umgebungsvariable APPWRITE_API_KEY!');
    return;
  }

  Client client = Client()
    .setEndpoint(endpoint)
    .setProject(projectId)
    .setKey(apiKey)
    .setSelfSigned(status: true);

  Databases databases = Databases(client);

  try {
    print("Listing collections...");
    final response = await databases.listCollections(
      databaseId: databaseId,
    );
    
    print("Found ${response.collections.length} collections.");
    for (var col in response.collections) {
      print("Name: ${col.name} -> ID: ${col.$id}");
    }
  } catch (e) {
    print("Error: $e");
  }
}
