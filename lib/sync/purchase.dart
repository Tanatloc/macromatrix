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

enum ProPlan {
  monthly(299, 'month', 'pro_monthly'),
  yearly(1999, 'year', 'pro_yearly');

  const ProPlan(this.cents, this.period, this.productId);

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

  /// "€19.99 / year" met een andere prijs (bv. die van de winkel, in je eigen munt).
  String labelFor(String price) => switch (this) {
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
