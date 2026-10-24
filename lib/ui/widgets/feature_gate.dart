/// Kleine onderdelen voor vroege toegang: [featureOn] om iets achter een vlag te zetten, en het label
/// "Early access" (zie lib/sync/features.dart voor hoe je een functie achter een vlag zet).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n.dart';
import '../../sync/features.dart';
import '../theme.dart';

/// De vlaggen, als ze er zijn. Schermen die zonder (bv. in tests) gebouwd worden, krijgen null.
Features? featuresOf(BuildContext context, {bool listen = true}) => listen ? context.watch<Features?>() : context.read<Features?>();

/// Staat functie [id] aan? Bouwt opnieuw als dat verandert. Zonder [Features] (bv. in tests): de standaard uit
/// [knownFeatures].
bool featureOn(BuildContext context, String id) => featuresOf(context)?.has(id) ?? (knownFeatures[id] ?? false);

/// "Early access" bij een functie die je nu alleen als supporter hebt.
class EarlyAccessChip extends StatelessWidget {
  const EarlyAccessChip({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      key: const ValueKey('early-access-chip'),
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: p.brandSoft, borderRadius: BorderRadius.circular(11)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt_rounded, size: 13, color: p.brand),
          const SizedBox(width: 3),
          Text(
            tr('Early access', 'Vroege toegang'),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: p.brand),
          ),
        ],
      ),
    );
  }
}
