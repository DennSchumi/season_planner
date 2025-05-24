import 'package:flutter/cupertino.dart';
import 'package:season_planer/data/models/user_model.dart';

class AppState{
  static final AppState _instance = AppState._internal();

  factory AppState() => _instance;

  AppState._internal();
  final ValueNotifier<UserModel> userData = ValueNotifier(UserModel.empty());

  void setUser(UserModel user){
    userData.value =user;
  }

  void updateUser(UserModel Function(UserModel) updater){
    final current = userData.value;
    userData.value = updater(current);
  }

  void clear(){
    userData;
  }
}