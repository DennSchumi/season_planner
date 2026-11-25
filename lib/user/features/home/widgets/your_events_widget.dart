import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/core/data/enums/event_status_enum.dart';
import 'package:season_planner/core/data/enums/event_user_status_enum.dart';
import 'package:season_planner/core/data/models/event_model.dart';
import 'package:season_planner/core/data/models/tandem_model.dart';
import 'package:season_planner/core/services/tandem_service.dart';
import 'package:season_planner/core/theme.dart';
import 'package:season_planner/core/widgets/ux_components.dart';
import 'package:season_planner/user/data/models/flight_school_model_user_view.dart';
import 'package:season_planner/user/features/home/widgets/event_preview_sheet.dart';
import 'package:season_planner/user/services/database_service.dart';
import '../../../user_provider.dart';
import 'event_card_tile_widget.dart';

class YourEventsWidget extends StatefulWidget {
  final List<Event> events;
  final List<TandemDutyBundle> tandemBundles;
  final VoidCallback? onOpenOpportunitiesTap;

  const YourEventsWidget({
    super.key,
    required this.events,
    this.tandemBundles = const [],
    this.onOpenOpportunitiesTap,
  });

  @override
  State<YourEventsWidget> createState() => _YourEventsWidgetState();
}

class _YourEventsWidgetState extends State<YourEventsWidget> {
  static const int _initialPreviewLimit = 3;

  bool _showAllEvents = false;
  bool _showAllTandem = false;

  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';

  String _formatTime(DateTime date) =>
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

  void _openDetail(BuildContext context, Event event) {
    showEventPreviewSheet(context, event: event);
  }

  Future<void> _openTandemSheet(
    BuildContext context,
    TandemDutyBundle bundle,
    FlightSchoolUserView? flightSchool,
  ) async {
    await showUserTandemPreviewSheet(
      context,
      bundle: bundle,
      flightSchool: flightSchool,
    );
  }

  Widget _buildShowMoreButton({
    required BuildContext context,
    required bool expanded,
    required int hiddenCount,
    required VoidCallback onPressed,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: cs.primary,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          ),
          onPressed: onPressed,
          icon: Icon(
            expanded
                ? Icons.keyboard_arrow_up_rounded
                : Icons.keyboard_arrow_down_rounded,
            size: 18,
          ),
          label: Text(
            expanded ? 'Weniger anzeigen' : 'Mehr anzeigen (+$hiddenCount)',
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserProvider>().user;

    if (user == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final Map<String, FlightSchoolUserView> fsById = {
      for (final fs in user.flightSchools) fs.id: fs,
    };

    if (widget.events.isEmpty && widget.tandemBundles.isEmpty) {
      return EmptyStateView(
        icon: Icons.event_available_outlined,
        title: 'Noch keine bestätigten Einsätze',
        subtitle:
            'Sobald du ein Event oder einen Tandem-Einsatz bestätigt hast, erscheint er hier.',
        actionLabel: widget.onOpenOpportunitiesTap != null
            ? 'Zu „Anfragen & Offen“'
            : null,
        actionIcon: Icons.inbox_outlined,
        onAction: widget.onOpenOpportunitiesTap,
      );
    }

    final sorted = List<Event>.from(widget.events)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    // Abgesagte Events dürfen nie in die Hero-Card rutschen – dort immer nur
    // das aktuell laufende bzw. nächste reguläre Event anzeigen.
    final activeSorted = sorted
        .where((e) => e.status != EventStatusEnum.canceled)
        .toList();
    final nextEvent = activeSorted.isNotEmpty ? activeSorted.first : null;
    final nextFs = nextEvent != null ? fsById[nextEvent.flightSchoolId] : null;
    final restEvents = nextEvent == null
        ? sorted
        : sorted.where((e) => !identical(e, nextEvent)).toList();
    final visibleRestEvents = _showAllEvents
        ? restEvents
        : restEvents.take(_initialPreviewLimit).toList();
    final hiddenRestEvents = restEvents.length - visibleRestEvents.length;

    final visibleTandem = _showAllTandem
        ? widget.tandemBundles
        : widget.tandemBundles.take(_initialPreviewLimit).toList();
    final hiddenTandem = widget.tandemBundles.length - visibleTandem.length;

    final cs = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 104),
      children: [
        if (nextEvent != null)
          _NextEventHeroCard(
            event: nextEvent,
            flightSchool: nextFs,
            dateRange:
                nextEvent.startTime.year == nextEvent.endTime.year &&
                    nextEvent.startTime.month == nextEvent.endTime.month &&
                    nextEvent.startTime.day == nextEvent.endTime.day
                ? '${_formatDate(nextEvent.startTime)} · ${_formatTime(nextEvent.startTime)} – ${_formatTime(nextEvent.endTime)}'
                : '${_formatDate(nextEvent.startTime)} ${_formatTime(nextEvent.startTime)} – ${_formatDate(nextEvent.endTime)}',
            onTap: () => _openDetail(context, nextEvent),
          ),
        if (restEvents.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
            child: Text(
              'WEITERE EVENTS (${restEvents.length})',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          for (var i = 0; i < visibleRestEvents.length; i++) ...[
            EventCardTile(
              event: visibleRestEvents[i],
              flightSchool: fsById[visibleRestEvents[i].flightSchoolId],
              dateText:
                  '${_formatDate(visibleRestEvents[i].startTime)} – ${_formatDate(visibleRestEvents[i].endTime)}',
              status: visibleRestEvents[i].status,
              onTap: () => _openDetail(context, visibleRestEvents[i]),
            ),
            if (i != visibleRestEvents.length - 1) const SizedBox(height: 10),
          ],
          if (restEvents.length > _initialPreviewLimit)
            _buildShowMoreButton(
              context: context,
              expanded: _showAllEvents,
              hiddenCount: hiddenRestEvents,
              onPressed: () => setState(() => _showAllEvents = !_showAllEvents),
            ),
        ],
        if (widget.tandemBundles.isNotEmpty) ...[
          Padding(
            padding: EdgeInsets.fromLTRB(
              4,
              (nextEvent != null || restEvents.isNotEmpty) ? 18 : 4,
              4,
              8,
            ),
            child: Text(
              'TANDEM-EINSÄTZE (${widget.tandemBundles.length})',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          for (var i = 0; i < visibleTandem.length; i++) ...[
            _TandemBundleCard(
              bundle: visibleTandem[i],
              flightSchool: fsById[visibleTandem[i].flightSchoolId],
              onTap: () => _openTandemSheet(
                context,
                visibleTandem[i],
                fsById[visibleTandem[i].flightSchoolId],
              ),
            ),
            if (i != visibleTandem.length - 1) const SizedBox(height: 10),
          ],
          if (widget.tandemBundles.length > _initialPreviewLimit)
            _buildShowMoreButton(
              context: context,
              expanded: _showAllTandem,
              hiddenCount: hiddenTandem,
              onPressed: () => setState(() => _showAllTandem = !_showAllTandem),
            ),
        ],
      ],
    );
  }
}

class _TandemBundleCard extends StatelessWidget {
  final TandemDutyBundle bundle;
  final FlightSchoolUserView? flightSchool;
  final VoidCallback? onTap;

  const _TandemBundleCard({
    required this.bundle,
    required this.flightSchool,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final schoolLabel = flightSchool == null
        ? ''
        : (flightSchool!.displayShortName.isNotEmpty
              ? flightSchool!.displayShortName
              : flightSchool!.displayName);
    final daysSuffix = bundle.dayCount > 1 ? ' (${bundle.dayCount} Tage)' : '';
    final isCancelReq = bundle.hasCancellationRequest;

    final assignmentPill = isCancelReq
        ? const StatusPill(
            label: 'Absage angefragt',
            foreground: AppTheme.warningColor,
            background: AppTheme.warningBg,
            fontSize: 10.5,
          )
        : const StatusPill(
            label: 'Arbeitseinsatz bestätigt',
            foreground: AppTheme.successColor,
            background: AppTheme.successBg,
            fontSize: 10.5,
          );

    return SoftCard(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 430;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              DateBadgeBox(
                date: bundle.startDate,
                accentColor: isCancelReq
                    ? AppTheme.warningColor
                    : AppTheme.successColor,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.paragliding_rounded,
                          size: 16,
                          color: AppTheme.primaryColor,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            schoolLabel.isNotEmpty
                                ? 'Tandempilot · $schoolLabel'
                                : 'Tandempilot',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${bundle.dateRangeLabel}$daysSuffix · ${bundle.timeLabel}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: cs.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                    if (!isWide) ...[const SizedBox(height: 8), assignmentPill],
                  ],
                ),
              ),
              if (isWide) ...[const SizedBox(width: 12), assignmentPill],
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: cs.onSurfaceVariant,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Öffnet das untere Detail- & Absage-Popup für einen bestätigten (oder bereits
/// zur Absage angefragten) Tandem-Einsatz auf Startseite und im Kalender.
Future<void> showUserTandemPreviewSheet(
  BuildContext context, {
  required TandemDutyBundle bundle,
  required FlightSchoolUserView? flightSchool,
}) async {
  await showAdaptiveSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    wrapDesktopCard: false,
    desktopMaxWidth: 500,
    builder: (_) =>
        _TandemPreviewSheet(bundle: bundle, flightSchool: flightSchool),
  );
}

class _TandemPreviewSheet extends StatefulWidget {
  final TandemDutyBundle bundle;
  final FlightSchoolUserView? flightSchool;

  const _TandemPreviewSheet({required this.bundle, required this.flightSchool});

  @override
  State<_TandemPreviewSheet> createState() => _TandemPreviewSheetState();
}

class _TandemPreviewSheetState extends State<_TandemPreviewSheet> {
  bool _busy = false;

  Future<void> _updateBundleStatus({
    required TandemDutyStatus newStatus,
    required String successMessage,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      bool allOk = true;
      for (final d in widget.bundle.duties) {
        if (d.status == newStatus) continue;
        final ok = await TandemService().updateDutyStatus(
          flightSchoolId: d.flightSchoolId,
          dutyId: d.id,
          newStatus: newStatus,
          summary: 'Tandem ${d.dateRangeLabel}',
        );
        if (!ok) allOk = false;
      }
      final fresh = await DatabaseService().getUserInformation();
      if (!mounted) return;
      if (fresh != null) {
        context.read<UserProvider>().setUser(fresh);
      }
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            allOk
                ? successMessage
                : 'Status konnte nicht vollständig aktualisiert werden.',
          ),
        ),
      );
      if (allOk) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmAndRequestCancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tandem-Einsatz absagen?'),
        content: Text(
          'Möchtest du für deinen Tandem-Einsatz (${widget.bundle.dateRangeLabel}) eine Absage anfragen?\n\n'
          'Ein Admin deiner Flugschule muss die Absage anschließend bestätigen. Bis dahin bleibst du regulär eingeteilt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.dangerColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Absage anfragen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _updateBundleStatus(
      newStatus: TandemDutyStatus.cancellationRequested,
      successMessage:
          'Absage angefragt – wartet auf Bestätigung durch die Flugschule.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bundle = widget.bundle;
    final fs = widget.flightSchool;
    final schoolName = fs == null
        ? 'Flugschule'
        : (fs.displayName.trim().isNotEmpty
              ? fs.displayName.trim()
              : fs.displayShortName.trim());
    final isCancelReq = bundle.allCancellationRequested;
    final hasAnyCancelReq = bundle.hasCancellationRequest;
    final daysSuffix = bundle.dayCount > 1 ? ' (${bundle.dayCount} Tage)' : '';
    final notes = bundle.combinedNotes;

    final isDesktop = context.isDesktop;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? AppTheme.darkCard
            : (isDesktop
                  ? AppTheme.desktopBackground
                  : AppTheme.backgroundColor),
        borderRadius: isDesktop
            ? BorderRadius.circular(24)
            : const BorderRadius.vertical(top: Radius.circular(28)),
        border: isDesktop
            ? Border.all(
                color: isDark ? AppTheme.darkBorder : AppTheme.desktopBorder,
              )
            : null,
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 28,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, isDesktop ? 20 : 10, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!isDesktop) ...[
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.outlineVariant,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Row(
                children: [
                  const TintedIconBadge(
                    icon: Icons.paragliding_rounded,
                    iconColor: AppTheme.primaryColor,
                    backgroundColor: AppTheme.primaryTint,
                    size: 46,
                    iconSize: 24,
                    radius: 14,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Tandem-Einsatz',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          schoolName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  StatusPill(
                    label: hasAnyCancelReq ? 'Absage angefragt' : 'Bestätigt',
                    foreground: hasAnyCancelReq
                        ? AppTheme.warningColor
                        : AppTheme.successColor,
                    background: hasAnyCancelReq
                        ? AppTheme.warningBg
                        : AppTheme.successBg,
                  ),
                  if (isDesktop) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Schließen',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              SoftCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today_rounded,
                          size: 16,
                          color: cs.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${bundle.dateRangeLabel}$daysSuffix',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: 16,
                          color: cs.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            bundle.timeLabel,
                            style: TextStyle(
                              fontSize: 13.5,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (notes.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.notes_rounded,
                            size: 16,
                            color: cs.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              notes,
                              style: TextStyle(
                                fontSize: 13,
                                color: cs.onSurfaceVariant,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (hasAnyCancelReq) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.warningColor.withValues(alpha: 0.14)
                        : AppTheme.warningBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppTheme.warningColor.withValues(alpha: 0.30),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.hourglass_top_rounded,
                        size: 18,
                        color: AppTheme.warningColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Deine Absage-Anfrage wurde gesendet und wartet auf Bestätigung durch einen Admin.',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? const Color(0xFFFCD34D)
                                : AppTheme.warningColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('Schließen'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: isCancelReq
                          ? FilledButton.tonal(
                              style: FilledButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: _busy
                                  ? null
                                  : () => _updateBundleStatus(
                                      newStatus: TandemDutyStatus.confirmed,
                                      successMessage:
                                          'Absage-Anfrage zurückgezogen – Einsatz bleibt bestätigt.',
                                    ),
                              child: const Text(
                                'Absage zurückziehen',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            )
                          : TextButton(
                              style: TextButton.styleFrom(
                                backgroundColor: isDark
                                    ? AppTheme.dangerColor.withValues(
                                        alpha: 0.18,
                                      )
                                    : AppTheme.dangerBg,
                                foregroundColor: isDark
                                    ? const Color(0xFFFCA5A5)
                                    : AppTheme.dangerColor,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              onPressed: _busy
                                  ? null
                                  : _confirmAndRequestCancel,
                              child: const Text(
                                'Einsatz absagen',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Revolut-inspirierte Primär-Hero-Karte für das nächste anstehende Event.
class _NextEventHeroCard extends StatelessWidget {
  final Event event;
  final FlightSchoolUserView? flightSchool;
  final String dateRange;
  final VoidCallback onTap;

  const _NextEventHeroCard({
    required this.event,
    required this.flightSchool,
    required this.dateRange,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isRunning =
        !event.startTime.isAfter(now) && event.endTime.isAfter(now);
    final isChangeReq =
        event.assignmentStatus == EventUserStatusEnum.user_requests_change;
    final schoolLabel = flightSchool == null
        ? ''
        : (flightSchool!.displayShortName.isNotEmpty
              ? flightSchool!.displayShortName
              : flightSchool!.displayName);

    final assignmentStatusLabel = isChangeReq
        ? 'Änderung angefragt'
        : event.swapOffered
        ? 'Tausch offen'
        : 'Arbeitseinsatz bestätigt';
    final assignmentStatusColor = isChangeReq
        ? AppTheme.warningColor
        : event.swapOffered
        ? AppTheme.swapColor
        : AppTheme.successColor;
    final eventStatusAccent = eventStatusColor(event.status.name);
    final isCanceled = event.status == EventStatusEnum.canceled;

    return CanceledEventDecorator(
      isCanceled: isCanceled,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppTheme.primaryColor, AppTheme.primaryDark],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: AppTheme.primaryGlow,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          isRunning ? 'AKTUELLES EVENT' : 'NÄCHSTES EVENT',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.7,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: assignmentStatusColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              assignmentStatusLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: assignmentStatusColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: DateBadgeBox(
                          date: event.startTime,
                          accentColor: eventStatusAccent,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              event.displayName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                                color: Colors.white,
                                height: 1.18,
                                decoration: isCanceled
                                    ? TextDecoration.lineThrough
                                    : null,
                                decorationColor: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(
                                  Icons.schedule_rounded,
                                  size: 14.5,
                                  color: Colors.white.withValues(alpha: 0.85),
                                ),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: Text(
                                    dateRange,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.white.withValues(
                                        alpha: 0.92,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      if (event.role.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            event.roleLabel,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (event.location.isNotEmpty || schoolLabel.isNotEmpty)
                        Expanded(
                          child: Row(
                            children: [
                              Icon(
                                event.location.isNotEmpty
                                    ? Icons.place_outlined
                                    : Icons.school_outlined,
                                size: 15,
                                color: Colors.white.withValues(alpha: 0.82),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  event.location.isNotEmpty
                                      ? (schoolLabel.isNotEmpty
                                            ? '${event.location} · $schoolLabel'
                                            : event.location)
                                      : schoolLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: Colors.white.withValues(alpha: 0.85),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        const Spacer(),
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.arrow_forward_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
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
}
