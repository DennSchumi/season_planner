import 'package:flutter/material.dart';
import 'package:inventar_manager/core/services/item_service.dart';
import 'package:inventar_manager/core/services/transaction_service.dart';
import 'package:inventar_manager/core/services/auth_service.dart';
import 'package:inventar_manager/core/theme.dart';
import 'package:inventar_manager/core/widgets/ui_primitives.dart';

class TroubleTicketView extends StatefulWidget {
  final ItemModel? item;

  const TroubleTicketView({super.key, this.item});

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
      _selectedItem!.isLocked = true;
      _selectedItem!.lockReason = 'Wegen Defekt gesperrt';
      await ItemService().updateItem(_selectedItem!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Trouble Ticket erstellt & Gegenstand gesperrt!'),
          ),
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

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text("Neues Trouble Ticket")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SoftCard(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Betroffener Gegenstand",
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        if (widget.item != null)
                          Row(
                            children: [
                              const TintedIconBadge(
                                icon: Icons.inventory_2_outlined,
                                size: 38,
                                iconSize: 19,
                                radius: 10,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  "${widget.item!.name} (SN: ${widget.item!.serialNumber ?? '-'})",
                                  style: TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w600,
                                    color: cs.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          )
                        else
                          DropdownButtonFormField<ItemModel>(
                            decoration: const InputDecoration(
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                            ),
                            hint: const Text('Bitte Gegenstand auswählen'),
                            initialValue: _selectedItem,
                            items: availableItems
                                .map(
                                  (i) => DropdownMenuItem(
                                    value: i,
                                    child: Text(i.name),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => setState(() => _selectedItem = v),
                            validator: (v) => v == null
                                ? 'Bitte wählen Sie einen Gegenstand'
                                : null,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppTheme.dangerColor.withValues(alpha: 0.16)
                          : AppTheme.dangerBg,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: AppTheme.dangerColor.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      children: [
                        const TintedIconBadge(
                          icon: Icons.warning_rounded,
                          iconColor: AppTheme.dangerColor,
                          backgroundColor: Colors.white,
                          size: 40,
                          iconSize: 22,
                          radius: 12,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Achtung",
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.dangerColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Durch Erstellen dieses Tickets wird der Gegenstand (${widget.item?.name ?? _selectedItem?.name ?? ''}) automatisch für die Ausgabe gesperrt.",
                                style: TextStyle(
                                  color: isDark
                                      ? cs.onSurface
                                      : AppTheme.dangerColor,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  SoftCard(
                    padding: const EdgeInsets.all(18),
                    child: TextFormField(
                      controller: _descController,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: "Fehlerbeschreibung",
                        alignLabelWithHint: true,
                      ),
                      validator: (value) =>
                          value!.isEmpty ? "Bitte beschreibe das Problem" : null,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.report_problem_rounded),
                      label: const Text("Ticket erstellen & Sperren"),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.dangerColor,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
