import 'package:flutter/material.dart';
import 'package:season_planer/services/auth_service.dart';

class RegisterView extends StatefulWidget{
  const RegisterView({super.key});

  @override
  _RegisterView createState() => _RegisterView();
}

class _RegisterView extends State<RegisterView>{
  final TextEditingController nameController = TextEditingController();
  final TextEditingController lastnNameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController passwordRedoController = TextEditingController();
  String passwordSame = "nc";
  bool passwordNorm = true;
  String passwordErrorText = "";

  void checkPasswordNorm(){
    var pwd = passwordController.text;
    if(pwd.contains(" ")){
      if(pwd.length >= 8){
        passwordNorm = true;
      }else{
        passwordNorm = false;
        passwordErrorText ="Das Passwort muss 8 Zeichen lang sein";
      }
    }else{
      passwordNorm = false;
      passwordErrorText ="Das Passwort darf keine Leerzeichen enthalten";
    }
  }

  void checkPasswords(){
    if(passwordController.text.trim() == passwordRedoController.text.trim()){
      passwordSame = "true";
    }
    else{
      passwordSame ="false";
    }
  }

  Future<void> handleRegistration() async{
    String name = "${nameController.text.trim()} ${lastnNameController .text.trim()}";
    String password = passwordRedoController.text.trim();
    String email = emailController.text.trim();

    AuthService().signUp(email, password, name);
  }

  @override
  Widget build(BuildContext context) {
   return Scaffold(
     body: Center(
       child: SizedBox(
         width: 300,
         child: Column(
           mainAxisAlignment: MainAxisAlignment.center,
           children: [
             Text("Registrierung"),
             TextField(
               controller: nameController,
               decoration:InputDecoration(
                 label: Text("Name"),
               ),
             ),
             const SizedBox(height: 10),

             TextField(
               controller: emailController,
               decoration:InputDecoration(
                 label: Text("E-mail"),
               ),
             ),
             const SizedBox(height: 10),

             TextField(
               controller: passwordController,
               decoration:InputDecoration(
                 label: Text("Passwort"),
               ),
               autocorrect: false,
               onEditingComplete: checkPasswordNorm,
             ),
             const SizedBox(height: 10),

             TextField(
               controller: passwordRedoController,
               decoration:InputDecoration(
                 label: Text("Passwort wiederholen"),
               ),
               autocorrect: false,
               onEditingComplete: checkPasswords,
             ),
             const SizedBox(height: 10),

             SizedBox(
               width: double.infinity,
               child: OutlinedButton(
                 onPressed: handleRegistration,
                 child: Text("Registrieren"),
               ),
             ),
           ],
         ),
       ),
     ),
   );
  }
  
  
}