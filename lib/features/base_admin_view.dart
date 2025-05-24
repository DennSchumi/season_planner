import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planer/features/admin_features/main_scaffold/main_admin_scaffold_view.dart';
import 'package:season_planer/services/flight_school_provider.dart';

import '../data/models/flight_school_model.dart';
import '../services/user_provider.dart';

class BaseAdminView extends StatefulWidget {
  @override
  _BaseAdminViewState createState() => _BaseAdminViewState();
}

//flightschools vom user holen, schauen bei welchen er Admin ist, wenn bei einer , direkt weiterleiten , wenn bei mehreren dann auswahl. Vor dem Weiterleiten noch die flight school im provider setzen

class _BaseAdminViewState extends State<BaseAdminView> {
  @override
  Widget build(BuildContext context) {
    final user = Provider.of<UserProvider>(context).user;
    final flight_school_provider = Provider.of<FlightSchoolProvider>(context);

    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final List<FlightSchool> adminFlightSchools =
        user.flightSchools
            .where((fs) => fs.adminUserIds.contains(user.id))
            .toList();
    if (adminFlightSchools.length == 1) {
      flight_school_provider.setFlightSchool(adminFlightSchools[0]);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MainAdminScaffoldView(),
        ),
      );
    } else {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              ...adminFlightSchools.asMap().entries.map((entry) {
                final index = entry.key;
                final fs = entry.value;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Card(
                    elevation: 2,
                    child: ListTile(
                      title: Text(fs.displayName),
                      onTap: () {
                        flight_school_provider.setFlightSchool(
                          adminFlightSchools[index],
                        );
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => MainAdminScaffoldView(),
                          ),
                        );
                      },
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      );
    }

    // TODO: implement build
    throw UnimplementedError();
  }
}
