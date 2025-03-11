
import 'package:flutter/cupertino.dart';
import 'package:season_planer/features/login/login_view.dart';

import '../features/home/home_view.dart';

class AppRouter {
  Map<String,WidgetBuilder> getRoutes(){
    return{
      "/": (context) =>  HomeView(),
      "/login": (context) =>  LoginView()
    };
  }
}