/// Uur waarop een nieuwe dag begint (0–5). Wie na middernacht nog eet, logt tot dan op de dag ervoor.
int dayStartHour = 3;

/// Het moment van nu, verschoven naar de dag waarin je zit: vóór [dayStartHour] is het nog gisteren.
/// Gebruik dit voor alles wat bepaalt welke dag "vandaag" is, niet voor kloktijden.
DateTime logicalNow() => DateTime.now().subtract(Duration(hours: dayStartHour));
