import 'package:dart_appwrite/dart_appwrite.dart';
import 'dart:io';

const String endpoint = 'https://cloud.appwrite.io/v1'; // Bitte anpassen, falls lokal (http://localhost/v1)
const String projectId = '6aa0f487000340aa9e05'; // Deine Projekt-ID
final String apiKey = Platform.environment['APPWRITE_API_KEY'] ?? ''; 
const String databaseId = '6aa99ffb00070a53db7e';
const String itemCol = 'items';

void main() async {
  if (apiKey.isEmpty) {
    print('FEHLER: Bitte setze die Umgebungsvariable APPWRITE_API_KEY!');
    return;
  }

  Client client = Client()
    .setEndpoint(endpoint)
    .setProject(projectId)
    .setKey(apiKey);

  Databases databases = Databases(client);

  print('Füge neue Attribute zur Items Collection hinzu...');

  try {
    await databases.createBooleanAttribute(
      databaseId: databaseId, 
      collectionId: itemCol, 
      key: 'isLocked', 
      xdefault: false, 
      xrequired: false
    );
    print('✅ Attribut "isLocked" erfolgreich erstellt.');
  } catch (e) {
    print('Fehler bei "isLocked": $e');
  }

  try {
    await databases.createStringAttribute(
      databaseId: databaseId, 
      collectionId: itemCol, 
      key: 'lockReason', 
      size: 255, 
      xrequired: false
    );
    print('✅ Attribut "lockReason" erfolgreich erstellt.');
  } catch (e) {
    print('Fehler bei "lockReason": $e');
  }

  print('\nFertig!');
}
