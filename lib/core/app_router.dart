
import 'package:flutter/cupertino.dart';
import 'package:season_planner/main.dart';
import '../features/authentification/login/login_view.dart';
import '../features/authentification/register/register_view.dart';
import '../features/user_features/main_scaffold/main_user_scaffold_view.dart';

class AppRouter {
  Map<String,WidgetBuilder> getRoutes(){
    return{
      "/home": (context) =>  MainUserScaffoldView(),
      "/login": (context) =>  LoginView(),
      "/register": (context) => RegisterView(),
      "/main": (context) => MyApp(),
    };
  }
}