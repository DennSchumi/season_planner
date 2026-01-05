import 'dart:math';

import 'package:flutter/material.dart';
import 'package:season_planer/data/models/user_models/flight_school_model_user_view.dart';

class FlightSchoolSelector extends StatefulWidget {
  final List<FlightSchoolUserView> flightSchools;
  final void Function(Set<String> selectedIds) onSelectionChanged;

  const FlightSchoolSelector({
    super.key,
    required this.flightSchools,
    required this.onSelectionChanged,
  });

  @override
  State<FlightSchoolSelector> createState() => _FlightSchoolSelectorState();
}

class _FlightSchoolSelectorState extends State<FlightSchoolSelector> {
  late Set<String> selectedIds;

  bool get allSelected => selectedIds.length == widget.flightSchools.length;

  @override
  void initState() {
    super.initState();
    selectedIds = widget.flightSchools.map((fs) => fs.id).toSet();
  }

  void toggleSelectAll(bool? value) {
    setState(() {
      if (value == true) {
        selectedIds = widget.flightSchools.map((fs) => fs.id).toSet();
      } else {
        selectedIds.clear();
      }
    });
    widget.onSelectionChanged(selectedIds);
  }

  void toggleFlightSchool(String id) {
    setState(() {
      if (selectedIds.contains(id)) {
        selectedIds.remove(id);
      } else {
        selectedIds.add(id);
      }
    });
    widget.onSelectionChanged(selectedIds);
  }

  @override
  Widget build(BuildContext context) {

    return SizedBox(
      height: 92,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 8),
            child: _SelectAllCard(
              checked: allSelected,
              onChanged: toggleSelectAll,
            ),
          ),

          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(right: 12),
              itemCount: widget.flightSchools.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final fs = widget.flightSchools[index];
                final selected = selectedIds.contains(fs.id);

                return _FlightSchoolChipCard(
                  label: fs.displayShortName,
                  selected: selected,
                  logoUrl: fs.logoLink,
                  onTap: () => toggleFlightSchool(fs.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectAllCard extends StatelessWidget {
  final bool checked;
  final ValueChanged<bool?> onChanged;

  const _SelectAllCard({
    required this.checked,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 72,
      height: 76,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Checkbox(
            value: checked,
            onChanged: onChanged,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(height: 4),
          Text(
            "All",
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}


class _FlightSchoolChipCard extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String logoUrl;

  const _FlightSchoolChipCard({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.logoUrl,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 100,
      height: 85,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [


                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: logoUrl.isEmpty
                      ? Image.asset(
                    "lib/assets/images/fsBaseImage.webp",
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                  )
                      : Image.network(
                    logoUrl,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Image.asset(
                      "lib/assets/images/fsBaseImage.webp",
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),

                if (selected)
                  Positioned(
                    right: -6,
                    bottom: -6,
                    child: Icon(
                      Icons.check_circle,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


