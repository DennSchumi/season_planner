import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/core/widgets/ux_components.dart';
import 'package:season_planner/fsAdmin/data/models/flight_school_model_flight_school_view.dart';
import 'package:season_planner/fsAdmin/features/main_scaffold/main_admin_scaffold_view.dart';
import 'package:season_planner/fsAdmin/flight_school_provider.dart';
import 'package:season_planner/fsAdmin/services/flight_school_service.dart';
import 'package:season_planner/user/data/models/flight_school_model_user_view.dart';
import 'package:season_planner/user/user_provider.dart';

/// Öffnet direkt den Admin-Bereich mit der zuletzt verwendeten Flugschule
/// (oder der ersten verfügbaren Admin-Flugschule, falls noch keine gespeichert ist).
/// Zwischen mehreren Flugschulen kann jederzeit direkt über den Umschalter
/// in der Admin-AppBar gewechselt werden.
class BaseAdminView extends StatefulWidget {
  const BaseAdminView({super.key});

  @override
  State<BaseAdminView> createState() => _BaseAdminViewState();
}

class _BaseAdminViewState extends State<BaseAdminView> {
  bool _started = false;
  String? _errorMessage;

  Future<void> _openInitialFlightSchool(
    List<FlightSchoolUserView> adminFlightSchools,
  ) async {
    final flightSchoolProvider = Provider.of<FlightSchoolProvider>(
      context,
      listen: false,
    );

    final lastId = await flightSchoolProvider.loadLastAdminFlightSchoolId();
    if (!mounted) return;

    final target = adminFlightSchools.firstWhere(
      (fs) => fs.id == lastId,
      orElse: () => adminFlightSchools.first,
    );

    // Wenn dieselbe Flugschule bereits geladen im Provider liegt, sofort öffnen
    // und im Hintergrund frisch aktualisieren.
    if (flightSchoolProvider.flightSchool?.id == target.id) {
      flightSchoolProvider.reloadFlightSchoolInBackground(
        FlightSchoolService().getFlightSchool,
      );
      Navigator.pushReplacement(
        context,
        fadePageRoute(const MainAdminScaffoldView()),
      );
      return;
    }

    final FlightSchoolModelFlightSchoolView? fs =
        await FlightSchoolService().getFlightSchool(target.id);

    if (!mounted) return;

    if (fs == null) {
      setState(() {
        _errorMessage =
            'Flugschule „${target.displayName}“ konnte nicht geladen werden.';
      });
      return;
    }

    flightSchoolProvider.setFlightSchool(fs);
    Navigator.pushReplacement(
      context,
      fadePageRoute(const MainAdminScaffoldView()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<UserProvider>(context).user;

    if (user == null) {
      return const ParagliderLoadingView(
        message: 'Flugschule wird geladen…',
      );
    }

    final List<FlightSchoolUserView> adminFlightSchools =
        user.adminFlightSchools;

    if (adminFlightSchools.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin-Bereich')),
        body: EmptyStateView(
          icon: Icons.admin_panel_settings_outlined,
          title: 'Kein Admin-Zugang vorhanden',
          subtitle:
              'Du bist aktuell bei keiner Flugschule als Administrator eingetragen.',
          actionLabel: 'Zurück',
          actionIcon: Icons.arrow_back,
          onAction: () => Navigator.maybePop(context),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin-Bereich')),
        body: EmptyStateView(
          icon: Icons.cloud_off_outlined,
          title: 'Laden fehlgeschlagen',
          subtitle: _errorMessage!,
          actionLabel: 'Erneut versuchen',
          actionIcon: Icons.refresh,
          onAction: () {
            setState(() {
              _errorMessage = null;
              _started = false;
            });
          },
        ),
      );
    }

    if (!_started) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _openInitialFlightSchool(adminFlightSchools);
        }
      });
    }

    return const ParagliderLoadingView(
      message: 'Flugschule wird geladen…',
    );
  }
}
