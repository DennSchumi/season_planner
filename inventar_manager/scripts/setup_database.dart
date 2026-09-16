import 'package:dart_appwrite/dart_appwrite.dart';
import 'dart:io';

// --- KONFIGURATION ---
const String endpoint = 'http://localhost/v1'; // Oder deine IP
const String projectId = '6aa0f487000340aa9e05'; // Deine Projekt-ID aus appwrite_config.dart
final String apiKey = Platform.environment['APPWRITE_API_KEY'] ?? ''; // Erstelle einen API Key in der Appwrite Console und setze die Umgebungsvariable
const String databaseId = '6aa99ffb00070a53db7e';

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
  Storage storage = Storage(client);

  print('Starte Appwrite Datenbank Setup...');

  try {
    // 1. FlightSchools Collection
    print('Erstelle FlightSchools Collection...');
    const String schoolCol = 'flight_schools';
    try {
      await databases.createCollection(
        databaseId: databaseId,
        collectionId: schoolCol,
        name: 'Flight Schools',
        permissions: [
          Permission.read(Role.users()),
          Permission.write(Role.users()),
        ]
      );
      await databases.createStringAttribute(databaseId: databaseId, collectionId: schoolCol, key: 'name', size: 255, xrequired: true);
    } catch (e) {
      print('FlightSchools existiert möglicherweise schon: $e');
    }

    // 2. Categories Collection
    print('Erstelle Categories Collection...');
    const String catCol = 'categories';
    try {
      await databases.createCollection(
        databaseId: databaseId,
        collectionId: catCol,
        name: 'Categories',
        permissions: [
          Permission.read(Role.users()),
          Permission.write(Role.users()),
        ]
      );
      await databases.createStringAttribute(databaseId: databaseId, collectionId: catCol, key: 'schoolId', size: 255, xrequired: true);
      await databases.createStringAttribute(databaseId: databaseId, collectionId: catCol, key: 'name', size: 255, xrequired: true);
      await databases.createStringAttribute(databaseId: databaseId, collectionId: catCol, key: 'prefix', size: 10, xrequired: true);
      await databases.createIntegerAttribute(databaseId: databaseId, collectionId: catCol, key: 'serviceIntervalMonths', xrequired: true);
      await databases.createBooleanAttribute(databaseId: databaseId, collectionId: catCol, key: 'serviceRequiresDoc', xdefault: false, xrequired: false);
      await databases.createStringAttribute(databaseId: databaseId, collectionId: catCol, key: 'iconData', size: 50, xdefault: 'support', xrequired: false);
    } catch (e) {
      print('Categories existiert möglicherweise schon: $e');
    }

    // 3. Items Collection
    print('Erstelle Items Collection...');
    const String itemCol = 'items';
    try {
      await databases.createCollection(
        databaseId: databaseId,
        collectionId: itemCol,
        name: 'Items',
        permissions: [
          Permission.read(Role.users()),
          Permission.write(Role.users()),
        ]
      );
      await databases.createStringAttribute(databaseId: databaseId, collectionId: itemCol, key: 'schoolId', size: 255, xrequired: true);
      await databases.createStringAttribute(databaseId: databaseId, collectionId: itemCol, key: 'categoryId', size: 255, xrequired: true);
      await databases.createStringAttribute(databaseId: databaseId, collectionId: itemCol, key: 'materialNumber', size: 50, xrequired: true);
      await databases.createStringAttribute(databaseId: databaseId, collectionId: itemCol, key: 'name', size: 255, xrequired: true);
      await databases.createStringAttribute(databaseId: databaseId, collectionId: itemCol, key: 'serialNumber', size: 255, xrequired: false);
      await databases.createStringAttribute(databaseId: databaseId, collectionId: itemCol, key: 'status', size: 50, xdefault: 'in_stock', xrequired: false);
      await databases.createStringAttribute(databaseId: databaseId, collectionId: itemCol, key: 'assignedTo', size: 255, xrequired: false);
      await databases.createDatetimeAttribute(databaseId: databaseId, collectionId: itemCol, key: 'lastServiceDate', xrequired: false);
      await databases.createDatetimeAttribute(databaseId: databaseId, collectionId: itemCol, key: 'nextServiceDate', xrequired: false);
    } catch (e) {
      print('Items existiert möglicherweise schon: $e');
    }

    // 4. Transactions Collection
    print('Erstelle Transactions Collection...');
    const String transCol = 'transactions';
    try {
      await databases.createCollection(
        databaseId: databaseId,
        collectionId: transCol,
        name: 'Transactions',
        permissions: [
          Permission.read(Role.users()),
          Permission.write(Role.users()),
        ]
      );
      await databases.createStringAttribute(databaseId: databaseId, collectionId: transCol, key: 'schoolId', size: 255, xrequired: true);
      await databases.createStringAttribute(databaseId: databaseId, collectionId: transCol, key: 'itemId', size: 255, xrequired: true);
      await databases.createStringAttribute(databaseId: databaseId, collectionId: transCol, key: 'type', size: 50, xrequired: true);
      await databases.createStringAttribute(databaseId: databaseId, collectionId: transCol, key: 'status', size: 50, xrequired: true);
      await databases.createStringAttribute(databaseId: databaseId, collectionId: transCol, key: 'initiator', size: 255, xrequired: true);
      await databases.createStringAttribute(databaseId: databaseId, collectionId: transCol, key: 'captureMethod', size: 50, xrequired: true);
      await databases.createStringAttribute(databaseId: databaseId, collectionId: transCol, key: 'details', size: 500, xrequired: false);
      await databases.createDatetimeAttribute(databaseId: databaseId, collectionId: transCol, key: 'date', xrequired: false);
    } catch (e) {
      print('Transactions existiert möglicherweise schon: $e');
    }

    // 5. Storage Bucket
    print('Erstelle Storage Bucket...');
    const String bucketId = '6aaafd07000885e37e40';
    try {
      await storage.createBucket(
        bucketId: bucketId,
        name: 'Service Proofs',
        permissions: [
          Permission.read(Role.users()),
          Permission.write(Role.users()),
        ],
        allowedFileExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
        maximumFileSize: 10485760, // 10 MB
      );
    } catch (e) {
      print('Storage Bucket existiert möglicherweise schon: \$e');
    }

    print('\n🚀 Setup erfolgreich abgeschlossen!');
  } catch (e) {
    print('Fehler beim Setup: $e');
  }
}
