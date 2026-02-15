import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/data/models/admin_models/flight_school_model_flight_school_view.dart';
import 'package:season_planner/features/admin_features/main_scaffold/main_admin_scaffold_view.dart';
import 'package:season_planner/services/database_service.dart';
import 'package:season_planner/services/flight_school_service.dart';
import 'package:season_planner/services/providers/flight_school_provider.dart';
import 'package:season_planner/services/providers/user_provider.dart';
import '../data/models/user_models/flight_school_model_user_view.dart';

class BaseAdminView extends StatefulWidget {
  const BaseAdminView({super.key});

  @override
  State<BaseAdminView> createState() => _BaseAdminViewState();
}

class _BaseAdminViewState extends State<BaseAdminView> {
  bool _autoNavigated = false;
  bool _isBusy = false;

  Future<void> _selectFlightSchool(BuildContext context, String id) async {
    final flightSchoolProvider =
    Provider.of<FlightSchoolProvider>(context, listen: false);


    setState(() {
      _isBusy = true;
    });
    final FlightSchoolModelFlightSchoolView? fs = await FlightSchoolService().getFlightSchool(id);

    if (!mounted) return;

    if (fs == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("FlightSchool could´nt be loaded.")),
      );
      return;
    }

    flightSchoolProvider.setFlightSchool(fs);


    setState(() {
      _isBusy = false;
    });
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MainAdminScaffoldView()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<UserProvider>(context).user;

    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final List<FlightSchoolUserView> adminFlightSchools = user.flightSchools
        .where((fs) => fs.adminUserIds.contains(user.id))
        .toList();

    if (adminFlightSchools.length == 1 && !_autoNavigated) {
      _autoNavigated = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _selectFlightSchool(context, adminFlightSchools.first.id);
      });

      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Select Flight School")),
      body: SafeArea(
        child: Stack(
          children: [
            ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: adminFlightSchools.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final fs = adminFlightSchools[index];

                return Card(
                  elevation: 2,
                  child: ListTile(
                    title: Text(fs.displayName),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _isBusy ? null : () => _selectFlightSchool(context, fs.id),
                  ),
                );
              },
            ),

            if (_isBusy)
              Positioned.fill(
                child: AbsorbPointer(
                  absorbing: true,
                  child: Container(
                    color: Colors.black.withOpacity(0.2),
                    child: const Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

  }
}
