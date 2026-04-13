import 'package:appwrite/appwrite.dart';

class testService {

  void main(){
    Client client = Client();
    client
        .setEndpoint('http://localhost/v1')
        .setProject('67cf0f1a000eaeacf5e7')
        .setSelfSigned(status: true);
  }
  }

