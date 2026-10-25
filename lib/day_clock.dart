/// Uur waarop een nieuwe dag begint (0–5). Wie na middernacht nog eet, logt tot dan op de dag ervoor.
int dayStartHour = 3;

/// De klok van de app. Alleen tests zetten hier een vast moment (bv. 00:40, als de app-dag nog gisteren is).
DateTime Function() appClock = DateTime.now;

/// Het moment van nu, verschoven naar de dag waarin je zit: vóór [dayStartHour] is het nog gisteren.
/// Gebruik dit voor alles wat bepaalt welke dag "vandaag" is, niet voor kloktijden.
///
/// Op de klok gerekend, niet in echte uren: in de nacht dat de klok verspringt, is 03:30 al vandaag en het tweede
/// 02:30 nog gisteren.
DateTime logicalNow() {
  final n = appClock();
  return n.isUtc
      ? DateTime.utc(n.year, n.month, n.day, n.hour - dayStartHour, n.minute, n.second, n.millisecond)
      : DateTime(n.year, n.month, n.day, n.hour - dayStartHour, n.minute, n.second, n.millisecond);
}

/// Aantal kalenderdagen van [from] tot [to], los van de klok (een dag met zomer- of wintertijd telt ook als één).
int daysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

extension CalendarDays on DateTime {
  /// [days] kalenderdagen verder (of terug), op dezelfde kloktijd. Niet `add(Duration(days: …))`: op de dag dat de
  /// klok verspringt duurt een dag 23 of 25 uur, en dan kom je op dezelfde dag of één te ver uit.
  DateTime plusDays(int days) => isUtc
      ? DateTime.utc(year, month, day + days, hour, minute, second, millisecond, microsecond)
      : DateTime(year, month, day + days, hour, minute, second, millisecond, microsecond);
}
