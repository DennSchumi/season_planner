import 'package:appwrite/appwrite.dart';
import 'package:flutter/material.dart';
import 'package:inventar_manager/core/services/database_service.dart';
import 'package:inventar_manager/core/appwrite_config.dart';

class TransactionModel {
  String id;
  String schoolId;
  String itemId;
  String type;
  String status;
  String initiator;
  String captureMethod;
  String? details;
  DateTime date;

  TransactionModel({
    required this.id,
    required this.schoolId,
    required this.itemId,
    required this.type,
    required this.status,
    required this.initiator,
    required this.captureMethod,
    this.details,
    required this.date,
  });

  factory TransactionModel.fromDocument(dynamic doc) {
    return TransactionModel(
      id: doc.$id,
      schoolId: doc.data['schoolId'],
      itemId: doc.data['itemId'],
      type: doc.data['type'],
      status: doc.data['status'],
      initiator: doc.data['initiator'],
      captureMethod: doc.data['captureMethod'],
      details: doc.data['details'],
      date: doc.data['date'] != null ? DateTime.parse(doc.data['date']) : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'schoolId': schoolId,
      'itemId': itemId,
      'type': type,
      'status': status,
      'initiator': initiator,
      'captureMethod': captureMethod,
      'details': details,
      'date': date.toIso8601String(),
    };
  }
}

class TransactionService extends ChangeNotifier {
  static final TransactionService _instance = TransactionService._internal();

  factory TransactionService() {
    return _instance;
  }

  TransactionService._internal();

  List<TransactionModel> _transactions = [];
  bool _isLoading = false;

  List<TransactionModel> get transactions => List.unmodifiable(_transactions);
  bool get isLoading => _isLoading;

  Future<void> loadTransactionsForItem(String itemId) async {
    _isLoading = true;
    notifyListeners();

    try {
      final queries = [
        Query.equal('itemId', itemId),
        Query.orderDesc('date'),
        Query.limit(100)
      ];
      final docs = await DatabaseService().getDocuments(AppwriteConfig.transactionsCollectionId, queries: queries);
      
      _transactions = docs.map((d) => TransactionModel.fromDocument(d)).toList();
    } catch (e) {
      print("Error loading transactions: $e");
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<List<TransactionModel>> getOpenTroubleTickets() async {
    try {
      final queries = [
        Query.equal('type', 'troubleticket'),
        Query.equal('status', 'offen'),
        Query.orderDesc('date'),
        Query.limit(100)
      ];
      final docs = await DatabaseService().getDocuments(AppwriteConfig.transactionsCollectionId, queries: queries);
      return docs.map((d) => TransactionModel.fromDocument(d)).toList();
    } catch (e) {
      print("Error loading open trouble tickets: $e");
      return [];
    }
  }

  Future<TransactionModel?> getLastServiceTransaction(String itemId) async {
    try {
        final queries = [
          Query.equal('itemId', itemId),
          Query.equal('type', ['service', 'service_check']),
          Query.orderDesc('date'),
          Query.limit(1)
        ];
      final docs = await DatabaseService().getDocuments(AppwriteConfig.transactionsCollectionId, queries: queries);
      
      if (docs.isNotEmpty) {
        return TransactionModel.fromDocument(docs.first);
      }
    } catch (e) {
      print("Error getting last service transaction: $e");
    }
    return null;
  }

  Future<TransactionModel?> addTransaction(TransactionModel transaction) async {
    final doc = await DatabaseService().createDocument(AppwriteConfig.transactionsCollectionId, transaction.toMap());
    if (doc != null) {
      transaction.id = doc.$id;
      _transactions.insert(0, transaction); // prepend since sorted descending
      notifyListeners();
      return transaction;
    }
    return null;
  }

  Future<TransactionModel?> getOpenCheckout(String itemId) async {
    try {
      final queries = [
        Query.equal('itemId', itemId),
        Query.equal('type', 'checkout'),
        Query.equal('status', 'open'),
        Query.orderDesc('date'),
        Query.limit(1)
      ];
      final docs = await DatabaseService().getDocuments(AppwriteConfig.transactionsCollectionId, queries: queries);
      if (docs.isNotEmpty) {
        return TransactionModel.fromDocument(docs.first);
      }
    } catch (e) {
      print("Error getting open checkout: $e");
    }
    return null;
  }

  Future<void> closeOpenCheckout(String itemId) async {
    try {
      final queries = [
        Query.equal('itemId', itemId),
        Query.equal('type', 'checkout'),
        Query.equal('status', 'open'),
        Query.limit(1)
      ];
      final docs = await DatabaseService().getDocuments(AppwriteConfig.transactionsCollectionId, queries: queries);
      
      if (docs.isNotEmpty) {
        final txDoc = docs.first;
        final tx = TransactionModel.fromDocument(txDoc);
        final docId = tx.id;
        
        // Calculate duration in calendar days
        final now = DateTime.now();
        final startMidnight = DateTime(tx.date.year, tx.date.month, tx.date.day);
        final endMidnight = DateTime(now.year, now.month, now.day);
        final days = endMidnight.difference(startMidnight).inDays + 1;
        
        final currentDetails = tx.details ?? '';
        final suffix = '(Ausgeliehen für $days ${days == 1 ? "Tag" : "Tage"})';
        final newDetails = currentDetails.isEmpty ? suffix : '$currentDetails $suffix';

        await DatabaseService().updateDocument(
          AppwriteConfig.transactionsCollectionId,
          docId,
          {
            'status': 'closed',
            'details': newDetails,
          }
        );
        
        // Update local state if the transaction is in the list
        final index = _transactions.indexWhere((t) => t.id == docId);
        if (index != -1) {
          _transactions[index].status = 'closed';
          _transactions[index].details = newDetails;
          notifyListeners();
        }
      }
    } catch (e) {
      print("Error closing open checkout: $e");
    }
  }

  Future<void> updateTransactionStatus(String txId, String newStatus) async {
    try {
      await DatabaseService().updateDocument(
        AppwriteConfig.transactionsCollectionId,
        txId,
        {'status': newStatus}
      );
      
      final index = _transactions.indexWhere((tx) => tx.id == txId);
      if (index != -1) {
        _transactions[index].status = newStatus;
        notifyListeners();
      }
    } catch (e) {
      print("Error updating transaction status: $e");
    }
  }
}
