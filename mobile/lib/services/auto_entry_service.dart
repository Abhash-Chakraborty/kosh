import 'dart:ui' show DartPluginRegistrant, PlatformDispatcher;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../l10n/app_localizations.dart';
import '../models/payment_message.dart';
import '../utils/account_number_masker.dart';
import '../utils/payment_text_filter.dart';
import 'api_config.dart';
import 'auth_service.dart';
import 'auto_entry_platform.dart';
import 'auto_entry_queue.dart';
import 'auto_entry_queue_policy.dart';
import 'log_service.dart';
import 'payment_messages_service.dart';

/// What one delivery pass did.
class AutoEntrySyncResult {
  const AutoEntrySyncResult({
    this.queued = 0,
    this.sent = 0,
    this.pending = 0,
    this.retryLater = false,
    this.unauthorized = false,
    this.waitingForWifi = false,
  });

  final int queued;
  final int sent;
  final int pending;

  /// Some messages failed for a reason that may pass (network, server error).
  final bool retryLater;
  final bool unauthorized;
  final bool waitingForWifi;
}

/// Runs auto-entry end to end: takes what the native receivers captured,
/// filters and masks it, queues it in sqflite and sends the queue.
/// Used by the app while it's open and by the background worker.
class AutoEntryService {
  AutoEntryService({
    AutoEntryQueue? queue,
    AutoEntryPlatform? platform,
    PaymentMessagesService? api,
  })  : _queue = queue ?? AutoEntryQueue.instance,
        _platform = platform ?? AutoEntryPlatform.instance,
        _api = api ?? PaymentMessagesService();

  static final AutoEntryService instance = AutoEntryService();

  static const String _tag = 'AutoEntry';
  static const Uuid _uuid = Uuid();

  final AutoEntryQueue _queue;
  final AutoEntryPlatform _platform;
  final PaymentMessagesService _api;
  final LogService _log = LogService.instance;

  bool _syncing = false;

  /// Filters, masks and queues captured messages. Returns how many were
  /// queued. OTPs are only logged as "skipped OTP from" plus the sender.
  Future<int> ingest(InboxDrain drain) async {
    for (final skip in drain.skippedOtps) {
      await _recordOtp(skip.sender, skip.at);
    }

    var queued = 0;
    for (final captured in drain.messages) {
      final isSms = captured.source == PaymentMessageSource.sms.apiValue;
      final decision = isSms
          ? PaymentTextFilter.checkSms(
              sender: captured.sender,
              body: captured.body,
            )
          : PaymentTextFilter.checkNotification(captured.body);

      if (decision == PaymentTextDecision.skipOtp) {
        await _recordOtp(captured.sender, captured.receivedAt);
        continue;
      }
      if (decision != PaymentTextDecision.keep) continue;

      final message = PaymentMessage(
        clientId: _uuid.v4(),
        source: isSms
            ? PaymentMessageSource.sms
            : PaymentMessageSource.notification,
        sender: captured.sender,
        app: isSms ? null : PaymentApp.labelFor(captured.sender),
        body: AccountNumberMasker.mask(captured.body),
        receivedAt: captured.receivedAt,
        receivedAtIso: AutoEntryQueuePolicy.isoWithOffset(captured.receivedAt),
        createdAt: DateTime.now(),
      );
      if (await _queue.add(message)) queued++;
    }
    return queued;
  }

  Future<void> _recordOtp(String sender, DateTime at) async {
    _log.info(_tag, 'Skipped OTP from $sender');
    await _queue.recordSkippedOtp(sender, at);
  }

  /// Sends every due message, in batches of 50.
  Future<AutoEntrySyncResult> flush({
    required String accessToken,
    required bool mobileDataAllowed,
  }) async {
    if (!mobileDataAllowed && !await _onUnmeteredNetwork()) {
      return AutoEntrySyncResult(
        pending: await _queue.pendingCount(),
        waitingForWifi: true,
      );
    }

    final now = DateTime.now();
    final due = await _queue.due(now);
    var sent = 0;
    var retryLater = false;

    for (final batch in AutoEntryQueuePolicy.batches(due)) {
      final response = await _api.send(
        accessToken: accessToken,
        messages: batch,
      );
      switch (response.outcome) {
        case PaymentBatchOutcome.ok:
          sent += await _applyResults(batch, response.results, now);
          if (response.results.length < batch.length) retryLater = true;
        case PaymentBatchOutcome.unauthorized:
          _log.warning(_tag, 'Server refused auto-entry: ${response.error}');
          return AutoEntrySyncResult(
            sent: sent,
            pending: await _queue.pendingCount(),
            unauthorized: true,
          );
        case PaymentBatchOutcome.rejected:
          // One bad message shouldn't hold back the rest: retry them singly
          // and drop only the ones the server still refuses.
          final single = await _sendSingly(accessToken, batch, now);
          sent += single.sent;
          retryLater = retryLater || single.retryLater;
        case PaymentBatchOutcome.retry:
          _log.warning(_tag, 'Auto-entry send failed: ${response.error}');
          await _queue.markRetry(batch, response.error, now);
          retryLater = true;
      }
    }

    return AutoEntrySyncResult(
      sent: sent,
      pending: await _queue.pendingCount(),
      retryLater: retryLater,
    );
  }

  Future<AutoEntrySyncResult> _sendSingly(
    String accessToken,
    List<PaymentMessage> batch,
    DateTime now,
  ) async {
    var sent = 0;
    var retryLater = false;
    for (final message in batch) {
      final response = await _api.send(
        accessToken: accessToken,
        messages: [message],
      );
      switch (response.outcome) {
        case PaymentBatchOutcome.ok:
          sent += await _applyResults([message], response.results, now);
        case PaymentBatchOutcome.rejected:
          _log.warning(_tag, 'Server rejected one auto-entry message');
          await _queue.markRejected(message, response.error);
        case PaymentBatchOutcome.unauthorized:
        case PaymentBatchOutcome.retry:
          await _queue.markRetry([message], response.error, now);
          retryLater = true;
      }
    }
    return AutoEntrySyncResult(sent: sent, retryLater: retryLater);
  }

  Future<int> _applyResults(
    List<PaymentMessage> batch,
    List<PaymentMessageResult> results,
    DateTime now,
  ) async {
    final answered = <String>{};
    for (final result in results) {
      if (await _queue.applyResult(result)) answered.add(result.clientId);
    }
    final missing =
        batch.where((message) => !answered.contains(message.clientId));
    if (missing.isNotEmpty) {
      await _queue.markRetry(missing, 'no result', now);
    }
    return answered.length;
  }

  Future<bool> _onUnmeteredNetwork() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.contains(ConnectivityResult.wifi) ||
          results.contains(ConnectivityResult.ethernet);
    } catch (_) {
      return false;
    }
  }

  /// Shows a local notification for each new question from the server.
  Future<void> notifyQuestions() async {
    final questions = await _queue.unnotifiedQuestions();
    if (questions.isEmpty) return;
    final l = _localizations();
    for (final message in questions) {
      final text = message.question ?? message.summary;
      if (text == null) continue;
      try {
        await _platform.showQuestion(
          id: message.serverId ?? message.clientId,
          title: l.autoEntryQuestionNotificationTitle,
          text: text,
        );
        await _queue.markNotified(message.clientId);
      } catch (e) {
        _log.warning(_tag, 'Question notification failed: ${e.runtimeType}');
      }
    }
  }

  /// Server-side "pending" results younger than this keep the background
  /// worker polling (with its backoff) until the AI reader answers.
  static const Duration _pollPendingFor = Duration(minutes: 30);

  /// Re-fetches messages the server was still reading. Returns true while
  /// some recent ones are still pending.
  Future<bool> refreshServerPending(String accessToken) async {
    final waiting = await _queue.awaitingServer();
    if (waiting.isEmpty) return false;
    final ids = waiting.map((m) => m.serverId!).toList();
    for (final chunk in AutoEntryQueuePolicy.batches(ids)) {
      final results =
          await _api.fetchByIds(accessToken: accessToken, ids: chunk);
      if (results == null) return true;
      for (final result in results) {
        await _queue.applyResult(result);
      }
    }
    final cutoff = DateTime.now().subtract(_pollPendingFor);
    final still = await _queue.awaitingServer();
    return still.any((m) => m.createdAt.isAfter(cutoff));
  }

  /// Pulls the server's latest statuses (a question answered on the web
  /// becomes entered) into the local feed.
  Future<void> refreshFromServer(String accessToken) async {
    final recent = await _api.fetchRecent(accessToken: accessToken);
    if (recent == null) return;
    for (final result in recent) {
      await _queue.applyResult(result);
    }
  }

  /// One full pass: drain the native inbox, queue, send, notify, prune.
  /// [accessToken] null means signed out or expired: messages are still
  /// captured and masked, and wait in the queue.
  Future<AutoEntrySyncResult> syncNow({required String? accessToken}) async {
    if (!AutoEntryPlatform.isSupported) return const AutoEntrySyncResult();
    if (_syncing) return const AutoEntrySyncResult();
    _syncing = true;
    try {
      final native = await _platform.state();
      if (!native.available) return const AutoEntrySyncResult();
      final queued = await ingest(await _platform.drainInbox());
      if (accessToken == null) {
        return AutoEntrySyncResult(
          queued: queued,
          pending: await _queue.pendingCount(),
        );
      }
      final result = await flush(
        accessToken: accessToken,
        mobileDataAllowed: native.mobileData,
      );
      final serverPending = result.unauthorized || result.waitingForWifi
          ? false
          : await refreshServerPending(accessToken);
      await notifyQuestions();
      await _queue.prune(DateTime.now());
      return AutoEntrySyncResult(
        queued: queued,
        sent: result.sent,
        pending: result.pending,
        retryLater: result.retryLater || serverPending,
        unauthorized: result.unauthorized,
        waitingForWifi: result.waitingForWifi,
      );
    } finally {
      _syncing = false;
    }
  }

  /// Reads the last 90 days of bank texts once, through the same filters.
  Future<int> importOlderTexts() async {
    final queued = await ingest(await _platform.readOlderTexts(days: 90));
    _log.info(_tag, 'Imported $queued older texts');
    return queued;
  }

  /// The token the background worker can use without the UI: the API key,
  /// or a stored OAuth token that hasn't expired. Refreshing is left to the
  /// app so two isolates never rotate the refresh token at once.
  static Future<String?> storedAccessToken() async {
    final auth = AuthService();
    if (await auth.getStoredAuthMode() == 'api_key') {
      final key = await auth.getStoredApiKey();
      if (key != null) ApiConfig.setApiKeyAuth(key);
      return key;
    }
    final tokens = await auth.getStoredTokens();
    if (tokens == null || tokens.isExpired) return null;
    return tokens.accessToken;
  }

  /// Opens the server's Questions page (`/payment_questions`) in an in-app
  /// browser; the app has no native screen for answering.
  static Future<bool> openQuestions() async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/payment_questions');
    try {
      return await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    } catch (_) {
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  static AppLocalizations _localizations() {
    final locale = PlatformDispatcher.instance.locale;
    final supported = AppLocalizations.supportedLocales
        .any((l) => l.languageCode == locale.languageCode);
    return lookupAppLocalizations(supported ? locale : const Locale('en'));
  }
}

/// Entry point the Android worker starts in a headless engine when a bank
/// text or payment notification arrives while the app isn't open.
Future<void> runAutoEntryInBackground() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  var retry = false;
  try {
    await ApiConfig.initialize();
    final token = await AutoEntryService.storedAccessToken();
    final result = await AutoEntryService.instance.syncNow(accessToken: token);
    retry = result.retryLater;
  } catch (e) {
    LogService.instance.error(
      'AutoEntry',
      'Background run failed with ${e.runtimeType}',
    );
    retry = true;
  }
  await AutoEntryPlatform.instance.backgroundDone(retry: retry);
}
