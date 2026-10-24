/// De wekelijkse coach op de eigen server (/api/coach): de samenvatting van je week versturen en de tekst terugkrijgen.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../nutrition/coach.dart';
import '../sync/pro.dart' show PhotoQuota;
import 'ai_request.dart';

class CoachRequest {
  CoachRequest([this._client]);
  final http.Client? _client;

  /// Stand van de dagteller die de server meestuurde (ook bij een fout, als die er was).
  PhotoQuota? lastQuota;

  /// [week] uit [coachWeek]. Gooit een [AiException] (quota, not_configured, timeout, bad_output, network, …).
  Future<CoachResult> write(Map<String, Object?> week, {required String token}) async {
    lastQuota = null;
    try {
      final j = await aiSend(
        (c) => c.post(
          apiEndpoint('/api/coach'),
          headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
          body: jsonEncode(week),
        ),
        client: _client,
      );
      lastQuota = PhotoQuota.fromJson(j['quota']);
      final r = CoachResult.fromJson(j);
      if (r == null) throw AiException('bad_output');
      return r;
    } on AiException catch (e) {
      lastQuota = e.quota ?? lastQuota;
      rethrow;
    }
  }
}
