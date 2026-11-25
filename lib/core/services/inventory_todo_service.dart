import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:season_planner/core/appwrite_config.dart';
import 'package:season_planner/core/services/appwrite_pagination.dart';
import 'package:season_planner/core/services/auth_service.dart';

enum InventoryTaskKind {
  troubleTicket,
  repack,
  check,
  locked,
}

class InventoryTaskEntry {
  final InventoryTaskKind kind;
  final String itemId;
  final String itemName;
  final String materialNumber;
  final String categoryName;
  final String detail;
  final bool isOverdue;
  final int? daysUntilDue;

  const InventoryTaskEntry({
    required this.kind,
    required this.itemId,
    required this.itemName,
    required this.materialNumber,
    required this.categoryName,
    required this.detail,
    this.isOverdue = false,
    this.daysUntilDue,
  });

  String get displayItem =>
      materialNumber.trim().isNotEmpty
          ? '$itemName ($materialNumber)'
          : itemName;
}

class SchoolInventoryTodoSummary {
  final String flightSchoolId;
  final List<InventoryTaskEntry> troubleTickets;
  final List<InventoryTaskEntry> repacksDue;
  final List<InventoryTaskEntry> checksDue;
  final List<InventoryTaskEntry> lockedItems;

  const SchoolInventoryTodoSummary({
    required this.flightSchoolId,
    this.troubleTickets = const [],
    this.repacksDue = const [],
    this.checksDue = const [],
    this.lockedItems = const [],
  });

  int get totalCount =>
      troubleTickets.length +
      repacksDue.length +
      checksDue.length +
      lockedItems.length;

  bool get isEmpty => totalCount == 0;
  bool get isNotEmpty => totalCount > 0;

  bool get hasOverdueRepack => repacksDue.any((e) => e.isOverdue);
  bool get hasOverdueCheck => checksDue.any((e) => e.isOverdue);

  List<InventoryTaskEntry> get allTasks => [
        ...troubleTickets,
        ...repacksDue,
        ...checksDue,
        ...lockedItems,
      ];
}

/// Liest offene Aufgaben (Troubletickets, fällige Checks, fälliges Neupacken,
/// gesperrtes Material) direkt aus der gemeinsamen Appwrite-Datenbank
/// `inventory_db` des Inventarmanagers für eine Flugschule.
class InventoryTodoService {
  static final InventoryTodoService _instance =
      InventoryTodoService._internal();
  factory InventoryTodoService() => _instance;
  InventoryTodoService._internal();

  Client get _client => AuthService().client;

  late final TablesDB _tablesDB = TablesDB(_client);

  static bool _isRepackCategory(String categoryName, String itemName) {
    final combined = '${categoryName.toLowerCase()} ${itemName.toLowerCase()}';
    return combined.contains('retter') ||
        combined.contains('rettung') ||
        combined.contains('reserve') ||
        combined.contains('pack');
  }

  Future<SchoolInventoryTodoSummary> fetchOpenTodosForSchool(
    String flightSchoolId,
  ) async {
    if (flightSchoolId.trim().isEmpty) {
      return SchoolInventoryTodoSummary(flightSchoolId: flightSchoolId);
    }

    try {
      final cfg = AppwriteConfig();
      final results = await Future.wait([
        listAllRows(
          _tablesDB,
          databaseId: cfg.inventoryDatabaseId,
          tableId: cfg.inventoryCategoriesTableId,
          queries: [Query.equal('schoolId', flightSchoolId)],
        ),
        listAllRows(
          _tablesDB,
          databaseId: cfg.inventoryDatabaseId,
          tableId: cfg.inventoryItemsTableId,
          queries: [Query.equal('schoolId', flightSchoolId)],
        ),
        listAllRows(
          _tablesDB,
          databaseId: cfg.inventoryDatabaseId,
          tableId: cfg.inventoryTransactionsTableId,
          queries: [
            Query.equal('schoolId', flightSchoolId),
            Query.equal('type', 'troubleticket'),
            Query.equal('status', 'offen'),
            Query.orderDesc('date'),
          ],
        ),
      ]);

      final categoryRows = results[0];
      final itemRows = results[1];
      final ticketRows = results[2];

      final categoryNameById = <String, String>{
        for (final c in categoryRows)
          c.$id: (c.data['name'] ?? '').toString().trim(),
      };

      final activeItemById = <String, Map<String, dynamic>>{};
      for (final row in itemRows) {
        final status = (row.data['status'] ?? 'in_stock').toString();
        if (status == 'disposed') continue;
        activeItemById[row.$id] = row.data;
      }

      // 1) Offene Troubletickets
      final troubleTickets = <InventoryTaskEntry>[];
      final ticketItemIds = <String>{};
      for (final t in ticketRows) {
        final itemId = (t.data['itemId'] ?? '').toString();
        final itemData = activeItemById[itemId];
        if (itemData == null) continue;
        ticketItemIds.add(itemId);

        final name = (itemData['name'] ?? 'Artikel').toString();
        final matNr = (itemData['materialNumber'] ?? '').toString();
        final catName =
            categoryNameById[(itemData['categoryId'] ?? '').toString()] ?? '';
        final details = (t.data['details'] ?? '').toString().trim();

        troubleTickets.add(
          InventoryTaskEntry(
            kind: InventoryTaskKind.troubleTicket,
            itemId: itemId,
            itemName: name,
            materialNumber: matNr,
            categoryName: catName,
            detail: details.isNotEmpty ? details : 'Troubleticket offen',
            isOverdue: true,
          ),
        );
      }

      // 2) Fällige / überfällige Checks & Neupackungen (Schwelle: nächste 7 Tage,
      //    analog zum Dashboard im Inventarmanager) + manuell gesperrte Artikel
      final now = DateTime.now();
      final dueThreshold = now.add(const Duration(days: 7));

      final repacksDue = <InventoryTaskEntry>[];
      final checksDue = <InventoryTaskEntry>[];
      final lockedItems = <InventoryTaskEntry>[];

      for (final entry in activeItemById.entries) {
        final itemId = entry.key;
        final data = entry.value;
        final name = (data['name'] ?? 'Artikel').toString();
        final matNr = (data['materialNumber'] ?? '').toString();
        final catName =
            categoryNameById[(data['categoryId'] ?? '').toString()] ?? '';
        final isLocked = data['isLocked'] == true;
        final lockReason = (data['lockReason'] ?? '').toString().trim();

        if (isLocked && !ticketItemIds.contains(itemId)) {
          lockedItems.add(
            InventoryTaskEntry(
              kind: InventoryTaskKind.locked,
              itemId: itemId,
              itemName: name,
              materialNumber: matNr,
              categoryName: catName,
              detail: lockReason.isNotEmpty ? lockReason : 'Manuell gesperrt',
            ),
          );
        }

        final nextServiceRaw = data['nextServiceDate']?.toString();
        if (nextServiceRaw == null || nextServiceRaw.isEmpty) continue;
        final nextServiceDate = DateTime.tryParse(nextServiceRaw);
        if (nextServiceDate == null || !nextServiceDate.isBefore(dueThreshold)) {
          continue;
        }

        final isPastDue = nextServiceDate.isBefore(now);
        final diffDays = nextServiceDate.difference(now).inDays;
        final dueText = isPastDue
            ? (diffDays == 0
                ? 'Heute fällig'
                : 'Überfällig seit ${-diffDays} ${(-diffDays) == 1 ? "Tag" : "Tagen"}')
            : (diffDays == 0
                ? 'Heute fällig'
                : 'Fällig in $diffDays ${diffDays == 1 ? "Tag" : "Tagen"}');

        final isRepack = _isRepackCategory(catName, name);
        final task = InventoryTaskEntry(
          kind: isRepack ? InventoryTaskKind.repack : InventoryTaskKind.check,
          itemId: itemId,
          itemName: name,
          materialNumber: matNr,
          categoryName: catName,
          detail: dueText,
          isOverdue: isPastDue,
          daysUntilDue: diffDays,
        );

        if (isRepack) {
          repacksDue.add(task);
        } else {
          checksDue.add(task);
        }
      }

      int sortByDue(InventoryTaskEntry a, InventoryTaskEntry b) {
        final da = a.daysUntilDue ?? 9999;
        final db = b.daysUntilDue ?? 9999;
        return da.compareTo(db);
      }

      repacksDue.sort(sortByDue);
      checksDue.sort(sortByDue);

      return SchoolInventoryTodoSummary(
        flightSchoolId: flightSchoolId,
        troubleTickets: troubleTickets,
        repacksDue: repacksDue,
        checksDue: checksDue,
        lockedItems: lockedItems,
      );
    } catch (e) {
      debugPrint('InventoryTodoService.fetchOpenTodosForSchool error: $e');
      return SchoolInventoryTodoSummary(flightSchoolId: flightSchoolId);
    }
  }
}
