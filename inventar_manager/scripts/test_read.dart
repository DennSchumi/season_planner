import 'package:dart_appwrite/dart_appwrite.dart';

const String endpoint = 'http://localhost/v1';
const String projectId = '6aa0f487000340aa9e05';
const String databaseId = 'inventory_db';
const String collectionId = 'flight_schools';

void main() async {
  Client client = Client()
    .setEndpoint(endpoint)
    .setProject(projectId)
    .setSelfSigned(status: true);

  Account account = Account(client);
  
  try {
    // Try to create anonymous session to test 'Users' role
    await account.createAnonymousSession();
    print("Anonymous session created.");
  } catch (e) {
    print("Could not create anonymous session (might already have one): $e");
  }

  Databases databases = Databases(client);

  try {
    print("Fetching flight schools...");
    final response = await databases.listDocuments(
      databaseId: databaseId,
      collectionId: collectionId,
    );
    
    print("Found ${response.documents.length} schools.");
    for (var doc in response.documents) {
      print("ID: ${doc.$id}");
      print("Data: ${doc.data}");
    }
  } catch (e) {
    print("Error fetching: $e");
  }
}
