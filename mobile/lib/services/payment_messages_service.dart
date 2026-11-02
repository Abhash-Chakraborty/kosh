import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/payment_message.dart';
import 'api_config.dart';

/// Outcome of sending one batch to `POST /api/v1/payment_messages`.
enum PaymentBatchOutcome {
  /// 200: [PaymentBatchResponse.results] holds the server's answers.
  ok,

  /// 422: the batch was malformed.
  rejected,

  /// 401/403: signed out, or the token lacks read_write.
  unauthorized,

  /// Network error, timeout or 5xx: try again later.
  retry,
}

class PaymentBatchResponse {
  const PaymentBatchResponse(
    this.outcome, {
    this.results = const [],
    this.error,
  });

  final PaymentBatchOutcome outcome;
  final List<PaymentMessageResult> results;
  final String? error;
}

class PaymentMessagesService {
  PaymentMessagesService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const String _path = '/api/v1/payment_messages';

  Future<PaymentBatchResponse> send({
    required String accessToken,
    required List<PaymentMessage> messages,
  }) async {
    final url = Uri.parse('${ApiConfig.baseUrl}$_path');
    try {
      final response = await _client
          .post(
            url,
            headers: {
              ...ApiConfig.getAuthHeaders(accessToken),
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'messages': messages.map((m) => m.toApiJson()).toList(),
            }),
          )
          .timeout(const Duration(seconds: 30));

      switch (response.statusCode) {
        case 200:
        case 201:
          return PaymentBatchResponse(
            PaymentBatchOutcome.ok,
            results: _parseList(response.body, 'results'),
          );
        case 401:
        case 403:
          return PaymentBatchResponse(
            PaymentBatchOutcome.unauthorized,
            error: 'HTTP ${response.statusCode}',
          );
        case 422:
          return const PaymentBatchResponse(
            PaymentBatchOutcome.rejected,
            error: 'HTTP 422',
          );
        default:
          return PaymentBatchResponse(
            PaymentBatchOutcome.retry,
            error: 'HTTP ${response.statusCode}',
          );
      }
    } catch (e) {
      return PaymentBatchResponse(
        PaymentBatchOutcome.retry,
        error: e.runtimeType.toString(),
      );
    }
  }

  /// Current results for specific server ids: messages the server is still
  /// reading (`status: "pending"`). Null on failure.
  Future<List<PaymentMessageResult>?> fetchByIds({
    required String accessToken,
    required List<String> ids,
  }) async {
    if (ids.isEmpty) return const [];
    final url = Uri.parse('${ApiConfig.baseUrl}$_path')
        .replace(queryParameters: {'ids': ids.join(',')});
    try {
      final response = await _client
          .get(url, headers: ApiConfig.getAuthHeaders(accessToken))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) return null;
      return _parseList(response.body, 'payment_messages');
    } catch (_) {
      return null;
    }
  }

  /// The server's latest view of recent messages, for refreshing statuses
  /// (a question answered on the web becomes `entered`). Null on failure.
  Future<List<PaymentMessageResult>?> fetchRecent({
    required String accessToken,
    int limit = 50,
  }) async {
    final url = Uri.parse('${ApiConfig.baseUrl}$_path')
        .replace(queryParameters: {'limit': '$limit'});
    try {
      final response = await _client
          .get(url, headers: ApiConfig.getAuthHeaders(accessToken))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) return null;
      return _parseList(response.body, 'payment_messages');
    } catch (_) {
      return null;
    }
  }

  List<PaymentMessageResult> _parseList(String body, String key) {
    final decoded = jsonDecode(body);
    final raw = decoded is Map ? decoded[key] : null;
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => PaymentMessageResult.fromJson(item.cast<String, dynamic>()))
        .whereType<PaymentMessageResult>()
        .toList();
  }
}
