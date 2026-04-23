import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/core/services/auth_service.dart';
import 'package:season_planner/user/services/database_service.dart';
import 'package:season_planner/fsAdmin/services/flight_school_service.dart';
import 'package:season_planner/fsAdmin/flight_school_provider.dart';
import 'package:season_planner/user/user_provider.dart';
import 'core/app_router.dart';
import 'core/features/authentification/login/login_view.dart';
import 'user/features/main_scaffold/main_user_scaffold_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => FlightSchoolProvider())

      ],
      child: const MyApp(),
    ),
  );
  AuthService().init();
  DatabaseService().init();
  //AuthService().logout();
  //AuthService().testLogin();
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  //TODO: implement timer that loads data periodically

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
            return loggedIn ? MainUserScaffoldView() : LoginView();
            },
      )
    );
  }
}