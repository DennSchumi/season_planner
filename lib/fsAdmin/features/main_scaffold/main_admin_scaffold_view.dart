import 'dart:async';
import 'package:appwrite/appwrite.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/core/data/enums/event_status_enum.dart';
import 'package:season_planner/core/data/enums/event_user_status_enum.dart';
import 'package:season_planner/core/data/models/tandem_model.dart';
import 'package:season_planner/core/services/notification_service.dart';
import 'package:season_planner/core/services/realtime_service.dart';
import 'package:season_planner/core/widgets/desktop_shell.dart';
import 'package:season_planner/core/widgets/ux_components.dart';
import 'package:season_planner/fsAdmin/data/models/flight_school_model_flight_school_view.dart';
import 'package:season_planner/fsAdmin/features/calender_view/calender_view.dart';
import 'package:season_planner/fsAdmin/features/home/admin_home_view.dart';
import 'package:season_planner/fsAdmin/features/manage_events_view/manage_events_view.dart';
import 'package:season_planner/fsAdmin/features/manage_flight_school_view/manage_flight_school_view.dart';
import 'package:season_planner/fsAdmin/features/manage_personal/manage_personal_view.dart';
import 'package:season_planner/fsAdmin/features/widgets/subscription_locked_view.dart';
import 'package:season_planner/fsAdmin/flight_school_provider.dart';
import 'package:season_planner/fsAdmin/services/flight_school_service.dart';
import '../../../user/services/database_service.dart';
import '../../../user/user_provider.dart';

class MainAdminScaffoldView extends StatefulWidget {
  final int? selected_index;

  const MainAdminScaffoldView({super.key, this.selected_index});

  @override
  _MainAdminScaffoldState createState() => _MainAdminScaffoldState();
}

class _MainAdminScaffoldState extends State<MainAdminScaffoldView> {
  int _selectedIndex = 0;
  bool _isNavCompact = false;
  int _extraAsyncTodoCount = 0;
  Timer? _refreshTimer;
  RealtimeSubscription? _realtimeSub;
  bool isLoading = false;
  bool hasConnection = true;
  DateTime? lastUpdated;
  final Set<RealtimeChangeDomain> _queuedRealtimeDomains = {};

  void _selectTab(int index) {
    final clamped = index.clamp(0, 4);
    context.read<FlightSchoolProvider>().setSelectedTabIndex(clamped);
    setState(() {
      _selectedIndex = clamped;
      _isNavCompact = false;
    });
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

  List<Widget> get _widgetList => [
    SubscriptionGate(
      title: 'Startseite',
      featureName: 'Admin-Übersicht',
      child: AdminHomeView(
        isLoading: isLoading,
        hasConnection: hasConnection,
        lastUpdated: lastUpdated,
        onSelectTab: _selectTab,
        onExtraTodoCountChanged: (count) {
          if (mounted && _extraAsyncTodoCount != count) {
            setState(() => _extraAsyncTodoCount = count);
          }
        },
      ),
    ),
    SubscriptionGate(
      title: 'Events verwalten',
      featureName: 'Event-Verwaltung',
      child: ManageEventsView(
        isLoading: isLoading,
        hasConnection: hasConnection,
        lastUpdated: lastUpdated,
      ),
    ),
    SubscriptionGate(
      title: 'Personal verwalten',
      featureName: 'Personalverwaltung',
      child: ManagePersonalView(
        isLoading: isLoading,
        hasConnection: hasConnection,
        lastUpdated: lastUpdated,
      ),
    ),
    SubscriptionGate(
      title: 'Kalender',
      featureName: 'Flugschul-Kalender',
      child: CalenderViewFlightSchool(
        isLoading: isLoading,
        hasConnection: hasConnection,
        lastUpdated: lastUpdated,
      ),
    ),
    const ManageFlightSchoolView(),
  ];

  int _countSyncTodos(FlightSchoolModelFlightSchoolView? fs) {
    if (fs == null) return 0;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final soonHorizon = now.add(const Duration(days: 14));
    int count = fs.pendingRequests.length + fs.openQualificationRequestCount;

    if (fs.tandemEnabled) {
      count += fs.tandemDuties
          .where(
            (d) =>
                (d.status == TandemDutyStatus.requestedByPilot ||
                    d.status == TandemDutyStatus.cancellationRequested) &&
                !d.endDay.isBefore(today),
          )
          .length;
    }

    for (final ev in fs.events) {
      if (ev.status == EventStatusEnum.canceled || ev.endTime.isBefore(now)) {
        continue;
      }
      bool hasOpenSlot = false;
      for (final tm in ev.team) {
        if (tm.hasOpenSwapRequest) count++;
        if (tm.isSlot || tm.statusEnum == EventUserStatusEnum.open) {
          hasOpenSlot = true;
        } else {
          final st = tm.statusEnum;
          if (st == EventUserStatusEnum.pending_flight_school ||
              st == EventUserStatusEnum.user_requests_change ||
              st == EventUserStatusEnum.denied_user) {
            count++;
          }
        }
      }
      if (hasOpenSlot && !ev.startTime.isAfter(soonHorizon)) {
        count++;
      }
    }
    return count;
  }

  @override
  void initState() {
    super.initState();
    final savedIdx = context.read<FlightSchoolProvider>().selectedTabIndex;
    _selectedIndex = (widget.selected_index ?? savedIdx).clamp(0, 4);
    _refreshData();

    _realtimeSub = RealtimeService().subscribeToSeasonPlanner(
      onDomainsChanged: (domains) {
        if (!mounted) return;
        _handleRealtimeDomains(domains);
      },
      relevantFlightSchoolIds: () {
        final id = context.read<FlightSchoolProvider>().flightSchool?.id ?? '';
        return id.isEmpty ? const {} : {id};
      },
    );

    // Bei aktiver Realtime-Verbindung reicht ein 3-Minuten-Fallback-Polling
    _refreshTimer = Timer.periodic(
      Duration(minutes: _realtimeSub != null ? 3 : 1),
      (_) {
        if (mounted) _refreshData();
      },
    );
  }

  Future<void> _handleRealtimeDomains(Set<RealtimeChangeDomain> domains) async {
    if (!mounted || domains.isEmpty) return;
    if (isLoading) {
      _queuedRealtimeDomains.addAll(domains);
      return;
    }

    final fsProvider = context.read<FlightSchoolProvider>();
    final current = fsProvider.flightSchool;
    final needsFullReload =
        current == null ||
        domains.contains(RealtimeChangeDomain.full) ||
        domains.contains(RealtimeChangeDomain.metadata);

    if (needsFullReload) {
      await _refreshData();
      return;
    }

    final reloadEvents = domains.contains(RealtimeChangeDomain.events);
    final reloadTandem = domains.contains(RealtimeChangeDomain.tandem);
    final reloadMembers = domains.contains(RealtimeChangeDomain.members);
    final reloadPlanning = domains.contains(RealtimeChangeDomain.planning);

    // Nur Dokumente/Stundenzettel geändert -> reicht Zeitstempel-Bump für Async-To-Do-Refresh
    if (!reloadEvents && !reloadTandem && !reloadMembers && !reloadPlanning) {
      if (mounted) {
        setState(() {
          hasConnection = true;
          lastUpdated = DateTime.now();
        });
      }
      return;
    }

    setState(() => isLoading = true);
    try {
      final svc = FlightSchoolService();
      final includeArchive = fsProvider.includeArchive;
      var updated = current;

      // Mitglieder zuerst aktualisieren, falls gleichzeitig Events neu geladen werden (für Avatare)
      if (reloadMembers) {
        final withMembers = await svc.refreshMembersOnly(updated);
        if (withMembers != null) updated = withMembers;
      }
      if (reloadPlanning) {
        final withPlanning = await svc.refreshPlanningOnly(updated);
        if (withPlanning != null) updated = withPlanning;
      }

      final eventsFuture = reloadEvents
          ? svc.refreshEventsOnly(updated, includeArchive: includeArchive)
          : Future<FlightSchoolModelFlightSchoolView?>.value(null);
      final tandemFuture = reloadTandem
          ? svc.refreshTandemOnly(updated, includeArchive: includeArchive)
          : Future<FlightSchoolModelFlightSchoolView?>.value(null);

      final results = await Future.wait([eventsFuture, tandemFuture]);
      if (!mounted) return;

      if (results[0] != null) {
        updated = updated.copyWith(
          events: results[0]!.events,
          hasLoadedArchive: results[0]!.hasLoadedArchive,
        );
      }
      if (results[1] != null) {
        updated = updated.copyWith(
          tandemDuties: results[1]!.tandemDuties,
          tandemDemands: results[1]!.tandemDemands,
          hasLoadedArchive: results[1]!.hasLoadedArchive,
        );
      }

      fsProvider.applyPartialUpdate(updated);
      unawaited(
        NotificationService().evaluateAdminSnapshot(
          fs: updated,
          context: context,
        ),
      );

      if (mounted) {
        setState(() {
          hasConnection = true;
          lastUpdated = DateTime.now();
        });
      }
    } catch (e) {
      debugPrint('Fehler beim selektiven Admin-Reload: $e');
      if (mounted) setState(() => hasConnection = false);
    } finally {
      if (mounted) setState(() => isLoading = false);
      _flushQueuedRealtimeDomains();
    }
  }

  void _flushQueuedRealtimeDomains() {
    if (!mounted || isLoading || _queuedRealtimeDomains.isEmpty) return;
    final next = Set<RealtimeChangeDomain>.from(_queuedRealtimeDomains);
    _queuedRealtimeDomains.clear();
    unawaited(_handleRealtimeDomains(next));
  }

  Future<void> _refreshData() async {
    if (!mounted) return;
    setState(() => isLoading = true);

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final fsProvider = Provider.of<FlightSchoolProvider>(
        context,
        listen: false,
      );

      final user = await DatabaseService().getUserInformation(
        includeArchive: userProvider.includeArchive,
      );
      if (!mounted) return;
      if (user != null) {
        userProvider.setUser(user);
      }

      if (fsProvider.flightSchool != null) {
        final effArchive = fsProvider.includeArchive;
        await fsProvider.reloadFlightSchool(
          (id) => FlightSchoolService().getFlightSchool(
            id,
            includeArchive: effArchive,
          ),
        );
        final updatedFs = fsProvider.flightSchool;
        if (updatedFs != null && mounted) {
          unawaited(
            NotificationService().evaluateAdminSnapshot(
              fs: updatedFs,
              context: context,
            ),
          );
        }
      }

      if (mounted) {
        setState(() {
          hasConnection = true;
          lastUpdated = DateTime.now();
        });
      }
    } catch (e) {
      debugPrint('Fehler beim Laden im Admin-Modus: $e');
      if (mounted) setState(() => hasConnection = false);
    } finally {
      if (mounted) setState(() => isLoading = false);
      _flushQueuedRealtimeDomains();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _realtimeSub?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context).user;
    final fs = Provider.of<FlightSchoolProvider>(context).flightSchool;
    final totalTodoCount = _countSyncTodos(fs) + _extraAsyncTodoCount;
    final safeIndex = _selectedIndex.clamp(0, _widgetList.length - 1);
    final isDesktop = context.isDesktop;

    final navItems = [
      ModernNavItem(
        icon: Icons.home_outlined,
        label: 'Übersicht',
        badgeCount: totalTodoCount,
      ),
      const ModernNavItem(icon: Icons.event_note_outlined, label: 'Events'),
      const ModernNavItem(
        icon: Icons.people_outline_rounded,
        label: 'Personal',
      ),
      const ModernNavItem(
        icon: Icons.calendar_today_outlined,
        label: 'Kalender',
      ),
      const ModernNavItem(icon: Icons.school_outlined, label: 'Flugschule'),
    ];

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      transitionBuilder: softCrossfadeTransition,
      child: userProvider == null
          ? const ParagliderLoadingView(
              key: ValueKey('admin_scaffold_loading'),
              message: 'Admin-Bereich wird geladen…',
            )
          : isDesktop
          ? DesktopAppShell(
              key: const ValueKey('admin_scaffold_desktop'),
              selectedIndex: safeIndex,
              onSelected: _selectTab,
              items: navItems,
              isAdminMode: true,
              isLoading: isLoading,
              hasConnection: hasConnection,
              lastUpdated: lastUpdated,
              onTapUserProfile: () => _selectTab(4),
              child: _widgetList[safeIndex],
            )
          : Scaffold(
              key: const ValueKey('admin_scaffold_ready'),
              extendBody: true,
              body: FloatingNavScope(
                isCompact: _isNavCompact,
                child: NotificationListener<ScrollNotification>(
                  onNotification: _handleScrollNotification,
                  child: _widgetList[safeIndex],
                ),
              ),
              bottomNavigationBar: ModernBottomNavBar(
                selectedIndex: safeIndex,
                isCompact: _isNavCompact,
                onSelected: _selectTab,
                items: navItems,
              ),
            ),
    );
  }
}
