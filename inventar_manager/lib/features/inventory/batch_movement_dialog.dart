import 'package:flutter/material.dart';
import 'package:inventar_manager/core/services/category_service.dart';
import 'package:inventar_manager/core/services/item_service.dart';
import 'package:inventar_manager/core/services/transaction_service.dart';
import 'package:inventar_manager/core/services/auth_service.dart';
import 'package:inventar_manager/core/theme.dart';

class BatchMovementDialog extends StatefulWidget {
  final CategoryModel category;
  final List<ItemModel> items;

  const BatchMovementDialog({
    super.key,
    required this.category,
    required this.items,
  });

  static Future<void> show(
    BuildContext context,
    CategoryModel category,
    List<ItemModel> items,
  ) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          BatchMovementDialog(category: category, items: items),
    );
  }

  @override
  State<BatchMovementDialog> createState() => _BatchMovementDialogState();
}

class _BatchMovementDialogState extends State<BatchMovementDialog> {
  String _selectedAction = 'Auslagerung';
  final Set<String> _selectedItemIds = {};
  final TextEditingController _commentController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _lockReasonController = TextEditingController();
  bool _isLoading = false;
  bool _lockAfterCheckIn = false;

  @override
  void dispose() {
    _commentController.dispose();
    _nameController.dispose();
    _lockReasonController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedItemIds.isEmpty) return;

    final isCheckout = _selectedAction == 'Auslagerung';

    if (!isCheckout &&
        _lockAfterCheckIn &&
        _lockReasonController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte gib einen Grund für die Sperre ein!'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final transactionService = TransactionService();
      final itemService = ItemService();
      final user = await AuthService().getCurrentUser();
      final currentUserName = user?.name ?? "Unbekannt";
      final initiator = _nameController.text.trim().isNotEmpty
          ? _nameController.text.trim()
          : currentUserName;

      final isCheckout = _selectedAction == 'Auslagerung';

      for (final itemId in _selectedItemIds) {
        final item = widget.items.firstWhere((i) => i.id == itemId);
        final oldStatus = item.status;

        try {
          if (isCheckout) {
            final tx = TransactionModel(
              id: '',
              schoolId: item.schoolId,
              itemId: item.id,
              type: 'checkout',
              status: 'open',
              initiator: initiator,
              captureMethod: 'manual',
              details: _commentController.text.trim(),
              date: DateTime.now(),
            );
            final txResult = await transactionService.addTransaction(tx);
            if (txResult == null)
              throw Exception(
                "Transaktion für ${item.materialNumber} fehlgeschlagen",
              );

            item.status = 'out';
            final updateSuccess = await itemService.updateItem(item);
            if (!updateSuccess)
              throw Exception(
                "Update für ${item.materialNumber} fehlgeschlagen",
              );
          } else {
            final tx = TransactionModel(
              id: '',
              schoolId: item.schoolId,
              itemId: item.id,
              type: 'checkin',
              status: 'closed',
              initiator: initiator,
              captureMethod: 'manual',
              details: _commentController.text.trim(),
              date: DateTime.now(),
            );
            final txResult = await transactionService.addTransaction(tx);
            if (txResult == null)
              throw Exception(
                "Transaktion für ${item.materialNumber} fehlgeschlagen",
              );
            await transactionService.closeOpenCheckout(item.id);

            item.status = 'in_stock';
            if (_lockAfterCheckIn) {
              item.isLocked = true;
              item.lockReason = _lockReasonController.text.trim();
            }
            final updateSuccess = await itemService.updateItem(item);
            if (!updateSuccess)
              throw Exception(
                "Update für ${item.materialNumber} fehlgeschlagen",
              );

            if (_lockAfterCheckIn) {
              final lockTx = TransactionModel(
                id: '',
                schoolId: item.schoolId,
                itemId: item.id,
                type: 'service_lock',
                status: 'closed',
                initiator: 'System',
                captureMethod: 'manual',
                details: 'Gesperrt: ${item.lockReason}',
                date: DateTime.now(),
              );
              await transactionService.addTransaction(lockTx);
            }
          }
        } catch (itemError) {
          debugPrint(
            "Fehler bei Gegenstand ${item.materialNumber}: $itemError",
          );
          item.status = oldStatus;
        }
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isCheckout
                  ? '${_selectedItemIds.length} Gegenstände erfolgreich ausgegeben'
                  : '${_selectedItemIds.length} Gegenstände erfolgreich zurückgenommen',
            ),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Allgemeiner Fehler: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine visible items based on action and validity
    final isCheckout = _selectedAction == 'Auslagerung';

    // We only show items that are not disposed, and not in troubleticket.
    // For checkout, we need items in_stock.
    // For checkin, we need items that are out.
    final visibleItems = widget.items.where((item) {
      if (item.status == 'disposed' || item.status == 'troubleticket')
        return false;

      // Filter out items with expired service if checkout
      if (isCheckout) {
        if (item.status != 'in_stock') return false;
        if (item.isLocked) return false;

        final nextService = item.nextServiceDate;
        if (nextService != null && nextService.isBefore(DateTime.now())) {
          return false; // Service expired, can't checkout
        }
        return true;
      } else {
        return item.status == 'out';
      }
    }).toList();

    return AlertDialog(
      title: Text(
        "Sammelbewegung - ${widget.category.name}",
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: 600,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: RadioListTile<String>(
                    title: const Text("Auslagerung"),
                    value: 'Auslagerung',
                    groupValue: _selectedAction,
                    onChanged: (val) {
                      setState(() {
                        _selectedAction = val!;
                        _selectedItemIds.clear();
                      });
                    },
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                Expanded(
                  child: RadioListTile<String>(
                    title: const Text("Einlagerung"),
                    value: 'Einlagerung',
                    groupValue: _selectedAction,
                    onChanged: (val) {
                      setState(() {
                        _selectedAction = val!;
                        _selectedItemIds.clear();
                      });
                    },
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (isCheckout) ...[
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: "Wer leiht das Material aus? (Name)",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _commentController,
              decoration: const InputDecoration(
                labelText: "Verwendungszweck / Kommentar (optional)",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.notes),
              ),
            ),
            if (!isCheckout) const SizedBox(height: 16),
            if (!isCheckout)
              SwitchListTile(
                title: const Text("Nach Einlagerung sperren"),
                subtitle: const Text("Z.B. wegen Service-Bedarf"),
                value: _lockAfterCheckIn,
                onChanged: (val) => setState(() => _lockAfterCheckIn = val),
                activeThumbColor: const Color(0xFF9333EA),
              ),
            if (!isCheckout && _lockAfterCheckIn) const SizedBox(height: 8),
            if (!isCheckout && _lockAfterCheckIn)
              TextField(
                controller: _lockReasonController,
                decoration: const InputDecoration(
                  labelText: "Grund für Sperre",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_rounded),
                ),
                maxLines: 1,
              ),
            const SizedBox(height: 24),
            Text(
              "Gegenstände auswählen (${_selectedItemIds.length} ausgewählt):",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (visibleItems.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  isCheckout
                      ? "Keine Gegenst\u00e4nde im Lager verf\u00fcgbar (oder Service abgelaufen)."
                      : "Alle Gegenst\u00e4nde sind bereits im Lager.",
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              )
            else
              Flexible(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: visibleItems.map((item) {
                      final isSelected = _selectedItemIds.contains(item.id);
                      final cs = Theme.of(context).colorScheme;
                      final isDark =
                          Theme.of(context).brightness == Brightness.dark;
                      return InkWell(
                        onTap: () {
                          setState(() {
                            if (isSelected) {
                              _selectedItemIds.remove(item.id);
                            } else {
                              _selectedItemIds.add(item.id);
                            }
                          });
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppTheme.primaryColor
                                : (isDark
                                      ? AppTheme.darkCardElevated
                                      : AppTheme.backgroundColor),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? AppTheme.primaryDark
                                  : cs.outlineVariant,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Stack(
                            children: [
                              Center(
                                child: Text(
                                  item.materialNumber.isNotEmpty
                                      ? item.materialNumber
                                      : '-',
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : cs.onSurface,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15.5,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                const Positioned(
                                  top: 4,
                                  right: 4,
                                  child: Icon(
                                    Icons.check_circle,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text("Abbrechen"),
        ),
        FilledButton(
          onPressed: (_selectedItemIds.isEmpty || _isLoading) ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : Text(isCheckout ? "Auslagern" : "Einlagern"),
        ),
      ],
    );
  }
}
