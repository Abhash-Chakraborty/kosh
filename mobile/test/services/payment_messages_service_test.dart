import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sure_mobile/models/payment_message.dart';
import 'package:sure_mobile/services/payment_messages_service.dart';

PaymentMessage _message(String clientId) {
  final at = DateTime.utc(2026, 11, 3, 4, 45);
  return PaymentMessage(
    clientId: clientId,
    source: PaymentMessageSource.notification,
    sender: 'com.google.android.apps.nbu.paisa.user',
    app: 'Google Pay',
    body: '₹40 paid to Sharma Tea Stall',
    receivedAt: at,
    receivedAtIso: '2026-11-03T10:15:00+05:30',
    createdAt: at,
  );
}

void main() {
  group('PaymentMessagesService.send', () {
    test('posts the batch in the agreed shape and reads results', () async {
      final service = PaymentMessagesService(
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/v1/payment_messages');
          expect(request.headers['Authorization'], 'Bearer token');

          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          final messages = payload['messages'] as List;
          expect(messages, hasLength(1));
          expect(messages.first, {
            'client_id': 'c1',
            'source': 'notification',
            'sender': 'com.google.android.apps.nbu.paisa.user',
            'app': 'Google Pay',
            'body': '₹40 paid to Sharma Tea Stall',
            'received_at': '2026-11-03T10:15:00+05:30',
          });

          return http.Response(
            jsonEncode({
              'results': [
                {
                  'client_id': 'c1',
                  'id': 'srv-1',
                  'status': 'question',
                  'summary': '₹40 to Sharma Tea Stall',
                  'question': 'What was ₹40 to Sharma Tea Stall for?',
                  'entry_id': null,
                },
                {'id': 'no-client-id'},
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final response = await service.send(
        accessToken: 'token',
        messages: [_message('c1')],
      );

      expect(response.outcome, PaymentBatchOutcome.ok);
      expect(response.results, hasLength(1));
      final result = response.results.single;
      expect(result.clientId, 'c1');
      expect(result.id, 'srv-1');
      expect(result.status, PaymentMessageStatus.question);
      expect(result.question, 'What was ₹40 to Sharma Tea Stall for?');
      expect(result.entryId, isNull);
    });

    test('maps error statuses to outcomes', () async {
      Future<PaymentBatchOutcome> outcomeFor(int status) async {
        final service = PaymentMessagesService(
          client: MockClient((_) async => http.Response('{}', status)),
        );
        final response = await service.send(
          accessToken: 'token',
          messages: [_message('c1')],
        );
        return response.outcome;
      }

      expect(await outcomeFor(401), PaymentBatchOutcome.unauthorized);
      expect(await outcomeFor(403), PaymentBatchOutcome.unauthorized);
      expect(await outcomeFor(422), PaymentBatchOutcome.rejected);
      expect(await outcomeFor(500), PaymentBatchOutcome.retry);
      expect(await outcomeFor(503), PaymentBatchOutcome.retry);
    });

    test('treats network failures as retry', () async {
      final service = PaymentMessagesService(
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      final response = await service.send(
        accessToken: 'token',
        messages: [_message('c1')],
      );
      expect(response.outcome, PaymentBatchOutcome.retry);
    });
  });

  group('PaymentMessagesService reads', () {
    test('fetchByIds asks for the given ids', () async {
      final service = PaymentMessagesService(
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/v1/payment_messages');
          expect(request.url.queryParameters['ids'], 'srv-1,srv-2');
          return http.Response(
            jsonEncode({
              'payment_messages': [
                {
                  'id': 'srv-1',
                  'client_id': 'c1',
                  'status': 'entered',
                  'summary': '₹40 to Sharma Tea Stall',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final results = await service.fetchByIds(
        accessToken: 'token',
        ids: ['srv-1', 'srv-2'],
      );
      expect(results, isNotNull);
      expect(results!.single.status, PaymentMessageStatus.entered);
    });

    test('fetchRecent returns null on failure', () async {
      final service = PaymentMessagesService(
        client: MockClient((_) async => http.Response('nope', 500)),
      );
      expect(await service.fetchRecent(accessToken: 'token'), isNull);
    });
  });
}
