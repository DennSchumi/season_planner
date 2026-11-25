import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/core/data/enums/subscription_status_enum.dart';
import 'package:season_planner/core/features/notifications/notification_settings_view.dart';
import 'package:season_planner/core/theme.dart';
import 'package:season_planner/core/widgets/ics_subscription_dialog.dart';
import 'package:season_planner/core/widgets/ux_components.dart';
import 'package:season_planner/fsAdmin/features/audit_exports/audit_exports_view.dart';
import 'package:season_planner/fsAdmin/features/audit_log/audit_log_view.dart';
import 'package:season_planner/fsAdmin/features/manage_documents/manage_role_documents_view.dart';
import 'package:season_planner/fsAdmin/features/manage_flight_school_view/manage_admin_user/manage_admin_users_view.dart';
import 'package:season_planner/fsAdmin/features/manage_flight_school_view/manage_flight_school_informations/manage_flight_school_informations_view.dart';
import 'package:season_planner/fsAdmin/features/manage_planning/manage_planning_periods_view.dart';
import 'package:season_planner/fsAdmin/features/manage_qualifications/manage_qualifications_view.dart';
import 'package:season_planner/fsAdmin/features/manage_qualifications/review_qualifications_view.dart';
import 'package:season_planner/fsAdmin/features/manage_roles/manage_team_roles_view.dart';
import 'package:season_planner/fsAdmin/features/manage_tandem/manage_tandem_view.dart';
import 'package:season_planner/fsAdmin/features/manage_timesheets/manage_timesheets_view.dart';
import 'package:season_planner/fsAdmin/features/statistics/member_statistics_view.dart';
import 'package:season_planner/fsAdmin/features/widgets/subscription_locked_view.dart';
import 'package:season_planner/fsAdmin/flight_school_provider.dart';
import 'package:season_planner/fsAdmin/services/flight_school_service.dart';

class ManageFlightSchoolView extends StatefulWidget {
  const ManageFlightSchoolView({super.key});

  @override
  _ManageFlightSchoolView createState() => _ManageFlightSchoolView();
}

class _ManageFlightSchoolView extends State<ManageFlightSchoolView> {
  @override
  Widget build(BuildContext context) {
    final fs = Provider.of<FlightSchoolProvider>(context).flightSchool;
    if (fs == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Flugschule verwalten'),
        automaticallyImplyLeading: false,
        actions: const [
          AdminFlightSchoolSwitcherChip(),
          AppModeSwitchChip(isAdminMode: true),
          SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 108),
          children: [
            // Kompakte Flugschul-Kopf-Kachel
            SoftCard(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: fs.logoLink.isEmpty
                        ? Image.asset(
                            "lib/assets/images/fsBaseImage.webp",
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                          )
                        : Image.network(
                            fs.logoLink,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Image.asset(
                              "lib/assets/images/fsBaseImage.webp",
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                            ),
                          ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fs.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 6),
                        StatusPill(
                          label: 'Abo: ${fs.subscriptionStatus.label}',
                          icon: fs.isSubscriptionActive
                              ? Icons.check_circle_outline
                              : Icons.hourglass_top_rounded,
                          foreground: fs.isSubscriptionActive
                              ? AppTheme.successColor
                              : AppTheme.warningColor,
                          background: fs.isSubscriptionActive
                              ? AppTheme.successBg
                              : AppTheme.warningBg,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 22),

            // 1. Organisation
            const _SectionHeader(title: 'Organisation'),
            _GroupedMenuCard(
              iconColor: AppTheme.primaryColor,
              iconBg: AppTheme.primaryTint,
              tiles: [
                _MenuEntry(
                  icon: Icons.folder_outlined,
                  label: 'Stammdaten & Logo',
                  subtitle: 'Name, Kurzname und Logo der Flugschule',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            const ManageFlightSchoolAdminInfoView(),
                      ),
                    );
                  },
                ),
                _MenuEntry(
                  icon: Icons.admin_panel_settings_outlined,
                  label: 'Admin-Nutzer verwalten',
                  subtitle: 'Zugriffsrechte für Administratoren',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ManageAdminsPage(),
                      ),
                    );
                  },
                ),
                _MenuEntry(
                  icon: Icons.badge_outlined,
                  label: 'Teamrollen',
                  subtitle: 'Startplatz, Trainingsleiter, Kamera, Checklisten',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ManageTeamRolesView(),
                      ),
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 20),

            // 2. Qualität & Sicherheit
            const _SectionHeader(title: 'Qualität & Sicherheit'),
            _GroupedMenuCard(
              iconColor: AppTheme.warningColor,
              iconBg: AppTheme.warningBg,
              tiles: [
                _MenuEntry(
                  icon: Icons.workspace_premium_outlined,
                  label: 'Qualifikationen & Nachweise',
                  subtitle: fs.openQualificationRequestCount > 0
                      ? '${fs.openQualificationRequestCount} offene Anfrage${fs.openQualificationRequestCount == 1 ? "" : "n"} warten auf Prüfung'
                      : 'Fluglehrer, Sicherheitstrainer, Nachweis-Anforderungen',
                  badgeCount: fs.openQualificationRequestCount,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ManageQualificationsView(
                          initialTab:
                              fs.openQualificationRequestCount > 0 ? 1 : 0,
                        ),
                      ),
                    );
                  },
                ),
                _MenuEntry(
                  icon: Icons.verified_user_outlined,
                  label: 'Qualifikationsprüfung',
                  subtitle: 'Eingereichte Nachweise der Mitglieder freigeben',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SubscriptionGate(
                          title: 'Qualifikationsprüfung',
                          featureName: 'Qualifikationsprüfung',
                          automaticallyImplyLeading: true,
                          child: ReviewQualificationsView(),
                        ),
                      ),
                    );
                  },
                ),
                _MenuEntry(
                  icon: Icons.description_outlined,
                  label: 'Arbeitsanweisungen & Checklisten',
                  subtitle: 'Zentrale Markdown-Bibliothek inkl. Bildern',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ManageRoleDocumentsView(),
                      ),
                    );
                  },
                ),
                _MenuEntry(
                  icon: Icons.fact_check_outlined,
                  label: 'Audit Exports',
                  subtitle: fs.auditExportsEnabled
                      ? 'Aktiv · ÖAeC Stellenbesetzungsplan & Nachweise'
                      : 'Deaktiviert – zum Aktivieren tippen',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SubscriptionGate(
                          title: 'Audit Exports',
                          featureName: 'Audit Exports',
                          automaticallyImplyLeading: true,
                          child: AuditExportsView(),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 20),

            // 3. Planung & Auswertung
            const _SectionHeader(title: 'Planung & Auswertung'),
            _GroupedMenuCard(
              iconColor: AppTheme.stage1Color,
              iconBg: AppTheme.stage1Bg,
              tiles: [
                _MenuEntry(
                  icon: Icons.layers_outlined,
                  label: 'Saisonplanung & Stufen',
                  subtitle: 'Planungsstufen 1–3, Verfügbarkeiten & Tausch',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SubscriptionGate(
                          title: 'Saisonplanung & Stufen',
                          featureName: 'Saisonplanung & Stufen',
                          automaticallyImplyLeading: true,
                          child: ManagePlanningPeriodsView(),
                        ),
                      ),
                    );
                  },
                ),
                _MenuEntry(
                  icon: Icons.paragliding_rounded,
                  label: 'Tandemplanung',
                  subtitle: fs.tandemEnabled
                      ? 'Aktiv · Bedarfszeiträume & Piloteneinteilung'
                      : 'Deaktiviert – zum Aktivieren tippen',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SubscriptionGate(
                          title: 'Tandemplanung',
                          featureName: 'Tandemplanung',
                          automaticallyImplyLeading: true,
                          child: ManageTandemView(),
                        ),
                      ),
                    );
                  },
                ),
                _MenuEntry(
                  icon: Icons.access_time_rounded,
                  label: 'Stundenzettel',
                  subtitle: fs.timesheetEnabled
                      ? 'Aktiv · Pflicht-Qualifikationen & Team-Export'
                      : 'Deaktiviert – zum Aktivieren tippen',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SubscriptionGate(
                          title: 'Stundenzettel',
                          featureName: 'Stundenzettel',
                          automaticallyImplyLeading: true,
                          child: ManageTimesheetsView(),
                        ),
                      ),
                    );
                  },
                ),
                _MenuEntry(
                  icon: Icons.bar_chart_outlined,
                  label: 'Statistik & Einsätze',
                  subtitle: 'Auswertung nach Saison und Einsatzrollen',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SubscriptionGate(
                          title: 'Statistik & Einsätze',
                          featureName: 'Statistik & Einsätze',
                          automaticallyImplyLeading: true,
                          child: MemberStatisticsView(),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 20),

            // 4. Sonstiges
            const _SectionHeader(title: 'Sonstiges'),
            _GroupedMenuCard(
              iconColor: cs.onSurfaceVariant,
              iconBg: AppTheme.backgroundColor,
              tiles: [
                _MenuEntry(
                  icon: Icons.notifications_outlined,
                  label: 'Benachrichtigungen',
                  subtitle: 'Push-Meldungen für Admin-Aufgaben & Einsätze',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const NotificationSettingsView(),
                      ),
                    );
                  },
                ),
                _MenuEntry(
                  icon: Icons.history_outlined,
                  label: 'Audit-Log',
                  subtitle: 'Nachvollziehbare Historie aller Änderungen',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AuditLogView()),
                    );
                  },
                ),
                _MenuEntry(
                  icon: Icons.rss_feed_outlined,
                  label: 'Kalender-Abo (ICS)',
                  subtitle: 'Abo-Link für Apple, Google & Outlook Kalender',
                  onTap: () {
                    showIcsSubscriptionDialog(
                      context: context,
                      title: 'Flugschul-Kalender-Abo',
                      subtitle:
                          'Automatisch aktueller ICS-Feed aller Events von ${fs.displayName}.',
                      loadUrl: () => FlightSchoolService()
                          .getOrCreateSchoolIcsFeedUrl(fs.id),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.7,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _MenuEntry {
  final IconData icon;
  final String label;
  final String? subtitle;
  final int badgeCount;
  final VoidCallback onTap;

  const _MenuEntry({
    required this.icon,
    required this.label,
    this.subtitle,
    this.badgeCount = 0,
    required this.onTap,
  });
}

class _GroupedMenuCard extends StatelessWidget {
  final Color iconColor;
  final Color iconBg;
  final List<_MenuEntry> tiles;

  const _GroupedMenuCard({
    required this.iconColor,
    required this.iconBg,
    required this.tiles,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SoftCard(
      child: Column(
        children: [
          for (int i = 0; i < tiles.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 68, color: cs.outlineVariant),
            InkWell(
              onTap: tiles[i].onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
                child: Row(
                  children: [
                    TintedIconBadge(
                      icon: tiles[i].icon,
                      iconColor: iconColor,
                      backgroundColor: iconBg,
                      size: 40,
                      iconSize: 20,
                      radius: 12,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tiles[i].label,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                              color: cs.onSurface,
                            ),
                          ),
                          if (tiles[i].subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              tiles[i].subtitle!,
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (tiles[i].badgeCount > 0) ...[
                      const SizedBox(width: 8),
                      StatusPill(
                        label: '${tiles[i].badgeCount}',
                        foreground: AppTheme.warningColor,
                        background: AppTheme.warningBg,
                      ),
                    ],
                    const SizedBox(width: 6),
                    Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: cs.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
