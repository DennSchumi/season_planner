import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

Future<bool> downloadBytesFileImpl({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
}) async {
  try {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Export speichern',
      fileName: filename,
      bytes: bytes,
    );
    if (path == null || path.trim().isEmpty) return false;
    final file = File(path);
    if (!await file.exists() || await file.length() == 0) {
      await file.writeAsBytes(bytes, flush: true);
    }
    return true;
  } catch (_) {
    return false;
  }
}
