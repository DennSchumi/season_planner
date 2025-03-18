import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class CalenderView extends StatefulWidget{
  @override
  _CalenderView createState() => _CalenderView();
}

class _CalenderView extends State<CalenderView>{

  @override
  Widget build(BuildContext context){
    return Scaffold(
      body: Center(
        child: Text("Kalender"),
      ),
    );
  }
}