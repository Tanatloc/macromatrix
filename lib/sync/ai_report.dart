/// Een AI-tekst melden (Google Play-beleid voor generatieve AI): de tekst komt in de tabel ai_reports via de functie
/// ai_report (migratie 20261105000000_ai_reports). Bruikbaar voor de coach, en later ook voor foto en etiket via
/// [kind]. Gebruikers kunnen meldingen niet lezen; alleen de beheerder bekijkt ze.
library;

import 'api.dart';

/// Hoogstens zoveel tekens tekst (de tabel weigert meer).
const aiReportMaxText = 4000;

/// Hoogstens zoveel tekens notitie.
const aiReportMaxNote = 1000;

/// Uitkomst van een melding.
enum AiReportResult {
  /// Opgeslagen.
  reported,

  /// Te veel meldingen vandaag.
  limit,

  /// Niet gelukt: geen verbinding, niet ingelogd of de migratie ontbreekt.
  failed,
}

class AiReporter {
  const AiReporter();

  /// Meldt [text] (bv. de samenvatting en de tips van de coach) met [note] (week, model, en wat de gebruiker
  /// eventueel schreef). [kind]: 'coach', 'photo', 'label', … Gooit nooit.
  Future<AiReportResult> report(Rpc? client, {required String kind, required String text, String? note}) async {
    if (client == null) return AiReportResult.failed;
    try {
      final r = await client.rpc(
        'ai_report',
        params: {
          'p_kind': kind,
          'p_text': text.length > aiReportMaxText ? text.substring(0, aiReportMaxText) : text,
          'p_note': note == null ? null : (note.length > aiReportMaxNote ? note.substring(0, aiReportMaxNote) : note),
        },
      );
      return switch (r) {
        'reported' => AiReportResult.reported,
        'limit' => AiReportResult.limit,
        _ => AiReportResult.failed,
      };
    } catch (_) {
      return AiReportResult.failed;
    }
  }
}
