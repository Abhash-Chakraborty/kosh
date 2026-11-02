import 'package:flutter_test/flutter_test.dart';
import 'package:sure_mobile/models/payment_message.dart';
import 'package:sure_mobile/services/auto_entry_queue_policy.dart';

PaymentMessage _message({
  String clientId = 'c1',
  PaymentMessageSource source = PaymentMessageSource.notification,
  String sender = 'com.google.android.apps.nbu.paisa.user',
  String body = '₹40 paid to Sharma Tea Stall',
  DateTime? receivedAt,
  PaymentMessageState state = PaymentMessageState.pending,
  DateTime? nextAttemptAt,
  String? status,
}) {
  final at = receivedAt ?? DateTime(2026, 11, 3, 10, 15);
  return PaymentMessage(
    clientId: clientId,
    source: source,
    sender: sender,
    body: body,
    receivedAt: at,
    receivedAtIso: '2026-11-03T10:15:00+05:30',
    createdAt: at,
    state: state,
    nextAttemptAt: nextAttemptAt,
    status: status,
  );
}

void main() {
  group('AutoEntryQueuePolicy.backoff', () {
    test('doubles from 30 seconds', () {
      expect(AutoEntryQueuePolicy.backoff(0), Duration.zero);
      expect(AutoEntryQueuePolicy.backoff(1), const Duration(seconds: 30));
      expect(AutoEntryQueuePolicy.backoff(2), const Duration(minutes: 1));
      expect(AutoEntryQueuePolicy.backoff(3), const Duration(minutes: 2));
      expect(AutoEntryQueuePolicy.backoff(10), const Duration(seconds: 15360));
    });

    test('is capped at 6 hours', () {
      expect(AutoEntryQueuePolicy.backoff(11), const Duration(hours: 6));
      expect(AutoEntryQueuePolicy.backoff(500), const Duration(hours: 6));
    });
  });

  group('AutoEntryQueuePolicy.isDue', () {
    final now = DateTime(2026, 11, 3, 12);

    test('pending messages without a retry time are due', () {
      expect(AutoEntryQueuePolicy.isDue(_message(), now), isTrue);
    });

    test('waits for the retry time', () {
      expect(
        AutoEntryQueuePolicy.isDue(
          _message(nextAttemptAt: now.add(const Duration(seconds: 1))),
          now,
        ),
        isFalse,
      );
      expect(
        AutoEntryQueuePolicy.isDue(_message(nextAttemptAt: now), now),
        isTrue,
      );
    });

    test('sent and rejected messages are never due', () {
      expect(
        AutoEntryQueuePolicy.isDue(
            _message(state: PaymentMessageState.sent), now),
        isFalse,
      );
      expect(
        AutoEntryQueuePolicy.isDue(
            _message(state: PaymentMessageState.rejected), now),
        isFalse,
      );
    });
  });

  group('AutoEntryQueuePolicy.isDuplicate', () {
    final existing = _message();

    bool dup({
      PaymentMessageSource source = PaymentMessageSource.notification,
      String? sender,
      String? body,
      Duration gap = Duration.zero,
    }) {
      return AutoEntryQueuePolicy.isDuplicate(
        existing: existing,
        source: source,
        sender: sender ?? existing.sender,
        body: body ?? existing.body,
        receivedAt: existing.receivedAt.add(gap),
      );
    }

    test('same notification within 60 seconds is a duplicate', () {
      expect(dup(gap: const Duration(seconds: 59)), isTrue);
      expect(dup(gap: const Duration(seconds: -60)), isTrue);
    });

    test('same notification after 60 seconds is a new payment', () {
      expect(dup(gap: const Duration(seconds: 61)), isFalse);
    });

    test('different text, package or source is not a duplicate', () {
      expect(dup(body: '₹41 paid to Sharma Tea Stall'), isFalse);
      expect(dup(sender: 'com.phonepe.app'), isFalse);
      expect(dup(source: PaymentMessageSource.sms), isFalse);
    });

    test('texts repeat only with the same timestamp (re-import)', () {
      final sms = _message(
        source: PaymentMessageSource.sms,
        sender: 'AD-HDFCBK-S',
        body: 'Rs 40 debited',
      );
      expect(
        AutoEntryQueuePolicy.isDuplicate(
          existing: sms,
          source: PaymentMessageSource.sms,
          sender: 'AD-HDFCBK-S',
          body: 'Rs 40 debited',
          receivedAt: sms.receivedAt,
        ),
        isTrue,
      );
      expect(
        AutoEntryQueuePolicy.isDuplicate(
          existing: sms,
          source: PaymentMessageSource.sms,
          sender: 'AD-HDFCBK-S',
          body: 'Rs 40 debited',
          receivedAt: sms.receivedAt.add(const Duration(seconds: 30)),
        ),
        isFalse,
      );
    });
  });

  group('AutoEntryQueuePolicy.batches', () {
    test('splits into batches of 50', () {
      final items = List.generate(120, (i) => i);
      final batches = AutoEntryQueuePolicy.batches(items);
      expect(batches.map((b) => b.length), [50, 50, 20]);
      expect(batches.first.first, 0);
      expect(batches.last.last, 119);
    });

    test('returns nothing for an empty queue', () {
      expect(AutoEntryQueuePolicy.batches(<int>[]), isEmpty);
    });
  });

  group('AutoEntryQueuePolicy.isoWithOffset', () {
    test('formats with a positive offset', () {
      expect(
        AutoEntryQueuePolicy.isoWithOffset(
          DateTime.utc(2026, 11, 3, 4, 45),
          offset: const Duration(hours: 5, minutes: 30),
        ),
        '2026-11-03T10:15:00+05:30',
      );
    });

    test('formats with a negative offset across midnight', () {
      expect(
        AutoEntryQueuePolicy.isoWithOffset(
          DateTime.utc(2026, 1, 1, 2, 0, 5),
          offset: const Duration(hours: -3, minutes: -30),
        ),
        '2025-12-31T22:30:05-03:30',
      );
    });

    test('formats UTC as +00:00', () {
      expect(
        AutoEntryQueuePolicy.isoWithOffset(
          DateTime.utc(2026, 6, 9, 8, 7, 6),
          offset: Duration.zero,
        ),
        '2026-06-09T08:07:06+00:00',
      );
    });
  });

  group('AutoEntryQueuePolicy.monthCounts', () {
    test('counts this month only, by outcome', () {
      final now = DateTime(2026, 11, 20);
      final counts = AutoEntryQueuePolicy.monthCounts([
        _message(
          state: PaymentMessageState.sent,
          status: PaymentMessageStatus.entered,
        ),
        _message(
          state: PaymentMessageState.sent,
          status: PaymentMessageStatus.merged,
        ),
        _message(
          state: PaymentMessageState.sent,
          status: PaymentMessageStatus.question,
        ),
        _message(
          state: PaymentMessageState.sent,
          status: PaymentMessageStatus.pending,
        ),
        _message(),
        _message(state: PaymentMessageState.rejected),
        _message(
          state: PaymentMessageState.sent,
          status: PaymentMessageStatus.entered,
          receivedAt: DateTime(2026, 10, 31),
        ),
      ], now);

      expect(counts.sent, 4);
      expect(counts.entered, 2);
      expect(counts.questions, 1);
      expect(counts.waiting, 1);
    });
  });
}
