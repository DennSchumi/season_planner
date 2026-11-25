import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;

/// Lädt alle passenden Zeilen einer Appwrite-2.x-Tabelle per Cursor-Pagination
/// (`Query.cursorAfter`), sodass wachsende Datenbestände nicht still nach dem
/// ersten `Query.limit` abgeschnitten werden.
Future<List<models.Row>> listAllRows(
  TablesDB tablesDB, {
  required String databaseId,
  required String tableId,
  List<String> queries = const [],
  int pageSize = 100,
  int maxRows = 5000,
}) async {
  final all = <models.Row>[];
  String? cursorAfter;

  while (all.length < maxRows) {
    final remaining = maxRows - all.length;
    final batchLimit = remaining < pageSize ? remaining : pageSize;

    final res = await tablesDB.listRows(
      databaseId: databaseId,
      tableId: tableId,
      queries: [
        ...queries,
        Query.limit(batchLimit),
        if (cursorAfter != null) Query.cursorAfter(cursorAfter),
      ],
    );

    if (res.rows.isEmpty) break;
    all.addAll(res.rows);
    if (res.rows.length < batchLimit) break;
    cursorAfter = res.rows.last.$id;
  }

  return all;
}

/// Zerlegt eine Liste in gleichgroße Chunks (z. B. für `Query.equal(field, chunk)`).
Iterable<List<T>> chunkList<T>(List<T> items, {int size = 100}) sync* {
  for (var i = 0; i < items.length; i += size) {
    final end = (i + size < items.length) ? i + size : items.length;
    yield items.sublist(i, end);
  }
}
