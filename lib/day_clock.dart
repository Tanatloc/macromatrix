/// Uur waarop een nieuwe dag begint (0–5). Wie na middernacht nog eet, logt tot dan op de dag ervoor.
int dayStartHour = 3;

/// Het moment van nu, verschoven naar de dag waarin je zit: vóór [dayStartHour] is het nog gisteren.
/// Gebruik dit voor alles wat bepaalt welke dag "vandaag" is, niet voor kloktijden.
DateTime logicalNow() => DateTime.now().subtract(Duration(hours: dayStartHour));

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
