import 'dart:typed_data';
import 'file_download_stub.dart'
    if (dart.library.js_interop) 'file_download_web.dart' as impl;

/// Speichert bzw. lädt eine generierte Datei (PDF/CSV) plattformübergreifend herunter.
/// Gibt `true` zurück, wenn die Datei erfolgreich ausgeliefert/gespeichert wurde.
Future<bool> downloadBytesFile({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
}) {
  return impl.downloadBytesFileImpl(
    bytes: bytes,
    filename: filename,
    mimeType: mimeType,
  );
}
