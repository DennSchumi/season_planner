import 'package:flutter/material.dart';
import 'package:inventar_manager/core/services/category_service.dart';
import 'package:inventar_manager/core/services/item_service.dart';
import 'package:inventar_manager/features/inventory/inventory_detail_view.dart';
import 'package:inventar_manager/features/inventory/new_item_view.dart';
import 'package:inventar_manager/features/inventory/check_in_out_dialog.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:intl/intl.dart';

class InventoryListView extends StatefulWidget {
  const InventoryListView({Key? key}) : super(key: key);

  @override
  _InventoryListViewState createState() => _InventoryListViewState();
}

class _InventoryListViewState extends State<InventoryListView> {
  final CategoryService _categoryService = CategoryService();
  final ItemService _itemService = ItemService();
  
  String _searchQuery = "";
  String _selectedCategory = "Alle";
  String _selectedStatus = "Alle";
  bool _showDisposed = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_categoryService, _itemService]),
      builder: (context, child) {
        if (_categoryService.isLoading || _itemService.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        final categories = _categoryService.categories;
        final items = _itemService.items;

        final categoryNames = ['Alle'] + categories.map((c) => c.name).toList();

        final filteredItems = items.where((item) {
          final catName = categories.where((c) => c.id == item.categoryId).firstOrNull?.name ?? '';
          
          bool matchesSearch = item.name.toLowerCase().contains(_searchQuery.toLowerCase()) || 
                               (item.serialNumber ?? '').toLowerCase().contains(_searchQuery.toLowerCase()) ||
                               item.materialNumber.toLowerCase().contains(_searchQuery.toLowerCase());
          
          bool matchesCategory = _selectedCategory == 'Alle' || catName == _selectedCategory;
          
          bool matchesStatus = true;
          if (_selectedStatus != 'Alle') {
            if (_selectedStatus == 'Lager' && item.status != 'in_stock') matchesStatus = false;
            if (_selectedStatus == 'Ausgegeben' && item.status != 'out') matchesStatus = false;
            if (_selectedStatus == 'Gesperrt' && item.status != 'blocked' && item.status != 'defekt') matchesStatus = false;
          }
          
          if (!_showDisposed && item.status == 'disposed') return false;

          return matchesSearch && matchesCategory && matchesStatus;
        }).toList();

        return Scaffold(
          backgroundColor: const Color(0xFFF1F5F9), // Match detail view background
          body: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Filters
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                    ),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 250,
                    child: TextField(
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        hintText: "Suchen (Name, Serial)...",
                        prefixIcon: const Icon(Icons.search, size: 20),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onChanged: (val) => setState(() => _searchQuery = val),
                    ),
                  ),
                  _buildDropdown("Kategorie", categoryNames, _selectedCategory, (v) => setState(() => _selectedCategory = v!)),
                  _buildDropdown("Status", ['Alle', 'Lager', 'Ausgegeben', 'Gesperrt'], _selectedStatus, (v) => setState(() => _selectedStatus = v!)),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        value: _showDisposed,
                        onChanged: (val) => setState(() => _showDisposed = val ?? false),
                      ),
                      const Text("entsorgte Ger\u00e4te anzeigen", style: TextStyle(color: Color(0xFF64748B))),
                    ],
                  ),
                ],
              ),
            ),
            
                // Data Table
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minWidth: constraints.maxWidth),
                            child: DataTable(
                              headingRowColor: MaterialStateProperty.all(const Color(0xFFF8FAFC)),
                              dataRowColor: MaterialStateProperty.resolveWith<Color?>((Set<MaterialState> states) {
                                if (states.contains(MaterialState.selected)) {
                                  return Theme.of(context).colorScheme.primary.withOpacity(0.08);
                                }
                                return null;
                              }),
                              columns: const [
                                DataColumn(label: Text('Aktionen')),
                                DataColumn(label: Text('Ger\u00e4tenummer')),
                      DataColumn(label: Text('Name')),
                      DataColumn(label: Text('Serial No')),
                      DataColumn(label: Text('Kategorie')),
                      DataColumn(label: Text('Status')),
                      DataColumn(label: Text('Letzter Service')),
                    ],
                    rows: filteredItems.asMap().entries.map((entry) {
                      final index = entry.key;
                      final item = entry.value;
                      final bool isDisposed = item.status == 'disposed';
                      final Color rowColor = index.isEven ? Colors.white : const Color(0xFFF8FAFC);
                      
                      final catName = categories.where((c) => c.id == item.categoryId).firstOrNull?.name ?? '';
                      
                      final textStyle = TextStyle(
                        color: isDisposed ? const Color(0xFF94A3B8) : const Color(0xFF334155),
                        fontWeight: FontWeight.normal,
                      );
                      
                      return DataRow(
                        color: MaterialStateProperty.all(rowColor),
                        cells: [
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.visibility, color: isDisposed ? const Color(0xFF94A3B8) : const Color(0xFF3B82F6), size: 20),
                                  onPressed: () {
                                    Navigator.of(context).push(MaterialPageRoute(
                                      builder: (context) => InventoryDetailView(item: item),
                                    ));
                                  },
                                  tooltip: "Details ansehen",
                                ),
                                  IconButton(
                                    icon: Icon(Icons.swap_horiz, color: isDisposed ? const Color(0xFF94A3B8) : const Color(0xFF64748B), size: 20),
                                    onPressed: isDisposed ? null : () {
                                      CheckInOutDialog.show(context, item);
                                    },
                                    tooltip: "Aus-/Einlagern",
                                  ),
                              ],
                            ),
                          ),
                          DataCell(Text(item.materialNumber, style: textStyle.copyWith(fontWeight: FontWeight.w600))),
                          DataCell(Text(item.name, style: textStyle)),
                          DataCell(Text(item.serialNumber ?? '-', style: textStyle)),
                          DataCell(Text(catName, style: textStyle)),
                          DataCell(_buildStatusBadge(item)),
                          DataCell(Text(item.lastServiceDate != null ? DateFormat('dd.MM.yyyy').format(item.lastServiceDate!) : '-', style: textStyle)),
                        ],
                        );
                      }).toList(),
                    ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
          floatingActionButton: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FloatingActionButton(
                heroTag: "qr_btn",
                backgroundColor: const Color(0xFF10B981),
                mini: true,
                onPressed: () {},
                child: const Icon(Icons.qr_code_scanner, color: Colors.white),
              ),
              const SizedBox(height: 16),
              SpeedDial(
                icon: Icons.add,
                activeIcon: Icons.close,
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
                activeBackgroundColor: const Color(0xFFEF4444),
                activeForegroundColor: Colors.white,
                visible: true,
                closeManually: false,
                curve: Curves.bounceIn,
                overlayColor: Colors.black,
                overlayOpacity: 0.5,
                elevation: 8.0,
                shape: const CircleBorder(),
                children: [
                  SpeedDialChild(
                    child: const Icon(Icons.inventory_2),
                    backgroundColor: const Color(0xFF3B82F6),
                    foregroundColor: Colors.white,
                    label: 'Neues Item anlegen',
                    labelStyle: const TextStyle(fontSize: 14.0),
                    onTap: () {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (context) => const NewItemView(),
                      ));
                    },
                  ),
                  SpeedDialChild(
                    child: const Icon(Icons.sync_alt_rounded),
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    label: 'Bewegung erfassen',
                    labelStyle: const TextStyle(fontSize: 14.0),
                    onTap: () => print('Bewegung'),
                  ),
                  SpeedDialChild(
                    child: const Icon(Icons.report_problem_rounded),
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                    label: 'Trouble Ticket',
                    labelStyle: const TextStyle(fontSize: 14.0),
                    onTap: () => print('Trouble Ticket'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDropdown(String label, List<String> items, String value, ValueChanged<String?> onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text("$label: ", style: const TextStyle(color: Color(0xFF64748B), fontSize: 14)),
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              items: items.map((i) => DropdownMenuItem(value: i, child: Text(i, style: const TextStyle(fontSize: 14)))).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(ItemModel item) {
    Color bgColor;
    Color textColor;
    String label;

    if (item.status == 'defekt' || item.status == 'troubleticket') {
      bgColor = const Color(0xFFEF4444).withOpacity(0.1);
      textColor = const Color(0xFFEF4444);
      label = 'Troubleticket';
    } else if (item.isLocked) {
      bgColor = const Color(0xFF9333EA).withOpacity(0.1);
      textColor = const Color(0xFF9333EA);
      label = 'Gesperrt';
    } else {
      switch (item.status) {
        case 'in_stock':
          bgColor = const Color(0xFF10B981).withOpacity(0.1);
          textColor = const Color(0xFF10B981);
          label = 'Lager';
          break;
        case 'out':
          bgColor = const Color(0xFFF59E0B).withOpacity(0.1);
          textColor = const Color(0xFFF59E0B);
          label = 'Ausgegeben';
          break;
        case 'blocked':
          bgColor = const Color(0xFFEF4444).withOpacity(0.1);
          textColor = const Color(0xFFEF4444);
          label = 'Gesperrt';
          break;
        case 'disposed':
          bgColor = const Color(0xFF94A3B8).withOpacity(0.1);
          textColor = const Color(0xFF94A3B8);
          label = 'Entsorgt';
          break;
        default:
          bgColor = Colors.grey.withOpacity(0.1);
          textColor = Colors.grey;
          label = item.status;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
