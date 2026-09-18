import 'package:appwrite/appwrite.dart';

void main() async {
  final client = Client()
      .setEndpoint('http://localhost/v1')
      .setProject('6aa0f487000340aa9e05')
      .setSelfSigned(status: true);

  final databases = Databases(client);
  final dbId = '6aa137f3001249bfafae'; // Season Planner DB

  try {
    print('Listing collections in database $dbId...');
    final result = await databases.listCollections(databaseId: dbId);
    
    for (var doc in result.collections) {
      print('Collection ID: ${doc.$id}, Name: ${doc.name}');
    }
  } catch (e) {
    print('Error: $e');
  }
}
