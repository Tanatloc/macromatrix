/// Korte tip in de webapp als de browser geen grafische versnelling (WebGL) geeft, bv. LibreWolf standaard: de app
/// werkt dan wel, maar voelt traag aan. Eén keer per browser; wie op OK tikt, ziet hem niet meer (lokale instelling
/// `_webgl_tip`, niet gesynchroniseerd: een andere browser kan het wel nodig hebben).
library;

import 'package:flutter/material.dart';

import '../../data/user_db.dart';
import '../../i18n.dart';
import '../../platform/platform.dart' as platform;

const _key = '_webgl_tip';

/// De tip tonen als dat nodig is. [accelerated]: te vervangen in tests (anders [platform.graphicsAccelerated]).
void maybeShowWebGlTip(BuildContext context, UserDb user, {bool? accelerated}) {
  if (accelerated ?? platform.graphicsAccelerated) return;
  if (user.setting(_key)?['dismissed'] == true) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.showMaterialBanner(
    MaterialBanner(
      key: const ValueKey('webgl-tip'),
      leading: const Icon(Icons.speed_rounded),
      content: Text(
        tr(
          'Your browser has graphics acceleration turned off, so the app may feel slow. In LibreWolf: about:config → webgl.disabled = false.',
          'Je browser heeft grafische versnelling uitgezet, waardoor de app traag kan aanvoelen. In LibreWolf: about:config → webgl.disabled = false.',
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('webgl-tip-ok'),
          onPressed: () {
            user.setSetting(_key, {'dismissed': true});
            messenger.hideCurrentMaterialBanner();
          },
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
