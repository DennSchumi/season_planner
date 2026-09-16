import 'package:dart_appwrite/dart_appwrite.dart';
import 'dart:io';

const String endpoint = 'http://localhost/v1';
const String projectId = '6aa0f487000340aa9e05';
final String apiKey = Platform.environment['APPWRITE_API_KEY'] ?? '';
const String databaseId = '6aa99ffb00070a53db7e';
const String collectionId = 'flight_schools';

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
    final response = await databases.listDocuments(
      databaseId: databaseId,
      collectionId: collectionId,
    );
    
    print("Found ${response.documents.length} schools.");
    for (var doc in response.documents) {
      print("ID: ${doc.$id}");
      print("Data: ${doc.data}");
      print("Permissions: ${doc.$permissions}");
    }
  } catch (e) {
    print("Error: $e");
  }
}
