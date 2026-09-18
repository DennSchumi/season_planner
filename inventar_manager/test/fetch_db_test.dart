import 'package:flutter_test/flutter_test.dart';
import 'package:appwrite/appwrite.dart';
import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  test('fetch user docs', () async {
    final client = Client()
        .setEndpoint('http://localhost/v1')
        .setProject('6aa0f487000340aa9e05')
        .setSelfSigned(status: true);

    final databases = Databases(client);

    try {
      print('Fetching user documents...');
      final userDocs = await databases.listDocuments(
        databaseId: '6aa137f3001249bfafae',
        collectionId: '6aa1394b0029b8f3bb56',
        queries: [Query.limit(1)]
      );
      
      print('Found ${userDocs.documents.length} users.');
      if (userDocs.documents.isNotEmpty) {
        final data = userDocs.documents.first.data;
        print('User ID: ${data['\$id']}');
        
        final memberships = data['memberships'];
        print('Memberships Type: ${memberships.runtimeType}');
        print('Memberships Data: $memberships');
        
        if (memberships is List && memberships.isNotEmpty) {
           final firstMem = memberships.first;
           print('First Membership Type: ${firstMem.runtimeType}');
           if (firstMem is Map) {
             print('FlightSchools data: ${firstMem["flightSchools"]}');
           }
        }
      }
    } catch (e) {
      print('Error: $e');
    }
  });
}
