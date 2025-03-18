import 'package:flutter/material.dart';
import 'package:season_planer/features/home/home_view.dart';
import 'package:season_planer/services/auth_service.dart';

import 'core/app_router.dart';
import 'features/authentification/login/login_view.dart';

void main() {
  runApp(const MyApp());
  AuthService().init();
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});


  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        routes: AppRouter().getRoutes(),
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