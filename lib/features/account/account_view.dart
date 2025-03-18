import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class AccountView extends StatefulWidget{
  @override
  _AccountViewState createState() => _AccountViewState();
}

class _AccountViewState extends State<AccountView>{

  @override
  Widget build(BuildContext context){
    return Scaffold(
      body: Center(
        child: Text("Account"),
      ),
    );
  }
}