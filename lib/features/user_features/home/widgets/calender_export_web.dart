// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:convert';
import 'package:season_planner/data/models/event_model.dart';

void exportEventAsICS(Event event) {
  final startUtc = event.startTime.toUtc();
  final endUtc = event.endTime.toUtc();

  String formatDate(DateTime dt) =>
      "${dt.year.toString().padLeft(4, '0')}"
          "${dt.month.toString().padLeft(2, '0')}"
          "${dt.day.toString().padLeft(2, '0')}T"
          "${dt.hour.toString().padLeft(2, '0')}"
          "${dt.minute.toString().padLeft(2, '0')}"
          "${dt.second.toString().padLeft(2, '0')}Z";

  String esc(String s) => s
      .replaceAll('\\', '\\\\')
      .replaceAll('\n', '\\n')
      .replaceAll(',', '\\,')
      .replaceAll(';', '\\;');

  final icsContent = '''
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Season Planner//EN
CALSCALE:GREGORIAN
METHOD:PUBLISH
BEGIN:VEVENT
UID:${esc(event.id)}
DTSTAMP:${formatDate(DateTime.now().toUtc())}
DTSTART:${formatDate(startUtc)}
DTEND:${formatDate(endUtc)}
SUMMARY:${esc(event.displayName)}
DESCRIPTION:${esc(event.notes)}
LOCATION:${esc((event.location ?? "").toString())}
END:VEVENT
END:VCALENDAR
''';

  final bytes = utf8.encode(icsContent);
  final blob = html.Blob([bytes], 'text/calendar;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);

  final safeName = event.displayName
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      .trim();

  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', '${safeName.isEmpty ? "event" : safeName}.ics')
    ..style.display = 'none';

  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();

  html.Url.revokeObjectUrl(url);
}
