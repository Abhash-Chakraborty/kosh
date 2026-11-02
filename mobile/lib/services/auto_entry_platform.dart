import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A payment-app package the notification listener can read.
class PaymentApp {
  const PaymentApp(this.packageName, this.label);

  final String packageName;
  final String label;

  /// Package ids checked against their Google Play listings (Nov 2026).
  static const List<PaymentApp> all = [
    PaymentApp('com.google.android.apps.nbu.paisa.user', 'Google Pay'),
    PaymentApp('indwin.c3.shareapp', 'slice'),
    PaymentApp('com.nextbillion.groww', 'Groww'),
    PaymentApp('com.phonepe.app', 'PhonePe'),
    PaymentApp('net.one97.paytm', 'Paytm'),
    PaymentApp('com.dreamplug.androidapp', 'CRED'),
    PaymentApp('in.amazon.mShop.android.shopping', 'Amazon'),
  ];

  static String? labelFor(String packageName) {
    for (final app in all) {
      if (app.packageName == packageName) return app.label;
    }
    return null;
  }
}

/// A message captured natively (SMS receiver, notification listener or the
/// older-texts import) before the Dart filters and masking run.
class CapturedMessage {
  const CapturedMessage({
    required this.source,
    required this.sender,
    required this.body,
    required this.receivedAt,
  });

  /// `sms` or `notification`.
  final String source;
  final String sender;
  final String body;
  final DateTime receivedAt;

  static CapturedMessage? fromMap(Map<Object?, Object?> map) {
    final source = map['source'];
    final sender = map['sender'];
    final body = map['body'];
    final receivedMs = map['receivedAt'];
    if (source is! String || sender is! String || body is! String) return null;
    return CapturedMessage(
      source: source,
      sender: sender,
      body: body,
      receivedAt: DateTime.fromMillisecondsSinceEpoch(
        receivedMs is int ? receivedMs : DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}

class SkippedOtp {
  const SkippedOtp(this.sender, this.at);

  final String sender;
  final DateTime at;
}

class InboxDrain {
  const InboxDrain(this.messages, this.skippedOtps);

  final List<CapturedMessage> messages;
  final List<SkippedOtp> skippedOtps;
}

/// Native side of auto-entry: permissions, settings the receivers read, and
/// the inbox they write to.
class AutoEntryNativeState {
  const AutoEntryNativeState({
    this.available = false,
    this.smsSupported = false,
    this.smsPermission = false,
    this.notificationAccess = false,
    this.canPostNotifications = false,
    this.paused = false,
    this.smsEnabled = true,
    this.enabledPackages = const {},
    this.mobileData = true,
  });

  /// Whether this build declares the receivers (the sideload APK does).
  final bool available;

  /// Whether READ_SMS is declared, so SMS can be read at all.
  final bool smsSupported;
  final bool smsPermission;
  final bool notificationAccess;
  final bool canPostNotifications;
  final bool paused;
  final bool smsEnabled;
  final Set<String> enabledPackages;
  final bool mobileData;

  factory AutoEntryNativeState.fromMap(Map<Object?, Object?> map) {
    bool flag(String key, bool fallback) {
      final value = map[key];
      return value is bool ? value : fallback;
    }

    final packages = map['enabledPackages'];
    return AutoEntryNativeState(
      available: flag('available', false),
      smsSupported: flag('smsSupported', false),
      smsPermission: flag('smsPermission', false),
      notificationAccess: flag('notificationAccess', false),
      canPostNotifications: flag('canPostNotifications', false),
      paused: flag('paused', false),
      smsEnabled: flag('smsEnabled', true),
      enabledPackages: packages is List
          ? packages.whereType<String>().toSet()
          : const <String>{},
      mobileData: flag('mobileData', true),
    );
  }
}

class AutoEntryPlatform {
  AutoEntryPlatform._();

  static final AutoEntryPlatform instance = AutoEntryPlatform._();

  static const MethodChannel _channel = MethodChannel('sure/auto_entry');

  /// Auto-entry exists only on Android; every call is a no-op elsewhere.
  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  void Function(String action)? _onLaunchAction;

  /// Listens for taps on a question notification while the app is running.
  void setLaunchActionHandler(void Function(String action) handler) {
    _onLaunchAction = handler;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'launchAction' && call.arguments is String) {
        _onLaunchAction?.call(call.arguments as String);
      }
      return null;
    });
  }

  Future<AutoEntryNativeState> state() async {
    if (!isSupported) return const AutoEntryNativeState();
    try {
      final map = await _channel.invokeMapMethod<Object?, Object?>('getState');
      return map == null
          ? const AutoEntryNativeState()
          : AutoEntryNativeState.fromMap(map);
    } on MissingPluginException {
      return const AutoEntryNativeState();
    }
  }

  Future<void> updateSettings({
    bool? paused,
    bool? smsEnabled,
    Set<String>? enabledPackages,
    bool? mobileData,
  }) async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('setSettings', {
      if (paused != null) 'paused': paused,
      if (smsEnabled != null) 'smsEnabled': smsEnabled,
      if (enabledPackages != null) 'enabledPackages': enabledPackages.toList(),
      if (mobileData != null) 'mobileData': mobileData,
    });
  }

  Future<bool> requestSmsPermission() => _askBool('requestSmsPermission');

  Future<bool> requestPostNotifications() =>
      _askBool('requestPostNotifications');

  Future<void> openNotificationAccessSettings() async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('openNotificationAccess');
  }

  /// Takes everything the receivers stored since the last drain. The native
  /// inbox is emptied in the same step.
  Future<InboxDrain> drainInbox() async {
    if (!isSupported) return const InboxDrain([], []);
    final map =
        await _channel.invokeMapMethod<Object?, Object?>('drainInbox') ?? {};
    return InboxDrain(
      _messagesFrom(map['messages']),
      _skipsFrom(map['skipped']),
    );
  }

  /// Bank texts from the last [days] days whose sender looks transactional.
  Future<InboxDrain> readOlderTexts({int days = 90}) async {
    if (!isSupported) return const InboxDrain([], []);
    final map = await _channel.invokeMapMethod<Object?, Object?>(
          'readOlderSms',
          {'days': days},
        ) ??
        {};
    return InboxDrain(
      _messagesFrom(map['messages']),
      _skipsFrom(map['skipped']),
    );
  }

  /// Asks WorkManager to deliver the queue (now if the network allows).
  Future<void> scheduleFlush() async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('scheduleFlush');
  }

  Future<void> showQuestion({
    required String id,
    required String title,
    required String text,
  }) async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('showQuestion', {
      'id': id,
      'title': title,
      'text': text,
    });
  }

  /// The action of the notification that opened the app, if any (once).
  Future<String?> takeLaunchAction() async {
    if (!isSupported) return null;
    try {
      return await _channel.invokeMethod<String>('takeLaunchAction');
    } on MissingPluginException {
      return null;
    }
  }

  /// Tells the background worker this run is over.
  Future<void> backgroundDone({required bool retry}) async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('backgroundDone', {'retry': retry});
  }

  Future<bool> _askBool(String method) async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>(method) ?? false;
  }

  List<CapturedMessage> _messagesFrom(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map<Object?, Object?>>()
        .map(CapturedMessage.fromMap)
        .whereType<CapturedMessage>()
        .toList();
  }

  List<SkippedOtp> _skipsFrom(Object? raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map<Object?, Object?>>().map((map) {
      final at = map['at'];
      return SkippedOtp(
        map['sender'] as String? ?? '?',
        DateTime.fromMillisecondsSinceEpoch(
          at is int ? at : DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }).toList();
  }
}
