import 'package:flutter/material.dart';
import 'package:season_planner/core/theme.dart';
import 'package:season_planner/user/data/models/flight_school_model_user_view.dart';

class FlightSchoolSelector extends StatefulWidget {
  final List<FlightSchoolUserView> flightSchools;
  final Set<String>? selectedIds;
  final void Function(Set<String> selectedIds) onSelectionChanged;

  const FlightSchoolSelector({
    super.key,
    required this.flightSchools,
    this.selectedIds,
    required this.onSelectionChanged,
  });

  @override
  State<FlightSchoolSelector> createState() => _FlightSchoolSelectorState();
}

class _FlightSchoolSelectorState extends State<FlightSchoolSelector> {
  late Set<String> _internalSelectedIds;

  Set<String> get selectedIds => widget.selectedIds ?? _internalSelectedIds;

  bool get allSelected =>
      widget.flightSchools.isNotEmpty &&
      selectedIds.length == widget.flightSchools.length;

  @override
  void initState() {
    super.initState();
    _internalSelectedIds = widget.selectedIds != null
        ? Set<String>.from(widget.selectedIds!)
        : widget.flightSchools.map((fs) => fs.id).toSet();
  }

  @override
  void didUpdateWidget(covariant FlightSchoolSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIds != null) {
      _internalSelectedIds = Set<String>.from(widget.selectedIds!);
      return;
    }
    final validIds = widget.flightSchools.map((fs) => fs.id).toSet();
    final oldIds = oldWidget.flightSchools.map((fs) => fs.id).toSet();
    if (validIds.length != oldIds.length || !validIds.containsAll(oldIds)) {
      _internalSelectedIds = _internalSelectedIds.intersection(validIds);
      for (final id in validIds) {
        if (!oldIds.contains(id)) _internalSelectedIds.add(id);
      }
    }
  }

  void toggleSelectAll() {
    final next = allSelected
        ? <String>{}
        : widget.flightSchools.map((fs) => fs.id).toSet();
    setState(() => _internalSelectedIds = next);
    widget.onSelectionChanged(Set<String>.from(next));
  }

  void toggleFlightSchool(String id) {
    final next = Set<String>.from(selectedIds);
    if (next.contains(id)) {
      next.remove(id);
    } else {
      next.add(id);
    }
    setState(() => _internalSelectedIds = next);
    widget.onSelectionChanged(Set<String>.from(next));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      height: 28,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          // Dezenter, kompakter „Alle“-Pill-Filter
          _SchoolFilterPill(
            selected: allSelected,
            isDark: isDark,
            colorScheme: cs,
            onTap: toggleSelectAll,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  allSelected
                      ? Icons.done_all_rounded
                      : Icons.filter_list_rounded,
                  size: 13,
                  color: allSelected
                      ? (isDark ? cs.onPrimaryContainer : AppTheme.primaryColor)
                      : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  'Alle',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: allSelected ? FontWeight.w700 : FontWeight.w500,
                    color: allSelected
                        ? (isDark
                            ? cs.onPrimaryContainer
                            : AppTheme.primaryColor)
                        : cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          for (var i = 0; i < widget.flightSchools.length; i++) ...[
            Builder(
              builder: (context) {
                final fs = widget.flightSchools[i];
                final selected = selectedIds.contains(fs.id);
                final label = fs.displayShortName.trim().isNotEmpty
                    ? fs.displayShortName.trim()
                    : fs.displayName;
                return _SchoolFilterPill(
                  selected: selected,
                  isDark: isDark,
                  colorScheme: cs,
                  onTap: () => toggleFlightSchool(fs.id),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Opacity(
                        opacity: selected ? 1.0 : 0.4,
                        child: _MiniSchoolLogo(logoUrl: fs.logoLink),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected
                              ? (isDark
                                  ? cs.onPrimaryContainer
                                  : AppTheme.primaryColor)
                              : cs.onSurfaceVariant.withValues(alpha: 0.78),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            if (i != widget.flightSchools.length - 1) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class _SchoolFilterPill extends StatelessWidget {
  final bool selected;
  final bool isDark;
  final ColorScheme colorScheme;
  final VoidCallback onTap;
  final Widget child;

  const _SchoolFilterPill({
    required this.selected,
    required this.isDark,
    required this.colorScheme,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? (isDark
            ? colorScheme.primaryContainer.withValues(alpha: 0.65)
            : AppTheme.primaryTint.withValues(alpha: 0.75))
        : colorScheme.onSurface.withValues(alpha: isDark ? 0.08 : 0.05);
    final borderColor = selected
        ? (isDark
            ? colorScheme.primary.withValues(alpha: 0.35)
            : AppTheme.primaryColor.withValues(alpha: 0.22))
        : Colors.transparent;

    return Material(
      color: bg,
      clipBehavior: Clip.antiAlias,
      shape: StadiumBorder(side: BorderSide(color: borderColor, width: 0.8)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _MiniSchoolLogo extends StatelessWidget {
  final String logoUrl;

  const _MiniSchoolLogo({required this.logoUrl});

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: logoUrl.isEmpty
          ? Image.asset(
              "lib/assets/images/fsBaseImage.webp",
              width: 15,
              height: 15,
              fit: BoxFit.cover,
            )
          : Image.network(
              logoUrl,
              width: 15,
              height: 15,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Image.asset(
                "lib/assets/images/fsBaseImage.webp",
                width: 15,
                height: 15,
                fit: BoxFit.cover,
              ),
            ),
    );
  }
}
