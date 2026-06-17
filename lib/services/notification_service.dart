import 'dart:convert';
import 'package:http/http.dart' as http;

class NotificationService {
  // TODO: Replace this with your deployed Firebase Function URL.
  // Example: https://us-central1-<project>.cloudfunctions.net/sendWhatsApp
  static String cloudFunctionUrl = 'REPLACE_WITH_CLOUD_FUNCTION_URL';

  /// Notify the host that [leaverName] has left the party.
  /// [hostPhone] should be in international format (e.g. +91XXXXXXXXXX).
  static Future<void> notifyHostLeave({
    required String hostPhone,
    required String leaverName,
    required String partyId,
  }) async {
    if (cloudFunctionUrl.contains('REPLACE_WITH')) {
      // Nothing to do in dev until user provides URL.
      return;
    }

    final uri = Uri.parse(cloudFunctionUrl);
    final body = jsonEncode({
      'toPhone': hostPhone,
      'message': "$leaverName has left your party (id: $partyId).",
    });

    final resp = await http.post(uri,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Failed to notify host: ${resp.statusCode} ${resp.body}');
    }
  }
}
