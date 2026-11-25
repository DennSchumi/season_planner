import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/core/appwrite_config.dart';
import 'package:season_planner/core/features/authentification/login/login_view.dart';
import 'package:season_planner/core/features/notifications/notification_settings_view.dart';
import 'package:season_planner/core/services/auth_service.dart';
import 'package:season_planner/core/services/file_download_helper.dart';
import 'package:season_planner/core/services/notification_service.dart';
import 'package:season_planner/core/services/security_privacy_service.dart';
import 'package:season_planner/core/theme.dart';
import 'package:season_planner/core/widgets/ics_subscription_dialog.dart';
import 'package:season_planner/core/widgets/legal_links.dart';
import 'package:season_planner/core/widgets/user_avatar.dart';
import 'package:season_planner/core/widgets/ux_components.dart';
import 'package:season_planner/fsAdmin/flight_school_provider.dart';
import 'package:season_planner/user/features/account/widgets/manage_account.dart';
import 'package:season_planner/user/features/account/widgets/manage_flight_school_memberships.dart';
import 'package:season_planner/user/features/availability/my_availability_view.dart';
import 'package:season_planner/user/features/qualifications/my_qualifications_view.dart';
import 'package:season_planner/user/features/timesheets/my_timesheets_view.dart';
import 'package:season_planner/user/services/database_service.dart';
import 'package:season_planner/user/services/user_badge_state_service.dart';
import '../../user_provider.dart';

class AccountView extends StatefulWidget {
  const AccountView({super.key});

  @override
  _AccountViewState createState() => _AccountViewState();
}

class _AccountViewState extends State<AccountView> {
  bool _exportingData = false;

  Future<void> _logOut() async {
    UserBadgeStateService().clearOnLogout();
    await AuthService().logout();
    if (!mounted) return;
    context.read<UserProvider>().clearUser();
    Navigator.pushReplacementNamed(context, '/login');
  }

  Future<void> _exportMyData() async {
    if (_exportingData) return;
    setState(() => _exportingData = true);
    try {
      final data = await SecurityPrivacyService().exportMyData();
      final prettyJson = const JsonEncoder.withIndent('  ').convert(data);
      final bytes = Uint8List.fromList(utf8.encode(prettyJson));
      final now = DateTime.now();
      final stamp =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      await downloadBytesFile(
        bytes: bytes,
        filename: 'tragegurt_datenexport_$stamp.json',
        mimeType: 'application/json',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dein DSGVO-Datenexport wurde heruntergeladen.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Datenexport fehlgeschlagen: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _exportingData = false);
    }
  }

  Future<void> _confirmDeleteAccount(String userEmail) async {
    final emailCtrl = TextEditingController();
    bool deleting = false;
    String? errorText;

    final deleted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final cs = Theme.of(ctx).colorScheme;
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: AppTheme.dangerColor),
                  SizedBox(width: 8),
                  Expanded(child: Text('Konto dauerhaft löschen?')),
                ],
              ),
              content: SizedBox(
                width: 440,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Folgende Daten werden endgültig und unwiderruflich gelöscht:\n'
                        '• Dein Tragegurt-Login & Profil (inkl. Adresse, Telefon, Notfallkontakt, Profilbild)\n'
                        '• Alle hochgeladenen Qualifikationsdokumente & Nachweise\n'
                        '• Alle Verfügbarkeiten, Mitgliedschaften & zukünftigen Einteilungen',
                        style: TextStyle(fontSize: 13, height: 1.4),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Hinweis zu gesetzlichen Aufbewahrungspflichten: Bereits eingereichte Stundenzettel und unterschriebene Sicherheits-Einweisungen bleiben bei den jeweiligen Flugschulen zur Erfüllung gesetzlicher/behördlicher Nachweispflichten archiviert.',
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.35,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Gib zur Bestätigung deine E-Mail-Adresse ein ($userEmail):',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: emailCtrl,
                        enabled: !deleting,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: 'E-Mail zur Bestätigung',
                          hintText: userEmail,
                        ),
                      ),
                      if (errorText != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          errorText!,
                          style: TextStyle(
                            color: cs.error,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: deleting ? null : () => Navigator.pop(ctx, false),
                  child: const Text('Abbrechen'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.dangerColor,
                  ),
                  onPressed: deleting
                      ? null
                      : () async {
                          if (emailCtrl.text.trim().toLowerCase() !=
                              userEmail.trim().toLowerCase()) {
                            setLocal(() {
                              errorText =
                                  'Bitte gib exakt deine E-Mail-Adresse ein.';
                            });
                            return;
                          }
                          setLocal(() {
                            deleting = true;
                            errorText = null;
                          });
                          try {
                            await SecurityPrivacyService().deleteMyAccount(
                              confirmEmail: emailCtrl.text.trim(),
                            );
                            if (ctx.mounted) Navigator.pop(ctx, true);
                          } catch (e) {
                            setLocal(() {
                              deleting = false;
                              errorText = e
                                  .toString()
                                  .replaceFirst('Exception: ', '');
                            });
                          }
                        },
                  child: deleting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Endgültig löschen'),
                ),
              ],
            );
          },
        );
      },
    );

    emailCtrl.dispose();

    if (deleted == true && mounted) {
      UserBadgeStateService().clearOnLogout();
      await AuthService().clearLocalSessionData();
      if (!mounted) return;
      context.read<UserProvider>().clearUser();
      context.read<FlightSchoolProvider>().clearFlightSchool();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginView()),
        (_) => false,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dein Konto wurde dauerhaft gelöscht.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserProvider>().user;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Konto'),
        automaticallyImplyLeading: false,
        actions: const [
          AppModeSwitchChip(isAdminMode: false),
          SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 108),
          children: [
            // Profil-Karte (Revolut-Stil)
            SoftCard(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ManageAccountView()),
                );
              },
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      UserAvatar(
                        avatarUrl: user.avatarUrl,
                        name: user.name,
                        radius: 28,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.name.isEmpty ? 'Benutzer' : user.name,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16.5,
                                color: cs.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              user.mail,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Persönliche Daten, Profilbild, Notfallkontakt & Lizenzdaten',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: cs.onSurfaceVariant,
                      ),
                    ],
                  ),
                  if (!user.hasEmergencyContact) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.warningBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.emergency_outlined,
                            size: 17,
                            color: AppTheme.warningColor,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Noch kein Notfallkontakt hinterlegt – jetzt ergänzen',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.warningColor,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: AppTheme.warningColor.withValues(alpha: 0.8),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 22),
            _AccountSectionLabel('MEIN PROFIL'),
            ListenableBuilder(
              listenable: UserBadgeStateService(),
              builder: (context, _) {
                final badge = UserBadgeStateService();
                return SoftCard(
                  child: Column(
                    children: [
                      _AccountMenuRow(
                        icon: Icons.event_available_outlined,
                        iconColor: AppTheme.primaryColor,
                        iconBg: AppTheme.primaryTint,
                        title: 'Verfügbarkeiten & Abwesenheiten',
                        subtitle: 'Verfügbare Tage & Abwesenheiten verwalten',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const MyAvailabilityView(),
                            ),
                          );
                        },
                      ),
                      Divider(height: 1, indent: 68, color: cs.outlineVariant),
                      _AccountMenuRow(
                        icon: Icons.verified_user_outlined,
                        iconColor: AppTheme.primaryColor,
                        iconBg: AppTheme.primaryTint,
                        title: 'Qualifikationen & Nachweise',
                        subtitle: 'Qualifikationen anfragen & Dokumente hochladen',
                        showRedDot: badge.hasOpenQualifications,
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const MyQualificationsView(),
                            ),
                          );
                          if (!context.mounted) return;
                          final freshUser = context.read<UserProvider>().user;
                          if (freshUser != null) {
                            UserBadgeStateService().refreshFromUser(freshUser);
                          }
                        },
                      ),
                      Divider(height: 1, indent: 68, color: cs.outlineVariant),
                      _AccountMenuRow(
                        icon: Icons.access_time_rounded,
                        iconColor: AppTheme.primaryColor,
                        iconBg: AppTheme.primaryTint,
                        title: 'Stundenzettel & Lehrtätigkeit',
                        subtitle: 'Arbeitszeiten auswerten & als PDF/CSV exportieren',
                        showRedDot: badge.hasOpenTimesheets,
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const MyTimesheetsView(),
                            ),
                          );
                          if (!context.mounted) return;
                          final freshUser = context.read<UserProvider>().user;
                          if (freshUser != null) {
                            UserBadgeStateService().refreshFromUser(freshUser);
                          }
                        },
                      ),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: 22),
            _AccountSectionLabel('EINSTELLUNGEN'),
            SoftCard(
              child: Column(
                children: [
                  ListenableBuilder(
                    listenable: NotificationService(),
                    builder: (context, _) {
                      final np = NotificationService().prefs;
                      final isAdmin = user.flightSchools
                          .any((fs) => fs.adminUserIds.contains(user.id));
                      final active = np.activeUserCategoryCount +
                          (isAdmin ? np.activeAdminCategoryCount : 0);
                      final total = isAdmin ? 11 : 7;
                      return _AccountMenuRow(
                        icon: np.enabled
                            ? Icons.notifications_active_outlined
                            : Icons.notifications_off_outlined,
                        iconColor: np.enabled
                            ? AppTheme.primaryColor
                            : cs.onSurfaceVariant,
                        iconBg: np.enabled
                            ? AppTheme.primaryTint
                            : AppTheme.backgroundColor,
                        title: 'Benachrichtigungen',
                        subtitle: np.enabled
                            ? 'Aktiv · $active von $total Kategorien'
                            : 'Deaktiviert',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const NotificationSettingsView(),
                            ),
                          );
                        },
                      );
                    },
                  ),
                  Divider(height: 1, indent: 68, color: cs.outlineVariant),
                  _AccountMenuRow(
                    icon: Icons.school_outlined,
                    iconColor: cs.onSurfaceVariant,
                    iconBg: AppTheme.backgroundColor,
                    title: 'Flugschul-Mitgliedschaften',
                    subtitle:
                        '${user.flightSchools.length} Flugschule${user.flightSchools.length == 1 ? "" : "n"}',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const ManageFlightSchoolMemberships(),
                        ),
                      );
                    },
                  ),
                  Divider(height: 1, indent: 68, color: cs.outlineVariant),
                  _AccountMenuRow(
                    icon: Icons.rss_feed_outlined,
                    iconColor: cs.onSurfaceVariant,
                    iconBg: AppTheme.backgroundColor,
                    title: 'Kalender-Abo (ICS)',
                    subtitle: 'Bestätigte Events automatisch synchronisieren',
                    onTap: () {
                      showIcsSubscriptionDialog(
                        context: context,
                        title: 'Persönliches Kalender-Abo',
                        subtitle:
                            'Synchronisiert automatisch alle deine bestätigten Events aus allen Flugschulen.',
                        loadUrl: () =>
                            DatabaseService().getOrCreateUserIcsFeedUrl(),
                        onRegenerateUrl: () => DatabaseService()
                            .getOrCreateUserIcsFeedUrl(forceRegenerate: true),
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Divider(
                height: 1,
                color: cs.outlineVariant.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 20),
            _AccountSectionLabel('RECHTLICHES & DATENSCHUTZ'),
            SoftCard(
              radius: 18,
              child: Column(
                children: [
                  _CompactAccountMenuRow(
                    icon: Icons.download_outlined,
                    iconColor: cs.onSurfaceVariant,
                    title: _exportingData
                        ? 'Datenexport wird erstellt…'
                        : 'Meine Daten exportieren (DSGVO)',
                    onTap: _exportingData ? () {} : _exportMyData,
                  ),
                  Divider(
                    height: 1,
                    indent: 44,
                    color: cs.outlineVariant.withValues(alpha: 0.7),
                  ),
                  _CompactAccountMenuRow(
                    icon: Icons.privacy_tip_outlined,
                    iconColor: cs.onSurfaceVariant,
                    title: 'Datenschutzerklärung',
                    onTap: () => openLegalUrl(
                      context,
                      AppwriteConfig().legalPrivacyUrl,
                    ),
                  ),
                  Divider(
                    height: 1,
                    indent: 44,
                    color: cs.outlineVariant.withValues(alpha: 0.7),
                  ),
                  _CompactAccountMenuRow(
                    icon: Icons.description_outlined,
                    iconColor: cs.onSurfaceVariant,
                    title: 'AGB / Nutzungsbedingungen',
                    onTap: () => openLegalUrl(
                      context,
                      AppwriteConfig().legalTermsUrl,
                    ),
                  ),
                  Divider(
                    height: 1,
                    indent: 44,
                    color: cs.outlineVariant.withValues(alpha: 0.7),
                  ),
                  _CompactAccountMenuRow(
                    icon: Icons.gavel_outlined,
                    iconColor: cs.onSurfaceVariant,
                    title: 'Impressum',
                    onTap: () => openLegalUrl(
                      context,
                      AppwriteConfig().legalImprintUrl,
                    ),
                  ),
                  Divider(
                    height: 1,
                    indent: 44,
                    color: cs.outlineVariant.withValues(alpha: 0.7),
                  ),
                  _CompactAccountMenuRow(
                    icon: Icons.delete_forever_outlined,
                    iconColor: AppTheme.dangerColor,
                    titleColor: AppTheme.dangerColor,
                    title: 'Konto dauerhaft löschen',
                    onTap: () => _confirmDeleteAccount(user.mail),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
            SoftCard(
              onTap: _logOut,
              padding: const EdgeInsets.symmetric(vertical: 15),
              child: const Center(
                child: Text(
                  'Abmelden',
                  style: TextStyle(
                    color: AppTheme.dangerColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
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

class _AccountSectionLabel extends StatelessWidget {
  final String text;
  const _AccountSectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.7,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _AccountMenuRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String? subtitle;
  final bool showRedDot;
  final VoidCallback onTap;

  const _AccountMenuRow({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    this.subtitle,
    this.showRedDot = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            TintedIconBadge(
              icon: icon,
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
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                      color: cs.onSurface,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (showRedDot) ...[
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: AppTheme.dangerColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.dangerColor.withValues(alpha: 0.35),
                      blurRadius: 5,
                      spreadRadius: 0.5,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
            ],
            Icon(Icons.chevron_right, size: 20, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _CompactAccountMenuRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color? titleColor;
  final String title;
  final VoidCallback onTap;

  const _CompactAccountMenuRow({
    required this.icon,
    required this.iconColor,
    this.titleColor,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: titleColor ?? cs.onSurfaceVariant,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 17,
              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    );
  }
}
