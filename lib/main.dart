import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/core/features/authentification/reset_password/reset_password_view.dart';
import 'package:season_planner/core/services/auth_service.dart';
import 'package:season_planner/core/services/notification_service.dart';
import 'package:season_planner/core/services/web_url_helper.dart';
import 'package:season_planner/core/theme.dart';
import 'package:season_planner/core/widgets/ux_components.dart';
import 'package:season_planner/fsAdmin/flight_school_provider.dart';
import 'package:season_planner/fsAdmin/services/flight_school_service.dart';
import 'package:season_planner/user/services/database_service.dart';
import 'package:season_planner/user/user_provider.dart';
import 'core/app_router.dart';
import 'core/features/authentification/login/login_view.dart';
import 'user/features/main_scaffold/main_user_scaffold_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AuthService().init();
  DatabaseService().init();
  FlightSchoolService().init();
  NotificationService().init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => FlightSchoolProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
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
      routes: AppRouter().getRoutes(),
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
      title: 'Season Planner',
      debugShowCheckedModeBanner: false,
      locale: const Locale('de', 'DE'),
      supportedLocales: const [Locale('de', 'DE'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();
        final isDesktopLight =
            context.isDesktop &&
            Theme.of(context).brightness == Brightness.light;
        if (!isDesktopLight) return child;
        return Theme(data: AppTheme.desktopLightTheme, child: child);
      },
      home: recovery != null
          ? ResetPasswordView(userId: recovery.userId, secret: recovery.secret)
          : FutureBuilder<bool>(
              future: _sessionCheckFuture,
              builder: (context, snapshot) {
                final Widget child;
                if (snapshot.connectionState == ConnectionState.waiting) {
                  child = const ParagliderLoadingView(
                    key: ValueKey('app_startup_loading'),
                    message: 'Season Planner',
                  );
                } else {
                  final loggedIn = snapshot.data ?? false;
                  child = loggedIn
                      ? const MainUserScaffoldView(
                          key: ValueKey('app_main_user'),
                        )
                      : const LoginView(key: ValueKey('app_login'));
                }

                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 420),
                  transitionBuilder: softCrossfadeTransition,
                  child: child,
                );
              },
            ),
    );
  }
}
