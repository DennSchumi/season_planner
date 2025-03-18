
import 'package:flutter/cupertino.dart';
import '../features/authentification/login/login_view.dart';
import '../features/authentification/register/register_view.dart';
import '../features/home/home_view.dart';

class AppRouter {
  Map<String,WidgetBuilder> getRoutes(){
    return{
      "/home": (context) =>  HomeView(),
      "/login": (context) =>  LoginView(),
      "/register": (context) => RegisterView(),
    };
  }
}