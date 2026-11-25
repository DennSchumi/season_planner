import 'dart:async';
import 'package:appwrite/appwrite.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/core/features/authentification/login/login_view.dart';
import 'package:season_planner/core/services/auth_service.dart';
import 'package:season_planner/core/services/notification_service.dart';
import 'package:season_planner/core/services/realtime_service.dart';
import 'package:season_planner/core/theme.dart';
import 'package:season_planner/core/widgets/desktop_shell.dart';
import 'package:season_planner/core/widgets/ux_components.dart';
import '../../services/database_service.dart';
import '../../services/user_badge_state_service.dart';
import '../../user_provider.dart';
import '../account/account_view.dart';
import '../calender/calender_view.dart';
import '../home/home_view.dart';
import '../news/user_news_todos_view.dart';

class MainUserScaffoldView extends StatefulWidget {
  final int? selected_index;

  const MainUserScaffoldView({super.key, this.selected_index});

  @override
  _MainUserScaffoldState createState() => _MainUserScaffoldState();
}

class _MainUserScaffoldState extends State<MainUserScaffoldView> {
  int _selectedIndex = 0;
  bool _isNavCompact = false;
  Timer? _refreshTimer;
  RealtimeSubscription? _realtimeSub;
  DateTime? _lastUpdated;
  bool _isLoading = false;
  bool _hasConnection = true;
  final Set<RealtimeChangeDomain> _queuedRealtimeDomains = {};

  List<Widget> get widgetList => <Widget>[
    HomeView(
      isLoading: _isLoading,
      hasConnection: _hasConnection,
      lastUpdated: _lastUpdated,
    ),
    CalenderView(
      isLoading: _isLoading,
      hasConnection: _hasConnection,
      lastUpdated: _lastUpdated,
    ),
    UserNewsTodosView(
      isLoading: _isLoading,
      hasConnection: _hasConnection,
      lastUpdated: _lastUpdated,
    ),
    const AccountView(),
  ];

  @override
  void initState() {
    super.initState();
    final savedIdx = context.read<UserProvider>().selectedTabIndex;
    _selectedIndex = (widget.selected_index ?? savedIdx).clamp(0, 3);
    UserBadgeStateService().setViewingImportantTab(_selectedIndex == 2);
    _restoreCachedUserAndLoad();

    // Appwrite Realtime mit 2,5 s Entprellung + selektivem Nachladen je Fachbereich
    _realtimeSub = RealtimeService().subscribeToSeasonPlanner(
      onDomainsChanged: (domains) {
        if (!mounted) return;
        _handleRealtimeDomains(domains);
      },
      relevantFlightSchoolIds: () {
        final schools =
            context.read<UserProvider>().user?.flightSchools ?? const [];
        return schools.map((s) => s.id).where((id) => id.isNotEmpty).toSet();
      },
    );

    _refreshTimer = Timer.periodic(
      Duration(minutes: _realtimeSub != null ? 3 : 1),
      (_) {
        if (mounted) _loadUser();
      },
    );
  }

  Future<void> _restoreCachedUserAndLoad() async {
    final provider = Provider.of<UserProvider>(context, listen: false);
    if (provider.user == null) {
      final cached = await AuthService().loadCachedUser();
      if (cached != null && mounted && provider.user == null) {
        provider.setUser(cached);
      }
    }
    if (mounted) {
      await _loadUser();
    }
  }

  Future<void> _handleRealtimeDomains(Set<RealtimeChangeDomain> domains) async {
    if (!mounted || domains.isEmpty) return;
    if (_isLoading) {
      _queuedRealtimeDomains.addAll(domains);
      return;
    }

    final userProvider = context.read<UserProvider>();
    final current = userProvider.user;
    final needsFullReload =
        current == null ||
        domains.contains(RealtimeChangeDomain.full) ||
        domains.contains(RealtimeChangeDomain.metadata) ||
        domains.contains(RealtimeChangeDomain.members) ||
        domains.contains(RealtimeChangeDomain.planning);

    if (needsFullReload) {
      await _loadUser();
      return;
    }

    // Selektives Teil-Update (nur geänderte Bereiche statt komplettem _loadUser)
    final reloadEvents = domains.contains(RealtimeChangeDomain.events);
    final reloadTandem = domains.contains(RealtimeChangeDomain.tandem);
    final refreshBadgesOnly = !reloadEvents && !reloadTandem;

    if (refreshBadgesOnly) {
      unawaited(UserBadgeStateService().refreshFromUser(current));
      if (mounted) {
        setState(() {
          _lastUpdated = DateTime.now();
          _hasConnection = true;
        });
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      final includeArchive = userProvider.includeArchive;
      final db = DatabaseService();
      var updated = current;

      final eventsFuture = reloadEvents
          ? db.refreshUserEventsOnly(current, includeArchive: includeArchive)
          : Future.value(current);
      final tandemFuture = reloadTandem
          ? db.refreshUserTandemOnly(current, includeArchive: includeArchive)
          : Future.value(current);

      final results = await Future.wait([eventsFuture, tandemFuture]);
      if (!mounted) return;

      if (reloadEvents) {
        updated = updated.copyWith(
          events: results[0].events,
          hasLoadedArchive: results[0].hasLoadedArchive,
        );
      }
      if (reloadTandem) {
        updated = updated.copyWith(
          tandemDuties: results[1].tandemDuties,
          tandemDemands: results[1].tandemDemands,
          tandemPilotNamesById: results[1].tandemPilotNamesById,
          hasLoadedArchive: results[1].hasLoadedArchive,
        );
      }

      userProvider.applyPartialUpdate(updated);
      unawaited(AuthService().saveCachedUser(updated));
      unawaited(
        NotificationService().evaluateUserSnapshot(
          user: updated,
          context: context,
        ),
      );
      unawaited(UserBadgeStateService().refreshFromUser(updated));

      if (mounted) {
        setState(() {
          _lastUpdated = DateTime.now();
          _hasConnection = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _hasConnection = false);
    } finally {
      if (mounted) setState(() => _isLoading = false);
      _flushQueuedRealtimeDomains();
    }
  }

  void _flushQueuedRealtimeDomains() {
    if (!mounted || _isLoading || _queuedRealtimeDomains.isEmpty) return;
    final next = Set<RealtimeChangeDomain>.from(_queuedRealtimeDomains);
    _queuedRealtimeDomains.clear();
    unawaited(_handleRealtimeDomains(next));
  }

  Future<void> _loadUser({bool? includeArchive}) async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final provider = Provider.of<UserProvider>(context, listen: false);
      final effArchive = includeArchive ?? provider.includeArchive;
      final user = await DatabaseService().getUserInformation(
        includeArchive: effArchive,
      );
      if (!mounted) return;
      if (user != null) {
        provider.setUser(user);
        unawaited(AuthService().saveCachedUser(user));
        unawaited(
          NotificationService().evaluateUserSnapshot(
            user: user,
            context: context,
          ),
        );
        unawaited(UserBadgeStateService().refreshFromUser(user));
        setState(() {
          _lastUpdated = DateTime.now();
          _hasConnection = true;
        });
      } else {
        setState(() => _hasConnection = false);
        // Nur abmelden, wenn Appwrite die Session tatsächlich mit 401 abgelehnt hat
        final revoked = await AuthService().isSessionRevoked();
        if (revoked && mounted) {
          await AuthService().clearLocalSessionData();
          if (!mounted) return;
          Provider.of<UserProvider>(context, listen: false).clearUser();
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginView()),
            (_) => false,
          );
        }
      }
    } catch (_) {
      if (mounted) setState(() => _hasConnection = false);
    } finally {
      if (mounted) setState(() => _isLoading = false);
      _flushQueuedRealtimeDomains();
    }
  }

  @override
  void dispose() {
    UserBadgeStateService().setViewingImportantTab(false);
    _refreshTimer?.cancel();
    _realtimeSub?.close();
    super.dispose();
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    final pixels = notification.metrics.pixels;
    final maxExtent = notification.metrics.maxScrollExtent;
    if (!_isNavCompact && pixels > 48 && maxExtent > 60) {
      setState(() => _isNavCompact = true);
    } else if (_isNavCompact && pixels <= 28) {
      setState(() => _isNavCompact = false);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<UserProvider>(context).user;

    final safeIndex = _selectedIndex.clamp(0, widgetList.length - 1);
    final isDesktop = context.isDesktop;

    void selectTab(int index) {
      context.read<UserProvider>().setSelectedTabIndex(index);
      setState(() {
        _selectedIndex = index;
        _isNavCompact = false;
      });
      UserBadgeStateService().setViewingImportantTab(index == 2);
    }

    List<ModernNavItem> buildNavItems(UserBadgeStateService badge) {
      final startReqCount = badge.unseenDirectRequestCount;
      final startHasBlueDot =
          startReqCount == 0 && badge.hasUnseenOpenOpportunities;
      final importantCount = badge.unseenImportantCount;
      return [
        ModernNavItem(
          icon: Icons.home_outlined,
          label: 'Start',
          badgeCount: startReqCount,
          showBadgeDot: startHasBlueDot,
          badgeColor: startReqCount > 0
              ? AppTheme.dangerColor
              : AppTheme.infoColor,
        ),
        const ModernNavItem(
          icon: Icons.calendar_today_outlined,
          label: 'Kalender',
        ),
        ModernNavItem(
          icon: Icons.notifications_outlined,
          label: 'Wichtiges',
          badgeCount: importantCount,
          badgeColor: AppTheme.dangerColor,
        ),
        const ModernNavItem(icon: Icons.person_outline_rounded, label: 'Konto'),
      ];
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      transitionBuilder: softCrossfadeTransition,
      child: user == null
          ? const ParagliderLoadingView(
              key: ValueKey('user_scaffold_loading'),
              message: 'Deine Einsätze werden geladen…',
            )
          : isDesktop
          ? ListenableBuilder(
              key: const ValueKey('user_scaffold_desktop'),
              listenable: UserBadgeStateService(),
              builder: (context, _) {
                return DesktopAppShell(
                  selectedIndex: safeIndex,
                  onSelected: selectTab,
                  items: buildNavItems(UserBadgeStateService()),
                  isAdminMode: false,
                  isLoading: _isLoading,
                  hasConnection: _hasConnection,
                  lastUpdated: _lastUpdated,
                  onTapUserProfile: () => selectTab(3),
                  child: widgetList[safeIndex],
                );
              },
            )
          : Scaffold(
              key: const ValueKey('user_scaffold_ready'),
              extendBody: true,
              body: FloatingNavScope(
                isCompact: _isNavCompact,
                child: NotificationListener<ScrollNotification>(
                  onNotification: _handleScrollNotification,
                  child: widgetList[safeIndex],
                ),
              ),
              bottomNavigationBar: ListenableBuilder(
                listenable: UserBadgeStateService(),
                builder: (context, _) {
                  return ModernBottomNavBar(
                    selectedIndex: safeIndex,
                    isCompact: _isNavCompact,
                    onSelected: selectTab,
                    items: buildNavItems(UserBadgeStateService()),
                  );
                },
              ),
            ),
    );
  }
}
