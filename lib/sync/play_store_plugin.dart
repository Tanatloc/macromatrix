/// [PlayStore] met de in_app_purchase-plugin (Google Play Billing). Het enige bestand dat de plugin gebruikt: de
/// F-Droid-build vervangt het door play_store_stub.dart (zie tool/fdroid_no_billing.sh).
library;

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import 'play_purchase.dart';

PlayStore? createPlayStore() => InAppPurchasePlayStore();

class InAppPurchasePlayStore implements PlayStore {
  InAppPurchasePlayStore([InAppPurchase? iap]) : _iap = iap ?? InAppPurchase.instance;
  final InAppPurchase _iap;

  @override
  Future<bool> isAvailable() => _iap.isAvailable();

  @override
  Future<List<StoreProduct>> products(Set<String> ids) async {
    final r = await _iap.queryProductDetails(ids);
    // Per abonnement één regel per basisabonnement en per aanbieding: we nemen het basisabonnement (zonder offerId),
    // zodat een latere proefperiode of korting niet als vaste prijs getoond wordt
    final byId = <String, ProductDetails>{};
    for (final d in r.productDetails) {
      final isBase = d is! GooglePlayProductDetails ||
          d.subscriptionIndex == null ||
          d.productDetails.subscriptionOfferDetails![d.subscriptionIndex!].offerId == null;
      if (isBase) {
        byId[d.id] = d;
      } else {
        byId.putIfAbsent(d.id, () => d);
      }
    }
    return [for (final d in byId.values) StoreProduct(id: d.id, price: d.price, raw: d)];
  }

  @override
  Stream<List<StorePurchase>> get purchases => _iap.purchaseStream.map((list) => [for (final p in list) _wrap(p)]);

  StorePurchase _wrap(PurchaseDetails p) => StorePurchase(
    productId: p.productID,
    token: p.verificationData.serverVerificationData,
    status: switch (p.status) {
      PurchaseStatus.pending => StorePurchaseStatus.pending,
      PurchaseStatus.purchased => StorePurchaseStatus.purchased,
      PurchaseStatus.restored => StorePurchaseStatus.restored,
      PurchaseStatus.error => StorePurchaseStatus.error,
      PurchaseStatus.canceled => StorePurchaseStatus.canceled,
    },
    packageName: p is GooglePlayPurchaseDetails ? p.billingClientPurchase.packageName : null,
    needsCompletion: p.pendingCompletePurchase,
    error: p.error == null ? null : '${p.error!.code} ${p.error!.message}',
    raw: p,
  );

  @override
  Future<bool> buy(StoreProduct product, {String? accountId}) =>
      _iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: product.raw! as ProductDetails, applicationUserName: accountId));

  @override
  Future<void> complete(StorePurchase purchase) => _iap.completePurchase(purchase.raw! as PurchaseDetails);

  @override
  Future<void> restore() => _iap.restorePurchases();
}
