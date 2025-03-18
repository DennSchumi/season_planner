import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:season_planer/services/auth_service.dart';

import '../register/register_view.dart';

class LoginView extends StatefulWidget{

@override
_LoginViewState createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView>{
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  String errorMessage = '';

  void navigateRegister(){
    Navigator.push(context,MaterialPageRoute(builder: (context) => RegisterView()));
  }

  Future<void> handleLogin() async {
    String email = emailController.text.trim();
    String password = passwordController.text.trim();

    try {
      await AuthService().login(email, password);
      Navigator.pushReplacementNamed(context, '/');
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
      });
    }
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
             Image.asset("lib/assets/images/logo.png", width: 250,height: 250,),
             const SizedBox(height: 15),
             Text("Wilkommen beim SeasonPlanner"),
             const SizedBox(height: 15),
             TextField(
               controller: emailController,
               decoration:InputDecoration(
                 label: Text("E-mail"),
               ),
             ),
             TextField(
               controller: passwordController,
               decoration:InputDecoration(
                 label: Text("Password"),
               ),
             ),
             const SizedBox(height: 15),
             SizedBox(
               width: double.infinity,
               child: OutlinedButton(
                 onPressed: handleLogin,
                 child: Text("Login"),
               ),
             ),
             if(errorMessage.isNotEmpty)
               Text(errorMessage,style: TextStyle(color: Colors.red)),
             TextButton(
                 onPressed: navigateRegister,
                 child: Text("Noch kein Konto? Dann hier Registrieren...",
                   style: TextStyle(
                       fontSize: 10,
                       color: Colors.blueAccent,
                       decorationColor: Colors.blueAccent,
                       decoration: TextDecoration.underline
                   ),

                   )
             )
           ],
         ),
       )
     ),
   );
  }
  
}