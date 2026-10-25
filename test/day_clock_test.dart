import 'package:flutter_test/flutter_test.dart';
import 'package:macromatrix/day_clock.dart';

void main() {
  // Lokale tijd in Europa: 25 oktober 2026 duurt 25 uur, 29 maart 2026 maar 23
  test('plusDays telt kalenderdagen, ook rond de klokwissel', () {
    expect(DateTime(2026, 10, 25).plusDays(1), DateTime(2026, 10, 26));
    expect(DateTime(2026, 10, 26).plusDays(-1), DateTime(2026, 10, 25));
    expect(DateTime(2026, 3, 30).plusDays(-1), DateTime(2026, 3, 29));
    expect(DateTime(2026, 3, 29).plusDays(1), DateTime(2026, 3, 30));
    expect(DateTime(2026, 10, 20).plusDays(7), DateTime(2026, 10, 27));
    expect(DateTime(2026, 12, 31, 14, 30).plusDays(1), DateTime(2027, 1, 1, 14, 30));
    expect(DateTime.utc(2026, 3, 1).plusDays(-1), DateTime.utc(2026, 2, 28));
  });

  test('daysBetween over de klokwissel', () {
    expect(daysBetween(DateTime(2026, 3, 29), DateTime(2026, 3, 30)), 1);
    expect(daysBetween(DateTime(2026, 10, 25), DateTime(2026, 10, 26)), 1);
  });

  test('logicalNow rekent op de klok, ook in de nacht van de klokwissel', () {
    final old = appClock;
    addTearDown(() => appClock = old);
    appClock = () => DateTime(2026, 3, 29, 3, 30);
    expect(logicalNow().day, 29);
    appClock = () => DateTime(2026, 3, 29, 1, 59);
    expect(logicalNow().day, 28);
    appClock = () => DateTime(2026, 10, 25, 2, 30);
    expect(logicalNow().day, 24);
    appClock = () => DateTime(2026, 10, 25, 3, 0);
    expect(logicalNow().day, 25);
  });
}
