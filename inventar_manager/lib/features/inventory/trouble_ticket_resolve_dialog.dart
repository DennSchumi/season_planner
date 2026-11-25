import 'package:flutter/material.dart';
import 'package:inventar_manager/core/services/item_service.dart';
import 'package:inventar_manager/core/services/transaction_service.dart';
import 'package:inventar_manager/core/services/auth_service.dart';
import 'package:inventar_manager/core/theme.dart';

class TroubleTicketResolveDialog extends StatefulWidget {
  final ItemModel item;
  final TransactionModel ticketTx;

  const TroubleTicketResolveDialog({
    super.key,
    required this.item,
    required this.ticketTx,
  });

  static void show(
    BuildContext context,
    ItemModel item,
    TransactionModel ticketTx,
  ) {
    showDialog(
      context: context,
      builder: (context) =>
          TroubleTicketResolveDialog(item: item, ticketTx: ticketTx),
    );
  }

  @override
  _TroubleTicketResolveDialogState createState() =>
      _TroubleTicketResolveDialogState();
}

class _TroubleTicketResolveDialogState
    extends State<TroubleTicketResolveDialog> {
  final _noteController = TextEditingController();
  bool _isLoading = false;
  String _mode = ''; // 'repair', 'dispose' or 'edit'

  @override
  void initState() {
    super.initState();
    _noteController.text = widget.ticketTx.details ?? '';
  }

  Future<void> _submit() async {
    if (_mode == 'repair' && _noteController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte gib eine Notiz zur Reparatur ein!'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    final String oldStatus = widget.item.status;

    try {
      final transactionService = TransactionService();
      final itemService = ItemService();
      final user = AuthService().currentUser;
      final userName = user?.name ?? "Unbekannt";

      if (_mode == 'edit') {
        await transactionService.updateTransactionDetails(
          widget.ticketTx.id,
          _noteController.text.trim(),
        );
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Fehlerbeschreibung aktualisiert'),
              backgroundColor: Color(0xFF10B981),
            ),
          );
        }
        return; // Early return for edit mode
      }

      if (_mode == 'repair') {
        // Create repair transaction
        final repairTx = TransactionModel(
          id: '',
          schoolId: widget.item.schoolId,
          itemId: widget.item.id,
          type: 'repair',
          status: 'closed',
          initiator: userName,
          captureMethod: 'manual',
          details: _noteController.text.trim(),
          date: DateTime.now(),
        );
        await transactionService.addTransaction(repairTx);

        // Update item to in_stock
        widget.item.status = 'in_stock';
        widget.item.isLocked = false;
        widget.item.lockReason = null;
        await itemService.updateItem(widget.item);
      } else if (_mode == 'dispose') {
        // Create dispose transaction
        final disposeTx = TransactionModel(
          id: '',
          schoolId: widget.item.schoolId,
          itemId: widget.item.id,
          type: 'dispose',
          status: 'closed',
          initiator: userName,
          captureMethod: 'manual',
          details: 'Gegenstand entsorgt',
          date: DateTime.now(),
        );
        await transactionService.addTransaction(disposeTx);

        // Update item to disposed
        widget.item.status = 'disposed';
        widget.item.isLocked = false;
        widget.item.lockReason = null;
        await itemService.updateItem(widget.item);
      }

      // Close the open trouble ticket
      await transactionService.updateTransactionStatus(
        widget.ticketTx.id,
        'closed',
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _mode == 'repair'
                  ? 'Erfolgreich repariert und freigegeben'
                  : 'Gegenstand entsorgt',
            ),
            backgroundColor: _mode == 'repair'
                ? const Color(0xFF10B981)
                : const Color(0xFF64748B),
          ),
        );
      }
    } catch (e) {
      widget.item.status = oldStatus; // Rollback on error
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_mode == '') {
      return AlertDialog(
        title: Text("Trouble Ticket: ${widget.item.serialNumber}"),
        content: const Text(
          "Wie m\u00f6chtest du mit diesem Trouble Ticket verfahren?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Abbrechen"),
          ),
          FilledButton.icon(
            onPressed: () {
              _noteController.text = widget.ticketTx.details ?? '';
              setState(() => _mode = 'edit');
            },
            icon: const Icon(Icons.edit_rounded, size: 17),
            label: const Text("Bearbeiten"),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.warningColor,
              foregroundColor: Colors.white,
            ),
          ),
          FilledButton.icon(
            onPressed: () {
              _noteController.clear();
              setState(() => _mode = 'repair');
            },
            icon: const Icon(Icons.build_rounded, size: 17),
            label: const Text("Reparieren"),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
            ),
          ),
          FilledButton.icon(
            onPressed: () => setState(() => _mode = 'dispose'),
            icon: const Icon(Icons.delete_outline_rounded, size: 17),
            label: const Text("Entsorgen"),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.dangerColor,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      );
    }

    if (_mode == 'repair') {
      return AlertDialog(
        title: Text("Reparatur: ${widget.item.serialNumber}"),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _noteController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: "Notiz zur Reparatur",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.note),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : () => setState(() => _mode = ''),
            child: const Text("Zur\u00fcck"),
          ),
          ElevatedButton(
            onPressed: _isLoading ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text("Best\u00e4tigen & in Umlauf"),
          ),
        ],
      );
    }

    if (_mode == 'edit') {
      return AlertDialog(
        title: Text("Ticket bearbeiten: ${widget.item.serialNumber}"),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _noteController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: "Fehlerbeschreibung",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.description),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : () => setState(() => _mode = ''),
            child: const Text("Zurück"),
          ),
          FilledButton(
            onPressed: _isLoading ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text("Speichern"),
          ),
        ],
      );
    }

    // Dispose confirmation
    return AlertDialog(
      title: Text("Entsorgen: ${widget.item.serialNumber}"),
      content: const Text(
        "Bist du sicher, dass du diesen Gegenstand endg\u00fcltig entsorgen m\u00f6chtest? Er wird vom Dashboard entfernt.",
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => setState(() => _mode = ''),
          child: const Text("Zur\u00fcck"),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFEF4444),
            foregroundColor: Colors.white,
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text("Endg\u00fcltig entsorgen"),
        ),
      ],
    );
  }
}
