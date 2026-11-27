import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'embedded_pdf_view_stub.dart'
    if (dart.library.js_interop) 'embedded_pdf_view_web.dart' as impl;

/// Plattformübergreifende eingebettete PDF-Vorschau:
/// - Im Web: nativer Browser-PDF-Viewer per Blob-URL im `<iframe>`.
/// - Auf nativen Plattformen: Vorschau-Karte mit direktem Extern-Öffnen / Download.
class EmbeddedPdfView extends StatelessWidget {
  final Uint8List bytes;
  final String fileName;
  final VoidCallback? onOpenExternal;

  /// Im Web muss der eingebettete `<iframe>` Pointer-Events vorübergehend
  /// freigeben (`pointer-events: none`), sobald darüber ein Flutter-Dialog
  /// (z. B. DatePicker oder Ablehnen-Popup) geöffnet wird, damit der `<iframe>`
  /// keine Klicks/Taps verschluckt.
  final bool pointerEventsEnabled;

  const EmbeddedPdfView({
    super.key,
    required this.bytes,
    required this.fileName,
    this.onOpenExternal,
    this.pointerEventsEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return impl.buildEmbeddedPdfView(
      context: context,
      bytes: bytes,
      fileName: fileName,
      onOpenExternal: onOpenExternal,
      pointerEventsEnabled: pointerEventsEnabled,
    );
  }
}
