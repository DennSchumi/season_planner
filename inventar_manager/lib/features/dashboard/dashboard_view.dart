import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:inventar_manager/core/services/category_service.dart';
import 'package:inventar_manager/core/services/item_service.dart';
import 'package:inventar_manager/core/theme.dart';
import 'package:inventar_manager/core/widgets/ui_primitives.dart';
import 'package:inventar_manager/features/inventory/inventory_detail_view.dart';
import 'package:inventar_manager/features/inventory/check_in_out_dialog.dart';
import 'package:inventar_manager/features/inventory/batch_movement_dialog.dart';
import 'package:inventar_manager/features/dashboard/item_swap_dialog.dart';
import 'package:inventar_manager/core/services/transaction_service.dart';

enum TodoType { ok, dueSoon, pastDue, ticket, locked }

class DashboardView extends StatefulWidget {
  const DashboardView({super.key});

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
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
                Text(
                  "Kategorien",
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        ItemSwapDialog.show(
                          context,
                          _categoryService,
                          _itemService,
                        );
                      },
                      icon: const Icon(Icons.swap_horiz_rounded, size: 19),
                      label: const Text("Tauschen"),
                    ),
                    PopupMenuButton<String>(
                      icon: Icon(
                        Icons.filter_list_rounded,
                        color: cs.onSurfaceVariant,
                      ),
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
            if (_categoryService.errorMessage != null ||
                _itemService.errorMessage != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppTheme.dangerColor.withValues(alpha: 0.16)
                      : AppTheme.dangerBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: AppTheme.dangerColor,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _categoryService.errorMessage ??
                            _itemService.errorMessage ??
                            "",
                        style: const TextStyle(color: AppTheme.dangerColor),
                      ),
                    ),
                  ],
                ),
              ),
            categories.isEmpty
                ? SoftCard(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      children: [
                        const TintedIconBadge(
                          icon: Icons.inbox_outlined,
                          size: 52,
                          iconSize: 26,
                          radius: 16,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "Keine Kategorien vorhanden",
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "Lege deine erste Kategorie in den Einstellungen an, um Gegenstände hinzuzufügen.",
                          style: TextStyle(color: cs.onSurfaceVariant),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () {
                            Navigator.pushReplacementNamed(
                              context,
                              '/settings',
                            );
                          },
                          icon: const Icon(Icons.settings_rounded, size: 18),
                          label: const Text("Zu den Einstellungen"),
                        ),
                      ],
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      // Make cards larger by reducing columns
                      int crossAxisCount = constraints.maxWidth > 1400
                          ? 3
                          : constraints.maxWidth > 900
                          ? 2
                          : 1;
                      double spacing = 16.0;
                      double width =
                          (constraints.maxWidth -
                              (spacing * (crossAxisCount - 1))) /
                          crossAxisCount;

                      return Wrap(
                        spacing: spacing,
                        runSpacing: spacing,
                        children: categories
                            .where((c) => !_hiddenCategories.contains(c.name))
                            .map((c) {
                              final catItems = items
                                  .where(
                                    (i) =>
                                        i.categoryId == c.id &&
                                        i.status != 'disposed',
                                  )
                                  .toList();
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

        Widget sidebarContent = SoftCard(
          padding: const EdgeInsets.all(18.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const TintedIconBadge(
                    icon: Icons.checklist_rtl_rounded,
                    size: 36,
                    iconSize: 19,
                    radius: 10,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    "To-Do Liste",
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
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
                    if (i.status == 'disposed' || i.nextServiceDate == null) {
                      return false;
                    }
                    return i.nextServiceDate!.isBefore(dueThreshold);
                  }).toList();

                  final ticketWidgets = _openTickets
                      .where(
                        (ticket) => items.any((i) => i.id == ticket.itemId),
                      )
                      .map((ticket) {
                        final item = items.firstWhere(
                          (i) => i.id == ticket.itemId,
                        );
                        final itemName =
                            "${item.name} (${item.materialNumber})";
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: InkWell(
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) =>
                                      InventoryDetailView(item: item),
                                ),
                              );
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
                      })
                      .toList();

                  final ticketItemIds = _openTickets
                      .map((t) => t.itemId)
                      .toSet();

                  final lockedItemsWidgets = items
                      .where((i) => i.isLocked && !ticketItemIds.contains(i.id))
                      .map((item) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: InkWell(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) =>
                                      InventoryDetailView(item: item),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: _buildTodoCard(
                              "${item.name} (${item.materialNumber})",
                              item.lockReason ?? "Manuell gesperrt",
                              Icons.lock_rounded,
                              TodoType.locked,
                            ),
                          ),
                        );
                      })
                      .toList();

                  final dueServiceWidgets = dueItems.map((item) {
                    final isPastDue = item.nextServiceDate!.isBefore(now);
                    final daysRemaining = item.nextServiceDate!
                        .difference(now)
                        .inDays;
                    final subtitle = isPastDue
                        ? "Überfällig seit ${-daysRemaining} Tagen"
                        : "Fällig in $daysRemaining Tagen";

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) =>
                                  InventoryDetailView(item: item),
                            ),
                          );
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

                  if (ticketWidgets.isEmpty &&
                      dueServiceWidgets.isEmpty &&
                      lockedItemsWidgets.isEmpty) {
                    return _buildTodoCard(
                      "Keine Services oder Tickets",
                      "Alles in Ordnung",
                      Icons.check_circle_outline_rounded,
                      TodoType.ok,
                    );
                  }

                  return Column(
                    children: [
                      ...lockedItemsWidgets,
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
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Übersicht",
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 20),

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
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    int outCount = items.where((i) => i.status == "out").length;
    int inStockCount = items.length - outCount;

    return SoftCard(
      padding: const EdgeInsets.all(18.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppTheme.primaryColor.withValues(alpha: 0.18)
                      : AppTheme.primaryTint,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: category.buildIcon(
                  color: isDark ? AppTheme.darkPrimary : AppTheme.primaryColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  category.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                    fontSize: 16,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.library_add_check_outlined,
                  color: cs.onSurfaceVariant,
                ),
                tooltip: "Sammelbewegung",
                onPressed: () {
                  BatchMovementDialog.show(context, category, items);
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: items.map((item) {
              final isOut = item.status == "out";
              final hasOpenTicket = _openTickets.any(
                (t) => t.itemId == item.id,
              );
              return InkWell(
                onTap: () => CheckInOutDialog.show(context, item),
                onLongPress: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => InventoryDetailView(item: item),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: hasOpenTicket
                      ? BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 3,
                              offset: const Offset(0, 1),
                            ),
                          ],
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment(0.4, 0.4),
                            tileMode: TileMode.repeated,
                            colors: [
                              AppTheme.dangerColor,
                              AppTheme.dangerColor,
                              Colors.white,
                              Colors.white,
                            ],
                            stops: [0.0, 0.5, 0.5, 1.0],
                          ),
                        )
                      : BoxDecoration(
                          color: item.isLocked
                              ? AppTheme.stage1Color
                              : (isOut
                                    ? AppTheme.dangerColor
                                    : AppTheme.successColor),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 3,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                  child: Text(
                    item.materialNumber.isNotEmpty ? item.materialNumber : '-',
                    style: TextStyle(
                      color: hasOpenTicket ? Colors.black : Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      shadows: hasOpenTicket
                          ? [
                              const Shadow(color: Colors.white, blurRadius: 4),
                            ]
                          : null,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              StatusPill(
                label: "Lager: $inStockCount",
                foreground: AppTheme.successColor,
                background: AppTheme.successBg,
              ),
              StatusPill(
                label: "Out: $outCount",
                foreground: AppTheme.dangerColor,
                background: AppTheme.dangerBg,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTodoCard(
    String title,
    String subtitle,
    IconData icon,
    TodoType type,
  ) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Color accent;
    Color lightBg;

    switch (type) {
      case TodoType.pastDue:
        accent = AppTheme.dangerColor;
        lightBg = AppTheme.dangerBg;
        break;
      case TodoType.dueSoon:
        accent = AppTheme.warningColor;
        lightBg = AppTheme.warningBg;
        break;
      case TodoType.ticket:
        accent = const Color(0xFFEA580C);
        lightBg = const Color(0xFFFFEDD5);
        break;
      case TodoType.locked:
        accent = AppTheme.stage1Color;
        lightBg = AppTheme.stage1Bg;
        break;
      case TodoType.ok:
        accent = AppTheme.successColor;
        lightBg = AppTheme.successBg;
        break;
    }

    final bgColor = isDark
        ? accent.withValues(alpha: 0.14)
        : lightBg.withValues(alpha: 0.55);
    final fgAccent = isDark
        ? Color.lerp(accent, Colors.white, 0.35) ?? accent
        : accent;

    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14.0),
        border: Border.all(color: accent.withValues(alpha: isDark ? 0.3 : 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TintedIconBadge(
            icon: icon,
            iconColor: accent,
            backgroundColor: lightBg,
            size: 36,
            iconSize: 18,
            radius: 10,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: type == TodoType.ok ? cs.onSurfaceVariant : fgAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
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
