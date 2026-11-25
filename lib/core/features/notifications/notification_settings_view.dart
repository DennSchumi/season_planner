import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/core/services/notification_service.dart';
import 'package:season_planner/core/theme.dart';
import 'package:season_planner/core/widgets/ux_components.dart';
import 'package:season_planner/user/user_provider.dart';

class NotificationSettingsView extends StatefulWidget {
  const NotificationSettingsView({super.key});

  @override
  State<NotificationSettingsView> createState() =>
      _NotificationSettingsViewState();
}

class _NotificationSettingsViewState extends State<NotificationSettingsView> {
  final _service = NotificationService();
  bool _requestingPermission = false;

  @override
  void initState() {
    super.initState();
    _service.init();
    _service.syncFromAccountPrefs();
  }

  Future<void> _requestPermission() async {
    setState(() => _requestingPermission = true);
    try {
      final status = await _service.requestSystemPermission();
      if (!mounted) return;
      final msg = switch (status) {
        'granted' => 'System-Benachrichtigungen wurden aktiviert!',
        'denied' => kIsWeb
            ? 'Benachrichtigungen wurden im Browser blockiert. Bitte in den Browser-Einstellungen freigeben.'
            : 'Benachrichtigungen wurden blockiert. Bitte in den App-Einstellungen des Geräts freigeben.',
        'unsupported' => kIsWeb
            ? 'Dein aktueller Browser unterstützt keine Web-Push-Benachrichtigungen (In-App-Banner bleiben aktiv).'
            : 'System-Push ist auf diesem Gerät nicht verfügbar (In-App-Banner bleiben aktiv).',
        _ => 'Berechtigung wurde noch nicht erteilt.',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _requestingPermission = false);
    }
  }

  Future<void> _sendTest() async {
    final nativeSent = await _service.sendTestNotification(context: context);
    if (!mounted) return;
    if (!nativeSent && _service.isSystemPushSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'In-App-Vorschau angezeigt. Für System-Push bitte oben „Push erlauben“ tippen.',
          ),
        ),
      );
    }
  }

  String _fmtTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} Uhr';

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserProvider>().user;
    final isAdmin = user != null &&
        user.flightSchools.any((fs) => fs.adminUserIds.contains(user.id));
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Benachrichtigungen'),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _service,
          builder: (context, _) {
            final p = _service.prefs;
            final perm = _service.systemPermissionStatus;
            final history = _service.history;

            final (permLabel, permColor, permBg) = switch (perm) {
              'granted' => (
                  'Push aktiv',
                  AppTheme.successColor,
                  AppTheme.successBg,
                ),
              'denied' => (
                  'Blockiert',
                  AppTheme.dangerColor,
                  AppTheme.dangerBg,
                ),
              'default' => (
                  'Noch nicht erlaubt',
                  AppTheme.warningColor,
                  AppTheme.warningBg,
                ),
              _ => (
                  kIsWeb ? 'In-App aktiv' : 'Mobil / In-App',
                  AppTheme.infoColor,
                  AppTheme.infoBg,
                ),
            };

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
              children: [
                // 1) System-Push-Status & Test-Karte
                SoftCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          TintedIconBadge(
                            icon: Icons.notifications_active_outlined,
                            iconColor: permColor,
                            backgroundColor: permBg,
                            size: 42,
                            iconSize: 21,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Push-Benachrichtigungen',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15.5,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  perm == 'granted'
                                      ? 'System-Mitteilungen sind für dieses Gerät freigegeben.'
                                      : perm == 'denied'
                                          ? (kIsWeb
                                              ? 'Im Browser blockiert – bitte in den Website-Einstellungen erlauben.'
                                              : 'Auf dem Gerät blockiert – bitte in den App-Einstellungen erlauben.')
                                          : 'Erhalte Meldungen direkt als Push-Banner auf diesem Gerät.',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          StatusPill(
                            label: permLabel,
                            foreground: permColor,
                            background: permBg,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (_service.isSystemPushSupported &&
                              perm != 'granted')
                            FilledButton.icon(
                              onPressed: _requestingPermission
                                  ? null
                                  : _requestPermission,
                              icon: _requestingPermission
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.notifications_outlined,
                                      size: 18,
                                    ),
                              label: const Text('Push erlauben'),
                            ),
                          OutlinedButton.icon(
                            onPressed: _sendTest,
                            icon: const Icon(Icons.send_outlined, size: 17),
                            label: const Text('Test senden'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // 2) Master-Schalter
                SoftCard(
                  child: Column(
                    children: [
                      _SwitchRow(
                        icon: Icons.notifications_none_rounded,
                        iconColor: AppTheme.primaryColor,
                        iconBg: AppTheme.primaryTint,
                        title: 'Benachrichtigungen aktivieren',
                        subtitle:
                            'Einstellungen werden geräteübergreifend in deinem Konto gespeichert',
                        value: p.enabled,
                        onChanged: (v) =>
                            _service.updatePreferences(p.copyWith(enabled: v)),
                      ),
                      if (p.enabled) ...[
                        Divider(height: 1, indent: 68, color: cs.outlineVariant),
                        _SwitchRow(
                          icon: Icons.mark_chat_unread_outlined,
                          iconColor: AppTheme.infoColor,
                          iconBg: AppTheme.infoBg,
                          title: 'In-App-Banner anzeigen',
                          subtitle:
                              'Dezente Meldung am oberen Rand, während die App geöffnet ist',
                          value: p.inAppBanners,
                          onChanged: (v) => _service.updatePreferences(
                            p.copyWith(inAppBanners: v),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                if (p.enabled) ...[
                  // 3) Mitarbeiter – Einsätze & Planung
                  const SizedBox(height: 20),
                  const _SectionLabel('EINSÄTZE & PLANUNG'),
                  SoftCard(
                    child: Column(
                      children: [
                        _SwitchRow(
                          icon: Icons.assignment_ind_outlined,
                          iconColor: AppTheme.primaryColor,
                          iconBg: AppTheme.primaryTint,
                          title: 'Einsatz-Anfragen & Zuteilungen',
                          subtitle:
                              'Direktanfragen, neue verbindliche Einsätze & Bewerbungs-Status',
                          value: p.assignmentRequests,
                          onChanged: (v) => _service.updatePreferences(
                            p.copyWith(assignmentRequests: v),
                          ),
                        ),
                        Divider(height: 1, indent: 68, color: cs.outlineVariant),
                        _SwitchRow(
                          icon: Icons.swap_horiz_rounded,
                          iconColor: AppTheme.swapColor,
                          iconBg: AppTheme.swapBg,
                          title: 'Tauschanfragen',
                          subtitle:
                              'Freigegebene Tauschplätze deiner Rolle & Bestätigungen',
                          value: p.swapRequests,
                          onChanged: (v) => _service.updatePreferences(
                            p.copyWith(swapRequests: v),
                          ),
                        ),
                        Divider(height: 1, indent: 68, color: cs.outlineVariant),
                        _SwitchRow(
                          icon: Icons.work_outline_rounded,
                          iconColor: AppTheme.infoColor,
                          iconBg: AppTheme.infoBg,
                          title: 'Neue offene Stellen (Stufe 2/3)',
                          subtitle:
                              'Wenn freie Einsatzpositionen für deine Rollen ausgeschrieben werden',
                          value: p.openOpportunities,
                          onChanged: (v) => _service.updatePreferences(
                            p.copyWith(openOpportunities: v),
                          ),
                        ),
                        Divider(height: 1, indent: 68, color: cs.outlineVariant),
                        _SwitchRow(
                          icon: Icons.event_available_outlined,
                          iconColor: AppTheme.stage1Color,
                          iconBg: AppTheme.stage1Bg,
                          title: 'Verfügbarkeit eintragen (Stufe 1)',
                          subtitle:
                              'Hinweis, sobald ein Zeitraum für Verfügbarkeiten eröffnet wird',
                          value: p.stage1Availability,
                          onChanged: (v) => _service.updatePreferences(
                            p.copyWith(stage1Availability: v),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 4) Mitarbeiter – To-Do & Erinnerungen
                  const SizedBox(height: 20),
                  const _SectionLabel('TO-DO-LISTE & ERINNERUNGEN'),
                  SoftCard(
                    child: Column(
                      children: [
                        _SwitchRow(
                          icon: Icons.fact_check_outlined,
                          iconColor: AppTheme.warningColor,
                          iconBg: AppTheme.warningBg,
                          title: 'Checklisten & Nachweise',
                          subtitle:
                              'Offene Checklisten-Unterschriften, fehlende/abgelaufene Dokumente',
                          value: p.checklistsAndDocs,
                          onChanged: (v) => _service.updatePreferences(
                            p.copyWith(checklistsAndDocs: v),
                          ),
                        ),
                        Divider(height: 1, indent: 68, color: cs.outlineVariant),
                        _SwitchRow(
                          icon: Icons.inventory_2_outlined,
                          iconColor: AppTheme.dangerColor,
                          iconBg: AppTheme.dangerBg,
                          title: 'Inventarmanager-Aufgaben',
                          subtitle:
                              'Troubletickets, Checks & Neupacken während deiner laufenden Events',
                          value: p.inventoryTodos,
                          onChanged: (v) => _service.updatePreferences(
                            p.copyWith(inventoryTodos: v),
                          ),
                        ),
                        Divider(height: 1, indent: 68, color: cs.outlineVariant),
                        _SwitchRow(
                          icon: Icons.group_add_outlined,
                          iconColor: AppTheme.successColor,
                          iconBg: AppTheme.successBg,
                          title: 'Flugschul-Einladungen',
                          subtitle:
                              'Wenn dich eine neue Flugschule ins Team einlädt',
                          value: p.flightSchoolInvites,
                          onChanged: (v) => _service.updatePreferences(
                            p.copyWith(flightSchoolInvites: v),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 5) Admin-Meldungen (nur für Admins sichtbar)
                  if (isAdmin) ...[
                    const SizedBox(height: 20),
                    const _SectionLabel('ADMIN-AUFGABEN'),
                    SoftCard(
                      child: Column(
                        children: [
                          _SwitchRow(
                            icon: Icons.person_add_alt_1_outlined,
                            iconColor: AppTheme.successColor,
                            iconBg: AppTheme.successBg,
                            title: 'Team-Beitrittsanfragen',
                            subtitle:
                                'Wenn neue Mitarbeiter deiner Flugschule beitreten möchten',
                            value: p.adminJoinRequests,
                            onChanged: (v) => _service.updatePreferences(
                              p.copyWith(adminJoinRequests: v),
                            ),
                          ),
                          Divider(
                            height: 1,
                            indent: 68,
                            color: cs.outlineVariant,
                          ),
                          _SwitchRow(
                            icon: Icons.how_to_reg_outlined,
                            iconColor: AppTheme.infoColor,
                            iconBg: AppTheme.infoBg,
                            title: 'Bewerbungen, Tausch & Änderungen',
                            subtitle:
                                'Bewerbungen auf Stellen, Tauschwünsche & abgelehnte Einteilungen',
                            value: p.adminApplicationsAndSwaps,
                            onChanged: (v) => _service.updatePreferences(
                              p.copyWith(adminApplicationsAndSwaps: v),
                            ),
                          ),
                          Divider(
                            height: 1,
                            indent: 68,
                            color: cs.outlineVariant,
                          ),
                          _SwitchRow(
                            icon: Icons.verified_user_outlined,
                            iconColor: AppTheme.warningColor,
                            iconBg: AppTheme.warningBg,
                            title: 'Dokumente & Qualifikationen',
                            subtitle:
                                'Neu eingereichte Nachweise & Qualifikations-Anfragen',
                            value: p.adminDocumentsAndQuals,
                            onChanged: (v) => _service.updatePreferences(
                              p.copyWith(adminDocumentsAndQuals: v),
                            ),
                          ),
                          Divider(
                            height: 1,
                            indent: 68,
                            color: cs.outlineVariant,
                          ),
                          _SwitchRow(
                            icon: Icons.event_busy_outlined,
                            iconColor: AppTheme.dangerColor,
                            iconBg: AppTheme.dangerBg,
                            title: 'Unbesetzte Stellen & Checklisten',
                            subtitle:
                                'Offene Positionen in den nächsten 14 Tagen & fehlende Unterschriften',
                            value: p.adminUnfilledAndChecklists,
                            onChanged: (v) => _service.updatePreferences(
                              p.copyWith(adminUnfilledAndChecklists: v),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],

                // 6) Verlauf der letzten Benachrichtigungen
                if (history.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      const Expanded(
                        child: _SectionLabel('LETZTE BENACHRICHTIGUNGEN'),
                      ),
                      TextButton(
                        onPressed: _service.clearHistory,
                        child: const Text('Leeren'),
                      ),
                    ],
                  ),
                  SoftCard(
                    child: Column(
                      children: [
                        for (var i = 0; i < history.length; i++) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 11,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const TintedIconBadge(
                                  icon: Icons.notifications_outlined,
                                  iconColor: AppTheme.primaryColor,
                                  backgroundColor: AppTheme.primaryTint,
                                  size: 34,
                                  iconSize: 17,
                                  radius: 10,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              history[i].title,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 13.5,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            _fmtTime(history[i].createdAt),
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: cs.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        history[i].body,
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (i != history.length - 1)
                            Divider(
                              height: 1,
                              indent: 60,
                              color: cs.outlineVariant,
                            ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

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

class _SwitchRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            TintedIconBadge(
              icon: icon,
              iconColor: iconColor,
              backgroundColor: iconBg,
              size: 38,
              iconSize: 19,
              radius: 11,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch.adaptive(
              value: value,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
