import 'package:flutter/material.dart';
import 'package:inventar_manager/core/services/category_service.dart';
import 'package:inventar_manager/core/services/item_service.dart';
import 'package:inventar_manager/core/services/transaction_service.dart';

class ItemSwapDialog extends StatefulWidget {
  final CategoryService categoryService;
  final ItemService itemService;

  const ItemSwapDialog({Key? key, required this.categoryService, required this.itemService}) : super(key: key);

  static void show(BuildContext context, CategoryService catService, ItemService itemService) {
    showDialog(
      context: context,
      builder: (context) => ItemSwapDialog(categoryService: catService, itemService: itemService),
    );
  }

  @override
  State<ItemSwapDialog> createState() => _ItemSwapDialogState();
}

class _ItemSwapDialogState extends State<ItemSwapDialog> {
  CategoryModel? _selectedCategory;
  ItemModel? _item1;
  ItemModel? _item2;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Preselect first category with at least 2 checked-out items if possible
    for (var cat in widget.categoryService.categories) {
      final outItems = widget.itemService.items.where((i) => i.categoryId == cat.id && i.status == 'out').toList();
      if (outItems.length >= 2) {
        _selectedCategory = cat;
        break;
      }
    }
  }

  List<ItemModel> get _availableItems1 {
    if (_selectedCategory == null) return [];
    return widget.itemService.items.where((i) => i.categoryId == _selectedCategory!.id && i.status == 'out').toList();
  }

  List<ItemModel> get _availableItems2 {
    if (_selectedCategory == null) return [];
    return _availableItems1.where((i) => i.id != _item1?.id).toList();
  }

  Future<void> _submit() async {
    if (_item1 == null || _item2 == null) return;
    
    setState(() => _isLoading = true);
    
    try {
      final txService = TransactionService();
      
      // Fetch open checkouts
      final tx1 = await txService.getOpenCheckout(_item1!.id);
      final tx2 = await txService.getOpenCheckout(_item2!.id);
      
      if (tx1 == null || tx2 == null) {
        throw Exception("Für mindestens einen Gegenstand konnte kein offener Ausleih-Vorgang gefunden werden.");
      }
      
      // Close open checkouts
      await txService.closeOpenCheckout(_item1!.id);
      await txService.closeOpenCheckout(_item2!.id);
      
      // Checkin for Item 1
      final checkin1 = TransactionModel(
        id: '',
        schoolId: _item1!.schoolId,
        itemId: _item1!.id,
        type: 'checkin',
        status: 'closed',
        initiator: tx1.initiator,
        captureMethod: 'manual',
        details: "Rücknahme wegen Tausch mit ${_item2!.name} (${_item2!.materialNumber})",
        date: DateTime.now(),
      );
      await txService.addTransaction(checkin1);
      
      // Checkin for Item 2
      final checkin2 = TransactionModel(
        id: '',
        schoolId: _item2!.schoolId,
        itemId: _item2!.id,
        type: 'checkin',
        status: 'closed',
        initiator: tx2.initiator,
        captureMethod: 'manual',
        details: "Rücknahme wegen Tausch mit ${_item1!.name} (${_item1!.materialNumber})",
        date: DateTime.now(),
      );
      await txService.addTransaction(checkin2);
      
      // New Checkout for Item 1 (to Person 2)
      final newTx1 = TransactionModel(
        id: '',
        schoolId: _item1!.schoolId,
        itemId: _item1!.id,
        type: 'checkout',
        status: 'open',
        initiator: tx2.initiator,
        captureMethod: 'manual',
        details: tx2.details != null && tx2.details!.isNotEmpty ? "${tx2.details} (Getauscht von ${_item2!.materialNumber})" : "(Getauscht von ${_item2!.materialNumber})",
        date: DateTime.now(),
      );
      await txService.addTransaction(newTx1);
      
      // New Checkout for Item 2 (to Person 1)
      final newTx2 = TransactionModel(
        id: '',
        schoolId: _item2!.schoolId,
        itemId: _item2!.id,
        type: 'checkout',
        status: 'open',
        initiator: tx1.initiator,
        captureMethod: 'manual',
        details: tx1.details != null && tx1.details!.isNotEmpty ? "${tx1.details} (Getauscht von ${_item1!.materialNumber})" : "(Getauscht von ${_item1!.materialNumber})",
        date: DateTime.now(),
      );
      await txService.addTransaction(newTx2);
      
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Gegenstände erfolgreich getauscht!"),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Tauschen: $e')),
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
      title: const Text("Gegenstände tauschen"),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Tauscht die Verwender und Verwendungszwecke zweier ausgelagerter Gegenstände miteinander.",
              style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
            ),
            const SizedBox(height: 24),
            DropdownButtonFormField<CategoryModel>(
              decoration: const InputDecoration(labelText: "Kategorie", border: OutlineInputBorder()),
              value: _selectedCategory,
              items: widget.categoryService.categories.map((c) {
                return DropdownMenuItem(value: c, child: Text(c.name));
              }).toList(),
              onChanged: (val) {
                setState(() {
                  _selectedCategory = val;
                  _item1 = null;
                  _item2 = null;
                });
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<ItemModel>(
              decoration: const InputDecoration(labelText: "Gegenstand 1 (von Person A)", border: OutlineInputBorder()),
              value: _item1,
              items: _availableItems1.map((i) {
                return DropdownMenuItem(value: i, child: Text("${i.name} (${i.materialNumber})"));
              }).toList(),
              onChanged: (val) {
                setState(() {
                  _item1 = val;
                  if (_item2?.id == val?.id) _item2 = null;
                });
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<ItemModel>(
              decoration: const InputDecoration(labelText: "Gegenstand 2 (von Person B)", border: OutlineInputBorder()),
              value: _item2,
              items: _availableItems2.map((i) {
                return DropdownMenuItem(value: i, child: Text("${i.name} (${i.materialNumber})"));
              }).toList(),
              onChanged: (val) => setState(() => _item2 = val),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text("Abbrechen"),
        ),
        ElevatedButton.icon(
          onPressed: (_isLoading || _item1 == null || _item2 == null) ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3B82F6),
            foregroundColor: Colors.white,
          ),
          icon: _isLoading 
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Icon(Icons.swap_horiz),
          label: const Text("Tauschen"),
        ),
      ],
    );
  }
}
