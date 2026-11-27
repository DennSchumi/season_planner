import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:season_planner/core/services/file_optimization_backend_stub.dart'
    if (dart.library.js_interop) 'package:season_planner/core/services/file_optimization_backend_web.dart'
    if (dart.library.io) 'package:season_planner/core/services/file_optimization_backend_io.dart';

class OptimizedFileResult {
  final Uint8List bytes;
  final String fileName;
  final int originalBytes;
  final bool wasOptimized;

  const OptimizedFileResult({
    required this.bytes,
    required this.fileName,
    required this.originalBytes,
    required this.wasOptimized,
  });

  int get finalBytes => bytes.length;

  int get savedBytes =>
      originalBytes > finalBytes ? (originalBytes - finalBytes) : 0;

  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Clientseitiger Optimierungsdienst für Bilder und große PDFs vor dem Upload:
/// - Qualifikationsdokumente (Bilder): auf max. 1800 px & JPEG (~80 %) skalieren,
///   spart typischerweise 85–95 % Speicher bei voller Lesbarkeit.
/// - Qualifikationsdokumente (PDF > 1 MB): Seiten auf ~150 DPI als JPEG rendern
///   und sauber zu einem kompakten PDF zusammenbauen (nur übernehmen, wenn kleiner).
/// - Profilbilder & Flugschul-Logos: auf max. 512 × 512 px optimieren.
/// - Harte Upload-Obergrenze nach Optimierung: 4 MB für Dokumente, 500 KB für Avatare/Logos.
class FileOptimizationService {
  static final FileOptimizationService _instance =
      FileOptimizationService._internal();
  factory FileOptimizationService() => _instance;
  FileOptimizationService._internal();

  static const int maxRawInputBytes = 25 * 1024 * 1024; // 25 MB Eingabelimit
  static const int maxDocumentUploadBytes = 4 * 1024 * 1024; // 4 MB Upload-Limit
  static const int pdfCompressThresholdBytes = 1 * 1024 * 1024; // PDFs > 1 MB
  static const int imageDocumentTargetBytes = 1200 * 1024; // Ziel ~1,2 MB
  static const int maxAvatarUploadBytes = 500 * 1024; // 500 KB für Avatare/Logos

  static const Set<String> _imageExtensions = {'jpg', 'jpeg', 'png', 'webp'};

  /// Ermittelt die Dateiendung zunächst über den Dateinamen und fällt bei
  /// fehlender/unbekannter Endung (häufig bei Android-Chrome / Google Drive)
  /// zuverlässig auf die Magic-Bytes des Dateiinhalts zurück.
  static String detectExtension({
    required String fileName,
    required Uint8List bytes,
  }) {
    final idx = fileName.lastIndexOf('.');
    if (idx >= 0 && idx < fileName.length - 1) {
      final rawExt = fileName.substring(idx + 1).toLowerCase().trim();
      if (rawExt == 'pdf' || _imageExtensions.contains(rawExt)) {
        return rawExt;
      }
    }
    // Magic-Bytes prüfen
    if (bytes.length >= 5 &&
        bytes[0] == 0x25 && // %
        bytes[1] == 0x50 && // P
        bytes[2] == 0x44 && // D
        bytes[3] == 0x46 && // F
        bytes[4] == 0x2D) {
      return 'pdf';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'jpg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return 'png';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 && // R
        bytes[1] == 0x49 && // I
        bytes[2] == 0x46 && // F
        bytes[3] == 0x46 && // F
        bytes[8] == 0x57 && // W
        bytes[9] == 0x45 && // E
        bytes[10] == 0x42 && // B
        bytes[11] == 0x50) {
      return 'webp';
    }
    if (idx >= 0 && idx < fileName.length - 1) {
      return fileName.substring(idx + 1).toLowerCase().trim();
    }
    return '';
  }

  /// Stellt sicher, dass der Dateiname mit der erkannten Endung abschließt
  /// (wichtig für Appwrite-Bucket-Prüfung & PDF/Bild-Vorschau).
  static String ensureExtension(String fileName, String ext) {
    final trimmed = fileName.trim();
    final base = trimmed.isEmpty ? 'dokument' : trimmed;
    if (ext.isEmpty) return base;
    if (base.toLowerCase().endsWith('.$ext')) return base;
    if (ext == 'jpg' && base.toLowerCase().endsWith('.jpeg')) return base;
    return '$base.$ext';
  }

  String _mimeForExt(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'image/jpeg';
    }
  }

  String _replaceExtWithJpg(String fileName) {
    final idx = fileName.lastIndexOf('.');
    if (idx <= 0) return '$fileName.jpg';
    return '${fileName.substring(0, idx)}.jpg';
  }

  /// Optimiert ein Qualifikationsdokument (Bild oder PDF > 1 MB) clientseitig
  /// und prüft anschließend das harte 4-MB-Upload-Limit.
  Future<OptimizedFileResult> optimizeDocument({
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (bytes.isEmpty) {
      throw Exception('Die ausgewählte Datei ist leer.');
    }
    if (bytes.length > maxRawInputBytes) {
      throw Exception(
        'Die Datei ist größer als 25 MB und kann nicht verarbeitet werden.',
      );
    }

    final ext = detectExtension(fileName: fileName, bytes: bytes);
    final normalizedName = ensureExtension(fileName, ext);
    if (_imageExtensions.contains(ext)) {
      return _optimizeImageDocument(
        bytes: bytes,
        fileName: normalizedName,
        ext: ext,
        maxDimension: 1800,
        targetBytes: imageDocumentTargetBytes,
        hardLimitBytes: maxDocumentUploadBytes,
      );
    }

    if (ext == 'pdf') {
      return _optimizePdfDocument(
        bytes: bytes,
        fileName: normalizedName,
        compressThresholdBytes: pdfCompressThresholdBytes,
        hardLimitBytes: maxDocumentUploadBytes,
      );
    }

    // Andere Dateitypen unverändert prüfen
    if (bytes.length > maxDocumentUploadBytes) {
      throw Exception(
        'Die Datei überschreitet das Upload-Limit von 4 MB (${OptimizedFileResult.formatSize(bytes.length)}).',
      );
    }
    return OptimizedFileResult(
      bytes: bytes,
      fileName: normalizedName,
      originalBytes: bytes.length,
      wasOptimized: false,
    );
  }

  /// Optimiert ein Profilbild oder Flugschul-Logo auf max. 512 × 512 px (max. 500 KB).
  Future<OptimizedFileResult> optimizeAvatarOrLogo({
    required Uint8List bytes,
    required String fileName,
    bool preserveTransparency = false,
  }) async {
    if (bytes.isEmpty) {
      throw Exception('Die ausgewählte Bilddatei ist leer.');
    }
    if (bytes.length > maxRawInputBytes) {
      throw Exception('Das Bild darf maximal 25 MB groß sein.');
    }

    final ext = detectExtension(fileName: fileName, bytes: bytes);
    final normalizedName = ensureExtension(fileName, ext);
    final mime = _mimeForExt(ext);
    final originalLen = bytes.length;

    // Logos mit Transparenz (PNG) zunächst als kompaktes 512-px-PNG versuchen
    if (preserveTransparency && ext == 'png') {
      final pngBytes = await platformOptimizeImage(
        bytes: bytes,
        mimeType: mime,
        maxDimension: 512,
        quality: 85,
        outputPng: true,
      );
      if (pngBytes != null &&
          pngBytes.isNotEmpty &&
          pngBytes.length <= maxAvatarUploadBytes) {
        final chosen = pngBytes.length < originalLen ? pngBytes : bytes;
        return OptimizedFileResult(
          bytes: chosen,
          fileName: normalizedName,
          originalBytes: originalLen,
          wasOptimized: chosen.length < originalLen,
        );
      }
    }

    return _optimizeImageDocument(
      bytes: bytes,
      fileName: normalizedName,
      ext: ext,
      maxDimension: 512,
      targetBytes: 180 * 1024,
      hardLimitBytes: maxAvatarUploadBytes,
    );
  }

  /// Optimiert ein eingebettetes Bild in Einweisungs-Dokumenten (max. 1600 px).
  Future<OptimizedFileResult> optimizeInstructionImage({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final ext = detectExtension(fileName: fileName, bytes: bytes);
    final normalizedName = ensureExtension(fileName, ext);
    if (!_imageExtensions.contains(ext) || bytes.length <= 250 * 1024) {
      return OptimizedFileResult(
        bytes: bytes,
        fileName: normalizedName,
        originalBytes: bytes.length,
        wasOptimized: false,
      );
    }
    try {
      return await _optimizeImageDocument(
        bytes: bytes,
        fileName: normalizedName,
        ext: ext,
        maxDimension: 1600,
        targetBytes: 900 * 1024,
        hardLimitBytes: maxDocumentUploadBytes,
      );
    } catch (_) {
      return OptimizedFileResult(
        bytes: bytes,
        fileName: normalizedName,
        originalBytes: bytes.length,
        wasOptimized: false,
      );
    }
  }

  Future<OptimizedFileResult> _optimizeImageDocument({
    required Uint8List bytes,
    required String fileName,
    required String ext,
    required int maxDimension,
    required int targetBytes,
    required int hardLimitBytes,
  }) async {
    final originalLen = bytes.length;
    final mime = _mimeForExt(ext);

    Uint8List bestBytes = bytes;
    String bestName = fileName;

    // 3 abgestufte Qualitäts-Pässe (stoppt sofort, sobald das Ziel erreicht ist)
    final passes = <({int maxDim, int quality})>[
      (maxDim: maxDimension, quality: 82),
      (maxDim: maxDimension, quality: 68),
      (maxDim: (maxDimension * 0.78).round(), quality: 60),
    ];

    for (final pass in passes) {
      final candidate = await platformOptimizeImage(
        bytes: bytes,
        mimeType: mime,
        maxDimension: pass.maxDim,
        quality: pass.quality,
        outputPng: false,
      );
      if (candidate != null &&
          candidate.isNotEmpty &&
          candidate.length < bestBytes.length) {
        bestBytes = candidate;
        bestName = _replaceExtWithJpg(fileName);
      }
      if (bestBytes.length <= targetBytes) break;
    }

    if (bestBytes.length > hardLimitBytes) {
      throw Exception(
        'Das Bild ist auch nach Komprimierung größer als ${OptimizedFileResult.formatSize(hardLimitBytes)} (${OptimizedFileResult.formatSize(bestBytes.length)}). Bitte wähle ein kleineres Bild.',
      );
    }

    return OptimizedFileResult(
      bytes: bestBytes,
      fileName: bestName,
      originalBytes: originalLen,
      wasOptimized: bestBytes.length < originalLen,
    );
  }

  Future<OptimizedFileResult> _optimizePdfDocument({
    required Uint8List bytes,
    required String fileName,
    required int compressThresholdBytes,
    required int hardLimitBytes,
  }) async {
    final originalLen = bytes.length;

    // Kleine digitale PDFs (<= 1 MB) unverändert lassen (Vektortext bleibt verlustfrei)
    if (originalLen <= compressThresholdBytes) {
      return OptimizedFileResult(
        bytes: bytes,
        fileName: fileName,
        originalBytes: originalLen,
        wasOptimized: false,
      );
    }

    Uint8List bestBytes = bytes;

    // 1. Durchlauf: ~150 DPI (1650 px lange Kante), JPEG 76 %
    // 2. Durchlauf (nur falls noch > 4 MB): ~115 DPI (1280 px), JPEG 62 %
    final passes = <({int maxDim, int quality})>[
      (maxDim: 1650, quality: 76),
      (maxDim: 1280, quality: 62),
    ];

    for (final pass in passes) {
      final rendered = await platformRenderPdfPages(
        bytes: bytes,
        maxDimension: pass.maxDim,
        quality: pass.quality,
        maxPages: 40,
      );
      if (rendered == null || rendered.isEmpty) {
        break;
      }

      try {
        final compressedPdf = await _assembleJpegPagesToPdf(rendered);
        if (compressedPdf.isNotEmpty && compressedPdf.length < bestBytes.length) {
          bestBytes = compressedPdf;
        }
      } catch (e) {
        debugPrint('PDF reassembly error: $e');
        break;
      }

      if (bestBytes.length <= hardLimitBytes) {
        break;
      }
    }

    if (bestBytes.length > hardLimitBytes) {
      throw Exception(
        'Das PDF ist auch nach Komprimierung größer als ${OptimizedFileResult.formatSize(hardLimitBytes)} (${OptimizedFileResult.formatSize(bestBytes.length)}). Bitte verkleinere das PDF oder lade weniger Seiten hoch.',
      );
    }

    return OptimizedFileResult(
      bytes: bestBytes,
      fileName: fileName,
      originalBytes: originalLen,
      wasOptimized: bestBytes.length < originalLen,
    );
  }

  Future<Uint8List> _assembleJpegPagesToPdf(List<RenderedPdfPage> pages) async {
    final pdfDoc = pw.Document(compress: true);
    for (final p in pages) {
      final pageFormat = PdfPageFormat(p.widthPt, p.heightPt, marginAll: 0);
      final memImg = pw.MemoryImage(p.jpegBytes);
      pdfDoc.addPage(
        pw.Page(
          pageFormat: pageFormat,
          build: (_) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Image(memImg, fit: pw.BoxFit.fill),
          ),
        ),
      );
    }
    return Uint8List.fromList(await pdfDoc.save());
  }
}
