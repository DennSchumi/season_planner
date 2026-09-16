import 'package:flutter/material.dart';
import 'package:inventar_manager/core/services/auth_service.dart';
import 'package:inventar_manager/features/auth/login_view.dart';
import 'package:inventar_manager/features/dashboard/dashboard_view.dart';
import 'package:inventar_manager/features/inventory/inventory_list_view.dart';
import 'package:inventar_manager/features/settings/settings_view.dart';
import 'package:inventar_manager/core/services/flight_school_service.dart';
import 'package:inventar_manager/core/services/category_service.dart';
import 'package:inventar_manager/core/services/item_service.dart';

class MainScaffold extends StatefulWidget {
  const MainScaffold({Key? key}) : super(key: key);

  @override
  _MainScaffoldState createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _currentIndex = 0;
  final FlightSchoolService _flightSchoolService = FlightSchoolService();

  @override
  void initState() {
    super.initState();
    // Initialize DatabaseService and load schools
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

  void _logout() async {
    await AuthService().logout();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginView()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _flightSchoolService,
      builder: (context, child) {
        if (_flightSchoolService.isLoading) {
          return const Scaffold(
            backgroundColor: Color(0xFFF8FAFC),
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final currentSchool = _flightSchoolService.selectedSchool;
        if (currentSchool == null) {
          return const Scaffold(
            backgroundColor: Color(0xFFF8FAFC),
            body: Center(child: Text("Keine Flugschulen gefunden.")),
          );
        }

        final pages = _getPages(currentSchool.id);

        return Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          appBar: AppBar(
            title: const Text(
              "Inventarmanager",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            backgroundColor: Colors.white,
            elevation: 0,
            centerTitle: false,
            actions: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8.0),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: currentSchool.id,
                      icon: const Icon(
                        Icons.arrow_drop_down,
                        color: Color(0xFF64748B),
                      ),
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w500,
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
                icon: const Icon(Icons.logout, color: Color(0xFF64748B)),
                onPressed: _logout,
                tooltip: "Abmelden",
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1.0),
              child: Container(color: const Color(0xFFE2E8F0), height: 1.0),
            ),
          ),
          body: pages[_currentIndex],
          bottomNavigationBar: Container(
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: Color(0xFFE2E8F0), width: 1),
              ),
            ),
            child: BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: (index) => setState(() => _currentIndex = index),
              backgroundColor: Colors.white,
              selectedItemColor: const Color(0xFF3B82F6),
              unselectedItemColor: const Color(0xFF64748B),
              elevation: 0,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.dashboard_rounded),
                  label: "Dashboard",
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.inventory_2_rounded),
                  label: "Inventar",
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.settings_rounded),
                  label: "Einstellungen",
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
