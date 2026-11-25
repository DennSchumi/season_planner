import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:inventar_manager/core/services/auth_service.dart';
import 'package:inventar_manager/core/services/database_service.dart';
import 'package:inventar_manager/core/services/web_url_helper.dart';
import 'package:inventar_manager/core/theme.dart';
import 'package:inventar_manager/features/auth/login_view.dart';
import 'package:inventar_manager/features/auth/reset_password_view.dart';
import 'package:inventar_manager/features/dashboard/main_scaffold.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  AuthService().init();
  DatabaseService().init();

  runApp(const InventarManagerApp());
}

class InventarManagerApp extends StatefulWidget {
  const InventarManagerApp({super.key});

  @override
  State<InventarManagerApp> createState() => _InventarManagerAppState();
}

class _InventarManagerAppState extends State<InventarManagerApp> {
  late final Future<bool> _sessionCheckFuture;
  PasswordRecoveryParams? _recoveryParams;

  @override
  void initState() {
    super.initState();
    _recoveryParams = extractPasswordRecoveryParams();
    _sessionCheckFuture = _recoveryParams != null
        ? Future.value(false)
        : AuthService().isLoggedIn();
  }

  @override
  Widget build(BuildContext context) {
    final recovery = _recoveryParams;

    return MaterialApp(
      title: 'Inventar Manager',
      debugShowCheckedModeBanner: false,
      locale: const Locale('de', 'DE'),
      supportedLocales: const [
        Locale('de', 'DE'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      onGenerateRoute: (settings) {
        final name = settings.name ?? '';
        if (name.startsWith('/reset-password')) {
          final routeUri = Uri.tryParse(name);
          final params =
              extractPasswordRecoveryParams(routeUri) ??
              extractPasswordRecoveryParams();
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => ResetPasswordView(
              userId: params?.userId ?? '',
              secret: params?.secret ?? '',
            ),
          );
        }
        return null;
      },
      home: recovery != null
          ? ResetPasswordView(
              userId: recovery.userId,
              secret: recovery.secret,
            )
          : FutureBuilder<bool>(
              future: _sessionCheckFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }

                final loggedIn = snapshot.data ?? false;
                return loggedIn ? const MainScaffold() : const LoginView();
              },
            ),
    );
  }
}
