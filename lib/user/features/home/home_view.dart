import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/core/data/enums/event_status_enum.dart';
import 'package:season_planner/core/data/enums/event_user_status_enum.dart';
import 'package:season_planner/core/data/enums/membership_status_enum.dart';
import 'package:season_planner/core/data/models/event_model.dart';
import 'package:season_planner/core/data/models/tandem_model.dart';
import 'package:season_planner/core/features/onboarding/onboarding_choice_view.dart';
import 'package:season_planner/core/services/tandem_service.dart';
import 'package:season_planner/core/theme.dart';
import 'package:season_planner/core/widgets/user_avatar.dart';
import 'package:season_planner/core/widgets/ux_components.dart';
import 'package:season_planner/user/features/home/widgets/flight_school_selector_widget.dart';
import 'package:season_planner/user/features/home/widgets/requests_open_opportunities_widget.dart';
import 'package:season_planner/user/features/home/widgets/your_events_widget.dart';
import 'package:season_planner/user/services/user_badge_state_service.dart';
import 'package:season_planner/user/user_provider.dart';

class HomeView extends StatefulWidget {
  final bool isLoading;
  final bool hasConnection;
  final DateTime? lastUpdated;

  const HomeView({
    super.key,
    required this.isLoading,
    required this.hasConnection,
    required this.lastUpdated,
  });

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  String _eventKey(Event e) =>
      (e.eventDocId != null && e.eventDocId!.isNotEmpty) ? e.eventDocId! : e.id;

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final user = userProvider.user;

    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (user.flightSchools.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text('Hallo ${user.name.isEmpty ? "Gast" : user.name}'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.flight_outlined,
                    size: 70,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "Du bist noch keiner Flugschule zugeordnet.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Tritt einer bestehenden Flugschule bei oder lege direkt deine eigene Flugschule an.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const JoinFlightSchoolView(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.group_add),
                    label: const Text("Bestehender Flugschule beitreten"),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CreateFlightSchoolView(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.add_business),
                    label: const Text("Neue Flugschule anlegen"),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final selectedFlightSchools = userProvider.selectedFlightSchoolIds;

    final List<Event> publicRequests = [];
    final List<Event> acceptedEvents = [];
    final List<Event> pendingOrRequestedEvents = [];
    final List<Event> userChangeRequests = [];
    final List<Event> stage1PreviewEvents = [];
    final List<Event> swapOfferEvents = [];

    final now = DateTime.now();
    final fsById = {for (final fs in user.flightSchools) fs.id: fs};

    for (final event in user.events) {
      if (event.endTime.isBefore(now) ||
          !selectedFlightSchools.contains(event.flightSchoolId)) {
        continue;
      }

      final stage =
          fsById[event.flightSchoolId]?.effectiveStageFor(event) ??
          event.planningStage;

      // Bindende eigene Zuweisungen (z. B. durch Admin) erscheinen IMMER unter
      // „Meine Events“ – unabhängig von der Planungsstufe (auch in Stufe 1!).
      if (event.isOwnBindingAssignment) {
        if (event.assignmentStatus ==
            EventUserStatusEnum.user_requests_change) {
          userChangeRequests.add(event);
        } else {
          acceptedEvents.add(event);
        }
        continue;
      }

      final fs = fsById[event.flightSchoolId];
      // Reine Tandempiloten und Mitglieder im erweiterten Team sehen auf der
      // Startseite keine offenen Stellen/Tauschplätze – nur direkte Admin-Anfragen.
      if (fs != null && (fs.isTandemOnly || fs.isExtendedTeam)) {
        if (!event.isSwapOfferFromOther &&
            (event.assignmentStatus == EventUserStatusEnum.pending_user ||
                event.assignmentStatus ==
                    EventUserStatusEnum.pending_flight_school)) {
          pendingOrRequestedEvents.add(event);
        }
        continue;
      }

      if (stage == 1 &&
          event.assignmentStatus != EventUserStatusEnum.pending_user) {
        stage1PreviewEvents.add(event);
        continue;
      }

      if (event.isSwapOfferFromOther) {
        if (stage == 3) {
          swapOfferEvents.add(event);
        }
        continue;
      }

      switch (event.assignmentStatus) {
        case EventUserStatusEnum.accepted_user:
        case EventUserStatusEnum.accepted_flight_school:
          acceptedEvents.add(event);
          break;
        case EventUserStatusEnum.user_requests_change:
          userChangeRequests.add(event);
          break;
        case EventUserStatusEnum.pending_flight_school:
        case EventUserStatusEnum.pending_user:
        case EventUserStatusEnum.denied_flight_school:
        case EventUserStatusEnum.denied_user:
          pendingOrRequestedEvents.add(event);
          break;
        case EventUserStatusEnum.open:
          publicRequests.add(event);
          break;
      }
    }

    // Sichtbare unbeantwortete Anfragen vs. offene Stellen (gleiche Konflikt- &
    // Rollenfilterung wie in RequestsOpportunitiesWidget) für den interaktiven Tab
    final scheduledEvents = user.events
        .where(
          (e) =>
              e.isOwnBindingAssignment && e.status != EventStatusEnum.canceled,
        )
        .toList();
    final scheduledKeys = scheduledEvents.map(_eventKey).toSet();

    bool isBlockedBySchedule(Event candidate) {
      if (scheduledKeys.contains(_eventKey(candidate))) return true;
      final isOwnApplied =
          !candidate.isSwapOfferFromOther &&
          candidate.assignmentStatus ==
              EventUserStatusEnum.pending_flight_school;
      if (isOwnApplied) return false;
      final conflict = TandemService.findUserEventBookingConflict(
        userId: user.id,
        startTime: candidate.startTime,
        endTime: candidate.endTime,
        userEvents: user.events,
        userTandemDuties: user.tandemDuties,
        ignoreEventKey: _eventKey(candidate),
      );
      return conflict != null;
    }

    final opportunityPool = [
      ...swapOfferEvents,
      ...pendingOrRequestedEvents,
      ...publicRequests,
      ...stage1PreviewEvents,
    ];

    final today = DateTime(now.year, now.month, now.day);
    final ownUpcomingTandem = user.tandemDuties.where((d) {
      final fs = fsById[d.flightSchoolId];
      if (fs == null ||
          !fs.tandemEnabled ||
          !fs.isTandemPilot ||
          fs.membershipStatus != MembershipStatusEnum.active ||
          !selectedFlightSchools.contains(d.flightSchoolId)) {
        return false;
      }
      return d.userId == user.id && !d.endDay.isBefore(today);
    }).toList();

    final confirmedTandemBundles = bundleConsecutiveTandemDuties(
      ownUpcomingTandem
          .where(
            (d) =>
                d.status == TandemDutyStatus.confirmed ||
                d.status == TandemDutyStatus.cancellationRequested,
          )
          .toList(),
    );
    final pendingTandemRequests =
        ownUpcomingTandem
            .where(
              (d) =>
                  d.status == TandemDutyStatus.requestedByAdmin ||
                  d.status == TandemDutyStatus.requestedByPilot,
            )
            .toList()
          ..sort((a, b) => a.startDate.compareTo(b.startDate));

    bool hasUnansweredRequests = pendingTandemRequests.any(
      (d) => d.status == TandemDutyStatus.requestedByAdmin,
    );
    bool hasOpenOpportunities = false;
    for (final ev in opportunityPool) {
      final fs = fsById[ev.flightSchoolId];
      if (fs == null || fs.membershipStatus != MembershipStatusEnum.active) {
        continue;
      }
      if (isBlockedBySchedule(ev)) continue;

      final stage = fs.effectiveStageFor(ev);
      if (!ev.isSwapOfferFromOther &&
          ev.assignmentStatus == EventUserStatusEnum.pending_user) {
        hasUnansweredRequests = true;
      } else if (stage == 1) {
        hasOpenOpportunities = true;
      } else if ((ev.isSwapOfferFromOther ||
              ev.assignmentStatus == EventUserStatusEnum.open) &&
          fs.hasRole(ev.role)) {
        hasOpenOpportunities = true;
      }
    }

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            UserAvatar(
              avatarUrl: user.avatarUrl,
              name: user.name,
              radius: 17,
              backgroundColor: isDark
                  ? cs.primaryContainer
                  : AppTheme.primaryTint,
              foregroundColor: isDark
                  ? cs.onPrimaryContainer
                  : AppTheme.primaryColor,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Hallo ${user.name.isEmpty ? "Gast" : user.name}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          const AppModeSwitchChip(isAdminMode: false),
          const AppBarActionDivider(),
          ConnectionStatusAction(
            isLoading: widget.isLoading,
            hasConnection: widget.hasConnection,
            lastUpdated: widget.lastUpdated,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (user.flightSchools.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
              child: FlightSchoolSelector(
                flightSchools: user.flightSchools,
                selectedIds: selectedFlightSchools,
                onSelectionChanged: (Set<String> selected) {
                  context.read<UserProvider>().setSelectedFlightSchoolIds(
                    selected,
                  );
                },
              ),
            ),
          Expanded(
            child: DefaultTabController(
              length: 2,
              child: Builder(
                builder: (tabCtx) {
                  final tabCtrl = DefaultTabController.of(tabCtx);
                  return _TabSeenObserver(
                    controller: tabCtrl,
                    onOpportunitiesViewed: () {
                      UserBadgeStateService().markStartOpportunitiesSeen();
                    },
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? AppTheme.darkCard
                                  : (context.isDesktop
                                        ? AppTheme.desktopSurfaceSubtle
                                        : const Color(0xFFE2E2DE)),
                              border: !isDark && context.isDesktop
                                  ? Border.all(color: AppTheme.desktopBorder)
                                  : null,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: TabBar(
                              isScrollable: false,
                              dividerColor: Colors.transparent,
                              splashBorderRadius: BorderRadius.circular(11),
                              indicatorSize: TabBarIndicatorSize.tab,
                              indicator: BoxDecoration(
                                color: cs.surface,
                                borderRadius: BorderRadius.circular(11),
                                boxShadow: isDark
                                    ? null
                                    : const [
                                        BoxShadow(
                                          color: Color(0x12101828),
                                          blurRadius: 6,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                              ),
                              labelColor: cs.onSurface,
                              unselectedLabelColor: cs.onSurfaceVariant,
                              tabs: [
                                const Tab(height: 38, text: 'Meine Events'),
                                Tab(
                                  height: 38,
                                  child: _RequestsAndOpenTabLabel(
                                    hasUnansweredRequests:
                                        hasUnansweredRequests,
                                    hasOpenOpportunities: hasOpenOpportunities,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: TabBarView(
                            children: [
                              YourEventsWidget(
                                events: [
                                  ...acceptedEvents,
                                  ...userChangeRequests,
                                ],
                                tandemBundles: confirmedTandemBundles,
                                onOpenOpportunitiesTap: () {
                                  tabCtrl.animateTo(1);
                                  UserBadgeStateService()
                                      .markStartOpportunitiesSeen();
                                },
                              ),
                              RequestsOpportunitiesWidget(
                                events: opportunityPool,
                                tandemRequests: pendingTandemRequests,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabSeenObserver extends StatefulWidget {
  final TabController controller;
  final VoidCallback onOpportunitiesViewed;
  final Widget child;

  const _TabSeenObserver({
    required this.controller,
    required this.onOpportunitiesViewed,
    required this.child,
  });

  @override
  State<_TabSeenObserver> createState() => _TabSeenObserverState();
}

class _TabSeenObserverState extends State<_TabSeenObserver> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant _TabSeenObserver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
  }

  void _onChanged() {
    if (widget.controller.index == 1) {
      widget.onOpportunitiesViewed();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Interaktives Tab-Label für „Anfragen & Offen“:
/// - „Anfragen“ pulsiert farbig, wenn unbeantwortete Direktanfragen vorliegen.
/// - „Offen“ erscheint dezent leicht farbig, wenn neue offene Stellen verfügbar sind.
class _RequestsAndOpenTabLabel extends StatefulWidget {
  final bool hasUnansweredRequests;
  final bool hasOpenOpportunities;

  const _RequestsAndOpenTabLabel({
    required this.hasUnansweredRequests,
    required this.hasOpenOpportunities,
  });

  @override
  State<_RequestsAndOpenTabLabel> createState() =>
      _RequestsAndOpenTabLabelState();
}

class _RequestsAndOpenTabLabelState extends State<_RequestsAndOpenTabLabel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    if (widget.hasUnansweredRequests) {
      _pulseCtrl.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _RequestsAndOpenTabLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hasUnansweredRequests && !_pulseCtrl.isAnimating) {
      _pulseCtrl.repeat(reverse: true);
    } else if (!widget.hasUnansweredRequests && _pulseCtrl.isAnimating) {
      _pulseCtrl.stop();
      _pulseCtrl.value = 0;
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final defaultStyle = DefaultTextStyle.of(context).style;
    final cs = Theme.of(context).colorScheme;
    final subtleOpenColor = Color.lerp(
      defaultStyle.color ?? cs.onSurface,
      AppTheme.infoColor,
      0.58,
    );

    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (context, _) {
        final pulseT = Curves.easeInOut.transform(_pulseCtrl.value);
        final requestColor = widget.hasUnansweredRequests
            ? Color.lerp(AppTheme.warningColor, AppTheme.dangerColor, pulseT)
            : null;

        return Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.hasUnansweredRequests) ...[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: requestColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (requestColor ?? AppTheme.dangerColor).withValues(
                        alpha: 0.25 + 0.45 * pulseT,
                      ),
                      blurRadius: 4 + 4 * pulseT,
                      spreadRadius: 0.5 + 1.2 * pulseT,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Anfragen',
                      style: widget.hasUnansweredRequests
                          ? TextStyle(
                              color: requestColor,
                              fontWeight: FontWeight.w800,
                            )
                          : null,
                    ),
                    const TextSpan(text: ' & '),
                    TextSpan(
                      text: 'Offen',
                      style: widget.hasOpenOpportunities
                          ? TextStyle(
                              color: subtleOpenColor,
                              fontWeight: FontWeight.w600,
                            )
                          : null,
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      },
    );
  }
}
