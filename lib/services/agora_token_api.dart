// Add this method to your existing ApiService class

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart' as appConfig;

Future<Map<String, dynamic>> getAgoraToken(String token, String callId, String channelName) async {
  final response = await http.post(
    Uri.parse(appConfig.Config.agoraTokenEndpoint),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    },
    body: jsonEncode({
      'call_id': callId,
      'channel_name': channelName,
    }),
  );

  if (response.statusCode == 200) {
    return jsonDecode(response.body);
  } else {
    throw Exception('Failed to get Agora token: ${response.statusCode}');
  }
}