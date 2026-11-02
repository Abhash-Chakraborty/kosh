import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/payment_message.dart';
import 'auto_entry_queue_policy.dart';

/// The auto-entry outbox: masked messages waiting to be sent, and the
/// server's answer once they are. Its own database file, so it never touches
/// the offline transactions schema.
class AutoEntryQueue {
  AutoEntryQueue._();

  static final AutoEntryQueue instance = AutoEntryQueue._();

  static const String _fileName = 'kosh_auto_entry.db';
  static const String _messages = 'payment_messages';
  static const String _skips = 'skipped_otps';

  /// Sent messages older than this are pruned.
  static const Duration _keep = Duration(days: 120);

  Database? _db;

  Future<Database> get _database async {
    final existing = _db;
    if (existing != null) return existing;
    final path = join(await getDatabasesPath(), _fileName);
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_messages (
            client_id TEXT PRIMARY KEY,
            source TEXT NOT NULL,
            sender TEXT NOT NULL,
            app TEXT,
            body TEXT NOT NULL,
            received_ms INTEGER NOT NULL,
            received_at TEXT NOT NULL,
            created_ms INTEGER NOT NULL,
            state TEXT NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0,
            next_attempt_ms INTEGER,
            last_error TEXT,
            server_id TEXT,
            status TEXT,
            summary TEXT,
            question TEXT,
            entry_id TEXT,
            notified INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_${_messages}_state ON $_messages (state, next_attempt_ms)',
        );
        await db.execute(
          'CREATE INDEX idx_${_messages}_received ON $_messages (received_ms)',
        );
        await db.execute('''
          CREATE TABLE $_skips (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sender TEXT NOT NULL,
            at_ms INTEGER NOT NULL
          )
        ''');
      },
    );
    _db = db;
    return db;
  }

  /// Adds a message unless it repeats one already queued. Returns false for
  /// a duplicate.
  Future<bool> add(PaymentMessage message) async {
    final db = await _database;
    final window = AutoEntryQueuePolicy.duplicateWindow.inMilliseconds;
    final ms = message.receivedAt.millisecondsSinceEpoch;
    final nearby = await db.query(
      _messages,
      where: 'sender = ? AND source = ? AND received_ms BETWEEN ? AND ?',
      whereArgs: [
        message.sender,
        message.source.apiValue,
        ms - window,
        ms + window,
      ],
    );
    final duplicate = nearby.map(PaymentMessage.fromDb).any(
          (existing) => AutoEntryQueuePolicy.isDuplicate(
            existing: existing,
            source: message.source,
            sender: message.sender,
            body: message.body,
            receivedAt: message.receivedAt,
          ),
        );
    if (duplicate) return false;

    await db.insert(
      _messages,
      message.toDb(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return true;
  }

  Future<void> recordSkippedOtp(String sender, DateTime at) async {
    final db = await _database;
    await db.insert(_skips, {
      'sender': sender,
      'at_ms': at.millisecondsSinceEpoch,
    });
  }

  Future<int> skippedOtpsSince(DateTime since) async {
    final db = await _database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM $_skips WHERE at_ms >= ?',
      [since.millisecondsSinceEpoch],
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  /// Pending messages whose retry time has come, oldest first.
  Future<List<PaymentMessage>> due(DateTime now) async {
    final db = await _database;
    final rows = await db.query(
      _messages,
      where: 'state = ? AND (next_attempt_ms IS NULL OR next_attempt_ms <= ?)',
      whereArgs: [
        PaymentMessageState.pending.dbValue,
        now.millisecondsSinceEpoch,
      ],
      orderBy: 'received_ms ASC',
    );
    return rows.map(PaymentMessage.fromDb).toList();
  }

  Future<int> pendingCount() async {
    final db = await _database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM $_messages WHERE state = ?',
      [PaymentMessageState.pending.dbValue],
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  /// Most recent messages first, for the Latest feed.
  Future<List<PaymentMessage>> latest({int limit = 50}) async {
    final db = await _database;
    final rows = await db.query(
      _messages,
      orderBy: 'received_ms DESC',
      limit: limit,
    );
    return rows.map(PaymentMessage.fromDb).toList();
  }

  Future<List<PaymentMessage>> since(DateTime start) async {
    final db = await _database;
    final rows = await db.query(
      _messages,
      where: 'received_ms >= ?',
      whereArgs: [start.millisecondsSinceEpoch],
    );
    return rows.map(PaymentMessage.fromDb).toList();
  }

  /// Stores the server's answer for a message. Returns true if the row exists.
  Future<bool> applyResult(PaymentMessageResult result) async {
    final db = await _database;
    final changed = await db.update(
      _messages,
      {
        'state': PaymentMessageState.sent.dbValue,
        'server_id': result.id,
        'status': result.status,
        'summary': result.summary,
        'question': result.question,
        'entry_id': result.entryId,
        'last_error': null,
        'next_attempt_ms': null,
      },
      where: 'client_id = ?',
      whereArgs: [result.clientId],
    );
    return changed > 0;
  }

  Future<void> markRetry(
    Iterable<PaymentMessage> messages,
    String? error,
    DateTime now,
  ) async {
    final db = await _database;
    final batch = db.batch();
    for (final message in messages) {
      final attempts = message.attempts + 1;
      batch.update(
        _messages,
        {
          'attempts': attempts,
          'next_attempt_ms':
              now.add(AutoEntryQueuePolicy.backoff(attempts)).millisecondsSinceEpoch,
          'last_error': error,
        },
        where: 'client_id = ?',
        whereArgs: [message.clientId],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> markRejected(PaymentMessage message, String? error) async {
    final db = await _database;
    await db.update(
      _messages,
      {
        'state': PaymentMessageState.rejected.dbValue,
        'last_error': error,
      },
      where: 'client_id = ?',
      whereArgs: [message.clientId],
    );
  }

  /// Sent messages the server is still reading (status `pending`), so their
  /// final status can be fetched by id.
  Future<List<PaymentMessage>> awaitingServer() async {
    final db = await _database;
    final rows = await db.query(
      _messages,
      where: 'state = ? AND status = ? AND server_id IS NOT NULL',
      whereArgs: [
        PaymentMessageState.sent.dbValue,
        PaymentMessageStatus.pending,
      ],
    );
    return rows.map(PaymentMessage.fromDb).toList();
  }

  /// Questions the phone hasn't shown a notification for yet.
  Future<List<PaymentMessage>> unnotifiedQuestions() async {
    final db = await _database;
    final rows = await db.query(
      _messages,
      where: 'status = ? AND notified = 0',
      whereArgs: [PaymentMessageStatus.question],
    );
    return rows.map(PaymentMessage.fromDb).toList();
  }

  Future<void> markNotified(String clientId) async {
    final db = await _database;
    await db.update(
      _messages,
      {'notified': 1},
      where: 'client_id = ?',
      whereArgs: [clientId],
    );
  }

  /// Drops answered messages and OTP skip records past the retention window.
  Future<void> prune(DateTime now) async {
    final db = await _database;
    final cutoff = now.subtract(_keep).millisecondsSinceEpoch;
    await db.delete(
      _messages,
      where: 'state != ? AND received_ms < ?',
      whereArgs: [PaymentMessageState.pending.dbValue, cutoff],
    );
    await db.delete(_skips, where: 'at_ms < ?', whereArgs: [cutoff]);
  }
}
