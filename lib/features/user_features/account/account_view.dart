import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:season_planer/features/authentification/login/login_view.dart';
import 'package:season_planer/services/auth_service.dart';

class AccountView extends StatefulWidget{
  @override
  _AccountViewState createState() => _AccountViewState();
}

class _AccountViewState extends State<AccountView>{

  void _logOut() {
    AuthService().logout();
    Navigator.pushReplacementNamed(context, '/login');
  }


  @override
  Widget build(BuildContext context){
    return Scaffold(
      body: Center(
        child:
            TextButton(
                onPressed: _logOut,
                child: Text("Ausloggen",
                  style: TextStyle(
                      fontSize: 10,
                      color: Colors.blueAccent,
                      decorationColor: Colors.blueAccent,
                      decoration: TextDecoration.underline
                  ),
                )
            )
      ),
    );
  }
}