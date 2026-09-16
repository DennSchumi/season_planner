import 'package:flutter/material.dart';
import 'package:inventar_manager/core/services/item_service.dart';
import 'package:inventar_manager/core/services/transaction_service.dart';
import 'package:inventar_manager/core/services/auth_service.dart';

class TroubleTicketView extends StatefulWidget {
  final ItemModel? item;

  const TroubleTicketView({Key? key, this.item}) : super(key: key);

  @override
  _TroubleTicketViewState createState() => _TroubleTicketViewState();
}

class _TroubleTicketViewState extends State<TroubleTicketView> {
  final _formKey = GlobalKey<FormState>();
  final _descController = TextEditingController();
  ItemModel? _selectedItem;

  @override
  void initState() {
    super.initState();
    _selectedItem = widget.item;
  }

  Future<void> _save() async {
    if (_formKey.currentState!.validate() && _selectedItem != null) {
      final user = AuthService().currentUser;
      final userName = user != null ? user.name : "Unbekannt";

      final transaction = TransactionModel(
        id: '',
        schoolId: _selectedItem!.schoolId,
        itemId: _selectedItem!.id,
        type: 'troubleticket',
        status: 'offen',
        initiator: userName,
        captureMethod: 'manual',
        details: _descController.text.trim(),
        date: DateTime.now(),
      );

      await TransactionService().addTransaction(transaction);

      _selectedItem!.status = 'defekt'; // update status to reflect it's blocked
      await ItemService().updateItem(_selectedItem!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Trouble Ticket erstellt & Gegenstand gesperrt!')),
        );
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Falls kein Item direkt übergeben wurde, müssten wir hier theoretisch eine Liste laden.
    // Wir gehen aber davon aus, dass wir es meist aus der Detailansicht oder dem Modal öffnen.
    final List<ItemModel> availableItems = ItemService().items;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          "Neues Trouble Ticket",
          style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A), fontSize: 18),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: const Color(0xFFE2E8F0), height: 1.0),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Betroffener Gegenstand",
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: Color(0xFF334155)),
                    ),
                    const SizedBox(height: 12),
                    if (widget.item != null)
                      Row(
                        children: [
                          const Icon(Icons.inventory_2_outlined, color: Color(0xFF3B82F6)),
                          const SizedBox(width: 8),
                          Text(
                            "${widget.item!.name} (SN: ${widget.item!.serialNumber ?? '-'})",
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                          ),
                        ],
                      )
                    else
                      DropdownButtonFormField<ItemModel>(
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12),
                        ),
                        hint: const Text('Bitte Gegenstand auswählen'),
                        value: _selectedItem,
                        items: availableItems.map((i) => DropdownMenuItem(value: i, child: Text(i.name))).toList(),
                        onChanged: (v) => setState(() => _selectedItem = v),
                        validator: (v) => v == null ? 'Bitte wählen Sie einen Gegenstand' : null,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_rounded, color: Color(0xFFEF4444), size: 32),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Achtung",
                            style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF991B1B)),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Durch Erstellen dieses Tickets wird der Gegenstand (${widget.item?.name ?? _selectedItem?.name ?? ''}) automatisch für die Ausgabe gesperrt.",
                            style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              
              TextFormField(
                controller: _descController,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: "Fehlerbeschreibung",
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  filled: true,
                  fillColor: Colors.white,
                ),
                validator: (value) => value!.isEmpty ? "Bitte beschreibe das Problem" : null,
              ),
              
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.report_problem_rounded),
                label: const Text("Ticket erstellen & Sperren", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
