/// Betalen voor Pro: de naad waar later Google Play Billing (Play-build) en een betaalpagina op het web (Stripe of
/// Mollie) inpluggen.
///
/// De app beslist nooit zelf of je Pro hebt: dat komt altijd van de server (pro_status, zie lib/sync/pro.dart). Een
/// [PurchaseProvider] start alleen de betaling of het herstel; daarna schrijft de server (een webhook met de
/// service-role) de status, en de app haalt ze opnieuw op.
///
/// Bewust zonder in_app_purchase-plugin: de F-Droid-build mag geen niet-vrije bibliotheken bevatten. Die plugin komt
/// later alleen in de Play-build, achter deze interface.
library;

import '../i18n.dart';

enum ProPlan {
  monthly(299, 'month'),
  yearly(1999, 'year');

  const ProPlan(this.cents, this.period);

  /// Prijs in eurocent, btw inbegrepen.
  final int cents;
  final String period;

  String get price => '€${(cents / 100).toStringAsFixed(2).replaceAll('.', isNl ? ',' : '.')}';
  String get label => switch (this) {
    ProPlan.monthly => tr('$price / month', '$price / maand'),
    ProPlan.yearly => tr('$price / year', '$price / jaar'),
  };
}

/// Hoeveel je met een jaar bespaart tegenover 12 maanden (afgerond op een heel percent).
int get yearlySavingPercent => (100 - ProPlan.yearly.cents * 100 / (ProPlan.monthly.cents * 12)).round();

enum PurchaseOutcome {
  /// Betaald of hersteld; de app haalt de status daarna opnieuw op bij de server.
  done,

  /// Zelf afgebroken.
  cancelled,

  /// Nog geen manier om te betalen in deze build (voorlopig overal).
  unavailable,

  /// Iets misgelopen (geen verbinding, winkel weigert, ...).
  failed,
}

abstract class PurchaseProvider {
  const PurchaseProvider();

  /// Kan deze build al betalen? Zo niet, dan toont het Pro-scherm "Binnenkort".
  bool get available;

  /// Een abonnement starten. Bij [PurchaseOutcome.done] staat de betaling bij de winkel; de server zet Pro aan.
  Future<PurchaseOutcome> subscribe(ProPlan plan);

  /// Een eerdere aankoop opnieuw koppelen (nieuw toestel, opnieuw geïnstalleerd).
  Future<PurchaseOutcome> restore();
}

/// Voorlopig: nog geen Google Play-ontwikkelaarsaccount en geen Stripe/Mollie. Alles geeft "nog niet beschikbaar".
class NoPurchaseProvider extends PurchaseProvider {
  const NoPurchaseProvider();

  @override
  bool get available => false;

  @override
  Future<PurchaseOutcome> subscribe(ProPlan plan) async => PurchaseOutcome.unavailable;

  @override
  Future<PurchaseOutcome> restore() async => PurchaseOutcome.unavailable;
}
