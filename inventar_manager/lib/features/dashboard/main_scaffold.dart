import 'package:flutter/material.dart';
import 'package:inventar_manager/core/services/auth_service.dart';
import 'package:inventar_manager/core/services/category_service.dart';
import 'package:inventar_manager/core/services/flight_school_service.dart';
import 'package:inventar_manager/core/services/item_service.dart';
import 'package:inventar_manager/core/theme.dart';
import 'package:inventar_manager/core/widgets/ui_primitives.dart';
import 'package:inventar_manager/features/auth/login_view.dart';
import 'package:inventar_manager/features/dashboard/dashboard_view.dart';
import 'package:inventar_manager/features/inventory/inventory_list_view.dart';
import 'package:inventar_manager/features/settings/settings_view.dart';

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _currentIndex = 0;
  final FlightSchoolService _flightSchoolService = FlightSchoolService();

  @override
  void initState() {
    super.initState();
    _flightSchoolService.loadSchools().then((_) {
      if (_flightSchoolService.selectedSchool != null) {
        CategoryService().loadCategories(
          _flightSchoolService.selectedSchool!.id,
        );
        ItemService().loadItems(_flightSchoolService.selectedSchool!.id);
      }
    });

    _flightSchoolService.addListener(_onSchoolChanged);
  }

  void _onSchoolChanged() {
    if (_flightSchoolService.selectedSchool != null) {
      CategoryService().loadCategories(_flightSchoolService.selectedSchool!.id);
      ItemService().loadItems(_flightSchoolService.selectedSchool!.id);
    }
  }

  @override
  void dispose() {
    _flightSchoolService.removeListener(_onSchoolChanged);
    super.dispose();
  }

  List<Widget> _getPages(String schoolId) {
    return [
      DashboardView(key: ValueKey('dash_$schoolId')),
      InventoryListView(key: ValueKey('inv_$schoolId')),
      SettingsView(key: ValueKey('set_$schoolId')),
    ];
  }

  Future<void> _logout() async {
    await AuthService().logout();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        fadePageRoute(const LoginView()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: _flightSchoolService,
      builder: (context, child) {
        if (_flightSchoolService.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final currentSchool = _flightSchoolService.selectedSchool;
        if (currentSchool == null) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Inventar Manager'),
              actions: [
                IconButton(
                  icon: Icon(Icons.logout_rounded, color: cs.onSurfaceVariant),
                  onPressed: _logout,
                  tooltip: 'Abmelden',
                ),
              ],
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: SoftCard(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const TintedIconBadge(
                          icon: Icons.school_outlined,
                          iconColor: AppTheme.dangerColor,
                          backgroundColor: AppTheme.dangerBg,
                          size: 48,
                          iconSize: 24,
                          radius: 14,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          _flightSchoolService.errorMessage ??
                              'Keine Flugschulen gefunden.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 14.5,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _flightSchoolService.loadSchools,
                              icon: const Icon(Icons.refresh_rounded, size: 18),
                              label: const Text('Neu laden'),
                            ),
                            const SizedBox(width: 10),
                            FilledButton.icon(
                              onPressed: _logout,
                              icon: const Icon(Icons.logout_rounded, size: 18),
                              label: const Text('Abmelden'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        final pages = _getPages(currentSchool.id);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Inventar Manager'),
            actions: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: currentSchool.id,
                      icon: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: cs.onSurfaceVariant,
                      ),
                      dropdownColor: cs.surface,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                      ),
                      items: _flightSchoolService.schools.map((school) {
                        return DropdownMenuItem(
                          value: school.id,
                          child: Text(school.name),
                        );
                      }).toList(),
                      onChanged: (newId) {
                        if (newId != null) {
                          _flightSchoolService.selectSchool(newId);
                        }
                      },
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.logout_rounded, color: cs.onSurfaceVariant),
                onPressed: _logout,
                tooltip: 'Abmelden',
              ),
              const SizedBox(width: 6),
            ],
          ),
          body: pages[_currentIndex],
          bottomNavigationBar: Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: cs.outlineVariant, width: 1),
              ),
            ),
            child: NavigationBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: (index) =>
                  setState(() => _currentIndex = index),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard_rounded),
                  label: 'Dashboard',
                ),
                NavigationDestination(
                  icon: Icon(Icons.inventory_2_outlined),
                  selectedIcon: Icon(Icons.inventory_2_rounded),
                  label: 'Inventar',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings_rounded),
                  label: 'Einstellungen',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
