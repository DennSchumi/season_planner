import 'package:flutter/material.dart';
import 'package:inventar_manager/core/services/category_service.dart';
import 'package:inventar_manager/core/services/item_service.dart';
import 'package:inventar_manager/core/theme.dart';
import 'package:inventar_manager/core/widgets/ui_primitives.dart';
import 'package:inventar_manager/features/inventory/inventory_detail_view.dart';
import 'package:inventar_manager/features/inventory/new_item_view.dart';
import 'package:inventar_manager/features/inventory/check_in_out_dialog.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:intl/intl.dart';

class InventoryListView extends StatefulWidget {
  const InventoryListView({super.key});

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
          final catName =
              categories
                  .where((c) => c.id == item.categoryId)
                  .firstOrNull
                  ?.name ??
              '';

          bool matchesSearch =
              item.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              (item.serialNumber ?? '').toLowerCase().contains(
                _searchQuery.toLowerCase(),
              ) ||
              item.materialNumber.toLowerCase().contains(
                _searchQuery.toLowerCase(),
              );

          bool matchesCategory =
              _selectedCategory == 'Alle' || catName == _selectedCategory;

          bool matchesStatus = true;
          if (_selectedStatus != 'Alle') {
            if (_selectedStatus == 'Lager' && item.status != 'in_stock')
              matchesStatus = false;
            if (_selectedStatus == 'Ausgegeben' && item.status != 'out')
              matchesStatus = false;
            if (_selectedStatus == 'Gesperrt' &&
                item.status != 'blocked' &&
                item.status != 'defekt')
              matchesStatus = false;
          }

          if (!_showDisposed && item.status == 'disposed') return false;

          return matchesSearch && matchesCategory && matchesStatus;
        }).toList();

        final cs = Theme.of(context).colorScheme;
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20.0),
            child: SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Filters
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 14.0,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: cs.outlineVariant),
                      ),
                    ),
                    child: Wrap(
                      spacing: 14,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 250,
                          child: TextField(
                            decoration: const InputDecoration(
                              hintText: "Suchen (Name, Serial)...",
                              prefixIcon: Icon(Icons.search_rounded, size: 20),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                            onChanged: (val) =>
                                setState(() => _searchQuery = val),
                          ),
                        ),
                        _buildDropdown(
                          "Kategorie",
                          categoryNames,
                          _selectedCategory,
                          (v) => setState(() => _selectedCategory = v!),
                        ),
                        _buildDropdown(
                          "Status",
                          ['Alle', 'Lager', 'Ausgegeben', 'Gesperrt'],
                          _selectedStatus,
                          (v) => setState(() => _selectedStatus = v!),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              value: _showDisposed,
                              onChanged: (val) =>
                                  setState(() => _showDisposed = val ?? false),
                            ),
                            Text(
                              "entsorgte Geräte anzeigen",
                              style: TextStyle(color: cs.onSurfaceVariant),
                            ),
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
                              constraints: BoxConstraints(
                                minWidth: constraints.maxWidth,
                              ),
                              child: DataTable(
                                headingRowColor: WidgetStateProperty.all(
                                  isDark
                                      ? AppTheme.darkCardElevated
                                      : AppTheme.backgroundColor
                                            .withValues(alpha: 0.6),
                                ),
                                dataRowColor:
                                    WidgetStateProperty.resolveWith<Color?>((
                                      Set<WidgetState> states,
                                    ) {
                                      if (states.contains(
                                        WidgetState.selected,
                                      )) {
                                        return cs.primary.withValues(
                                          alpha: 0.08,
                                        );
                                      }
                                      return null;
                                    }),
                                columns: const [
                                  DataColumn(label: Text('Aktionen')),
                                  DataColumn(label: Text('Gerätenummer')),
                                  DataColumn(label: Text('Name')),
                                  DataColumn(label: Text('Serial No')),
                                  DataColumn(label: Text('Kategorie')),
                                  DataColumn(label: Text('Status')),
                                  DataColumn(label: Text('Letzter Service')),
                                ],
                                rows: filteredItems.asMap().entries.map((
                                  entry,
                                ) {
                                  final index = entry.key;
                                  final item = entry.value;
                                  final bool isDisposed =
                                      item.status == 'disposed';
                                  final Color rowColor = index.isEven
                                      ? cs.surface
                                      : (isDark
                                            ? AppTheme.darkCardElevated
                                                  .withValues(alpha: 0.4)
                                            : AppTheme.backgroundColor
                                                  .withValues(alpha: 0.35));

                                  final catName =
                                      categories
                                          .where((c) => c.id == item.categoryId)
                                          .firstOrNull
                                          ?.name ??
                                      '';

                                  final textStyle = TextStyle(
                                    color: isDisposed
                                        ? cs.onSurfaceVariant
                                              .withValues(alpha: 0.6)
                                        : cs.onSurface,
                                    fontWeight: FontWeight.normal,
                                  );

                                  return DataRow(
                                    color: WidgetStateProperty.all(rowColor),
                                    cells: [
                                      DataCell(
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: Icon(
                                                Icons.visibility_outlined,
                                                color: isDisposed
                                                    ? cs.onSurfaceVariant
                                                          .withValues(
                                                            alpha: 0.5,
                                                          )
                                                    : cs.primary,
                                                size: 20,
                                              ),
                                              onPressed: () {
                                                Navigator.of(context).push(
                                                  MaterialPageRoute(
                                                    builder: (context) =>
                                                        InventoryDetailView(
                                                          item: item,
                                                        ),
                                                  ),
                                                );
                                              },
                                              tooltip: "Details ansehen",
                                            ),
                                            IconButton(
                                              icon: Icon(
                                                Icons.swap_horiz_rounded,
                                                color: isDisposed
                                                    ? cs.onSurfaceVariant
                                                          .withValues(
                                                            alpha: 0.5,
                                                          )
                                                    : cs.onSurfaceVariant,
                                                size: 20,
                                              ),
                                              onPressed: isDisposed
                                                  ? null
                                                  : () {
                                                      CheckInOutDialog.show(
                                                        context,
                                                        item,
                                                      );
                                                    },
                                              tooltip: "Aus-/Einlagern",
                                            ),
                                          ],
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          item.materialNumber,
                                          style: textStyle.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(item.name, style: textStyle),
                                      ),
                                      DataCell(
                                        Text(
                                          item.serialNumber ?? '-',
                                          style: textStyle,
                                        ),
                                      ),
                                      DataCell(Text(catName, style: textStyle)),
                                      DataCell(_buildStatusBadge(item)),
                                      DataCell(
                                        Text(
                                          item.lastServiceDate != null
                                              ? DateFormat(
                                                  'dd.MM.yyyy',
                                                ).format(item.lastServiceDate!)
                                              : '-',
                                          style: textStyle,
                                        ),
                                      ),
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
                backgroundColor: AppTheme.successColor,
                mini: true,
                onPressed: () {},
                child: const Icon(Icons.qr_code_scanner, color: Colors.white),
              ),
              const SizedBox(height: 14),
              SpeedDial(
                icon: Icons.add_rounded,
                activeIcon: Icons.close_rounded,
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                activeBackgroundColor: AppTheme.dangerColor,
                activeForegroundColor: Colors.white,
                visible: true,
                closeManually: false,
                curve: Curves.bounceIn,
                overlayColor: Colors.black,
                overlayOpacity: 0.45,
                elevation: 4.0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                children: [
                  SpeedDialChild(
                    child: const Icon(Icons.inventory_2_outlined),
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    label: 'Neues Item anlegen',
                    labelStyle: const TextStyle(fontSize: 13.5),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const NewItemView(),
                        ),
                      );
                    },
                  ),
                  SpeedDialChild(
                    child: const Icon(Icons.sync_alt_rounded),
                    backgroundColor: AppTheme.successColor,
                    foregroundColor: Colors.white,
                    label: 'Bewegung erfassen',
                    labelStyle: const TextStyle(fontSize: 13.5),
                    onTap: () => debugPrint('Bewegung'),
                  ),
                  SpeedDialChild(
                    child: const Icon(Icons.report_problem_rounded),
                    backgroundColor: AppTheme.dangerColor,
                    foregroundColor: Colors.white,
                    label: 'Trouble Ticket',
                    labelStyle: const TextStyle(fontSize: 13.5),
                    onTap: () => debugPrint('Trouble Ticket'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDropdown(
    String label,
    List<String> items,
    String value,
    ValueChanged<String?> onChanged,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          "$label: ",
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13.5),
        ),
        Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              dropdownColor: cs.surface,
              style: TextStyle(fontSize: 13.5, color: cs.onSurface),
              items: items
                  .map(
                    (i) => DropdownMenuItem(
                      value: i,
                      child: Text(i),
                    ),
                  )
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(ItemModel item) {
    if (item.status == 'defekt' || item.status == 'troubleticket') {
      return const StatusPill(
        label: 'Troubleticket',
        foreground: AppTheme.dangerColor,
        background: AppTheme.dangerBg,
      );
    } else if (item.isLocked) {
      return const StatusPill(
        label: 'Gesperrt',
        foreground: AppTheme.stage1Color,
        background: AppTheme.stage1Bg,
      );
    }
    switch (item.status) {
      case 'in_stock':
        return const StatusPill(
          label: 'Lager',
          foreground: AppTheme.successColor,
          background: AppTheme.successBg,
        );
      case 'out':
        return const StatusPill(
          label: 'Ausgegeben',
          foreground: AppTheme.warningColor,
          background: AppTheme.warningBg,
        );
      case 'blocked':
        return const StatusPill(
          label: 'Gesperrt',
          foreground: AppTheme.dangerColor,
          background: AppTheme.dangerBg,
        );
      case 'disposed':
        return const StatusPill(
          label: 'Entsorgt',
          foreground: AppTheme.textSecondary,
          background: AppTheme.backgroundColor,
        );
      default:
        return StatusPill(
          label: item.status,
          foreground: AppTheme.textSecondary,
          background: AppTheme.backgroundColor,
        );
    }
  }
}
