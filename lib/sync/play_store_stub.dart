/// Zonder Google Play: op het web, en in de F-Droid-build (tool/fdroid_no_billing.sh kopieert dit bestand over
/// play_store_plugin.dart en haalt in_app_purchase uit pubspec.yaml). Pro toont dan "Binnenkort".
library;

import 'play_purchase.dart';

PlayStore? createPlayStore() => null;
