/// Zentrales Zeitfenster für Standard-Datenabfragen (Events, Tandem-Einsätze).
/// Begrenzt initial geladene Historie auf [heute - 3 Monate .. heute + 18 Monate],
/// damit wachsende Mehrjahres-Tabellen den App-Start dauerhaft schnell halten.
/// Ältere oder weiter entfernte Einträge können bei Bedarf („Archiv laden“)
/// gezielt nachgeladen werden.
class DataWindow {
  static const Duration pastHorizon = Duration(days: 90);
  static const Duration futureHorizon = Duration(days: 540);

  static DateTime defaultStart([DateTime? reference]) =>
      (reference ?? DateTime.now()).subtract(pastHorizon);

  static DateTime defaultEnd([DateTime? reference]) =>
      (reference ?? DateTime.now()).add(futureHorizon);

  /// Prüft, ob ein Zeitpunkt außerhalb des Standard-Zeitfensters liegt.
  static bool isOutsideDefaultWindow(DateTime date, [DateTime? reference]) {
    final start = defaultStart(reference);
    final end = defaultEnd(reference);
    return date.isBefore(start) || date.isAfter(end);
  }

  /// Prüft, ob ein angezeigter Kalendermonat (1. des Monats) ganz oder teilweise
  /// außerhalb des Standard-Zeitfensters liegt.
  static bool isMonthOutsideDefaultWindow(
    DateTime monthFirstDay, [
    DateTime? reference,
  ]) {
    final start = defaultStart(reference);
    final end = defaultEnd(reference);
    final monthStart = DateTime(monthFirstDay.year, monthFirstDay.month, 1);
    final monthEnd = DateTime(
      monthFirstDay.year,
      monthFirstDay.month + 1,
      0,
      23,
      59,
      59,
    );
    return monthStart.isBefore(start) || monthEnd.isAfter(end);
  }

  /// Prüft, ob ein ganzes Kalenderjahr außerhalb des Standard-Zeitfensters liegt.
  static bool isYearOutsideDefaultWindow(int year, [DateTime? reference]) {
    final start = defaultStart(reference);
    final end = defaultEnd(reference);
    final yearStart = DateTime(year, 1, 1);
    final yearEnd = DateTime(year, 12, 31, 23, 59, 59);
    return yearStart.isBefore(start) || yearEnd.isAfter(end);
  }
}
