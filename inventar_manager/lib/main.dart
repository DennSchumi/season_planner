import 'package:flutter/material.dart';
import 'package:inventar_manager/core/services/auth_service.dart';
import 'package:inventar_manager/core/services/database_service.dart';
import 'package:inventar_manager/features/auth/login_view.dart';
import 'package:inventar_manager/features/dashboard/main_scaffold.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize services
  AuthService().init();
  DatabaseService().init();
  
  runApp(const InventarManagerApp());
}

class InventarManagerApp extends StatelessWidget {
  const InventarManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Inventarmanager',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3B82F6)),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          iconTheme: IconThemeData(color: Color(0xFF0F172A)),
        ),
      ),
      home: FutureBuilder<bool>(
        future: AuthService().isLoggedIn(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          
          bool loggedIn = snapshot.data ?? false;
          return loggedIn ? const MainScaffold() : const LoginView();
        },
      ),
    );
  }
}
