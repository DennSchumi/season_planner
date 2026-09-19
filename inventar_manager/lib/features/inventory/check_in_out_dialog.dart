import 'package:flutter/material.dart';
import 'package:inventar_manager/core/services/item_service.dart';
import 'package:inventar_manager/core/services/transaction_service.dart';

class CheckInOutDialog extends StatefulWidget {
  final ItemModel item;

  const CheckInOutDialog({Key? key, required this.item}) : super(key: key);

  static void show(BuildContext context, ItemModel item) {
    if (item.status != 'out' && (item.isLocked || item.status == 'defekt')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dieses Gerät ist gesperrt oder defekt und kann nicht ausgegeben werden!')),
      );
      return;
    }
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
  final _lockReasonController = TextEditingController();
  bool _isLoading = false;
  bool _lockAfterCheckIn = false;

  bool get isOut => widget.item.status == 'out';

  @override
  void dispose() {
    _nameController.dispose();
    _detailsController.dispose();
    _lockReasonController.dispose();
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

    if (checkingIn && _lockAfterCheckIn && _lockReasonController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte gib einen Grund für die Sperre ein!')),
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
        if (_lockAfterCheckIn) {
          widget.item.isLocked = true;
          widget.item.lockReason = _lockReasonController.text.trim();
        }
        
        final updateSuccess = await itemService.updateItem(widget.item);
        if (!updateSuccess) throw Exception("Gegenstand konnte nicht aktualisiert werden");

        if (_lockAfterCheckIn) {
           final lockTx = TransactionModel(
             id: '',
             schoolId: widget.item.schoolId,
             itemId: widget.item.id,
             type: 'service_lock',
             status: 'closed',
             initiator: 'System', 
             captureMethod: 'manual',
             details: 'Gesperrt: ${widget.item.lockReason}',
             date: DateTime.now(),
           );
           await transactionService.addTransaction(lockTx);
        }
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
            if (isOut) const SizedBox(height: 16),
            if (isOut)
              SwitchListTile(
                title: const Text("Nach Rücknahme sperren"),
                subtitle: const Text("Z.B. wegen Service-Bedarf"),
                value: _lockAfterCheckIn,
                onChanged: (val) => setState(() => _lockAfterCheckIn = val),
                activeColor: const Color(0xFF9333EA),
              ),
            if (isOut && _lockAfterCheckIn) const SizedBox(height: 8),
            if (isOut && _lockAfterCheckIn)
              TextField(
                controller: _lockReasonController,
                decoration: const InputDecoration(
                  labelText: "Grund für Sperre",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_rounded),
                ),
                maxLines: 1,
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
