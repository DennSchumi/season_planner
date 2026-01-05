import 'package:flutter/material.dart';
import 'package:season_planer/features/user_features/main_scaffold/main_user_scaffold_view.dart';

class ManageFlightSchoolView extends StatefulWidget{
  const ManageFlightSchoolView({super.key});


  @override
  _ManageFlightSchoolView createState() => _ManageFlightSchoolView();
}

class _ManageFlightSchoolView extends State<ManageFlightSchoolView>{
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        body: SafeArea(
          child:
        OutlinedButton(
          onPressed:
              () => {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => MainUserScaffoldView(),
              ),
            ),
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Text("Switch to USER-Mode"),
              SizedBox(width: 8),
              Icon(Icons.accessible_forward_outlined),
            ],
          ),
        ),
        ),
    );
  }

}