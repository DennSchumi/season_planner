import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planer/features/admin_features/manage_flight_school_view/manage_admin_user/manage_admin_users_view.dart';
import 'package:season_planer/features/admin_features/manage_flight_school_view/manage_flight_school_informations/manage_flight_school_informations_view.dart';
import 'package:season_planer/features/user_features/main_scaffold/main_user_scaffold_view.dart';
import 'package:season_planer/services/providers/flight_school_provider.dart';

class ManageFlightSchoolView extends StatefulWidget{
  const ManageFlightSchoolView({super.key});


  @override
  _ManageFlightSchoolView createState() => _ManageFlightSchoolView();
}

class _ManageFlightSchoolView extends State<ManageFlightSchoolView>{
  @override
  Widget build(BuildContext context) {
    final fs = Provider.of<FlightSchoolProvider>(context).flightSchool;

    return Scaffold(
        body: SafeArea(
          child:Column(
            children: [
              SizedBox(height: 16),
              ClipOval(
                child: Image.network(
                  fs!.logoLink,
                  width: 256,
                  height: 256,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Image.asset(
                    "lib/assets/images/fsBaseImage.webp",
                    width: 256,
                    height: 256,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              Text(
                  fs.displayName,
                style: TextStyle(
                  fontSize: 34
                ),
              ),SizedBox(height: 16),
              OutlinedButton(
                onPressed:
                    () => {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ManageFlightSchoolAdminInfoView(),
                    ),
                  ),
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Text("Manage Flight School Informations"),
                  ],
                ),
              ),
              SizedBox(height: 16),
              OutlinedButton(
                onPressed:
                    () => {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ManageAdminsPage(),
                    ),
                  ),
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Text("Manage Admin User"),
                  ],
                ),
              ),
              SizedBox(height: 16),
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
            ],
          )

        ),
    );
  }

}