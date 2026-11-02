import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/payment_message.dart';
import '../services/auto_entry_platform.dart';
import '../services/auto_entry_queue.dart';
import '../services/auto_entry_queue_policy.dart';
import '../services/auto_entry_service.dart';
import '../services/log_service.dart';

/// State of the Auto-entry settings screen.
class AutoEntryProvider with ChangeNotifier {
  AutoEntryProvider({
    required Future<String?> Function() accessToken,
    AutoEntryPlatform? platform,
    AutoEntryService? service,
    AutoEntryQueue? queue,
  })  : _accessToken = accessToken,
        _platform = platform ?? AutoEntryPlatform.instance,
        _service = service ?? AutoEntryService.instance,
        _queue = queue ?? AutoEntryQueue.instance;

  static const String _importedAtKey = 'auto_entry_imported_at';

  final Future<String?> Function() _accessToken;
  final AutoEntryPlatform _platform;
  final AutoEntryService _service;
  final AutoEntryQueue _queue;

  AutoEntryNativeState _native = const AutoEntryNativeState();
  List<PaymentMessage> _latest = const [];
  AutoEntryMonthCounts _month = const AutoEntryMonthCounts();
  int _skippedOtps = 0;
  bool _loading = true;
  bool _syncing = false;
  bool _importing = false;
  DateTime? _importedAt;
  AutoEntrySyncResult? _lastSync;

  AutoEntryNativeState get native => _native;
  List<PaymentMessage> get latest => _latest;
  AutoEntryMonthCounts get month => _month;
  int get skippedOtps => _skippedOtps;
  bool get isLoading => _loading;
  bool get isSyncing => _syncing;
  bool get isImporting => _importing;
  DateTime? get importedAt => _importedAt;
  AutoEntrySyncResult? get lastSync => _lastSync;

  /// Reading means not paused and at least one source can deliver.
  bool get isReading =>
      !_native.paused &&
      ((_native.smsEnabled && _native.smsPermission) ||
          (_native.notificationAccess && _native.enabledPackages.isNotEmpty));

  Future<void> load() async {
    await _reloadNative();
    await _reloadLocal();
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_importedAtKey);
      _importedAt = ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {
      // Only used for the "Last imported" line.
    }
    _loading = false;
    notifyListeners();
    await sync();
  }

  /// Re-reads permissions after the user comes back from system settings.
  Future<void> refreshPermissions() async {
    await _reloadNative();
    notifyListeners();
  }

  Future<void> _reloadNative() async {
    try {
      _native = await _platform.state();
    } catch (e) {
      LogService.instance.warning(
        'AutoEntry',
        'Reading native state failed with ${e.runtimeType}',
      );
    }
  }

  Future<void> _reloadLocal() async {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month);
    _latest = await _queue.latest();
    _month =
        AutoEntryQueuePolicy.monthCounts(await _queue.since(monthStart), now);
    _skippedOtps = await _queue.skippedOtpsSince(monthStart);
  }

  /// Sends what's queued and refreshes statuses from the server.
  Future<void> sync() async {
    if (_syncing) return;
    _syncing = true;
    notifyListeners();
    try {
      final token = await _accessToken();
      _lastSync = await _service.syncNow(accessToken: token);
      if (token != null) await _service.refreshFromServer(token);
      await _reloadLocal();
    } catch (e) {
      LogService.instance.warning(
        'AutoEntry',
        'Sync failed with ${e.runtimeType}',
      );
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  Future<void> setPaused(bool paused) async {
    await _platform.updateSettings(paused: paused);
    await refreshPermissions();
  }

  Future<void> setSmsEnabled(bool enabled) async {
    if (enabled && !_native.smsPermission) {
      await _platform.requestSmsPermission();
    }
    await _platform.updateSettings(smsEnabled: enabled);
    await refreshPermissions();
  }

  Future<void> setAppEnabled(String packageName, bool enabled) async {
    final packages = {..._native.enabledPackages};
    if (enabled) {
      packages.add(packageName);
    } else {
      packages.remove(packageName);
    }
    await _platform.updateSettings(enabledPackages: packages);
    await refreshPermissions();
  }

  Future<void> setMobileData(bool allowed) async {
    await _platform.updateSettings(mobileData: allowed);
    await refreshPermissions();
    await _platform.scheduleFlush();
  }

  Future<void> requestSmsPermission() async {
    await _platform.requestSmsPermission();
    await refreshPermissions();
  }

  Future<void> requestPostNotifications() async {
    await _platform.requestPostNotifications();
    await refreshPermissions();
  }

  Future<void> openNotificationAccess() =>
      _platform.openNotificationAccessSettings();

  /// Reads the last 90 days of texts once. Returns how many were queued, or
  /// null if SMS can't be read.
  Future<int?> importOlderTexts() async {
    if (_importing) return null;
    if (!_native.smsPermission) {
      final granted = await _platform.requestSmsPermission();
      await refreshPermissions();
      if (!granted) return null;
    }
    _importing = true;
    notifyListeners();
    try {
      final queued = await _service.importOlderTexts();
      _importedAt = DateTime.now();
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_importedAtKey, _importedAt!.millisecondsSinceEpoch);
      } catch (_) {
        // Only used for the "Last imported" line.
      }
      await _reloadLocal();
      return queued;
    } finally {
      _importing = false;
      notifyListeners();
      await sync();
    }
  }
}
