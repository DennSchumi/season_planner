import 'package:flutter/material.dart';
import 'package:inventar_manager/core/services/item_service.dart';
import 'package:inventar_manager/core/services/transaction_service.dart';

class CheckInOutDialog extends StatefulWidget {
  final ItemModel item;

  const CheckInOutDialog({Key? key, required this.item}) : super(key: key);

  static void show(BuildContext context, ItemModel item) {
    showDialog(
      context: context,
      builder: (context) => CheckInOutDialog(item: item),
    );
  }

  @override
  State<CheckInOutDialog> createState() => _CheckInOutDialogState();
}

class _CheckInOutDialogState extends State<CheckInOutDialog> {
  final _nameController = TextEditingController();
  final _detailsController = TextEditingController();
  bool _isLoading = false;

  bool get isOut => widget.item.status == 'out';

  @override
  void dispose() {
    _nameController.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final bool checkingIn = isOut; // Cache initial status
    
    if (!checkingIn && name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte gib einen Namen ein!')),
      );
      return;
    }

    setState(() => _isLoading = true);
    final String oldStatus = widget.item.status;

    try {
      final transactionService = TransactionService();
      final itemService = ItemService();

      if (checkingIn) {
        // Checking IN
        final tx = TransactionModel(
          id: '',
          schoolId: widget.item.schoolId,
          itemId: widget.item.id,
          type: 'checkin',
          status: 'closed',
          initiator: name.isNotEmpty ? name : 'System',
          captureMethod: 'manual',
          details: _detailsController.text,
          date: DateTime.now(),
        );
        final txResult = await transactionService.addTransaction(tx);
        if (txResult == null) throw Exception("Transaktion konnte nicht gespeichert werden");
        await transactionService.closeOpenCheckout(widget.item.id);

        widget.item.status = 'in_stock';
        final updateSuccess = await itemService.updateItem(widget.item);
        if (!updateSuccess) throw Exception("Gegenstand konnte nicht aktualisiert werden");
      } else {
        // Checking OUT
        final tx = TransactionModel(
          id: '',
          schoolId: widget.item.schoolId,
          itemId: widget.item.id,
          type: 'checkout',
          status: 'open',
          initiator: name,
          captureMethod: 'manual',
          details: _detailsController.text,
          date: DateTime.now(),
        );
        final txResult = await transactionService.addTransaction(tx);
        if (txResult == null) throw Exception("Transaktion konnte nicht gespeichert werden");

        widget.item.status = 'out';
        final updateSuccess = await itemService.updateItem(widget.item);
        if (!updateSuccess) throw Exception("Gegenstand konnte nicht aktualisiert werden");
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(checkingIn ? 'Erfolgreich zur\u00fcckgenommen' : 'Erfolgreich ausgegeben'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      widget.item.status = oldStatus; // Rollback on error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(isOut ? "R\u00fccknahme: ${widget.item.serialNumber}" : "Ausgeben: ${widget.item.serialNumber}"),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isOut)
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: "Name des Sch\u00fclers / Piloten",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
              ),
            if (!isOut) const SizedBox(height: 16),
            TextField(
              controller: _detailsController,
              decoration: const InputDecoration(
                labelText: "Notiz (Optional)",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.note),
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text("Abbrechen"),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: isOut ? const Color(0xFF10B981) : const Color(0xFF3B82F6),
            foregroundColor: Colors.white,
          ),
          child: _isLoading 
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Text(isOut ? "Zur\u00fccknehmen" : "Ausgeben"),
        ),
      ],
    );
  }
}
