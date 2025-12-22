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
  Set<String> selectedIds = {};

  bool get allSelected =>
      selectedIds.length == widget.flightSchools.length;

  void toggleSelectAll() {
    setState(() {
      if (allSelected) {
        selectedIds.clear();
      } else {
        selectedIds =
            widget.flightSchools.map((fs) => fs.id).toSet();
      }
      widget.onSelectionChanged(selectedIds);
    });
  }

  void toggleFlightSchool(String id) {
    setState(() {
      if (selectedIds.contains(id)) {
        selectedIds.remove(id);
      } else {
        selectedIds.add(id);
      }
      widget.onSelectionChanged(selectedIds);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(    //TODO: bitte bitte am Design arbeiten
      height: 60,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        children: [
          _buildSelectorBox(
            label: allSelected ? "Unselect All" : "Select All",
            selected: allSelected,
            onTap: toggleSelectAll,
          ),
          ...widget.flightSchools.map((fs) => _buildSelectorBox(
            label: fs.displayName,
            selected: selectedIds.contains(fs.id),
            onTap: () => toggleFlightSchool(fs.id),
          )),
        ],
      ),
    );
  }

  Widget _buildSelectorBox({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? Colors.blueAccent : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.black87,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
