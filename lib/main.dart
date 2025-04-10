import 'package:flutter/material.dart';
import 'package:season_planer/features/main_scaffold/main_scaffold_view.dart';
import 'package:season_planer/services/auth_service.dart';
import 'package:season_planer/services/database_service.dart';
import 'core/app_router.dart';
import 'features/authentification/login/login_view.dart';
import './../core/theme.dart';

void main() {
  runApp(const MyApp());
  AuthService().init();
  DatabaseService().init();
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});


  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        routes: AppRouter().getRoutes(),
        title: 'seasonPlanner',
        //theme: AppTheme.lightTheme,
        home: FutureBuilder(
          future: AuthService().isLoggedIn(),
          builder: (context,snapshot){
            bool loggedIn = snapshot.data ?? true;
            return loggedIn ? MainScaffoldView() : LoginView();
            },
      )
    );
  }
}