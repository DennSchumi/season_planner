import 'dart:convert';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:season_planner/core/data/models/timesheet_model.dart';

class TimesheetExportRow {
  final DateTime date;
  final String dateLabel;
  final String memberName;
  final String schoolName;
  final String eventName;
  final String roleName;
  final String startLabel;
  final String endLabel;
  final int breakMinutes;
  final int netMinutes;
  final String statusLabel;

  const TimesheetExportRow({
    required this.date,
    required this.dateLabel,
    required this.memberName,
    required this.schoolName,
    required this.eventName,
    required this.roleName,
    required this.startLabel,
    required this.endLabel,
    required this.breakMinutes,
    required this.netMinutes,
    required this.statusLabel,
  });
}

class TimesheetExportService {
  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  /// Bereinigt Unicode-Zeichen, die nicht in der PDF-Standard-Helvetica (WinAnsi/Latin-1)
  /// enthalten sind (z. B. Gedankenstrich U+2013, typografische Anführungszeichen, Emojis).
  static String _pdfSafe(String input) {
    final replaced = input
        .replaceAll('\u2013', '-') // en-dash –
        .replaceAll('\u2014', '-') // em-dash —
        .replaceAll('\u2212', '-') // minus −
        .replaceAll('\u2018', "'")
        .replaceAll('\u2019', "'")
        .replaceAll('\u201A', "'")
        .replaceAll('\u201C', '"')
        .replaceAll('\u201D', '"')
        .replaceAll('\u201E', '"')
        .replaceAll('\u2026', '...')
        .replaceAll('\u2022', '-')
        .replaceAll('\u00A0', ' ');
    final buf = StringBuffer();
    for (final rune in replaced.runes) {
      if (rune == 0x0A || rune == 0x0D || (rune >= 0x20 && rune <= 0xFF)) {
        buf.writeCharCode(rune);
      }
    }
    return buf.toString();
  }

  /// Zerlegt alle Stundenzettel im gewählten Zeitraum [from]..[to] in chronologische Tageszeilen.
  static List<TimesheetExportRow> flattenRows({
    required List<EventTimesheet> sheets,
    required DateTime from,
    required DateTime to,
    required String Function(String schoolId) resolveSchoolName,
    required String Function(String userId) resolveMemberName,
    bool onlySubmitted = true,
  }) {
    final fromDay = DateTime(from.year, from.month, from.day);
    final toDay = DateTime(to.year, to.month, to.day);
    final rows = <TimesheetExportRow>[];

    for (final sheet in sheets) {
      if (onlySubmitted && !sheet.isSubmitted) continue;
      final schoolName = resolveSchoolName(sheet.flightSchoolId);
      final memberName = resolveMemberName(sheet.userId);

      for (final entry in sheet.entries) {
        if (!entry.active || entry.netMinutes <= 0) continue;
        final d = entry.date;
        if (d.isBefore(fromDay) || d.isAfter(toDay)) continue;

        rows.add(
          TimesheetExportRow(
            date: d,
            dateLabel: entry.formattedDate,
            memberName: memberName,
            schoolName: schoolName,
            eventName: sheet.eventName,
            roleName: sheet.roleName,
            startLabel: entry.startLabel,
            endLabel: entry.endLabel,
            breakMinutes: entry.breakMinutes,
            netMinutes: entry.netMinutes,
            statusLabel: sheet.status.label,
          ),
        );
      }
    }

    rows.sort((a, b) {
      final c = a.date.compareTo(b.date);
      if (c != 0) return c;
      return a.eventName.toLowerCase().compareTo(b.eventName.toLowerCase());
    });
    return rows;
  }

  static String _csvCell(String raw) {
    final clean = raw.replaceAll('"', '""');
    if (clean.contains(';') || clean.contains('"') || clean.contains('\n')) {
      return '"$clean"';
    }
    return clean;
  }

  /// Erzeugt eine deutsche Excel-kompatible CSV-Datei (UTF-8 mit BOM, Semikolon-getrennt).
  static Uint8List buildCsvBytes({
    required List<TimesheetExportRow> rows,
    required bool includeMemberColumn,
  }) {
    final buf = StringBuffer();
    final header = [
      'Datum',
      if (includeMemberColumn) 'Mitarbeiter',
      'Flugschule',
      'Event',
      'Rolle',
      'Beginn',
      'Ende',
      'Pause (Min.)',
      'Arbeitszeit (Std.)',
      'Arbeitszeit (Dezimal)',
    ];
    buf.writeln(header.map(_csvCell).join(';'));

    int totalMinutes = 0;
    for (final r in rows) {
      totalMinutes += r.netMinutes;
      final cols = [
        r.dateLabel,
        if (includeMemberColumn) r.memberName,
        r.schoolName,
        r.eventName,
        r.roleName,
        r.startLabel,
        r.endLabel,
        '${r.breakMinutes}',
        formatMinutesAsHours(r.netMinutes),
        formatMinutesAsDecimal(r.netMinutes),
      ];
      buf.writeln(cols.map(_csvCell).join(';'));
    }

    final totalCols = [
      'GESAMT',
      if (includeMemberColumn) '',
      '',
      '${rows.length} Einsatztage',
      '',
      '',
      '',
      '',
      formatMinutesAsHours(totalMinutes),
      formatMinutesAsDecimal(totalMinutes),
    ];
    buf.writeln(totalCols.map(_csvCell).join(';'));

    final utf8Bytes = utf8.encode(buf.toString());
    return Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8Bytes]);
  }

  /// Erzeugt einen druckfertigen PDF-Lehrtätigkeits-Nachweis im A4-Format.
  static Future<Uint8List> buildPdfBytes({
    required List<TimesheetExportRow> rows,
    required String title,
    required String subtitle,
    required DateTime from,
    required DateTime to,
    required bool includeMemberColumn,
    Uint8List? latestSignatureBytes,
    String? signerName,
  }) async {
    final doc = pw.Document(
      title: _pdfSafe(title),
      author: 'Season Planner',
    );

    final totalMinutes = rows.fold<int>(0, (s, r) => s + r.netMinutes);
    final uniqueDays = rows.map((r) => r.dateLabel).toSet().length;
    final uniqueEvents =
        rows.map((r) => '${r.schoolName}|${r.eventName}').toSet().length;
    final createdStr = _fmtDate(DateTime.now());

    final accentColor = PdfColor.fromHex('#5B3DF5');
    final lightBg = PdfColor.fromHex('#F4F4F6');
    final borderColor = PdfColor.fromHex('#D8DCE3');
    final mutedText = PdfColor.fromHex('#5B6270');

    final headers = <String>[
      'Datum',
      if (includeMemberColumn) 'Mitarbeiter',
      'Flugschule',
      'Event / Rolle',
      'Zeit',
      'Pause',
      'Netto',
    ];

    final tableData = rows.map((r) {
      return <String>[
        _pdfSafe(r.dateLabel),
        if (includeMemberColumn) _pdfSafe(r.memberName),
        _pdfSafe(r.schoolName),
        _pdfSafe(
          r.roleName.isNotEmpty
              ? '${r.eventName} (${r.roleName})'
              : r.eventName,
        ),
        _pdfSafe('${r.startLabel}-${r.endLabel}'),
        '${r.breakMinutes} Min.',
        _pdfSafe(formatMinutesAsHours(r.netMinutes)),
      ];
    }).toList();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(32, 32, 32, 36),
        footer: (ctx) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 10),
          child: pw.Text(
            _pdfSafe(
              'Erstellt am $createdStr | Season Planner | Seite ${ctx.pageNumber} von ${ctx.pagesCount}',
            ),
            style: pw.TextStyle(fontSize: 8.5, color: mutedText),
          ),
        ),
        build: (ctx) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      _pdfSafe(title),
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                        color: accentColor,
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      _pdfSafe(subtitle),
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Zeitraum: ${_fmtDate(from)} - ${_fmtDate(to)}',
                      style: pw.TextStyle(fontSize: 10, color: mutedText),
                    ),
                  ],
                ),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: pw.BoxDecoration(
                  color: lightBg,
                  borderRadius: pw.BorderRadius.circular(8),
                  border: pw.Border.all(color: borderColor),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      formatMinutesAsHours(totalMinutes),
                      style: pw.TextStyle(
                        fontSize: 15,
                        fontWeight: pw.FontWeight.bold,
                        color: accentColor,
                      ),
                    ),
                    pw.Text(
                      '$uniqueDays Einsatztage | $uniqueEvents Events',
                      style: pw.TextStyle(fontSize: 9, color: mutedText),
                    ),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          if (tableData.isEmpty)
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                color: lightBg,
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Text(
                'Keine abgesendeten Stundenzettel im gewählten Zeitraum vorhanden.',
                style: pw.TextStyle(fontSize: 10.5, color: mutedText),
              ),
            )
          else
            pw.TableHelper.fromTextArray(
              headers: headers,
              data: tableData,
              headerStyle: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: pw.BoxDecoration(color: accentColor),
              cellStyle: const pw.TextStyle(fontSize: 8.8),
              cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 5,
              ),
              border: pw.TableBorder.all(color: borderColor, width: 0.5),
              oddRowDecoration: pw.BoxDecoration(color: lightBg),
              cellAlignments: {
                headers.length - 1: pw.Alignment.centerRight,
                headers.length - 2: pw.Alignment.centerRight,
              },
            ),
          pw.SizedBox(height: 12),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: pw.BoxDecoration(
              color: lightBg,
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(color: borderColor),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Gesamt-Arbeitszeit im Zeitraum ($uniqueDays Tage / $uniqueEvents Events)',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  '${formatMinutesAsHours(totalMinutes)} (${formatMinutesAsDecimal(totalMinutes)} Std. dez.)',
                  style: pw.TextStyle(
                    fontSize: 10.5,
                    fontWeight: pw.FontWeight.bold,
                    color: accentColor,
                  ),
                ),
              ],
            ),
          ),
          if (latestSignatureBytes != null) ...[
            pw.SizedBox(height: 20),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Container(
                      width: 170,
                      height: 54,
                      padding: const pw.EdgeInsets.all(4),
                      decoration: pw.BoxDecoration(
                        border: pw.Border(
                          bottom: pw.BorderSide(color: borderColor, width: 1),
                        ),
                      ),
                      child: pw.Image(
                        pw.MemoryImage(latestSignatureBytes),
                        fit: pw.BoxFit.contain,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      signerName != null && signerName.isNotEmpty
                          ? _pdfSafe('Digitale Unterschrift | $signerName')
                          : 'Digitale Unterschrift',
                      style: pw.TextStyle(fontSize: 8.5, color: mutedText),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ],
      ),
    );

    return doc.save();
  }
}
