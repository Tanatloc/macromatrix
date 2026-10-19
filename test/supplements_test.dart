import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/nutrition/supplements.dart';

void main() {
  test('supplement aan- en afvinken: één regel per dag, telt niet als gelogde dag', () {
    final db = UserDb(sqlite3.openInMemory());
    final d = supplementCatalog.firstWhere((x) => x.id == 'vitd25');
    expect(db.hasSupplementRow('2026-10-16', d), isFalse);
    db.setSupplementTaken('2026-10-16', d, true);
    var e = db.entriesFor('2026-10-16').single;
    expect(e.id, 'supp:vitd25:2026-10-16');
    expect(e.amounts['vit_d'], 25);
    db.setSupplementTaken('2026-10-16', d, false);
    expect(db.entriesFor('2026-10-16'), isEmpty);
    expect(db.hasSupplementRow('2026-10-16', d), isTrue, reason: 'afgevinkt blijft bewaard, zodat automatisch aanvinken het niet terugzet');
    db.setSupplementTaken('2026-10-16', d, true);
    expect(db.entriesFor('2026-10-16'), hasLength(1));
    expect(db.loggedDays(), isEmpty);
  });

  test('eigen supplement bewaren en teruglezen', () {
    const s = Supplement(
      id: 'c1',
      name: 'Mg + B6',
      dose: '1 capsule',
      nutrients: {'energy': 0, 'magnesium': 150, 'b6': 1.4},
      auto: true,
      since: '2026-10-16',
    );
    final back = Supplement.fromJson(s.toJson());
    expect(back.nutrients, s.nutrients);
    expect(back.auto, isTrue);
    expect(back.summary, 'Magnesium 150 mg · B6 1.4 mg');
  });

  test('hetzelfde supplement twee keer: elk een eigen vinkje', () {
    final db = UserDb(sqlite3.openInMemory());
    final d = supplementCatalog.firstWhere((x) => x.id == 'vitd25');
    final d2 = d.copyWith(id: 'vitd25~2');
    expect(d2.baseId, 'vitd25');
    db.setSupplementTaken('2026-10-16', d, true);
    db.setSupplementTaken('2026-10-16', d2, true);
    expect(db.entriesFor('2026-10-16'), hasLength(2));
    db.setSupplementTaken('2026-10-16', d2, false);
    expect(db.entriesFor('2026-10-16').single.id, 'supp:vitd25:2026-10-16');
  });
}
