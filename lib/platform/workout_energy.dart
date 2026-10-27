/// Verbrande energie van een workout uit Health Connect, zonder je rustverbruik: dat zit al in je doel
/// (ruststofwisseling × activiteitsniveau), dus anders telt het dubbel. Los van het health-pakket, zodat het te testen
/// is zonder toestel.
library;

/// Een blok actieve energie (ActiveCaloriesBurnedRecord) van [start] tot [end].
class EnergySpan {
  const EnergySpan(this.start, this.end, this.kcal);
  final DateTime start, end;
  final double kcal;
}

/// Actieve energie van een workout van [start] tot [end], in kcal, of null als er niets te rekenen valt.
///
/// Eerst de blokken uit [active] die binnen de workout vallen (een minuut speling): een horloge schrijft die per
/// workout of per paar minuten. Een blok dat ver buiten de workout loopt (bv. een dagtotaal) telt niet, want daar zit
/// meer in dan de training. Nooit meer dan het totaal [total]. Zonder bruikbare blokken: het totaal min je
/// rustverbruik voor de duur van de workout ([restKcalPerMin] = ruststofwisseling / 1440), minstens 0.
double? workoutActiveKcal({
  required DateTime start,
  required DateTime end,
  required double? total,
  required List<EnergySpan> active,
  required double restKcalPerMin,
}) {
  const slack = Duration(minutes: 1);
  final inside = [
    for (final a in active)
      if (!a.start.isBefore(start.subtract(slack)) && !a.end.isAfter(end.add(slack)) && a.kcal > 0) a.kcal,
  ];
  if (inside.isNotEmpty) {
    final sum = inside.fold(0.0, (a, b) => a + b);
    return total != null && total > 0 && sum > total ? total : sum;
  }
  if (total == null || total <= 0) return null;
  final minutes = end.difference(start).inSeconds / 60;
  final rest = restKcalPerMin * (minutes > 0 ? minutes : 0);
  return total - rest > 0 ? total - rest : 0;
}
