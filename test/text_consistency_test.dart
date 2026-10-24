// Getallen, dagletters, portie- en activiteitsnamen: overal op dezelfde manier en in de taal die nu gekozen is.
import 'package:flutter_test/flutter_test.dart';
import 'package:macromatrix/data/models.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/nutrition/nutrients.dart';
import 'package:macromatrix/nutrition/values.dart';
import 'package:macromatrix/ui/widgets/kit.dart';

void main() {
  tearDown(() => setAppLang(AppLang.en));

  group('numbers', () {
    test('thousands in both languages, never in fmtNum (used for input fields)', () {
      setAppLang(AppLang.en);
      expect(fmtGrouped(549945), '549,945');
      expect(fmtGrouped(1022.5), '1,022.5');
      expect(fmtGrouped(-1234), '-1,234');
      expect(fmtGrouped(999), '999');
      expect(fmtDec(786421.4), '786,421.4');
      expect(fmtNum(1200, 0), '1200');
      setAppLang(AppLang.nl);
      expect(fmtGrouped(549945), '549.945');
      expect(fmtGrouped(1022.5), '1.022,5');
      expect(fmtDec(253.75, 2), '253,75');
      expect(fmtNum(1200, 0), '1200');
      expect(formatAmount(3500, nutrientByKey['potassium']!), '3.500');
    });

    test('signed values: no −0', () {
      expect(fmtSigned(-0.3), '0');
      expect(fmtSigned(0), '0');
      expect(fmtSigned(-1022), '−1,022');
      expect(fmtSigned(250), '+250');
    });

    test('percentages above 999 are capped', () {
      expect(fmtPct(440.94), '>999%');
      expect(fmtPct(9.99), '999%');
      expect(fmtPct(0.5), '50%');
    });
  });

  test('day letters are two letters and unique', () {
    for (final lang in AppLang.values) {
      setAppLang(lang);
      expect(weekdayShort.length, 7);
      expect(weekdayShort.toSet().length, 7);
      expect(weekdayShort.every((d) => d.length == 2), isTrue);
    }
    setAppLang(AppLang.nl);
    expect(weekdayShort, ['ma', 'di', 'wo', 'do', 'vr', 'za', 'zo']);
  });

  group('portion names', () {
    test('shown in the current language, whatever language they were saved in', () {
      setAppLang(AppLang.nl);
      expect(portionInLang('1 piece (≈120 g)'), '1 stuk (≈120 g)');
      expect(portionInLang('1 pcs'), '1 stuk');
      expect(portionInLang('1 portion (150 g)'), '1 portie (150 g)');
      expect(portionInLang('1 slice (≈35 g)'), '1 sneetje (≈35 g)');
      expect(portionInLang('1 stuk taart (≈75 g)'), '1 stuk taart (≈75 g)');
      expect(portionInLang('1 serving (1/4 of the recipe)'), '1 portie (1/4 van het recept)');
      expect(portionInLang('1 stuk (≈120 g)'), '1 stuk (≈120 g)');
      setAppLang(AppLang.en);
      expect(portionInLang('1 stuk (≈120 g)'), '1 piece (≈120 g)');
      expect(portionInLang('1 pcs'), '1 piece');
      expect(portionInLang('1 op een boterham (≈10 g)'), '1 on a slice (≈10 g)');
      expect(portionInLang('1 kom (≈250 g)'), '1 bowl (≈250 g)');
      expect(portionInLang('1 portie'), '1 serving');
      // Woorden die er alleen op lijken, blijven staan
      expect(portionInLang('1 stukje chocolade'), '1 stukje chocolade');
      expect(portionInLang('1 cup, chopped'), '1 cup, chopped');
    });

    test('a portion saved in the other language still matches', () {
      setAppLang(AppLang.en);
      expect(samePortion('1 stuk (≈120 g)', '1 piece (≈120 g)'), isTrue);
      expect(samePortion('1 kom (≈250 g)', '1 glass (≈250 ml)'), isFalse);
      expect(samePortion(null, '1 piece'), isFalse);
    });
  });

  test('activity names follow the current language', () {
    setAppLang(AppLang.nl);
    expect(exerciseNameInLang('Cycling (brisk, 19-22 km/h)'), 'Fietsen (stevig, 19-22 km/u)');
    expect(exerciseNameInLang('Spinning'), 'Spinning');
    setAppLang(AppLang.en);
    expect(exerciseNameInLang('Fietsen (stevig, 19-22 km/u)'), 'Cycling (brisk, 19-22 km/h)');
    expect(exerciseNameInLang('Cycling (brisk, 19-22 km/h)'), 'Cycling (brisk, 19-22 km/h)');
  });

  test('nutrient names keep their capitals in a sentence', () {
    setAppLang(AppLang.en);
    expect(inSentence(nutrientByKey['b9']!.name), 'B9 (folate)');
    expect(inSentence(nutrientByKey['vit_d']!.name), 'vitamin D');
    expect(nutrientByKey['fiber']!.name, 'Fiber');
  });
}
