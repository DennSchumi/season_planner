import 'package:flutter/material.dart';
import 'package:season_planner/services/auth_service.dart';
import 'package:season_planner/services/database_service.dart';

import 'core/AppState.dart';
import 'features/authentification/login/login_view.dart';

class BaseView extends StatefulWidget {
  const BaseView({super.key});

  @override
  _BaseViewState createState() => _BaseViewState();
}

class _BaseViewState extends State<BaseView> {
  bool? _isLoggedIn;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    final loggedIn = await AuthService().isLoggedIn();
    setState(() {
      _isLoggedIn = loggedIn;
    });

    if (loggedIn) {
      _loadUserData();
    }
  }

  _loadUserData() async {
    try {
      final user = await DatabaseService().getUserInformation();
      AppState().setUser(user!);
      Navigator.pushNamed(context, "/home");
    } catch (e) {
      print(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if(_isLoggedIn==null){
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if(_isLoggedIn == false){
      return LoginView();
    }

    return Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
