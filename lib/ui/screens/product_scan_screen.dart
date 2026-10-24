import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/food.dart';
import '../../data/off_client.dart';
import '../../data/product_info.dart';
import '../../data/user_db.dart';
import '../../i18n.dart';
import '../../platform/platform.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/allergen_banner.dart';
import '../widgets/info_tip.dart';
import '../widgets/kit.dart';
import 'food_detail_screen.dart';
import 'label_scan_screen.dart';
import 'scan_screen.dart';
import '../widgets/number_input.dart';

/// Tabblad Scan: een product scannen en zien wat erin zit (additieven, allergenen, Nutri-Score, bewerkingsgraad
/// en herkomst), zoals Yuka, maar met de knop om het meteen in je dagboek te zetten.
class ProductScanScreen extends StatefulWidget {
  const ProductScanScreen({super.key});

  @override
  State<ProductScanScreen> createState() => _ProductScanScreenState();
}

class _ProductScanScreenState extends State<ProductScanScreen> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _camera() async {
    final code = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ScanScreen()));
    if (code != null && mounted) _open(code);
  }

  void _submit() {
    final code = _code.text.replaceAll(RegExp(r'\s'), '');
    if (!looksLikeBarcode(code)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              'That is not a barcode. Type the 8 or 13 digits under the stripes.',
              'Dat is geen barcode. Typ de 8 of 13 cijfers onder de streepjes.',
            ),
          ),
        ),
      );
      return;
    }
    _code.clear();
    _open(code);
  }

  void _open(String code) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductResultScreen(code: code)));

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    final scans = s.scans;
    // Op een gsm geopend vanuit het +-menu: dan met een terugknop
    final pushed = ModalRoute.of(context)?.canPop ?? false;
    // Op een pc even breed als Vandaag en Profiel, met de recente scans in een tweede kolom
    final maxWidth = isDesktop(context) ? wideMaxWidth : 760.0;
    return Scaffold(
      appBar: pushed ? AppBar() : null,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Narrow(
              maxWidth: maxWidth,
              child: PageHeader(eyebrow: tr('What is in it?', 'Wat zit erin?'), title: 'Scan'),
            ),
            Narrow(
              maxWidth: maxWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SplitColumns(
                  gap: 14,
                  left: [
                    Panel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(color: p.brandSoft, borderRadius: BorderRadius.circular(14)),
                                child: Icon(Icons.qr_code_scanner_rounded, color: p.brand, size: 28),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  tr(
                                    'Scan a product to see its additives, allergens, how processed it is and where it comes from.',
                                    'Scan een product en zie de additieven, allergenen, hoe bewerkt het is en waar het vandaan komt.',
                                  ),
                                  style: TextStyle(fontSize: 14.5, color: p.ink2, height: 1.35),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (canScanBarcodes) ...[
                            FilledButton.icon(
                              onPressed: _camera,
                              icon: const Icon(Icons.photo_camera_outlined),
                              label: Text(tr('Scan with camera', 'Scannen met camera')),
                              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                            ),
                            const SizedBox(height: 12),
                          ],
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _code,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: wholeInput,
                                  textInputAction: TextInputAction.search,
                                  onSubmitted: (_) => _submit(),
                                  decoration: InputDecoration(
                                    hintText: tr('Or type the barcode', 'Of typ de barcode'),
                                    prefixIcon: const Icon(Icons.dialpad_rounded),
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SquareButton(
                                icon: Icons.arrow_forward_rounded,
                                tooltip: tr('Look up', 'Opzoeken'),
                                filled: true,
                                size: 48,
                                onPressed: _submit,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    const _ScoreLegend(),
                  ],
                  right: [
                    Panel(
                      padding: const EdgeInsets.fromLTRB(6, 14, 6, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: PanelTitle(
                              tr('Recently scanned', 'Recent gescand'),
                              subtitle: tr('${s.scannedCount} products in total', '${s.scannedCount} producten in totaal'),
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (scans.isEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                              child: Text(tr('Nothing scanned yet.', 'Nog niets gescand.'), style: TextStyle(color: p.ink3)),
                            ),
                          for (final (code, name, at) in scans.take(20))
                            ListTile(
                              dense: true,
                              leading: Icon(Icons.history_rounded, color: p.ink3),
                              title: Text(name.isEmpty ? code : name, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(DateFormat('d MMM · HH:mm', appLocale).format(at)),
                              trailing: Icon(Icons.chevron_right_rounded, color: p.ink3),
                              onTap: () => _open(code),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Korte uitleg van de productscore, zodat de kleur iets betekent.
class _ScoreLegend extends StatelessWidget {
  const _ScoreLegend();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget item(int score) => Expanded(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: scoreColor(score), shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              scoreWord(score),
              style: TextStyle(fontSize: 12.5, color: p.ink2),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
    return Panel(
      shadow: false,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(
              'The product score combines the Nutri-Score (60%), additives (30%) and organic (10%).',
              'De productscore combineert de Nutri-Score (60%), additieven (30%) en bio (10%).',
            ),
            style: TextStyle(fontSize: 13, color: p.ink2, height: 1.35),
          ),
          const SizedBox(height: 10),
          Row(children: [item(90), item(60), item(35), item(10)]),
        ],
      ),
    );
  }
}

Color scoreColor(int s) => s >= 75
    ? const Color(0xFF1E9E5A)
    : s >= 50
    ? const Color(0xFF8BC34A)
    : s >= 25
    ? const Color(0xFFF08C00)
    : const Color(0xFFE03131);

String scoreWord(int s) => s >= 75
    ? tr('Excellent', 'Uitstekend')
    : s >= 50
    ? tr('Good', 'Goed')
    : s >= 25
    ? tr('Poor', 'Matig')
    : tr('Bad', 'Slecht');

Color riskColor(AdditiveLevel l) => switch (l) {
  AdditiveLevel.free => const Color(0xFF1E9E5A),
  AdditiveLevel.limited => const Color(0xFFD4A000),
  AdditiveLevel.moderate => const Color(0xFFF08C00),
  AdditiveLevel.high => const Color(0xFFE03131),
};

String riskLabel(AdditiveLevel l) => switch (l) {
  AdditiveLevel.free => tr('No known risk', 'Geen gekend risico'),
  AdditiveLevel.limited => tr('Limited risk', 'Beperkt risico'),
  AdditiveLevel.moderate => tr('Moderate risk', 'Matig risico'),
  AdditiveLevel.high => tr('High risk', 'Hoog risico'),
};

/// Productdetails na een scan.
class ProductResultScreen extends StatefulWidget {
  const ProductResultScreen({super.key, required this.code, this.countScan = true});
  final String code;

  /// Meetellen als scan (geschiedenis en badge); niet voor een betere keuze die je alleen bekijkt.
  final bool countScan;

  @override
  State<ProductResultScreen> createState() => _ProductResultScreenState();
}

class _ProductResultScreenState extends State<ProductResultScreen> {
  late Future<(ProductInfo?, AdditiveCatalog)> _future = _load();

  Future<(ProductInfo?, AdditiveCatalog)> _load() async {
    final s = context.read<AppState>();
    final results = await Future.wait([s.productInfo(widget.code), AdditiveCatalog.load()]);
    final info = results[0] as ProductInfo?;
    if (info != null && widget.countScan) {
      final brand = info.brand;
      final showBrand = brand != null && !info.name.toLowerCase().contains(brand.toLowerCase());
      s.addScan(widget.code, showBrand ? '${info.name} · $brand' : info.name);
    }
    return (info, results[1] as AdditiveCatalog);
  }

  /// Niet gevonden: het etiket scannen en daarna meteen toevoegen aan het dagboek (als het bewaard werd).
  Future<void> _scanLabel() async {
    final food = await Navigator.of(context).push<Food>(MaterialPageRoute(builder: (_) => LabelScanScreen(barcode: widget.code)));
    if (food != null && mounted) await _addToDiary(food);
  }

  Future<void> _addToDiary(Food food) async {
    final s = context.read<AppState>();
    final full = await s.completeOff(food);
    if (!mounted) return;
    final added = await Navigator.of(context).push<Object>(
      MaterialPageRoute(
        builder: (_) => FoodDetailScreen(food: full, meal: Meal.forHour(DateTime.now().hour)),
      ),
    );
    if (added == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('${full.name} added to your diary', '${full.name} toegevoegd aan je dagboek'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Product', 'Product'))),
      body: FutureBuilder(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) {
            final msg = snap.error is OffException ? (snap.error as OffException).message : tr('Something went wrong.', 'Er ging iets mis.');
            return _Message(
              icon: Icons.wifi_off_rounded,
              text: msg,
              action: FilledButton(onPressed: () => setState(() => _future = _load()), child: Text(tr('Try again', 'Opnieuw proberen'))),
            );
          }
          final (info, catalog) = snap.data!;
          if (info == null) {
            return _Message(
              icon: Icons.search_off_rounded,
              text: tr(
                'Barcode ${widget.code} is not in Open Food Facts or the USDA database yet. Scan the nutrition label to add it as your own product.',
                'Barcode ${widget.code} staat nog niet in Open Food Facts of de USDA-databank. Scan het etiket om het als eigen product toe te voegen.',
              ),
              action: FilledButton.icon(
                key: const ValueKey('product-scan-label'),
                onPressed: _scanLabel,
                icon: const Icon(Icons.document_scanner_outlined),
                label: Text(tr('Scan the label', 'Etiket scannen')),
              ),
            );
          }
          final list = ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Narrow(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(info: info, score: info.score(catalog)),
                    const SizedBox(height: 12),
                    AllergenBanner(
                      food:
                          info.food ??
                          Food(
                            ref: 'scan:${info.code}',
                            name: info.name,
                            brand: info.brand,
                            source: FoodSource.off,
                            per100g: const {},
                            allergenTags: info.allergenTags,
                            traceTags: info.traceTags,
                            ingredients: info.ingredients,
                          ),
                    ),
                    _OriginCard(origin: info.origin),
                    const SizedBox(height: 12),
                    _QualityCard(info: info),
                    const SizedBox(height: 12),
                    if (info.offline) ...[
                      Text(
                        tr(
                          'No internet: these are the details saved from your last scan.',
                          'Geen internet: dit zijn de gegevens van je vorige scan.',
                        ),
                        style: TextStyle(fontSize: 13, color: p.ink3),
                      ),
                      const SizedBox(height: 12),
                    ],
                    _AdditivesCard(info: info, catalog: catalog),
                    if (!info.offline && info.source == 'off' && (info.score(catalog) ?? 100) < 50) ...[
                      const SizedBox(height: 12),
                      _BetterChoices(info: info, catalog: catalog),
                    ],
                    if (info.ingredients != null) ...[const SizedBox(height: 12), _IngredientsCard(text: info.ingredients!)],
                    const SizedBox(height: 16),
                    if (info.food == null)
                      Text(
                        tr('No nutrition values known, so it cannot be logged yet.', 'Geen voedingswaarden bekend, dus je kunt het nog niet loggen.'),
                        style: TextStyle(color: p.ink3),
                        textAlign: TextAlign.center,
                      ),
                    const SizedBox(height: 14),
                    Text(
                      info.source == 'usda'
                          ? tr('Data: USDA FoodData Central (public domain)', 'Gegevens: USDA FoodData Central (publiek domein)')
                          : tr(
                              'Data: Open Food Facts (ODbL). Always check the label.',
                              'Gegevens: Open Food Facts (ODbL). Kijk altijd ook het etiket na.',
                            ),
                      style: TextStyle(fontSize: 12, color: p.ink3),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          );
          if (info.food == null) return list;
          // Vaste knop onderaan: na het scannen meteen toevoegen, zonder te scrollen
          return Column(
            children: [
              Expanded(child: list),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Narrow(
                    child: FilledButton.icon(
                      onPressed: () => _addToDiary(info.food!),
                      icon: const Icon(Icons.add_rounded),
                      label: Text(tr('Add to diary', 'Toevoegen aan dagboek')),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: context.pal.ink3),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: context.pal.ink2),
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.info, required this.score});
  final ProductInfo info;
  final int? score;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Panel(
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 72,
              height: 72,
              color: p.sunken,
              child: info.image == null
                  ? Icon(Icons.inventory_2_outlined, color: p.ink3)
                  : Image.network(
                      info.image!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Icon(Icons.inventory_2_outlined, color: p.ink3),
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info.name,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.ink),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                if (info.brand != null) Text(info.brand!, style: TextStyle(fontSize: 14, color: p.ink2)),
                const SizedBox(height: 8),
                if (score != null)
                  Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(color: scoreColor(score!), shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$score/100 · ${scoreWord(score!)}',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: scoreColor(score!)),
                      ),
                    ],
                  )
                else
                  Text(tr('Not enough data for a score', 'Te weinig gegevens voor een score'), style: TextStyle(fontSize: 13, color: p.ink3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OriginCard extends StatelessWidget {
  const _OriginCard({required this.origin});
  final Origin origin;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final (badge, color, title) = switch (origin.region) {
      Region.eu => ('EU', const Color(0xFF1D4ED8), tr('From the EU', 'Uit de EU')),
      Region.us => ('US', const Color(0xFFB91C1C), tr('From the US', 'Uit de VS')),
      Region.other => ('', p.ink2, tr('From outside the EU and US', 'Van buiten de EU en de VS')),
      Region.unknown => ('?', p.ink3, tr('Origin unknown', 'Herkomst onbekend')),
    };
    final note = switch (origin.basis) {
      'made' => tr('Made in: ${origin.place}', 'Gemaakt in: ${origin.place}'),
      'ingredients' => tr('Ingredients from: ${origin.place}', 'Ingrediënten uit: ${origin.place}'),
      'source' => origin.place ?? '',
      _ =>
        origin.place == null
            ? tr('The manufacturer did not say where it is made.', 'De fabrikant zegt niet waar het gemaakt wordt.')
            // Buiten de EU en de VS: geen landnaam, dus niet "geregistreerd in Buiten de EU en de VS"
            : origin.region == Region.other
            ? tr(
                'Barcode registered outside the EU and US. That is where the brand is based, not always where it is made.',
                'Barcode geregistreerd buiten de EU en de VS. Daar zit het merk, niet altijd waar het gemaakt wordt.',
              )
            : tr(
                'Barcode registered in ${origin.place}. That is where the brand is based, not always where it is made.',
                'Barcode geregistreerd in ${origin.place}. Daar zit het merk, niet altijd waar het gemaakt wordt.',
              ),
    };
    return Panel(
      shadow: false,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: badge.isEmpty
                ? Icon(Icons.public_rounded, color: color)
                : Text(
                    badge,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color, letterSpacing: 0.5),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color),
                ),
                if (note.isNotEmpty) Text(note, style: TextStyle(fontSize: 13, color: p.ink2, height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Nutri-Score (A–E) en NOVA (1–4: hoe bewerkt).
class _QualityCard extends StatelessWidget {
  const _QualityCard({required this.info});
  final ProductInfo info;

  static const _nsColors = {'a': Color(0xFF038141), 'b': Color(0xFF85BB2F), 'c': Color(0xFFFECB02), 'd': Color(0xFFEE8100), 'e': Color(0xFFE63E11)};
  static const _novaColors = [Color(0xFF00AA00), Color(0xFFFFCC00), Color(0xFFFF6600), Color(0xFFFF0000)];

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget letter(String l) {
      final on = l == info.nutriscore;
      return Expanded(
        child: Container(
          height: on ? 34 : 26,
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _nsColors[l]!.withValues(alpha: on ? 1 : 0.3),
            borderRadius: BorderRadius.circular(on ? 8 : 5),
          ),
          child: Text(
            l.toUpperCase(),
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: on ? 18 : 13),
          ),
        ),
      );
    }

    final novaText = switch (info.nova) {
      1 => tr('Unprocessed or minimally processed', 'Onbewerkt of weinig bewerkt'),
      2 => tr('Processed culinary ingredient', 'Bewerkt keukeningrediënt'),
      3 => tr('Processed food', 'Bewerkt voedsel'),
      4 => tr('Ultra-processed', 'Ultrabewerkt'),
      _ => tr('Unknown', 'Onbekend'),
    };
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PanelTitle(
            'Nutri-Score',
            subtitle: tr('How healthy, compared with similar products', 'Hoe gezond, vergeleken met gelijkaardige producten'),
          ),
          const SizedBox(height: 10),
          if (info.nutriscore == null)
            Text(tr('Not known for this product.', 'Niet bekend voor dit product.'), style: TextStyle(color: p.ink3))
          else
            SizedBox(
              height: 34,
              child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [for (final l in 'abcde'.split('')) letter(l)]),
            ),
          const SizedBox(height: 16),
          PanelTitle(
            tr('Processing', 'Bewerking'),
            subtitle: tr('NOVA group: from 1 (natural) to 4 (ultra-processed)', 'NOVA-groep: van 1 (natuurlijk) tot 4 (ultrabewerkt)'),
            trailing: InfoTip(title: 'NOVA', message: novaInfo()),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (info.nova != null && info.nova! >= 1 && info.nova! <= 4)
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: _novaColors[info.nova! - 1], borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    '${info.nova}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
                  ),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  novaText,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.ink),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AdditivesCard extends StatelessWidget {
  const _AdditivesCard({required this.info, required this.catalog});
  final ProductInfo info;
  final AdditiveCatalog catalog;

  void _explain(BuildContext context, Additive a) {
    final text = switch (a.level) {
      AdditiveLevel.free => tr(
        'Allowed in the EU, with no known risk at normal amounts.',
        'Toegelaten in de EU, zonder gekend risico bij normale hoeveelheden.',
      ),
      AdditiveLevel.limited => tr(
        'Allowed in the EU, but the French food safety agency (ANSES) keeps a closer eye on it because of open questions about its health effects.',
        'Toegelaten in de EU, maar het Franse voedselagentschap (ANSES) volgt het extra op omdat er nog vragen zijn over de gezondheidseffecten.',
      ),
      AdditiveLevel.moderate => tr(
        'The European Food Safety Authority (EFSA) found that some people may get more than the acceptable daily amount. Not a reason to panic, but better not every day.',
        'De Europese voedselveiligheidsautoriteit (EFSA) stelde vast dat sommige mensen meer dan de aanvaardbare dagelijkse hoeveelheid kunnen binnenkrijgen. Geen reden tot paniek, maar liever niet elke dag.',
      ),
      AdditiveLevel.high => tr(
        'The European Food Safety Authority (EFSA) found that many people may get more than the acceptable daily amount. Best to limit products with this additive.',
        'De Europese voedselveiligheidsautoriteit (EFSA) stelde vast dat veel mensen meer dan de aanvaardbare dagelijkse hoeveelheid kunnen binnenkrijgen. Beperk producten met dit additief liever.',
      ),
    };
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${a.eNumber} · ${a.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(catalog.className(a.classKey), style: TextStyle(color: ctx.pal.ink2)),
            const SizedBox(height: 10),
            Text(
              riskLabel(a.level),
              style: TextStyle(fontWeight: FontWeight.w700, color: riskColor(a.level)),
            ),
            const SizedBox(height: 4),
            Text(text),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Close', 'Sluiten')))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final adds = info.additives(catalog)..sort((a, b) => b.level.index.compareTo(a.level.index));
    final known = info.source == 'off' && (info.ingredients != null || info.additiveTags.isNotEmpty);
    return Panel(
      padding: const EdgeInsets.fromLTRB(6, 14, 6, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: PanelTitle(
              tr('Additives', 'Additieven'),
              subtitle: adds.isEmpty ? null : tr('Tap one for more info', 'Tik op een additief voor meer uitleg'),
              trailing: Text('${adds.length}', style: numStyle(18, color: p.ink2)),
            ),
          ),
          const SizedBox(height: 4),
          if (adds.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
              child: Row(
                children: [
                  Icon(known ? Icons.check_circle_rounded : Icons.help_outline_rounded, color: known ? riskColor(AdditiveLevel.free) : p.ink3),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      known
                          ? tr('No additives. Nice!', 'Geen additieven. Top!')
                          : tr('Unknown: no ingredient list available.', 'Onbekend: geen ingrediëntenlijst beschikbaar.'),
                      style: TextStyle(fontSize: 14.5, color: p.ink),
                    ),
                  ),
                ],
              ),
            ),
          for (final a in adds)
            ListTile(
              dense: true,
              onTap: () => _explain(context, a),
              leading: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: riskColor(a.level), shape: BoxShape.circle),
              ),
              minLeadingWidth: 12,
              title: Text(
                '${a.eNumber} · ${a.name}',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: p.ink),
              ),
              subtitle: Text(catalog.className(a.classKey)),
              trailing: Text(
                riskLabel(a.level),
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: riskColor(a.level)),
              ),
            ),
        ],
      ),
    );
  }
}

class _IngredientsCard extends StatefulWidget {
  const _IngredientsCard({required this.text});
  final String text;

  @override
  State<_IngredientsCard> createState() => _IngredientsCardState();
}

class _IngredientsCardState extends State<_IngredientsCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Panel(
      onTap: () => setState(() => _open = !_open),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PanelTitle(tr('Ingredients', 'Ingrediënten'), trailing: Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: p.ink3)),
          const SizedBox(height: 6),
          Text(
            widget.text.replaceAll('_', ''),
            maxLines: _open ? null : 3,
            overflow: _open ? null : TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, color: p.ink2, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// Tot 3 gelijkaardige producten die beter scoren (zelfde categorie, betere Nutri-Score, minder risicovolle additieven).
class _BetterChoices extends StatefulWidget {
  const _BetterChoices({required this.info, required this.catalog});
  final ProductInfo info;
  final AdditiveCatalog catalog;

  @override
  State<_BetterChoices> createState() => _BetterChoicesState();
}

class _BetterChoicesState extends State<_BetterChoices> {
  late final Future<List<(ProductInfo, int)>> _future = context.read<AppState>().betterAlternatives(widget.info, widget.catalog);

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return FutureBuilder(
      future: _future,
      builder: (context, snap) {
        final list = snap.data;
        if (snap.hasError || (list != null && list.isEmpty)) return const SizedBox.shrink();
        return Panel(
          padding: const EdgeInsets.fromLTRB(6, 14, 6, 8),
          borderColor: scoreColor(80).withValues(alpha: 0.5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: PanelTitle(
                  tr('Better choices', 'Betere keuzes'),
                  subtitle: tr('Similar products that score higher', 'Gelijkaardige producten die beter scoren'),
                ),
              ),
              const SizedBox(height: 6),
              if (list == null)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))),
                ),
              for (final (alt, score) in list ?? const <(ProductInfo, int)>[])
                ListTile(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductResultScreen(code: alt.code, countScan: false))),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 44,
                      height: 44,
                      color: p.sunken,
                      child: alt.image == null
                          ? Icon(Icons.inventory_2_outlined, color: p.ink3, size: 20)
                          : Image.network(
                              alt.image!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Icon(Icons.inventory_2_outlined, color: p.ink3, size: 20),
                            ),
                    ),
                  ),
                  title: Text(
                    alt.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: p.ink),
                  ),
                  subtitle: alt.brand == null ? null : Text(alt.brand!, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(color: scoreColor(score), shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$score',
                        style: TextStyle(fontWeight: FontWeight.w700, color: scoreColor(score)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
