/// Versie van de app, zoals in pubspec.yaml (zonder buildnummer). Getoond onderaan Instellingen ("Over").
///
/// Bewust een vaste waarde in plaats van een plugin: geen extra bibliotheek (ook niet in de F-Droid-build).
/// test/review_r11_test.dart controleert dat ze gelijk is aan pubspec.yaml; verhoog ze samen met de versie daar.
const appVersion = '1.18.1';
