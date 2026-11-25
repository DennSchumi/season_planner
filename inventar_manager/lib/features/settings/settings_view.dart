import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:inventar_manager/core/appwrite_config.dart';
import 'package:inventar_manager/core/services/auth_service.dart';
import 'package:inventar_manager/core/services/category_service.dart';
import 'package:inventar_manager/core/services/file_download_helper.dart';
import 'package:inventar_manager/core/services/flight_school_service.dart';
import 'package:inventar_manager/core/services/security_privacy_service.dart';
import 'package:inventar_manager/core/theme.dart';
import 'package:inventar_manager/core/widgets/legal_links.dart';
import 'package:inventar_manager/core/widgets/ui_primitives.dart';
import 'package:inventar_manager/features/auth/login_view.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final CategoryService _categoryService = CategoryService();
  bool _exportingData = false;

  final List<Map<String, String>> _availableIcons = [
    {'name': 'Support (Standard)', 'value': 'support'},
    {'name': 'Funkgerät', 'value': 'assets/icons/funkgeraet.svg'},
    {'name': 'Gleitschirm', 'value': 'assets/icons/gleitschirm.svg'},
    {'name': 'Schwimmweste', 'value': 'assets/icons/schwimmweste.svg'},
    {'name': 'Gurtzeug', 'value': 'assets/icons/gurtzeug.svg'},
  ];

  Future<void> _exportMyData() async {
    if (_exportingData) return;
    setState(() => _exportingData = true);
    try {
      final exportData = await SecurityPrivacyService().exportMyData();
      final prettyJson = const JsonEncoder.withIndent('  ').convert(exportData);
      final bytes = Uint8List.fromList(utf8.encode(prettyJson));
      final stamp = DateTime.now()
          .toIso8601String()
          .substring(0, 10)
          .replaceAll('-', '');
      final saved = await downloadBytesFile(
        bytes: bytes,
        filename: 'tragegurt_datenexport_$stamp.json',
        mimeType: 'application/json',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved
                ? 'Dein DSGVO-Datenexport (JSON) wurde heruntergeladen.'
                : 'Datenexport wurde abgebrochen.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Datenexport fehlgeschlagen: $e'),
          backgroundColor: AppTheme.dangerColor,
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
            return AlertDialog(
              title: const Text('Konto dauerhaft löschen?'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Diese Aktion kann nicht rückgängig gemacht werden. Folgende Daten werden dauerhaft gelöscht:',
                      style: TextStyle(fontSize: 13.5),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '• Dein Tragegurt-Benutzerkonto & Login (Season Planner & Inventar Manager)\n'
                      '• Persönliche Profildaten, Avatar & Qualifikationsdokumente\n'
                      '• Alle Flugschul-Mitgliedschaften & offenen Bewerbungen',
                      style: TextStyle(fontSize: 12.5, height: 1.4),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.warningBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Hinweis: Gesetzlich aufbewahrungspflichtige Stundenzettel bleiben anonymisiert für deine Flugschule erhalten. Bist du alleiniger Admin einer Flugschule, übertrage die Admin-Rolle bitte vorher.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.warningColor,
                          height: 1.35,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Gib zur Bestätigung deine E-Mail-Adresse ($userEmail) ein:',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: emailCtrl,
                      enabled: !deleting,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'E-Mail-Adresse bestätigen',
                      ),
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        errorText!,
                        style: const TextStyle(
                          color: AppTheme.dangerColor,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ],
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
                    foregroundColor: Colors.white,
                  ),
                  onPressed: deleting
                      ? null
                      : () async {
                          final typed = emailCtrl.text.trim().toLowerCase();
                          if (typed != userEmail.trim().toLowerCase()) {
                            setLocal(() {
                              errorText =
                                  'Die eingegebene E-Mail stimmt nicht überein.';
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
      await AuthService().logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        fadePageRoute(const LoginView()),
        (_) => false,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dein Konto wurde dauerhaft gelöscht.')),
      );
    }
  }

  Future<void> _logOut() async {
    await AuthService().logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      fadePageRoute(const LoginView()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final currentUser = AuthService().currentUser;

    return ListenableBuilder(
      listenable: _categoryService,
      builder: (context, child) {
        if (_categoryService.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final categories = _categoryService.categories;

        return Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 48),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Kategorieverwaltung',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Definiere hier die Präfixe und Service-Einstellungen für jede Kategorie.',
                                style: TextStyle(
                                  color: cs.onSurfaceVariant,
                                  fontSize: 13.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: _showAddCategoryModal,
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Neue Kategorie'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SoftCard(
                      child: categories.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(28),
                              child: Column(
                                children: [
                                  const TintedIconBadge(
                                    icon: Icons.category_outlined,
                                    size: 48,
                                    iconSize: 24,
                                    radius: 14,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Noch keine Kategorien angelegt',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Erstelle deine erste Kategorie, um Gegenstände zu verwalten.',
                                    style: TextStyle(
                                      color: cs.onSurfaceVariant,
                                      fontSize: 13,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: categories.length,
                              separatorBuilder: (context, index) => Divider(
                                height: 1,
                                indent: 76,
                                color: cs.outlineVariant,
                              ),
                              itemBuilder: (context, index) {
                                final category = categories[index];
                                final isDark = Theme.of(context).brightness ==
                                    Brightness.dark;
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 10,
                                  ),
                                  leading: Container(
                                    width: 44,
                                    height: 44,
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? AppTheme.primaryColor
                                              .withValues(alpha: 0.18)
                                          : AppTheme.primaryTint,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: category.buildIcon(
                                      color: isDark
                                          ? AppTheme.darkPrimary
                                          : AppTheme.primaryColor,
                                    ),
                                  ),
                                  title: Text(
                                    category.name,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15.5,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      children: [
                                        _buildInfoChip(
                                          context,
                                          Icons.tag_rounded,
                                          'Präfix: ${category.prefix}',
                                        ),
                                        _buildInfoChip(
                                          context,
                                          Icons.update_rounded,
                                          'Intervall: ${category.serviceIntervalMonths} Monate',
                                        ),
                                        _buildInfoChip(
                                          context,
                                          category.serviceRequiresDocument
                                              ? Icons.upload_file_rounded
                                              : Icons.edit_document,
                                          category.serviceRequiresDocument
                                              ? 'Dokument nötig'
                                              : 'Protokoll',
                                        ),
                                      ],
                                    ),
                                  ),
                                  trailing: IconButton(
                                    icon: Icon(
                                      Icons.edit_outlined,
                                      color: cs.onSurfaceVariant,
                                    ),
                                    tooltip: 'Bearbeiten',
                                    onPressed: () =>
                                        _showEditCategoryModal(category),
                                  ),
                                );
                              },
                            ),
                    ),

                    // === Klar abgesetzter Bereich: Rechtliches & Datenschutz ===
                    const SizedBox(height: 28),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Divider(
                        height: 1,
                        color: cs.outlineVariant.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                      child: Text(
                        'RECHTLICHES & DATENSCHUTZ',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.7,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                    SoftCard(
                      radius: 18,
                      child: Column(
                        children: [
                          _CompactSettingsRow(
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
                          _CompactSettingsRow(
                            icon: Icons.privacy_tip_outlined,
                            iconColor: cs.onSurfaceVariant,
                            title: 'Datenschutzerklärung',
                            onTap: () => openLegalUrl(
                              context,
                              AppwriteConfig.legalPrivacyUrl,
                            ),
                          ),
                          Divider(
                            height: 1,
                            indent: 44,
                            color: cs.outlineVariant.withValues(alpha: 0.7),
                          ),
                          _CompactSettingsRow(
                            icon: Icons.description_outlined,
                            iconColor: cs.onSurfaceVariant,
                            title: 'AGB / Nutzungsbedingungen',
                            onTap: () => openLegalUrl(
                              context,
                              AppwriteConfig.legalTermsUrl,
                            ),
                          ),
                          Divider(
                            height: 1,
                            indent: 44,
                            color: cs.outlineVariant.withValues(alpha: 0.7),
                          ),
                          _CompactSettingsRow(
                            icon: Icons.gavel_outlined,
                            iconColor: cs.onSurfaceVariant,
                            title: 'Impressum',
                            onTap: () => openLegalUrl(
                              context,
                              AppwriteConfig.legalImprintUrl,
                            ),
                          ),
                          if (currentUser != null &&
                              currentUser.email.trim().isNotEmpty) ...[
                            Divider(
                              height: 1,
                              indent: 44,
                              color: cs.outlineVariant.withValues(alpha: 0.7),
                            ),
                            _CompactSettingsRow(
                              icon: Icons.delete_forever_outlined,
                              iconColor: AppTheme.dangerColor,
                              titleColor: AppTheme.dangerColor,
                              title: 'Konto dauerhaft löschen',
                              onTap: () =>
                                  _confirmDeleteAccount(currentUser.email),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),
                    SoftCard(
                      radius: 18,
                      onTap: _logOut,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: const Center(
                        child: Text(
                          'Abmelden',
                          style: TextStyle(
                            color: AppTheme.dangerColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoChip(BuildContext context, IconData icon, String text) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCardElevated : AppTheme.backgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13.5, color: cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  void _showAddCategoryModal() {
    final nameController = TextEditingController();
    final prefixController = TextEditingController();
    final intervalController = TextEditingController(text: '12');
    bool requiresDoc = false;
    String selectedIcon = 'support';

    showDialog(
      context: context,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return StatefulBuilder(
          builder: (context, setStateModal) {
            return AlertDialog(
              title: const Text('Neue Kategorie anlegen'),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Name (z.B. Schwimmwesten)',
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: prefixController,
                      decoration: const InputDecoration(
                        labelText: 'Präfix (z.B. SW, GZ)',
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: intervalController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Service-Intervall (Monate)',
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: selectedIcon,
                      decoration: const InputDecoration(
                        labelText: 'Kategorie-Icon',
                      ),
                      items: _availableIcons.map((iconMap) {
                        return DropdownMenuItem<String>(
                          value: iconMap['value'],
                          child: Row(
                            children: [
                              CategoryModel.buildIconWidget(
                                iconMap['value']!,
                                color: cs.onSurfaceVariant,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(iconMap['name']!),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setStateModal(() => selectedIcon = val);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Service-Nachweis'),
                      subtitle: Text(
                        requiresDoc
                            ? 'Dokument muss hochgeladen werden'
                            : 'Nur Text-Protokoll',
                      ),
                      value: requiresDoc,
                      onChanged: (val) {
                        setStateModal(() {
                          requiresDoc = val;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Abbrechen'),
                ),
                FilledButton(
                  onPressed: () async {
                    final newName = nameController.text.trim();
                    final newPrefix = prefixController.text.trim();
                    final newInterval =
                        int.tryParse(intervalController.text.trim()) ?? 12;

                    if (newName.isNotEmpty && newPrefix.isNotEmpty) {
                      final schoolId = FlightSchoolService().selectedSchool?.id;
                      if (schoolId != null) {
                        final newCat = CategoryModel(
                          id: '',
                          schoolId: schoolId,
                          name: newName,
                          prefix: newPrefix,
                          serviceIntervalMonths: newInterval,
                          serviceRequiresDocument: requiresDoc,
                          iconData: selectedIcon,
                        );

                        await _categoryService.addCategory(newCat);

                        if (context.mounted) {
                          Navigator.pop(context);
                        }
                      }
                    }
                  },
                  child: const Text('Erstellen'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEditCategoryModal(CategoryModel category) {
    final prefixController = TextEditingController(text: category.prefix);
    final intervalController = TextEditingController(
      text: category.serviceIntervalMonths.toString(),
    );
    bool requiresDoc = category.serviceRequiresDocument;

    String selectedIcon =
        _availableIcons.any((element) => element['value'] == category.iconData)
            ? category.iconData
            : 'support';

    showDialog(
      context: context,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return StatefulBuilder(
          builder: (context, setStateModal) {
            return AlertDialog(
              title: Text('Kategorie bearbeiten: ${category.name}'),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: prefixController,
                      decoration: const InputDecoration(
                        labelText: 'Präfix (z.B. SW, GZ)',
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: intervalController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Service-Intervall (Monate)',
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: selectedIcon,
                      decoration: const InputDecoration(
                        labelText: 'Kategorie-Icon',
                      ),
                      items: _availableIcons.map((iconMap) {
                        return DropdownMenuItem<String>(
                          value: iconMap['value'],
                          child: Row(
                            children: [
                              CategoryModel.buildIconWidget(
                                iconMap['value']!,
                                color: cs.onSurfaceVariant,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(iconMap['name']!),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setStateModal(() => selectedIcon = val);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Service-Nachweis'),
                      subtitle: Text(
                        requiresDoc
                            ? 'Dokument muss hochgeladen werden'
                            : 'Nur Text-Protokoll',
                      ),
                      value: requiresDoc,
                      onChanged: (val) {
                        setStateModal(() {
                          requiresDoc = val;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Abbrechen'),
                ),
                FilledButton(
                  onPressed: () {
                    final newPrefix = prefixController.text.trim();
                    final newInterval =
                        int.tryParse(intervalController.text.trim()) ??
                            category.serviceIntervalMonths;

                    if (newPrefix.isNotEmpty) {
                      category.prefix = newPrefix;
                      category.serviceIntervalMonths = newInterval;
                      category.serviceRequiresDocument = requiresDoc;
                      category.iconData = selectedIcon;

                      _categoryService.updateCategory(category);

                      setState(() {});
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('Speichern'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _CompactSettingsRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color? titleColor;
  final String title;
  final VoidCallback onTap;

  const _CompactSettingsRow({
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
