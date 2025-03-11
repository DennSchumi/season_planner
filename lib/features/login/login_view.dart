import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

class LoginView extends StatefulWidget{

@override
_LoginViewState createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView>{
  login(){

  }


  @override
  Widget build(BuildContext context) {
   return Scaffold(
     body: Center(
       child: Container(
         width: 300,
         child: Column(
           mainAxisAlignment: MainAxisAlignment.center,
           children: [
             Spacer(),
             Text("Wilkommen beim SeasonPlanner"),
             const SizedBox(height: 15),
             TextField(
               decoration:InputDecoration(
                 label: Text("E-mail"),
               ),
             ),
             TextField(
               decoration:InputDecoration(
                 label: Text("Password"),
               ),
             ),
             const SizedBox(height: 15),
             SizedBox(
               width: double.infinity,
               child: OutlinedButton(
                 onPressed: login,
                 child: Text("Login"),
               ),
             ),
            Spacer(),
           ],
         ),
       )
     ),
   );
  }
  
}