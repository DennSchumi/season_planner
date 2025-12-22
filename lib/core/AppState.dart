import 'package:flutter/cupertino.dart';
import 'package:season_planer/data/models/user_models/user_model_userView.dart';

class AppState{
  static final AppState _instance = AppState._internal();

  factory AppState() => _instance;

  AppState._internal();
  final ValueNotifier<UserModelUserView> userData = ValueNotifier(UserModelUserView.empty());

  void setUser(UserModelUserView user){
    userData.value =user;
  }

  void updateUser(UserModelUserView Function(UserModelUserView) updater){
    final current = userData.value;
    userData.value = updater(current);
  }

  void clear(){
    userData;
  }
}