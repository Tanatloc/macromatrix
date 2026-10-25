/// Betalen voor Pro: de naad waar Google Play Billing (lib/sync/play_purchase.dart) en later een betaalpagina op het
/// web (Stripe of Mollie) inpluggen.
///
/// De app beslist nooit zelf of je Pro hebt: dat komt altijd van de server (pro_status, zie lib/sync/pro.dart). Een
/// [PurchaseProvider] start alleen de betaling of het herstel; daarna schrijft de server (/api/play-verify met de
/// service-role) de status, en de app haalt ze opnieuw op.
///
/// De in_app_purchase-plugin zit alleen in lib/sync/play_store_plugin.dart. De F-Droid-build mag geen niet-vrije
/// bibliotheken bevatten: daar vervangt tool/fdroid_no_billing.sh dat bestand door play_store_stub.dart en haalt de
/// plugin uit pubspec.yaml, en blijft het [NoPurchaseProvider].
library;

import '../i18n.dart';

/// De abonnementen (prijzen van 25-10-2026). Duo: jij en één vriend die je kiest (server/src/rpc/duo.js).
enum ProPlan {
  monthly(399, 'month', 'pro_monthly'),
  yearly(2999, 'year', 'pro_yearly'),
  duoMonthly(499, 'month', 'duo_monthly', duo: true),
  duoYearly(3999, 'year', 'duo_yearly', duo: true);

  const ProPlan(this.cents, this.period, this.productId, {this.duo = false});

  /// Voor twee personen: de koper en één vriend.
  final bool duo;

  /// Het jaarplan bij dit plan (zelfde soort).
  ProPlan get yearlyOfKind => duo ? duoYearly : yearly;

  /// Het maandplan bij dit plan (zelfde soort).
  ProPlan get monthlyOfKind => duo ? duoMonthly : monthly;

  /// Prijs in eurocent, btw inbegrepen.
  final int cents;
  final String period;

  /// Het abonnement in de Play Console (elk met één basisabonnement dat zich vanzelf verlengt). Moet gelijk zijn aan
  /// PRODUCTS in functions/_lib/play.js en aan de check op play_purchases.product.
  final String productId;

  /// Het plan voor een product-id van de winkel (null = geen product van ons).
  static ProPlan? fromProductId(String? id) => values.where((p) => p.productId == id).firstOrNull;

  /// De vaste prijs in euro; de winkel toont liever zijn eigen prijs (zie [PurchaseProvider.priceOf]).
  String get price => '€${(cents / 100).toStringAsFixed(2).replaceAll('.', isNl ? ',' : '.')}';
  String get label => labelFor(price);

  /// "€29.99 / year" met een andere prijs (bv. die van de winkel, in je eigen munt).
  String labelFor(String price) => period == 'month' ? tr('$price / month', '$price / maand') : tr('$price / year', '$price / jaar');
}

/// Hoeveel je met een jaar bespaart tegenover 12 maanden (afgerond op een heel percent), voor Supporter of Duo.
int yearlySavingPercentFor({bool duo = false}) {
  final m = duo ? ProPlan.duoMonthly : ProPlan.monthly, y = duo ? ProPlan.duoYearly : ProPlan.yearly;
  return (100 - y.cents * 100 / (m.cents * 12)).round();
}

int get yearlySavingPercent => yearlySavingPercentFor();

enum PurchaseOutcome {
  /// Betaald of hersteld; de app haalt de status daarna opnieuw op bij de server.
  done,

  /// Zelf afgebroken.
  cancelled,

  /// Nog geen manier om te betalen in deze build (voorlopig overal).
  unavailable,

  /// Iets misgelopen (geen verbinding, winkel weigert, ...).
  failed,

  /// De betaling is nog bezig (bv. contant betalen in een winkel); Pro gaat aan zodra Google ze bevestigt.
  pending,

  /// Niet ingelogd: Pro hoort bij een account.
  signedOut,

  /// Deze aankoop hoort al bij een ander account.
  otherAccount,

  /// De server kan aankopen nog niet nakijken (de koppeling met Google Play staat nog niet klaar).
  notConfigured,

  /// Herstellen: geen aankoop gevonden bij de winkel.
  notFound,
}

abstract class PurchaseProvider {
  const PurchaseProvider();

  /// Kan deze build al betalen? Zo niet, dan toont het Pro-scherm "Binnenkort".
  bool get available;

  /// Een abonnement starten. Bij [PurchaseOutcome.done] staat de betaling bij de winkel; de server zet Pro aan.
  Future<PurchaseOutcome> subscribe(ProPlan plan);

  /// Een eerdere aankoop opnieuw koppelen (nieuw toestel, opnieuw geïnstalleerd).
  Future<PurchaseOutcome> restore();

  /// De prijs zoals de winkel ze toont (in je eigen munt), of null: dan de vaste prijs van [ProPlan].
  String? priceOf(ProPlan plan) => null;

  /// Kan Duo hier gekocht worden (de Duo-producten bestaan in de winkel)?
  bool get duoAvailable => false;

  /// Wacht er een betaling op bevestiging?
  bool get pending => false;

  /// Stil nakijken of een abonnement verlengd is (bij de start, als Pro bijna of net afgelopen is).
  Future<void> recheck() async {}

  /// [Pro] geeft hier mee hoe de status opnieuw opgehaald wordt (na een aankoop die de server goedkeurde).
  void attach(Future<void> Function() refresh) {}
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
