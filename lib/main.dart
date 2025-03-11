import 'package:flutter/material.dart';
import 'package:season_planer/features/home/home_view.dart';
import 'package:season_planer/features/login/login_view.dart';
import 'package:season_planer/services/auth_service.dart';

void main() {
  runApp(const MyApp());

}

class MyApp extends StatelessWidget {
  const MyApp({super.key});


  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'seasonPlanner',
      home: FutureBuilder(
          future: AuthService().isLoggedIn(),
          builder: (context,snapshot){
            bool loggedIn = snapshot.data ?? true;
            return loggedIn ? HomeView() : LoginView();
            },
      )
    );
  }
}