import 'package:dart_appwrite/dart_appwrite.dart';
import 'dart:io';

// IMPORTANT: This script uses the SERVER SDK, not the client SDK.
// You need to add 'dart_appwrite' to your pubspec.yaml to run this script:
// flutter pub add dart_appwrite
// 
// You also need an Appwrite API Key with the following scopes:
// databases.read, databases.write, collections.read, collections.write, attributes.read, attributes.write, indexes.read, indexes.write

void main() async {
  final String apiKey = Platform.environment['APPWRITE_API_KEY'] ?? '';
  if (apiKey.isEmpty) {
    print('FEHLER: Bitte setze die Umgebungsvariable APPWRITE_API_KEY!');
    return;
  }

  final client = Client()
      .setEndpoint('http://localhost/v1')
      .setProject('6aa0f487000340aa9e05')
      .setKey(apiKey)
      .setSelfSigned(status: true);

  final databases = Databases(client);
  final dbId = 'inventory_db';

  try {
  try {
    print('Creating database...');
    await databases.create(databaseId: dbId, name: 'Inventory Manager');
  } on AppwriteException catch (e) {
    if (e.code == 409) {
      print('Database already exists, proceeding to collections...');
    } else {
      rethrow;
    }
  }

    print('Creating categories collection...');
    await databases.createCollection(
      databaseId: dbId,
      collectionId: 'categories',
      name: 'Categories',
      documentSecurity: false,
    );
    await databases.createStringAttribute(databaseId: dbId, collectionId: 'categories', key: 'name', size: 255, xrequired: true);
    await databases.createStringAttribute(databaseId: dbId, collectionId: 'categories', key: 'icon', size: 255, xrequired: false);
    await databases.createIntegerAttribute(databaseId: dbId, collectionId: 'categories', key: 'defaultServiceIntervalDays', xrequired: false);

    print('Creating items collection...');
    await databases.createCollection(
      databaseId: dbId,
      collectionId: 'items',
      name: 'Items',
      documentSecurity: false,
    );
    await databases.createStringAttribute(databaseId: dbId, collectionId: 'items', key: 'categoryId', size: 255, xrequired: true);
    await databases.createStringAttribute(databaseId: dbId, collectionId: 'items', key: 'name', size: 255, xrequired: true);
    await databases.createStringAttribute(databaseId: dbId, collectionId: 'items', key: 'serialNumber', size: 255, xrequired: false);
    await databases.createStringAttribute(databaseId: dbId, collectionId: 'items', key: 'status', size: 50, xrequired: true); // In Stock, Out, Blocked
    await databases.createStringAttribute(databaseId: dbId, collectionId: 'items', key: 'assignedTo', size: 255, xrequired: false);
    await databases.createStringAttribute(databaseId: dbId, collectionId: 'items', key: 'nextServiceDate', size: 50, xrequired: false);
    await databases.createStringAttribute(databaseId: dbId, collectionId: 'items', key: 'createdAt', size: 50, xrequired: true);

    print('Creating service_logs collection...');
    await databases.createCollection(
      databaseId: dbId,
      collectionId: 'service_logs',
      name: 'Service Logs',
      documentSecurity: false,
    );
    await databases.createStringAttribute(databaseId: dbId, collectionId: 'service_logs', key: 'itemId', size: 255, xrequired: true);
    await databases.createStringAttribute(databaseId: dbId, collectionId: 'service_logs', key: 'date', size: 50, xrequired: true);
    await databases.createStringAttribute(databaseId: dbId, collectionId: 'service_logs', key: 'type', size: 100, xrequired: true); // Routine, Repack
    await databases.createStringAttribute(databaseId: dbId, collectionId: 'service_logs', key: 'inspectorName', size: 255, xrequired: true);
    await databases.createStringAttribute(databaseId: dbId, collectionId: 'service_logs', key: 'details', size: 10000, xrequired: false); // JSON data

    print('Creating trouble_tickets collection...');
    await databases.createCollection(
      databaseId: dbId,
      collectionId: 'trouble_tickets',
      name: 'Trouble Tickets',
      documentSecurity: false,
    );
    await databases.createStringAttribute(databaseId: dbId, collectionId: 'trouble_tickets', key: 'itemId', size: 255, xrequired: true);
    await databases.createStringAttribute(databaseId: dbId, collectionId: 'trouble_tickets', key: 'description', size: 5000, xrequired: true);
    await databases.createStringAttribute(databaseId: dbId, collectionId: 'trouble_tickets', key: 'status', size: 50, xrequired: true); // Open, Resolved
    await databases.createStringAttribute(databaseId: dbId, collectionId: 'trouble_tickets', key: 'reportedBy', size: 255, xrequired: true);
    await databases.createStringAttribute(databaseId: dbId, collectionId: 'trouble_tickets', key: 'createdAt', size: 50, xrequired: true);

    print('Database setup completed successfully!');
  } catch (e) {
    print('Error setting up database: $e');
  }
}
