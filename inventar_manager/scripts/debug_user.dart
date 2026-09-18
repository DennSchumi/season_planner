import 'package:appwrite/appwrite.dart';

void main() async {
  final client = Client()
      .setEndpoint('http://localhost/v1')
      .setProject('6aa0f487000340aa9e05')
      .setSelfSigned(status: true);

  final databases = Databases(client);

  try {
    print('Fetching first user document from Season Planner...');
    final result = await databases.listDocuments(
      databaseId: '6aa137f3001249bfafae',
      collectionId: '6aa1394b0029b8f3bb56',
      queries: [Query.limit(1)]
    );
    
    if (result.documents.isEmpty) {
      print('No users found.');
      return;
    }
    
    final doc = result.documents.first;
    print('User Data:');
    print(doc.data);
  } catch (e) {
    print('Error: $e');
  }
}
