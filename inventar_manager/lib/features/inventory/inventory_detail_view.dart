import 'package:flutter/material.dart';
import 'package:inventar_manager/core/services/item_service.dart';
import 'package:inventar_manager/core/services/transaction_service.dart';
import 'package:inventar_manager/core/services/category_service.dart';
import 'package:inventar_manager/features/inventory/service_check_view.dart';
import 'package:inventar_manager/features/inventory/trouble_ticket_view.dart';
import 'package:inventar_manager/features/inventory/check_in_out_dialog.dart';
import 'package:inventar_manager/features/inventory/trouble_ticket_resolve_dialog.dart';
import 'package:inventar_manager/core/services/database_service.dart';
import 'package:inventar_manager/core/appwrite_config.dart';
import 'package:inventar_manager/core/services/auth_service.dart';
import 'package:inventar_manager/core/theme.dart';
import 'package:inventar_manager/core/widgets/ui_primitives.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';

class InventoryDetailView extends StatefulWidget {
  final ItemModel item;

  const InventoryDetailView({super.key, required this.item});

  @override
  State<InventoryDetailView> createState() => _InventoryDetailViewState();
}

class _InventoryDetailViewState extends State<InventoryDetailView> {
  final TransactionService _transactionService = TransactionService();
  final CategoryService _categoryService = CategoryService();
  final ItemService _itemService = ItemService();

  final List<TransactionModel> _transactions = [];
  String _selectedFilter = 'all';

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  void _loadTransactions() async {
    await _transactionService.loadTransactionsForItem(widget.item.id);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _transactionService,
      builder: (context, child) {
        final transactions = _transactionService.transactions;
        final cs = Theme.of(context).colorScheme;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Scaffold(
          appBar: AppBar(
            title: Text(
              "${widget.item.serialNumber} - ${widget.item.materialNumber}",
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Row (Status & Actions)
                SoftCard(
                  padding: const EdgeInsets.all(20),
                  child: Wrap(
                    spacing: 20,
                    runSpacing: 16,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _buildStatusCard(),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _buildActionButton(
                            "Ausgeben / Rücknahme",
                            Icons.sync_alt_rounded,
                            AppTheme.successColor,
                            () {
                              CheckInOutDialog.show(context, widget.item);
                            },
                          ),
                          _buildActionButton(
                            "Service Check",
                            Icons.build_rounded,
                            AppTheme.primaryColor,
                            () {
                              if (widget.item.status == 'out') {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Das Gerät ist ausgelagert. Bitte erst einlagern!',
                                    ),
                                  ),
                                );
                                return;
                              }
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) =>
                                      ServiceCheckView(item: widget.item),
                                ),
                              );
                            },
                          ),
                          _buildActionButton(
                            "Trouble Ticket",
                            Icons.report_problem_rounded,
                            AppTheme.dangerColor,
                            () {
                              if (widget.item.status == 'out') {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Das Gerät ist ausgelagert. Bitte erst einlagern!',
                                    ),
                                  ),
                                );
                                return;
                              }
                              if (widget.item.status == 'defekt' ||
                                  widget.item.status == 'troubleticket') {
                                final openTickets = transactions.where(
                                  (tx) =>
                                      tx.type == 'troubleticket' &&
                                      tx.status == 'offen',
                                );
                                if (openTickets.isNotEmpty) {
                                  TroubleTicketResolveDialog.show(
                                    context,
                                    widget.item,
                                    openTickets.first,
                                  );
                                  return;
                                }
                              }
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) =>
                                      TroubleTicketView(item: widget.item),
                                ),
                              );
                            },
                          ),
                          _buildActionButton(
                            widget.item.isLocked
                                ? "Sperre aufheben"
                                : "Gerät sperren",
                            widget.item.isLocked
                                ? Icons.lock_open_rounded
                                : Icons.lock_rounded,
                            AppTheme.stage1Color,
                            widget.item.status == 'defekt'
                                ? null
                                : () {
                                    if (widget.item.isLocked) {
                                      _unlockItem();
                                    } else {
                                      _showLockItemDialog(context);
                                    }
                                  },
                          ),
                          _buildActionButton(
                            "Löschen",
                            Icons.delete_outline_rounded,
                            AppTheme.textSecondary,
                            () {
                              _showDeleteOptionsDialog(context);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // History Table (Internal Item Moves)
                SoftCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(18.0),
                        child: Text(
                          "Bewegungshistorie",
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      Divider(height: 1, color: cs.outlineVariant),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          return SingleChildScrollView(
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
                                columns: const [
                                  DataColumn(label: Text('Typ')),
                                  DataColumn(label: Text('Nutzer')),
                                  DataColumn(label: Text('Zusatzinfo')),
                                  DataColumn(label: Text('Datum')),
                                  DataColumn(label: Text('Notiz')),
                                ],
                                rows: transactions.isEmpty
                                    ? [
                                        const DataRow(
                                          cells: [
                                            DataCell(
                                              Text('Keine Eintr\u00e4ge'),
                                            ),
                                            DataCell(Text('')),
                                            DataCell(Text('')),
                                            DataCell(Text('')),
                                            DataCell(Text('')),
                                          ],
                                        ),
                                      ]
                                    : transactions
                                          .where((tx) {
                                            if (_selectedFilter == 'all')
                                              return true;
                                            if (_selectedFilter == 'services')
                                              return tx.type ==
                                                      'service_check' ||
                                                  tx.type == 'service';
                                            if (_selectedFilter == 'tickets')
                                              return tx.type ==
                                                      'troubleticket' ||
                                                  tx.type == 'repair';
                                            if (_selectedFilter == 'operations')
                                              return tx.type == 'checkout' ||
                                                  tx.type == 'checkin';
                                            return true;
                                          })
                                          .map((tx) {
                                            final isCheckout =
                                                tx.type == 'checkout';
                                            final isTicket =
                                                tx.type == 'troubleticket';
                                            final isService =
                                                tx.type == 'service_check' ||
                                                tx.type == 'service';
                                            final isServiceLock =
                                                tx.type == 'service_lock' ||
                                                tx.type ==
                                                    'service_lock_resolved';
                                            final isRepair =
                                                tx.type == 'repair';

                                            Color badgeColor = const Color(
                                              0xFF64748B,
                                            ); // default gray
                                            String typeLabel = tx.type;

                                            if (isCheckout) {
                                              badgeColor =
                                                  AppTheme.warningColor;
                                              typeLabel = "Ausgabe";
                                            } else if (tx.type == 'checkin') {
                                              badgeColor =
                                                  AppTheme.successColor;
                                              typeLabel = "Rücknahme";
                                            } else if (isService) {
                                              badgeColor =
                                                  AppTheme.primaryColor;
                                              typeLabel = "Service";
                                            } else if (isTicket) {
                                              badgeColor =
                                                  (tx.status == 'offen')
                                                  ? AppTheme.dangerColor
                                                  : AppTheme.textSecondary;
                                              typeLabel = "Ticket";
                                            } else if (isServiceLock) {
                                              badgeColor = AppTheme.stage1Color;
                                              typeLabel =
                                                  tx.type == 'service_lock'
                                                  ? "Sperre"
                                                  : "Sperre aufg.";
                                            } else if (isRepair) {
                                              badgeColor =
                                                  AppTheme.successColor;
                                              typeLabel = "Reparatur";
                                            }

                                            Widget detailsWidget = const Text(
                                              '-',
                                            );
                                            if (tx.details != null &&
                                                tx.details!.isNotEmpty) {
                                              if (isService) {
                                                try {
                                                  final data = jsonDecode(
                                                    tx.details!,
                                                  );
                                                  if (data['type'] == 'pdf' &&
                                                      data['fileId'] != null) {
                                                    detailsWidget = Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        const Icon(
                                                          Icons.picture_as_pdf,
                                                          color: Color(
                                                            0xFFEF4444,
                                                          ),
                                                          size: 16,
                                                        ),
                                                        const SizedBox(
                                                          width: 4,
                                                        ),
                                                        Text(
                                                          data['fileName'] ??
                                                              'PDF Dokument',
                                                        ),
                                                        const SizedBox(
                                                          width: 8,
                                                        ),
                                                        TextButton(
                                                          onPressed: () async {
                                                            final baseUrl = DatabaseService()
                                                                .getFileViewUrl(
                                                                  AppwriteConfig
                                                                      .serviceProofsBucketId,
                                                                  data['fileId'],
                                                                );
                                                            final jwt =
                                                                await AuthService()
                                                                    .getJWT();
                                                            final url =
                                                                jwt != null
                                                                ? "$baseUrl&jwt=$jwt"
                                                                : baseUrl;
                                                            if (await canLaunchUrl(
                                                              Uri.parse(url),
                                                            )) {
                                                              await launchUrl(
                                                                Uri.parse(url),
                                                                mode: LaunchMode
                                                                    .externalApplication,
                                                              );
                                                            } else {
                                                              ScaffoldMessenger.of(
                                                                context,
                                                              ).showSnackBar(
                                                                const SnackBar(
                                                                  content: Text(
                                                                    'Konnte Datei nicht öffnen.',
                                                                  ),
                                                                ),
                                                              );
                                                            }
                                                          },
                                                          style: TextButton.styleFrom(
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal: 8,
                                                                  vertical: 4,
                                                                ),
                                                            minimumSize:
                                                                Size.zero,
                                                            tapTargetSize:
                                                                MaterialTapTargetSize
                                                                    .shrinkWrap,
                                                          ),
                                                          child: const Text(
                                                            'Ansehen',
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    );
                                                  } else if (data['checkType'] !=
                                                      null) {
                                                    detailsWidget = Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Text(
                                                          "Formular: ${data['checkType']}",
                                                        ),
                                                        const SizedBox(
                                                          width: 8,
                                                        ),
                                                        TextButton(
                                                          onPressed: () =>
                                                              _showServiceDetailsDialog(
                                                                context,
                                                                data,
                                                              ),
                                                          style: TextButton.styleFrom(
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal: 8,
                                                                  vertical: 4,
                                                                ),
                                                            minimumSize:
                                                                Size.zero,
                                                            tapTargetSize:
                                                                MaterialTapTargetSize
                                                                    .shrinkWrap,
                                                          ),
                                                          child: const Text(
                                                            'Protokoll ansehen',
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    );
                                                  } else {
                                                    detailsWidget = Text(
                                                      tx.details!,
                                                    );
                                                  }
                                                } catch (e) {
                                                  detailsWidget = Text(
                                                    tx.details!,
                                                  );
                                                }
                                              } else {
                                                detailsWidget = Text(
                                                  tx.details!,
                                                );
                                              }
                                            }

                                            return DataRow(
                                              onSelectChanged:
                                                  (isTicket &&
                                                      tx.status == 'offen')
                                                  ? (selected) {
                                                      if (selected == true) {
                                                        TroubleTicketResolveDialog.show(
                                                          context,
                                                          widget.item,
                                                          tx,
                                                        );
                                                      }
                                                    }
                                                  : null,
                                              cells: [
                                                DataCell(
                                                  _buildTypeBadge(
                                                    typeLabel,
                                                    badgeColor,
                                                  ),
                                                ),
                                                DataCell(Text(tx.initiator)),
                                                DataCell(
                                                  Text(
                                                    tx.captureMethod.isNotEmpty
                                                        ? tx.captureMethod
                                                        : '-',
                                                  ),
                                                ),
                                                DataCell(
                                                  Text(
                                                    DateFormat(
                                                      'dd.MM.yyyy HH:mm',
                                                    ).format(tx.date),
                                                  ),
                                                ),
                                                DataCell(detailsWidget),
                                              ],
                                            );
                                          })
                                          .toList(),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusCard() {
    final catName =
        _categoryService.categories
            .where((c) => c.id == widget.item.categoryId)
            .firstOrNull
            ?.name ??
        'Unbekannt';

    int daysInOperation = 0;

    // We'll calculate unique calendar days the item was in operation
    final Set<String> uniqueOperationDays = {};

    DateTime? lastCheckout;
    // Iterate chronologically (reversed since list is descending)
    for (final tx in _transactionService.transactions.reversed) {
      if (tx.type == 'checkout') {
        lastCheckout = tx.date;
      } else if (tx.type == 'checkin' && lastCheckout != null) {
        // Add all days from lastCheckout to tx.date
        final start = DateTime(
          lastCheckout.year,
          lastCheckout.month,
          lastCheckout.day,
        );
        final end = DateTime(tx.date.year, tx.date.month, tx.date.day);
        for (int i = 0; i <= end.difference(start).inDays; i++) {
          final currentDay = start.add(Duration(days: i));
          uniqueOperationDays.add(
            '${currentDay.year}-${currentDay.month}-${currentDay.day}',
          );
        }
        lastCheckout = null;
      }
    }

    // If it's currently checked out, calculate days until today
    if (lastCheckout != null) {
      final start = DateTime(
        lastCheckout.year,
        lastCheckout.month,
        lastCheckout.day,
      );
      final end = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
      );
      for (int i = 0; i <= end.difference(start).inDays; i++) {
        final currentDay = start.add(Duration(days: i));
        uniqueOperationDays.add(
          '${currentDay.year}-${currentDay.month}-${currentDay.day}',
        );
      }
    }

    daysInOperation = uniqueOperationDays.length;

    int troubleTickets = _transactionService.transactions
        .where((t) => t.type == 'troubleticket')
        .length;
    int services = _transactionService.transactions
        .where((t) => t.type == 'service_check' || t.type == 'service')
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const TintedIconBadge(
              icon: Icons.inventory_2_outlined,
              size: 48,
              iconSize: 26,
              radius: 14,
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Kategorie: $catName",
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Text(
                      "Status: ",
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    StatusPill(
                      label: widget.item.status == 'in_stock'
                          ? 'Lager'
                          : widget.item.status,
                      foreground: widget.item.status == 'in_stock'
                          ? AppTheme.successColor
                          : AppTheme.warningColor,
                      background: widget.item.status == 'in_stock'
                          ? AppTheme.successBg
                          : AppTheme.warningBg,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _buildCounterBadge(
              "Tage in Betrieb",
              daysInOperation.toString(),
              Icons.access_time_rounded,
              'operations',
            ),
            _buildCounterBadge(
              "Services",
              services.toString(),
              Icons.build_rounded,
              'services',
            ),
            _buildCounterBadge(
              "Trouble Tickets",
              troubleTickets.toString(),
              Icons.report_problem_rounded,
              'tickets',
            ),
            if (_selectedFilter != 'all')
              InkWell(
                onTap: () => setState(() => _selectedFilter = 'all'),
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    "Filter löschen",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildCounterBadge(
    String label,
    String value,
    IconData icon,
    String filterKey,
  ) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = _selectedFilter == filterKey;
    return InkWell(
      onTap: () =>
          setState(() => _selectedFilter = isSelected ? 'all' : filterKey),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? cs.primary.withValues(alpha: 0.12)
              : cs.surface,
          border: Border.all(
            color: isSelected ? cs.primary : cs.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? cs.primary : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text(
              "$value $label",
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: isSelected ? cs.primary : cs.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(
    String label,
    IconData icon,
    Color color,
    VoidCallback? onTap,
  ) {
    return FilledButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 17),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: color,
        disabledBackgroundColor: color.withValues(alpha: 0.45),
        disabledForegroundColor: Colors.white70,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildTypeBadge(String text, Color color) {
    return StatusPill(
      label: text,
      foreground: color,
      background: color.withValues(alpha: 0.14),
    );
  }

  void _showServiceDetailsDialog(
    BuildContext context,
    Map<String, dynamic> data,
  ) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text(
            "Service Protokoll",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildServiceDetailRow("Art des Checks", data['checkType']),
                _buildServiceDetailRow("Prüfer", data['inspector']),
                if (data['dry'] != null)
                  _buildServiceDetailRow("Weste getrocknet", data['dry']),
                if (data['funcTest'] != null)
                  _buildServiceDetailRow("Funktion", data['funcTest']),
                const Divider(),
                _buildServiceDetailRow("DOM CO2 Kartusche", data['domCo2']),
                _buildServiceDetailRow("Min-Gewicht", "${data['minWeight']} g"),
                _buildServiceDetailRow("Ist-Gewicht", "${data['istWeight']} g"),
                _buildServiceDetailRow(
                  "Ablaufdatum Automatik",
                  data['expAuto'],
                ),
                const Divider(),
                _buildServiceDetailRow(
                  "Siegel man. Auslösung",
                  data['sealMan'],
                ),
                _buildServiceDetailRow(
                  "Siegel autom. Auslösung",
                  data['sealAuto'],
                ),
                _buildServiceDetailRow("Drucktest", data['pressure']),
                const Divider(),
                _buildServiceDetailRow("Sicherungstyp", data['triggerType']),
                _buildServiceDetailRow(
                  "Sicherung Zustand",
                  data['triggerState'],
                ),
                _buildServiceDetailRow("Korrekt gepackt", data['packed']),
                _buildServiceDetailRow("Gesamtzustand", data['condition']),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Schließen"),
            ),
          ],
        );
      },
    );
  }

  Widget _buildServiceDetailRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value?.toString() ?? "-",
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteOptionsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Gegenstand löschen"),
        content: const Text("Wie möchtest du den Gegenstand löschen?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              "Abbrechen",
              style: TextStyle(color: Color(0xFF64748B)),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _disposeItem();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF59E0B),
            ),
            child: const Text(
              "Entsorgen",
              style: TextStyle(color: Colors.white),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _itemService.deleteItem(widget.item.id);
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        "Gegenstand endgültig gelöscht",
                        style: TextStyle(color: Colors.white),
                      ),
                      backgroundColor: Color(0xFF10B981),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text("Fehler: $e")));
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            child: const Text("Löschen", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _unlockItem() async {
    try {
      await _itemService.unlockItem(widget.item.id);

      final tx = TransactionModel(
        id: '',
        schoolId: widget.item.schoolId,
        itemId: widget.item.id,
        type: 'service_lock_resolved',
        status: 'closed',
        initiator: 'System', // Could use actual user
        captureMethod: 'manual',
        details: 'Manuelle Sperre aufgehoben',
        date: DateTime.now(),
      );
      await _transactionService.addTransaction(tx);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Sperre erfolgreich aufgehoben",
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Color(0xFF10B981),
          ),
        );
        setState(() {}); // refresh view
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Fehler: $e")));
      }
    }
  }

  void _showLockItemDialog(BuildContext context) {
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("Gerät sperren"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Bitte gib einen Grund für die Sperre an (z.B. Service notwendig):",
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(
                  labelText: "Grund",
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Abbrechen"),
            ),
            ElevatedButton(
              onPressed: () async {
                if (reasonController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text("Bitte einen Grund eingeben")),
                  );
                  return;
                }
                Navigator.pop(ctx);
                await _lockItem(reasonController.text.trim());
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF9333EA),
              ),
              child: const Text(
                "Sperren",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _lockItem(String reason) async {
    try {
      await _itemService.lockItem(widget.item.id, reason);

      final tx = TransactionModel(
        id: '',
        schoolId: widget.item.schoolId,
        itemId: widget.item.id,
        type: 'service_lock',
        status: 'closed',
        initiator: 'System',
        captureMethod: 'manual',
        details: 'Gesperrt: $reason',
        date: DateTime.now(),
      );
      await _transactionService.addTransaction(tx);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Gerät erfolgreich gesperrt",
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Color(0xFF9333EA),
          ),
        );
        setState(() {}); // refresh view
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Fehler beim Sperren: $e")));
      }
    }
  }

  Future<void> _disposeItem() async {
    try {
      final tx = TransactionModel(
        id: '',
        schoolId: widget.item.schoolId,
        itemId: widget.item.id,
        type: 'repair',
        status: 'closed',
        initiator: 'System',
        captureMethod: 'manual',
        details: 'Gegenstand entsorgt',
        date: DateTime.now(),
      );
      await _transactionService.addTransaction(tx);
      await _transactionService.closeOpenCheckout(widget.item.id);

      widget.item.status = 'disposed';
      await _itemService.updateItem(widget.item);

      if (mounted) {
        Navigator.pop(context); // Go back to dashboard
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Gegenstand erfolgreich entsorgt",
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Fehler: $e")));
      }
    }
  }

  void _showHardDeleteConfirmDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Wirklich hart löschen?"),
        content: const Text(
          "Diese Aktion kann nicht rückgängig gemacht werden. Alle Daten dieses Gegenstands gehen verloren.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              "Abbrechen",
              style: TextStyle(color: Color(0xFF64748B)),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _hardDeleteItem();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            child: const Text(
              "Ja, unwiderruflich löschen",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _hardDeleteItem() async {
    try {
      await _itemService.deleteItem(widget.item.id);
      if (mounted) {
        Navigator.pop(context); // Go back to dashboard
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Gegenstand endgültig gelöscht",
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Fehler: $e")));
      }
    }
  }
}
