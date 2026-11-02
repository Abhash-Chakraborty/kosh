/// Where an auto-entry message came from.
enum PaymentMessageSource {
  sms('sms'),
  notification('notification');

  const PaymentMessageSource(this.apiValue);

  final String apiValue;

  static PaymentMessageSource fromApi(String? value) {
    return value == notification.apiValue ? notification : sms;
  }
}

/// Local delivery state of a queued message.
enum PaymentMessageState {
  /// Waiting to be sent (or to be retried).
  pending('pending'),

  /// The server answered with a result for it.
  sent('sent'),

  /// The server refused it (malformed); it won't be retried.
  rejected('rejected');

  const PaymentMessageState(this.dbValue);

  final String dbValue;

  static PaymentMessageState fromDb(String? value) {
    return PaymentMessageState.values.firstWhere(
      (state) => state.dbValue == value,
      orElse: () => PaymentMessageState.pending,
    );
  }
}

/// Server statuses from `POST /api/v1/payment_messages`.
class PaymentMessageStatus {
  PaymentMessageStatus._();

  static const entered = 'entered';
  static const merged = 'merged';
  static const question = 'question';
  static const ignored = 'ignored';
  static const failed = 'failed';

  /// The text went to the server's AI reader; the answer comes later and is
  /// fetched with `GET /api/v1/payment_messages?ids=...`.
  static const pending = 'pending';
}

/// One bank text or payment-app notification on its way to the server, and
/// what the server made of it.
class PaymentMessage {
  const PaymentMessage({
    required this.clientId,
    required this.source,
    required this.sender,
    required this.body,
    required this.receivedAt,
    required this.receivedAtIso,
    required this.createdAt,
    this.app,
    this.state = PaymentMessageState.pending,
    this.attempts = 0,
    this.nextAttemptAt,
    this.lastError,
    this.serverId,
    this.status,
    this.summary,
    this.question,
    this.entryId,
    this.notified = false,
  });

  final String clientId;
  final PaymentMessageSource source;

  /// DLT header for texts, package name for notifications.
  final String sender;

  /// Human app name for notifications ("Google Pay"); null for texts.
  final String? app;

  /// Masked text. The unmasked text is never stored here.
  final String body;
  final DateTime receivedAt;

  /// [receivedAt] as ISO 8601 with the phone's UTC offset, as sent.
  final String receivedAtIso;
  final DateTime createdAt;

  final PaymentMessageState state;
  final int attempts;
  final DateTime? nextAttemptAt;
  final String? lastError;

  final String? serverId;
  final String? status;
  final String? summary;
  final String? question;
  final String? entryId;

  /// Whether a local notification was already shown for its question.
  final bool notified;

  bool get isQuestion => status == PaymentMessageStatus.question;

  /// The payload item for `POST /api/v1/payment_messages`.
  Map<String, dynamic> toApiJson() {
    return {
      'client_id': clientId,
      'source': source.apiValue,
      'sender': sender,
      if (app != null) 'app': app,
      'body': body,
      'received_at': receivedAtIso,
    };
  }

  Map<String, Object?> toDb() {
    return {
      'client_id': clientId,
      'source': source.apiValue,
      'sender': sender,
      'app': app,
      'body': body,
      'received_ms': receivedAt.millisecondsSinceEpoch,
      'received_at': receivedAtIso,
      'created_ms': createdAt.millisecondsSinceEpoch,
      'state': state.dbValue,
      'attempts': attempts,
      'next_attempt_ms': nextAttemptAt?.millisecondsSinceEpoch,
      'last_error': lastError,
      'server_id': serverId,
      'status': status,
      'summary': summary,
      'question': question,
      'entry_id': entryId,
      'notified': notified ? 1 : 0,
    };
  }

  factory PaymentMessage.fromDb(Map<String, Object?> row) {
    DateTime? fromMs(Object? value) => value is int
        ? DateTime.fromMillisecondsSinceEpoch(value)
        : null;

    return PaymentMessage(
      clientId: row['client_id'] as String,
      source: PaymentMessageSource.fromApi(row['source'] as String?),
      sender: row['sender'] as String? ?? '',
      app: row['app'] as String?,
      body: row['body'] as String? ?? '',
      receivedAt: fromMs(row['received_ms']) ?? DateTime.now(),
      receivedAtIso: row['received_at'] as String? ?? '',
      createdAt: fromMs(row['created_ms']) ?? DateTime.now(),
      state: PaymentMessageState.fromDb(row['state'] as String?),
      attempts: row['attempts'] as int? ?? 0,
      nextAttemptAt: fromMs(row['next_attempt_ms']),
      lastError: row['last_error'] as String?,
      serverId: row['server_id'] as String?,
      status: row['status'] as String?,
      summary: row['summary'] as String?,
      question: row['question'] as String?,
      entryId: row['entry_id'] as String?,
      notified: row['notified'] == 1,
    );
  }
}

/// One item of the server's `results` (or `payment_messages`) list.
class PaymentMessageResult {
  const PaymentMessageResult({
    required this.clientId,
    this.id,
    this.status,
    this.summary,
    this.question,
    this.entryId,
  });

  final String clientId;
  final String? id;
  final String? status;
  final String? summary;
  final String? question;
  final String? entryId;

  static PaymentMessageResult? fromJson(Map<String, dynamic> json) {
    final clientId = json['client_id'];
    if (clientId is! String || clientId.isEmpty) return null;

    String? text(String key) {
      final value = json[key];
      if (value == null) return null;
      final string = value.toString().trim();
      return string.isEmpty ? null : string;
    }

    return PaymentMessageResult(
      clientId: clientId,
      id: text('id'),
      status: text('status'),
      summary: text('summary'),
      question: text('question'),
      entryId: text('entry_id'),
    );
  }
}
