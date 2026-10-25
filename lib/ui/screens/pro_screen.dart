import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../i18n.dart';
import '../../sync/pro.dart';
import '../../sync/purchase.dart';
import '../theme.dart';
import '../widgets/avatar_frame_picker.dart';
import '../widgets/kit.dart';
import '../widgets/pro_widgets.dart';
import 'roadmap_screen.dart';

/// Pro: eerlijk uitgelegd. Wat gratis blijft (bijna alles), wat Pro toevoegt en waarom, de prijzen, je status, en
/// abonneren (via Google Play, of "Binnenkort" waar dat niet kan, zie [PurchaseProvider]) of een aankoop herstellen.
class ProScreen extends StatefulWidget {
  const ProScreen({super.key});

  @override
  State<ProScreen> createState() => _ProScreenState();

  /// Wat er gebeurt als je supporterperiode afloopt, volgens waar ze vandaan komt (null: onbekend, dan niets zeggen).
  static String? renewalText(String? source) => switch (source) {
    'play' => tr(
      'Renews automatically through Google Play until you cancel. Cancel any time in Google Play under Payments & subscriptions.',
      'Verlengt automatisch via Google Play tot je opzegt. Opzeggen kan altijd in Google Play onder Betalingen en abonnementen.',
    ),
    null || 'manual' || 'gift' => tr(
      'A gift from MacroMatrix: it does not renew and you pay nothing. Afterwards everything free keeps working.',
      'Een geschenk van MacroMatrix: het verlengt niet en je betaalt niets. Daarna blijft alles wat gratis is gewoon werken.',
    ),
    _ => null,
  };
}

class _ProScreenState extends State<ProScreen> {
  ProPlan _plan = ProPlan.yearly;
  String? _message;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Status vers ophalen (bv. net met de hand toegekend)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) proOf(context, listen: false)?.refresh();
    });
  }

  Future<void> _subscribe(Pro? pro) async {
    setState(() => _busy = true);
    final out = pro == null ? PurchaseOutcome.unavailable : await pro.subscribe(_plan);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = switch (out) {
        PurchaseOutcome.done => tr("Thank you! You're a supporter now.", 'Bedankt! Je bent nu supporter.'),
        PurchaseOutcome.cancelled => null,
        PurchaseOutcome.unavailable => tr(
          "Coming soon. You can't subscribe in the app yet; we'll let you know as soon as you can. Everything that's free stays free.",
          'Binnenkort. Abonneren kan nog niet in de app; we laten het weten zodra het kan. Alles wat gratis is, blijft gratis.',
        ),
        PurchaseOutcome.failed => tr(
          'That did not work. Check your connection and try again.',
          'Dat lukte niet. Controleer je verbinding en probeer opnieuw.',
        ),
        PurchaseOutcome.pending => _pendingText,
        PurchaseOutcome.signedOut => _loginText,
        PurchaseOutcome.otherAccount => _otherAccountText,
        PurchaseOutcome.notConfigured => _notConfiguredText,
        PurchaseOutcome.notFound => tr('No subscription found.', 'Geen abonnement gevonden.'),
      };
    });
  }

  static String get _loginText =>
      tr('Log in first: being a supporter belongs to your account.', 'Log eerst in: supporter zijn hoort bij je account.');

  static String get _pendingText => tr(
    'Payment pending. Your supporter extras turn on as soon as Google Play confirms your payment.',
    "Betaling in behandeling. Je supporterextra's gaan aan zodra Google Play je betaling bevestigt.",
  );

  static String get _otherAccountText => tr(
    'This subscription already belongs to another MacroMatrix account. Log in with that account to use it.',
    'Dit abonnement hoort al bij een ander MacroMatrix-account. Log in met dat account om het te gebruiken.',
  );

  static String get _notConfiguredText => tr(
    "Your payment went through, but we can't switch on your supporter extras just yet. They will turn on by themselves soon; you don't need to pay again.",
    "Je betaling is gelukt, maar we kunnen je supporterextra's nog niet meteen aanzetten. Ze gaan binnenkort vanzelf aan; je hoeft niet opnieuw te betalen.",
  );

  Future<void> _restore(Pro? pro) async {
    // Zonder account (of zonder verbinding met de server) is er niets om te herstellen
    if (pro == null || pro.remote == null) {
      setState(() => _message = _loginText);
      return;
    }
    setState(() => _busy = true);
    final ok = await pro.restore();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = ok
          ? tr("You're a supporter on this account.", 'Je bent supporter op dit account.')
          : !pro.available
          ? tr('Supporter is not available yet.', 'Supporter is nog niet beschikbaar.')
          : switch (pro.restoreOutcome) {
              PurchaseOutcome.otherAccount => _otherAccountText,
              PurchaseOutcome.notConfigured => _notConfiguredText,
              PurchaseOutcome.pending => _pendingText,
              PurchaseOutcome.failed => tr(
                'That did not work. Check your connection and try again.',
                'Dat lukte niet. Controleer je verbinding en probeer opnieuw.',
              ),
              _ => tr('No Supporter subscription found for this account.', 'Geen Supporter-abonnement gevonden voor dit account.'),
            };
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final pro = proOf(context);
    final isPro = pro?.isPro ?? false;

    Widget bullet(IconData icon, String text, {Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color ?? p.ok),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 14, height: 1.35, color: p.ink)),
          ),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text(tr('Supporter', 'Supporter'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Narrow(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _status(context, pro),
                const SizedBox(height: 12),
                Panel(
                  key: const ValueKey('pro-free'),
                  shadow: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PanelTitle(
                        tr('Always free', 'Altijd gratis'),
                        subtitle: tr('Nobody loses anything they have today.', 'Niemand verliest iets wat hij vandaag heeft.'),
                      ),
                      const SizedBox(height: 8),
                      bullet(
                        Icons.check_rounded,
                        tr(
                          'Your diary with every nutrient, targets and the Nutrient score',
                          'Je dagboek met elke voedingsstof, doelen en de Voedingsscore',
                        ),
                      ),
                      bullet(
                        Icons.check_rounded,
                        tr('Search, barcode scanning, recipes and your own foods', 'Zoeken, barcodes scannen, recepten en eigen producten'),
                      ),
                      bullet(Icons.check_rounded, tr('Quick log by typing or with your voice', 'Snel loggen door te typen of met je stem')),
                      bullet(
                        Icons.check_rounded,
                        tr('Logging with a photo: $freePhotosPerDay photos per day', "Loggen met een foto: $freePhotosPerDay foto's per dag"),
                      ),
                      bullet(
                        Icons.check_rounded,
                        tr(
                          'Scanning the label of a product that is not found: ${AiKind.label.free} per day',
                          'Het etiket scannen van een product dat niet gevonden wordt: ${AiKind.label.free} per dag',
                        ),
                      ),
                      bullet(Icons.check_rounded, tr('Sync between your devices', 'Synchroniseren tussen je toestellen')),
                      bullet(Icons.check_rounded, tr('Friends, battles and challenges', 'Vrienden, battles en uitdagingen')),
                      bullet(
                        Icons.check_rounded,
                        tr(
                          'Trends, weekly reports, monthly recaps and your year in review',
                          'Trends, weekrapporten, maandoverzichten en je jaaroverzicht',
                        ),
                      ),
                      bullet(
                        Icons.check_rounded,
                        tr(
                          'Meal planner, shopping list, blood values and supplements',
                          'Maaltijdplanner, boodschappenlijst, bloedwaarden en supplementen',
                        ),
                      ),
                      bullet(Icons.check_rounded, tr('Export and backups of all your data', 'Export en back-ups van al je gegevens')),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Panel(
                  key: const ValueKey('pro-adds'),
                  shadow: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PanelTitle(tr('What Supporter adds', 'Wat Supporter toevoegt')),
                      const SizedBox(height: 8),
                      bullet(
                        Icons.photo_camera_outlined,
                        tr('Logging with a photo: up to $proPhotosPerDay photos a day', "Loggen met een foto: tot $proPhotosPerDay foto's per dag"),
                        color: p.brand,
                      ),
                      bullet(
                        Icons.menu_book_outlined,
                        tr(
                          'Import recipes from a link or a photo of a cookbook page (up to ${AiKind.recipe.pro} a day)',
                          'Recepten importeren uit een link of een foto van een kookboekpagina (tot ${AiKind.recipe.pro} per dag)',
                        ),
                        color: p.brand,
                      ),
                      bullet(
                        Icons.document_scanner_outlined,
                        tr('Up to ${AiKind.label.pro} label scans a day', 'Tot ${AiKind.label.pro} etiketscans per dag'),
                        color: p.brand,
                      ),
                      bullet(
                        Icons.auto_awesome_outlined,
                        tr('New AI features as they arrive', 'Nieuwe AI-functies zodra ze er zijn'),
                        color: p.brand,
                      ),
                      bullet(Icons.palette_outlined, tr('Extra colours and backgrounds', 'Extra kleuren en achtergronden'), color: p.brand),
                      bullet(
                        Icons.favorite_border_rounded,
                        tr('A Supporter badge your friends can see', 'Een Supporter-badge dat je vrienden zien'),
                        color: p.brand,
                      ),
                      bullet(
                        Icons.blur_circular_rounded,
                        tr(
                          'A special frame around your avatar, in your level colour, that your friends see',
                          'Een speciale rand rond je avatar, in de kleur van je level, die je vrienden zien',
                        ),
                        color: p.brand,
                      ),
                      bullet(
                        Icons.calendar_month_outlined,
                        tr(
                          'An extended year in review: nutrients month by month, your top 10 and your records',
                          'Een uitgebreid jaaroverzicht: voedingsstoffen per maand, je top 10 en je records',
                        ),
                        color: p.brand,
                      ),
                      // Vroege toegang en meestemmen over de roadmap (sync/features.dart, sync/roadmap.dart)
                      // De coach bij naam: de kaart in het weekrapport stuurt hierheen (SP-9)
                      bullet(
                        Icons.bolt_rounded,
                        tr('Early access to new features, now the weekly coach', 'Vroege toegang tot nieuwe functies, nu de wekelijkse coach'),
                        color: p.brand,
                      ),
                      bullet(Icons.how_to_vote_outlined, tr('Vote on what we build next', 'Mee stemmen over wat we hierna maken'), color: p.brand),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          key: const ValueKey('pro-roadmap'),
                          onPressed: () => openRoadmapScreen(context),
                          child: Text(tr("See what's next", 'Bekijk wat er komt')),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const AvatarFramePicker(),
                const SizedBox(height: 12),
                Panel(
                  shadow: false,
                  color: p.surface2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PanelTitle(tr('Why become a supporter?', 'Waarom supporter worden?')),
                      const SizedBox(height: 6),
                      Text(
                        tr(
                          'Reading a photo of your plate runs an AI model on a server, and every photo costs real computing. '
                              'Everything else in MacroMatrix costs us very little, so it stays free. Supporters pay for the photos and '
                              'help keep the rest free for everyone. No ads, and we never sell your data.',
                          'Een foto van je bord lezen gebeurt door een AI-model op een server, en elke foto kost echte rekenkracht. '
                              'Al de rest van MacroMatrix kost ons heel weinig, dus dat blijft gratis. Supporters betalen de foto\'s en helpen '
                              'de rest voor iedereen gratis te houden. Geen reclame, en we verkopen nooit je gegevens.',
                        ),
                        style: TextStyle(fontSize: 13.5, height: 1.5, color: p.ink2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Ook een supporter zonder Play-abonnement (bv. een geschenk) ziet wat het kost (SU-6)
                if (!isPro || !_playSubscriber(pro)) _prices(context, pro),
                const SizedBox(height: 4),
                // Herstellen alleen waar kopen kan: anders is er niets om te herstellen (SU-6)
                if (canBuy(pro))
                  Center(
                    child: TextButton(
                      key: const ValueKey('pro-restore'),
                      onPressed: _busy ? null : () => _restore(pro),
                      child: Text(tr('Restore purchase', 'Aankoop herstellen')),
                    ),
                  ),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _message!,
                      key: const ValueKey('pro-message'),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, height: 1.4, color: p.ink2),
                    ),
                  ),
                if (kDebugMode && pro != null) ...[const SizedBox(height: 20), _debug(context, pro)],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _status(BuildContext context, Pro? pro) {
    final p = context.pal;
    final isPro = pro?.isPro ?? false;
    final until = pro?.status.until;
    final q = pro?.quota;
    final String title, sub;
    if (isPro) {
      title = tr('You are a supporter', 'Je bent supporter');
      sub = until == null || pro?.debugPro == true
          ? tr('Your supporter extras are on.', "Je supporterextra's staan aan.")
          : until.year >= 9000
          ? tr('Supporter for life. Thank you!', 'Supporter voor altijd. Bedankt!')
          : tr(
              'Supporter until ${DateFormat('d MMMM y', appLocale).format(until.toLocal())}. Thank you!',
              'Supporter tot ${DateFormat('d MMMM y', appLocale).format(until.toLocal())}. Bedankt!',
            );
    } else {
      title = tr('Free plan', 'Gratis');
      sub = until != null
          ? tr(
              'Your supporter extras ended on ${DateFormat('d MMMM y', appLocale).format(until.toLocal())}. Everything free keeps working.',
              "Je supporterextra's liepen af op ${DateFormat('d MMMM y', appLocale).format(until.toLocal())}. Alles wat gratis is, blijft werken.",
            )
          : tr('You have everything that is free, for good.', 'Je hebt alles wat gratis is, voor altijd.');
    }
    return Panel(
      key: const ValueKey('pro-status'),
      color: isPro ? p.brandSoft : null,
      borderColor: isPro ? p.brandSoft : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.ink),
                ),
              ),
              // De titel zegt al "Je bent supporter": alleen het hartje, anders staat er twee keer Supporter
              if (pro?.supporter ?? false) const SupporterBadge(compact: true),
            ],
          ),
          const SizedBox(height: 4),
          Text(sub, style: TextStyle(fontSize: 13.5, height: 1.4, color: p.ink2)),
          // Hoe het verder gaat: verlengt het, en waar stop je (SU-6, GP-4)
          if (isPro && pro != null && pro.debugPro == null && until != null && until.year < 9000 && ProScreen.renewalText(pro.status.source) != null) ...[
            const SizedBox(height: 6),
            Text(
              ProScreen.renewalText(pro.status.source)!,
              key: const ValueKey('pro-renewal'),
              style: TextStyle(fontSize: 12.5, height: 1.4, color: p.ink2),
            ),
          ],
          if (q != null) ...[
            const SizedBox(height: 6),
            Text(
              tr("Photos today: ${q.used} of ${q.limit}", "Foto's vandaag: ${q.used} van ${q.limit}"),
              style: TextStyle(fontSize: 12.5, color: p.ink3),
            ),
          ],
          if (pro != null && !pro.available) ...[
            const SizedBox(height: 6),
            Text(tr('Supporter is not available yet.', 'Supporter is nog niet beschikbaar.'), style: TextStyle(fontSize: 12.5, color: p.ink3)),
          ],
          if (isPro && pro != null && pro.debugPro == null) ...[
            const SizedBox(height: 4),
            SwitchListTile(
              key: const ValueKey('pro-show-badge'),
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Show the Supporter badge to friends', 'Het Supporter-badge tonen aan vrienden')),
              value: pro.status.showBadge,
              onChanged: (v) => pro.setShowBadge(v),
            ),
          ],
        ],
      ),
    );
  }

  /// Supporter via een abonnement in Google Play (dat verlengt), niet via een geschenk of met de hand.
  static bool _playSubscriber(Pro? pro) => pro?.status.source == 'play';

  /// Kan je hier echt abonneren? Alleen als de winkel (Google Play) klaarstaat met onze producten en de server Pro
  /// kent. Anders geen actieve knop, maar meteen op die plek "Binnenkort" (Google-regel: geen knop die niets doet).
  static bool canBuy(Pro? pro) => pro != null && pro.available && pro.purchases.available;

  Widget _prices(BuildContext context, Pro? pro) {
    final p = context.pal;
    final buy = canBuy(pro);
    // De prijs van de winkel (in je eigen munt) als die er is, anders de vaste prijs in euro
    String priceOf(ProPlan plan) => pro?.purchases.priceOf(plan) ?? plan.price;
    Widget option(ProPlan plan, String sub) {
      final on = buy && _plan == plan;
      return Expanded(
        child: Panel(
          key: ValueKey('pro-plan-${plan.name}'),
          shadow: false,
          // Zonder winkel valt er niets te kiezen: de kaartjes tonen alleen de prijs
          onTap: buy ? () => setState(() => _plan = plan) : null,
          color: on ? p.brandSoft : null,
          borderColor: on ? p.brand : null,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                plan == ProPlan.monthly ? tr('Monthly', 'Per maand') : tr('Yearly', 'Per jaar'),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.ink2),
              ),
              const SizedBox(height: 4),
              Text(
                priceOf(plan),
                key: ValueKey('pro-price-${plan.name}'),
                style: numStyle(22, color: p.ink),
              ),
              Text(sub, style: TextStyle(fontSize: 12, color: p.ink3)),
            ],
          ),
        ),
      );
    }

    final price = priceOf(_plan);
    final renews = _plan == ProPlan.monthly
        ? tr(
            'MacroMatrix Supporter, monthly: $price per month. Renews automatically every month until you cancel. '
                'Cancel anytime in Google Play under Payments & subscriptions.',
            'MacroMatrix Supporter, per maand: $price per maand. Verlengt automatisch elke maand tot je opzegt. '
                'Opzeggen kan altijd in Google Play onder Betalingen en abonnementen.',
          )
        : tr(
            'MacroMatrix Supporter, yearly: $price per year. Renews automatically every year until you cancel. '
                'Cancel anytime in Google Play under Payments & subscriptions.',
            'MacroMatrix Supporter, per jaar: $price per jaar. Verlengt automatisch elk jaar tot je opzegt. '
                'Opzeggen kan altijd in Google Play onder Betalingen en abonnementen.',
          );
    final android = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

    return Panel(
      key: const ValueKey('pro-prices'),
      shadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelTitle(tr('Prices', 'Prijzen'), subtitle: tr('Including VAT.', 'Btw inbegrepen.')),
          const SizedBox(height: 10),
          Row(
            children: [
              option(ProPlan.monthly, tr('per month', 'per maand')),
              const SizedBox(width: 10),
              option(ProPlan.yearly, tr('per year · save $yearlySavingPercent%', 'per jaar · $yearlySavingPercent% goedkoper')),
            ],
          ),
          const SizedBox(height: 12),
          if (buy) ...[
            FilledButton(
              key: const ValueKey('pro-subscribe'),
              onPressed: _busy ? null : () => _subscribe(pro),
              child: Text(tr('Subscribe · ${_plan.labelFor(price)}', 'Abonneren · ${_plan.labelFor(price)}')),
            ),
            const SizedBox(height: 8),
            Text(
              renews,
              key: const ValueKey('pro-renews'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, height: 1.4, color: p.ink2),
            ),
          ] else
            // Op de plek van de knop: duidelijk dat kopen nog niet kan
            Container(
              key: const ValueKey('pro-coming-soon'),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(color: p.sunken, borderRadius: BorderRadius.circular(12)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.schedule_rounded, size: 20, color: p.ink2),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      android
                          ? tr(
                              "Coming soon: you'll be able to support MacroMatrix through Google Play. "
                                  "You can't subscribe in the app yet. Everything that's free stays free.",
                              'Binnenkort: je kunt MacroMatrix dan steunen via Google Play. Abonneren kan nog niet in '
                                  'de app. Alles wat gratis is, blijft gratis.',
                            )
                          : tr(
                              "Coming soon: you can't subscribe here yet. Everything that's free stays free.",
                              'Binnenkort: abonneren kan hier nog niet. Alles wat gratis is, blijft gratis.',
                            ),
                      style: TextStyle(fontSize: 13.5, height: 1.4, color: p.ink),
                    ),
                  ),
                ],
              ),
            ),
          if (pro?.purchases.pending ?? false)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _pendingText,
                key: const ValueKey('pro-pending'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, height: 1.4, color: p.ink3),
              ),
            ),
        ],
      ),
    );
  }

  /// Alleen in een debug-build: Pro op dit toestel nabootsen, om de extra's te testen.
  Widget _debug(BuildContext context, Pro pro) => Panel(
    key: const ValueKey('pro-debug'),
    shadow: false,
    dashed: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Debug',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.pal.ink2),
        ),
        const SizedBox(height: 6),
        Segmented<String>(
          height: 30,
          items: const [('server', 'Server'), ('pro', 'Pro'), ('free', 'Free')],
          selected: switch (pro.debugPro) {
            true => 'pro',
            false => 'free',
            null => 'server',
          },
          onChanged: (v) => pro.setDebugPro(switch (v) {
            'pro' => true,
            'free' => false,
            _ => null,
          }),
        ),
      ],
    ),
  );
}
