import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

Future<bool> downloadBytesFileImpl({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
}) async {
  try {
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Export speichern',
      fileName: filename,
      bytes: bytes,
    );
    if (uri == null) return false;
    if (uri.scheme.isEmpty || uri.scheme == 'file') {
      final file = uri.scheme == 'file' ? File.fromUri(uri) : File(uri.path);
      if (!await file.exists() || await file.length() == 0) {
        await file.writeAsBytes(bytes, flush: true);
      }
    }
    return true;
  } catch (_) {
    return false;
  }
}
