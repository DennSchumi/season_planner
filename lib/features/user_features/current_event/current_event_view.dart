import 'package:flutter/material.dart';

class CurrentEventView extends StatefulWidget{
  const CurrentEventView({super.key});

  @override
  _CurrentEventViewState createState() => _CurrentEventViewState();
}

class _CurrentEventViewState extends State<CurrentEventView>{
  @override
  Widget build(BuildContext context){
    return Scaffold(
      body: Center(
        child: Text("Event"),
      ),
    );
  }
}