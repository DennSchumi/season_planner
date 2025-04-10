
import 'package:flutter/cupertino.dart';
import 'package:season_planer/main.dart';
import '../features/authentification/login/login_view.dart';
import '../features/authentification/register/register_view.dart';
import '../features/main_scaffold/main_scaffold_view.dart';

class AppRouter {
  Map<String,WidgetBuilder> getRoutes(){
    return{
      "/home": (context) =>  MainScaffoldView(),
      "/login": (context) =>  LoginView(),
      "/register": (context) => RegisterView(),
      "/main": (context) => MyApp(),
    };
  }
}