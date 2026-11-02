import '../models/payment_message.dart';

/// The rules of the auto-entry queue that don't touch storage or the network,
/// kept apart so they can be unit tested.
class AutoEntryQueuePolicy {
  AutoEntryQueuePolicy._();

  /// The server accepts at most this many messages per request.
  static const int batchSize = 50;

  /// Two notifications with the same package and text this close together are
  /// one payment (apps often re-post the same notification).
  static const Duration duplicateWindow = Duration(seconds: 60);

  static const Duration _firstRetry = Duration(seconds: 30);
  static const Duration _maxRetry = Duration(hours: 6);

  /// Delay before the next try after [attempts] failed ones:
  /// 30 s, 1 min, 2 min, ... capped at 6 hours.
  static Duration backoff(int attempts) {
    if (attempts <= 0) return Duration.zero;
    final exponent = attempts - 1;
    if (exponent >= 20) return _maxRetry;
    final delay = _firstRetry * (1 << exponent);
    return delay > _maxRetry ? _maxRetry : delay;
  }

  /// Whether a pending message may be sent now.
  static bool isDue(PaymentMessage message, DateTime now) {
    if (message.state != PaymentMessageState.pending) return false;
    final next = message.nextAttemptAt;
    return next == null || !next.isAfter(now);
  }

  /// Whether [candidate] repeats a message already in the queue.
  ///
  /// Notifications: same package and text within [duplicateWindow].
  /// Texts: same sender, text and time (so "Import older texts" can be run
  /// twice without sending anything twice).
  static bool isDuplicate({
    required PaymentMessage existing,
    required PaymentMessageSource source,
    required String sender,
    required String body,
    required DateTime receivedAt,
  }) {
    if (existing.source != source ||
        existing.sender != sender ||
        existing.body != body) {
      return false;
    }
    final gap = existing.receivedAt.difference(receivedAt).abs();
    if (source == PaymentMessageSource.notification) {
      return gap <= duplicateWindow;
    }
    return gap < const Duration(seconds: 1);
  }

  /// Splits [messages] into request-sized batches, oldest first.
  static List<List<T>> batches<T>(List<T> messages, {int size = batchSize}) {
    final result = <List<T>>[];
    for (var start = 0; start < messages.length; start += size) {
      final end =
          start + size > messages.length ? messages.length : start + size;
      result.add(messages.sublist(start, end));
    }
    return result;
  }

  /// Formats [time] as ISO 8601 with a UTC offset, e.g.
  /// `2026-11-03T10:15:00+05:30`. [offset] defaults to the phone's own.
  static String isoWithOffset(DateTime time, {Duration? offset}) {
    final zone = offset ?? time.toLocal().timeZoneOffset;
    final local = time.toUtc().add(zone);
    String two(int value) => value.toString().padLeft(2, '0');

    final sign = zone.isNegative ? '-' : '+';
    final minutes = zone.inMinutes.abs();
    final date = '${local.year.toString().padLeft(4, '0')}-'
        '${two(local.month)}-${two(local.day)}';
    final clock =
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
    return '${date}T$clock$sign${two(minutes ~/ 60)}:${two(minutes % 60)}';
  }

  /// Counts for the "This month" block of the Auto-entry screen.
  static AutoEntryMonthCounts monthCounts(
    Iterable<PaymentMessage> messages,
    DateTime now,
  ) {
    var sent = 0;
    var entered = 0;
    var questions = 0;
    var waiting = 0;
    for (final message in messages) {
      final at = message.receivedAt;
      if (at.year != now.year || at.month != now.month) continue;
      switch (message.state) {
        case PaymentMessageState.pending:
          waiting++;
        case PaymentMessageState.rejected:
          break;
        case PaymentMessageState.sent:
          sent++;
          if (message.status == PaymentMessageStatus.entered ||
              message.status == PaymentMessageStatus.merged) {
            entered++;
          } else if (message.status == PaymentMessageStatus.question) {
            questions++;
          }
      }
    }
    return AutoEntryMonthCounts(
      sent: sent,
      entered: entered,
      questions: questions,
      waiting: waiting,
    );
  }
}

class AutoEntryMonthCounts {
  const AutoEntryMonthCounts({
    this.sent = 0,
    this.entered = 0,
    this.questions = 0,
    this.waiting = 0,
  });

  final int sent;
  final int entered;
  final int questions;
  final int waiting;
}
