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
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';

class InventoryDetailView extends StatefulWidget {
  final ItemModel item;

  const InventoryDetailView({Key? key, required this.item}) : super(key: key);

  @override
  State<InventoryDetailView> createState() => _InventoryDetailViewState();
}

class _InventoryDetailViewState extends State<InventoryDetailView> {
  final TransactionService _transactionService = TransactionService();
  final CategoryService _categoryService = CategoryService();
  final ItemService _itemService = ItemService();
  
  List<TransactionModel> _transactions = [];
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
        final _transactions = _transactionService.transactions;
        return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9), // Match list view background
      appBar: AppBar(
        title: Text(
          "${widget.item.serialNumber} - ${widget.item.materialNumber}",
          style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A), fontSize: 18),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(
            color: const Color(0xFFE2E8F0),
            height: 1.0,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Row (Status & Actions)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildStatusCard(),
                    Wrap(
                      spacing: 12,
                      children: [
                        _buildActionButton(
                          "Ausgeben / R\u00fccknahme",
                          Icons.sync_alt_rounded,
                          const Color(0xFF10B981),
                          () {
                            CheckInOutDialog.show(context, widget.item);
                          },
                        ),
                        _buildActionButton(
                          "Service Check",
                          Icons.build_rounded,
                          const Color(0xFF3B82F6),
                          () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => ServiceCheckView(item: widget.item),
                              ),
                            );
                          },
                        ),
                          _buildActionButton(
                            "Trouble Ticket",
                            Icons.report_problem_rounded,
                            const Color(0xFFEF4444),
                            () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => TroubleTicketView(item: widget.item),
                                ),
                              );
                            },
                          ),
                          _buildActionButton(
                            "L\u00f6schen",
                            Icons.delete,
                            const Color(0xFF94A3B8),
                            () {
                              _showDeleteOptionsDialog(context);
                            },
                          ),
                      ],
                    )
                  ],
                ),
                const SizedBox(height: 32),
                
                // History Table (Internal Item Moves)
                Container(
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
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text(
                          "Bewegungshistorie",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF334155),
                          ),
                        ),
                      ),
                      const Divider(height: 1, color: Color(0xFFE2E8F0)),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          return SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(minWidth: constraints.maxWidth),
                              child: DataTable(
                          headingRowColor: MaterialStateProperty.all(const Color(0xFFF8FAFC)),
                          columns: const [
                            DataColumn(label: Text('Typ')),
                            DataColumn(label: Text('Nutzer')),
                            DataColumn(label: Text('Zusatzinfo')),
                            DataColumn(label: Text('Datum')),
                            DataColumn(label: Text('Notiz')),
                          ],
                          rows: _transactions.isEmpty 
                              ? [
                                  const DataRow(cells: [
                                    DataCell(Text('Keine Eintr\u00e4ge')),
                                    DataCell(Text('')),
                                    DataCell(Text('')),
                                    DataCell(Text('')),
                                    DataCell(Text('')),
                                  ])
                                ]
                              : _transactions.where((tx) {
                                  if (_selectedFilter == 'all') return true;
                                  if (_selectedFilter == 'services') return tx.type == 'service_check' || tx.type == 'service';
                                  if (_selectedFilter == 'tickets') return tx.type == 'troubleticket';
                                  if (_selectedFilter == 'operations') return tx.type == 'checkout' || tx.type == 'checkin';
                                  return true;
                                }).map((tx) {
                                  final isCheckout = tx.type == 'checkout';
                                  final isTicket = tx.type == 'troubleticket';
                                  final isService = tx.type == 'service_check' || tx.type == 'service';
                                  
                                  Color badgeColor = const Color(0xFF64748B); // default gray
                                  if (isCheckout) badgeColor = const Color(0xFFF59E0B);
                                  else if (tx.type == 'checkin') badgeColor = const Color(0xFF10B981);
                                  else if (isService) badgeColor = const Color(0xFF3B82F6);
                                  else if (isTicket) {
                                    badgeColor = (tx.status == 'offen') ? const Color(0xFFEF4444) : const Color(0xFF64748B);
                                  }
                                  
                                  Widget detailsWidget = const Text('-');
                                  if (tx.details != null && tx.details!.isNotEmpty) {
                                    if (isService) {
                                      try {
                                        final data = jsonDecode(tx.details!);
                                        if (data['type'] == 'pdf' && data['fileId'] != null) {
                                          detailsWidget = Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.picture_as_pdf, color: Color(0xFFEF4444), size: 16),
                                              const SizedBox(width: 4),
                                              Text(data['fileName'] ?? 'PDF Dokument'),
                                              const SizedBox(width: 8),
                                              TextButton(
                                                onPressed: () async {
                                                  final url = DatabaseService().getFileViewUrl(AppwriteConfig.serviceProofsBucketId, data['fileId']);
                                                  if (await canLaunchUrl(Uri.parse(url))) {
                                                    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                                                  } else {
                                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Konnte Datei nicht öffnen.')));
                                                  }
                                                },
                                                style: TextButton.styleFrom(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  minimumSize: Size.zero,
                                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                ),
                                                child: const Text('Ansehen', style: TextStyle(fontSize: 12)),
                                              )
                                            ],
                                          );
                                        } else if (data['checkType'] != null) {
                                          detailsWidget = Text("Formular: ${data['checkType']}");
                                        } else {
                                          detailsWidget = Text(tx.details!);
                                        }
                                      } catch (e) {
                                        detailsWidget = Text(tx.details!);
                                      }
                                    } else {
                                      detailsWidget = Text(tx.details!);
                                    }
                                  }
                                  
                                  return DataRow(
                                    onSelectChanged: (isTicket && tx.status == 'offen') ? (selected) {
                                      if (selected == true) {
                                        TroubleTicketResolveDialog.show(context, widget.item, tx);
                                      }
                                    } : null,
                                    cells: [
                                      DataCell(_buildTypeBadge(tx.type, badgeColor)),
                                      DataCell(Text(tx.initiator)),
                                      DataCell(Text(tx.captureMethod.isNotEmpty ? tx.captureMethod : '-')),
                                      DataCell(Text(DateFormat('dd.MM.yyyy HH:mm').format(tx.date))),
                                      DataCell(detailsWidget),
                                    ],
                                  );
                                }).toList(),
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
    final catName = _categoryService.categories.where((c) => c.id == widget.item.categoryId).firstOrNull?.name ?? 'Unbekannt';
    
    int daysInOperation = 0;
    DateTime? lastCheckout;
    // Transactions are descending, so reversed is chronological
    for(final tx in _transactionService.transactions.reversed) {
      if (tx.type == 'checkout') {
        lastCheckout = tx.date;
      } else if (tx.type == 'checkin' && lastCheckout != null) {
        daysInOperation += tx.date.difference(lastCheckout).inDays;
        lastCheckout = null;
      }
    }
    if (lastCheckout != null) {
      daysInOperation += DateTime.now().difference(lastCheckout).inDays;
    }

    int troubleTickets = _transactionService.transactions.where((t) => t.type == 'troubleticket').length;
    int services = _transactionService.transactions.where((t) => t.type == 'service_check' || t.type == 'service').length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.inventory_2_outlined, size: 32, color: Color(0xFF3B82F6)),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Kategorie: $catName",
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Text("Status: ", style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(
                      widget.item.status == 'in_stock' ? 'Lager' : widget.item.status,
                      style: TextStyle(
                        color: widget.item.status == 'in_stock' ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                )
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _buildCounterBadge("Tage in Betrieb", daysInOperation.toString(), Icons.access_time, 'operations'),
            _buildCounterBadge("Services", services.toString(), Icons.build, 'services'),
            _buildCounterBadge("Trouble Tickets", troubleTickets.toString(), Icons.report_problem, 'tickets'),
            if (_selectedFilter != 'all')
              InkWell(
                onTap: () => setState(() => _selectedFilter = 'all'),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text("Filter l\u00f6schen", style: TextStyle(fontSize: 12, color: Color(0xFF334155))),
                ),
              ),
          ],
        )
      ],
    );
  }

  Widget _buildCounterBadge(String label, String value, IconData icon, String filterKey) {
    final isSelected = _selectedFilter == filterKey;
    return InkWell(
      onTap: () => setState(() => _selectedFilter = isSelected ? 'all' : filterKey),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF3B82F6).withOpacity(0.1) : Colors.white,
          border: Border.all(color: isSelected ? const Color(0xFF3B82F6) : const Color(0xFFE2E8F0)),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            if (!isSelected)
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 4,
                offset: const Offset(0, 1),
              )
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isSelected ? const Color(0xFF3B82F6) : const Color(0xFF64748B)),
            const SizedBox(width: 8),
            Text(
              "$value $label",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: isSelected ? const Color(0xFF3B82F6) : const Color(0xFF334155),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(String label, IconData icon, Color color, VoidCallback onTap) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildTypeBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 12),
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
            child: const Text("Abbrechen", style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _disposeItem();
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF59E0B)),
            child: const Text("Entsorgen", style: TextStyle(color: Colors.white)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showHardDeleteConfirmDialog(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            child: const Text("Hart Löschen", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
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
          const SnackBar(content: Text("Gegenstand erfolgreich entsorgt", style: TextStyle(color: Colors.white)), backgroundColor: Color(0xFF10B981)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Fehler: $e")),
        );
      }
    }
  }

  void _showHardDeleteConfirmDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Wirklich hart löschen?"),
        content: const Text("Diese Aktion kann nicht rückgängig gemacht werden. Alle Daten dieses Gegenstands gehen verloren."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Abbrechen", style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _hardDeleteItem();
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            child: const Text("Ja, unwiderruflich löschen", style: TextStyle(color: Colors.white)),
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
          const SnackBar(content: Text("Gegenstand endgültig gelöscht", style: TextStyle(color: Colors.white)), backgroundColor: Color(0xFF10B981)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Fehler: $e")),
        );
      }
    }
  }
}
