import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/core/data/enums/subscription_status_enum.dart';
import 'package:season_planner/core/widgets/ux_components.dart';
import 'package:season_planner/fsAdmin/flight_school_provider.dart';

/// Zentrale Abo-Sperre für Admin-Views: prüft automatisch `FlightSchoolProvider`
/// und sperrt den Bereich, solange `subscription_status != active` ist.
class SubscriptionGate extends StatelessWidget {
  final String title;
  final String featureName;
  final Widget child;
  final bool automaticallyImplyLeading;

  const SubscriptionGate({
    super.key,
    required this.title,
    required this.featureName,
    required this.child,
    this.automaticallyImplyLeading = false,
  });

  @override
  Widget build(BuildContext context) {
    final fs = context.watch<FlightSchoolProvider>().flightSchool;
    if (fs == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!fs.isSubscriptionActive) {
      return Scaffold(
        appBar: AppBar(
          title: Text(title),
          automaticallyImplyLeading: automaticallyImplyLeading,
          actions: const [
            AdminFlightSchoolSwitcherChip(),
            AppModeSwitchChip(isAdminMode: true),
            SizedBox(width: 6),
          ],
        ),
        body: SubscriptionLockedView(
          featureName: featureName,
          status: fs.subscriptionStatus,
        ),
      );
    }
    return child;
  }
}

class SubscriptionLockedView extends StatelessWidget {
  final String featureName;
  final SubscriptionStatusEnum status;

  const SubscriptionLockedView({
    super.key,
    required this.featureName,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final isPending = status == SubscriptionStatusEnum.pending;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isPending ? Icons.hourglass_top_rounded : Icons.lock_outline,
                    size: 56,
                    color: isPending ? Colors.orange : Colors.redAccent,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    isPending
                        ? 'Dein Abo wird gerade aktiviert'
                        : 'Abo derzeit deaktiviert',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    isPending
                        ? 'Der Bereich „$featureName“ wird automatisch freigeschaltet, sobald dein Flugschul-Abo aktiviert wurde.\n\nStammdaten, Logo und Teamrollen kannst du unter „Flugschule“ bereits jetzt pflegen.'
                        : 'Der Bereich „$featureName“ ist aktuell gesperrt. Bitte wende dich an den Tragegurt-Support.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
