import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:inventar_manager/core/services/category_service.dart';
import 'package:inventar_manager/core/services/item_service.dart';
import 'package:inventar_manager/core/services/flight_school_service.dart';
import 'package:inventar_manager/features/inventory/inventory_detail_view.dart';
import 'package:inventar_manager/features/inventory/check_in_out_dialog.dart';
import 'package:inventar_manager/features/inventory/batch_movement_dialog.dart';
import 'package:inventar_manager/features/dashboard/item_swap_dialog.dart';
import 'package:inventar_manager/core/services/transaction_service.dart';

enum TodoType { ok, dueSoon, pastDue, ticket }

class DashboardView extends StatefulWidget {
  const DashboardView({Key? key}) : super(key: key);

  @override
  _DashboardViewState createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  List<String> _hiddenCategories = [];
  List<TransactionModel> _openTickets = [];
  final CategoryService _categoryService = CategoryService();
  final ItemService _itemService = ItemService();
  final TransactionService _transactionService = TransactionService();

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  void _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _hiddenCategories = prefs.getStringList('hidden_categories') ?? [];
    });
    _loadOpenTickets();
  }

  Future<void> _loadOpenTickets() async {
    final tickets = await _transactionService.getOpenTroubleTickets();
    if (mounted) {
      setState(() {
        _openTickets = tickets;
      });
    }
  }

  void _toggleCategoryVisibility(String categoryName) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (_hiddenCategories.contains(categoryName)) {
        _hiddenCategories.remove(categoryName);
      } else {
        _hiddenCategories.add(categoryName);
      }
      prefs.setStringList('hidden_categories', _hiddenCategories);
    });
  }

  // The _showItemActionModal is no longer used, we call CheckInOutDialog directly

  @override
  Widget build(BuildContext context) {
    bool isDesktop = MediaQuery.of(context).size.width > 800;

    return ListenableBuilder(
      listenable: Listenable.merge([_categoryService, _itemService]),
      builder: (context, child) {
        if (_categoryService.isLoading || _itemService.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        final categories = _categoryService.categories;
        final items = _itemService.items;

        Widget mainContent = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Kategorien",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF334155),
                  ),
                ),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        ItemSwapDialog.show(context, _categoryService, _itemService);
                      },
                      icon: const Icon(Icons.swap_horiz, color: Color(0xFF64748B)),
                      label: const Text("Tauschen", style: TextStyle(color: Color(0xFF64748B))),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.filter_list, color: Color(0xFF64748B)),
                      tooltip: "Kategorien filtern",
                      onSelected: _toggleCategoryVisibility,
                      itemBuilder: (context) {
                        return categories.map((c) {
                          final isHidden = _hiddenCategories.contains(c.name);
                          return CheckedPopupMenuItem<String>(
                            value: c.name,
                            checked: !isHidden,
                            child: Text(c.name),
                          );
                        }).toList();
                      },
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_categoryService.errorMessage != null || _itemService.errorMessage != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Color(0xFFEF4444)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _categoryService.errorMessage ?? _itemService.errorMessage ?? "",
                        style: const TextStyle(color: Color(0xFF991B1B)),
                      ),
                    ),
                  ],
                ),
              ),
            categories.isEmpty 
              ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.inbox, size: 48, color: Color(0xFF94A3B8)),
                      const SizedBox(height: 16),
                      const Text(
                        "Keine Kategorien vorhanden",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Lege deine erste Kategorie in den Einstellungen an, um Gegenst\u00e4nde hinzuzuf\u00fcgen.",
                        style: TextStyle(color: Color(0xFF64748B)),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          // Navigate to Settings
                          Navigator.pushReplacementNamed(context, '/settings'); // Or how do we navigate to settings? The app uses a bottom nav bar.
                          // The main scaffold uses index. Let's just instruct them for now or use the nav if possible.
                        },
                        icon: const Icon(Icons.settings),
                        label: const Text("Zu den Einstellungen"),
                      )
                    ],
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    // Make cards larger by reducing columns
                    int crossAxisCount = constraints.maxWidth > 1400 ? 3 : constraints.maxWidth > 900 ? 2 : 1;
                    double spacing = 16.0;
                    double width = (constraints.maxWidth - (spacing * (crossAxisCount - 1))) / crossAxisCount;
                    
                    return Wrap(
                      spacing: spacing,
                      runSpacing: spacing,
                      children: categories
                          .where((c) => !_hiddenCategories.contains(c.name))
                          .map((c) {
                            final catItems = items.where((i) => i.categoryId == c.id && i.status != 'disposed').toList();
                            return SizedBox(
                              width: width - 0.1,
                              child: _buildCategoryCard(c, catItems),
                            );
                          })
                          .toList(),
                    );
                  },
                ),
          ],
        );

        Widget sidebarContent = Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F9FF),
            borderRadius: BorderRadius.circular(16.0),
            border: Border.all(color: const Color(0xFFBAE6FD)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.checklist_rtl_rounded, color: Color(0xFF0369A1)),
                  SizedBox(width: 8),
                  Text(
                    "To-Do Liste",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0369A1),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Builder(
                builder: (context) {
                  final now = DateTime.now();
                  final dueThreshold = now.add(const Duration(days: 7));
                  
                  final dueItems = items.where((i) {
                    if (i.status == 'disposed' || i.nextServiceDate == null) return false;
                    return i.nextServiceDate!.isBefore(dueThreshold);
                  }).toList();
                  
                  final ticketWidgets = _openTickets
                      .where((ticket) => items.any((i) => i.id == ticket.itemId))
                      .map((ticket) {
                    final item = items.firstWhere((i) => i.id == ticket.itemId);
                    final itemName = "${item.name} (${item.materialNumber})";
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: InkWell(
                        onTap: () async {
                          await Navigator.of(context).push(MaterialPageRoute(
                            builder: (context) => InventoryDetailView(item: item),
                          ));
                          _loadOpenTickets();
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: _buildTodoCard(
                          itemName,
                          "Troubleticket offen",
                          Icons.build_rounded,
                          TodoType.ticket,
                        ),
                      ),
                    );
                  }).toList();

                  final dueServiceWidgets = dueItems.map((item) {
                    final isPastDue = item.nextServiceDate!.isBefore(now);
                    final daysRemaining = item.nextServiceDate!.difference(now).inDays;
                    final subtitle = isPastDue 
                        ? "Überfällig seit ${-daysRemaining} Tagen"
                        : "Fällig in $daysRemaining Tagen";
                        
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (context) => InventoryDetailView(item: item),
                          ));
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: _buildTodoCard(
                          "${item.name} (${item.materialNumber})",
                          subtitle,
                          Icons.warning_amber_rounded,
                          isPastDue ? TodoType.pastDue : TodoType.dueSoon,
                        ),
                      ),
                    );
                  }).toList();
                  
                  if (ticketWidgets.isEmpty && dueServiceWidgets.isEmpty) {
                    return _buildTodoCard(
                      "Keine Services oder Tickets",
                      "Alles in Ordnung",
                      Icons.check_circle_outline_rounded,
                      TodoType.ok,
                    );
                  }
                  
                  return Column(
                    children: [
                      ...ticketWidgets,
                      ...dueServiceWidgets,
                    ],
                  );
                },
              ),
            ],
          ),
        );

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "\u00dcbersicht",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 24),
              
              if (isDesktop)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: mainContent),
                    const SizedBox(width: 24),
                    Expanded(flex: 1, child: sidebarContent),
                  ],
                )
              else
                Column(
                  children: [
                    mainContent,
                    const SizedBox(height: 32),
                    sidebarContent,
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCategoryCard(CategoryModel category, List<ItemModel> items) {
    int outCount = items.where((i) => i.status == "out").length;
    int inStockCount = items.length - outCount;

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.0),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              category.buildIcon(color: const Color(0xFF3B82F6), size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  category.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                    fontSize: 16,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.library_add_check, color: Color(0xFF64748B)),
                tooltip: "Sammelbewegung",
                onPressed: () {
                  BatchMovementDialog.show(context, category, items);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: items.map((item) {
              final isOut = item.status == "out";
              return InkWell(
                onTap: () => CheckInOutDialog.show(context, item),
                onLongPress: () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (context) => InventoryDetailView(item: item),
                  ));
                },
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isOut ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      )
                    ]
                  ),
                  child: Text(
                    item.materialNumber.isNotEmpty ? item.materialNumber : '-',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Lager: $inStockCount", style: const TextStyle(fontSize: 12, color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
              Text("Out: $outCount", style: const TextStyle(fontSize: 12, color: Color(0xFFEF4444), fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTodoCard(String title, String subtitle, IconData icon, TodoType type) {
    Color bgColor, borderColor, iconBgColor, iconColor, titleColor, subtitleColor;
    
    switch (type) {
      case TodoType.pastDue:
        bgColor = const Color(0xFFFEF2F2);
        borderColor = const Color(0xFFFECACA);
        iconBgColor = const Color(0xFFFEE2E2);
        iconColor = const Color(0xFFEF4444);
        titleColor = const Color(0xFF991B1B);
        subtitleColor = const Color(0xFFB91C1C);
        break;
      case TodoType.dueSoon:
        bgColor = const Color(0xFFFEFCE8);
        borderColor = const Color(0xFFFEF08A);
        iconBgColor = const Color(0xFFFEF9C3);
        iconColor = const Color(0xFFEAB308);
        titleColor = const Color(0xFF854D0E);
        subtitleColor = const Color(0xFFA16207);
        break;
      case TodoType.ticket:
        bgColor = const Color(0xFFFFF7ED);
        borderColor = const Color(0xFFFED7AA);
        iconBgColor = const Color(0xFFFFEDD5);
        iconColor = const Color(0xFFF97316);
        titleColor = const Color(0xFF9A3412);
        subtitleColor = const Color(0xFFC2410C);
        break;
      case TodoType.ok:
      default:
        bgColor = Colors.white;
        borderColor = const Color(0xFFE0F2FE);
        iconBgColor = const Color(0xFFE0F2FE);
        iconColor = const Color(0xFF0284C7);
        titleColor = const Color(0xFF0F172A);
        subtitleColor = const Color(0xFF64748B);
    }

    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: titleColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: subtitleColor,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
