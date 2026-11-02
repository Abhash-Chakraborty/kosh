import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/payment_message.dart';
import '../providers/auth_provider.dart';
import '../providers/auto_entry_provider.dart';
import '../services/auto_entry_platform.dart';
import '../services/auto_entry_service.dart';

/// Settings → Auto-entry (Android only): reads bank texts and payment-app
/// notifications, masks them and sends them to the server.
class AutoEntryScreen extends StatelessWidget {
  const AutoEntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    return ChangeNotifierProvider(
      create: (_) =>
          AutoEntryProvider(accessToken: auth.getValidAccessToken)..load(),
      child: const _AutoEntryView(),
    );
  }
}

class _AutoEntryView extends StatefulWidget {
  const _AutoEntryView();

  @override
  State<_AutoEntryView> createState() => _AutoEntryViewState();
}

class _AutoEntryViewState extends State<_AutoEntryView>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from the system's notification-access or permission page.
    if (state == AppLifecycleState.resumed) {
      context.read<AutoEntryProvider>().refreshPermissions();
    }
  }

  Future<void> _importOlderTexts() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final queued = await context.read<AutoEntryProvider>().importOlderTexts();
    messenger.showSnackBar(SnackBar(
      content: Text(
        queued == null
            ? l.autoEntryImportNoPermission
            : l.autoEntryImportDone(queued),
      ),
    ));
  }

  Future<void> _openQuestions() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final opened = await AutoEntryService.openQuestions();
    if (!opened) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.autoEntryOpenQuestionsFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final provider = context.watch<AutoEntryProvider>();
    final native = provider.native;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.autoEntryTitle),
        actions: [
          IconButton(
            tooltip: l.commonRefresh,
            onPressed: provider.isSyncing ? null : provider.sync,
            icon: provider.isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: provider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: provider.sync,
              child: ListView(
                children: [
                  _StatusCard(provider: provider),
                  ..._permissionTiles(context, provider),
                  _MonthCounts(provider: provider),
                  const Divider(),
                  _SectionHeader(l.autoEntrySectionSources),
                  SwitchListTile(
                    secondary: const Icon(Icons.sms_outlined),
                    title: Text(l.autoEntrySourceSms),
                    subtitle: Text(native.smsSupported
                        ? l.autoEntrySourceSmsSubtitle
                        : l.autoEntrySourceSmsUnavailable),
                    value: native.smsSupported && native.smsEnabled,
                    onChanged: native.smsSupported
                        ? (value) => provider.setSmsEnabled(value)
                        : null,
                  ),
                  for (final app in PaymentApp.all)
                    SwitchListTile(
                      secondary: const Icon(Icons.notifications_outlined),
                      title: Text(app.label),
                      subtitle: Text(app.packageName),
                      value: native.enabledPackages.contains(app.packageName),
                      onChanged: (value) =>
                          provider.setAppEnabled(app.packageName, value),
                    ),
                  const Divider(),
                  _SectionHeader(l.autoEntrySectionSending),
                  ListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: Text(l.autoEntryMaskTitle),
                    subtitle: Text(l.autoEntryMaskSubtitle),
                    trailing: const Icon(Icons.check),
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.signal_cellular_alt),
                    title: Text(l.autoEntryMobileData),
                    subtitle: Text(l.autoEntryMobileDataSubtitle),
                    value: native.mobileData,
                    onChanged: (value) => provider.setMobileData(value),
                  ),
                  if (native.smsSupported)
                    ListTile(
                      leading: const Icon(Icons.history),
                      title: Text(l.autoEntryImport),
                      subtitle: Text(
                        provider.importedAt == null
                            ? l.autoEntryImportSubtitle
                            : l.autoEntryImportedOn(
                                DateFormat.yMMMd(l.localeName)
                                    .format(provider.importedAt!),
                              ),
                      ),
                      trailing: provider.isImporting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.chevron_right),
                      onTap: provider.isImporting ? null : _importOlderTexts,
                    ),
                  const Divider(),
                  _SectionHeader(l.autoEntrySectionLatest),
                  if (provider.month.questions > 0)
                    ListTile(
                      leading: const Icon(Icons.help_outline),
                      title: Text(l.autoEntryOpenQuestions),
                      trailing: const Icon(Icons.open_in_new),
                      onTap: _openQuestions,
                    ),
                  if (provider.latest.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      child: Text(
                        l.autoEntryLatestEmpty,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  for (final message in provider.latest)
                    _LatestTile(
                      message: message,
                      onOpenQuestion: _openQuestions,
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  List<Widget> _permissionTiles(
    BuildContext context,
    AutoEntryProvider provider,
  ) {
    final l = AppLocalizations.of(context);
    final native = provider.native;
    final error = Theme.of(context).colorScheme.error;
    return [
      if (native.smsSupported && native.smsEnabled && !native.smsPermission)
        ListTile(
          leading: Icon(Icons.warning_amber_rounded, color: error),
          title: Text(l.autoEntryAllowSms),
          subtitle: Text(l.autoEntryAllowSmsSubtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: provider.requestSmsPermission,
        ),
      if (native.enabledPackages.isNotEmpty && !native.notificationAccess)
        ListTile(
          leading: Icon(Icons.warning_amber_rounded, color: error),
          title: Text(l.autoEntryNotificationAccess),
          subtitle: Text(l.autoEntryNotificationAccessSubtitle),
          trailing: const Icon(Icons.open_in_new),
          onTap: provider.openNotificationAccess,
        ),
      if (!native.canPostNotifications)
        ListTile(
          leading: const Icon(Icons.notifications_off_outlined),
          title: Text(l.autoEntryAllowNotifications),
          subtitle: Text(l.autoEntryAllowNotificationsSubtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: provider.requestPostNotifications,
        ),
      if (provider.lastSync?.unauthorized == true)
        ListTile(
          leading: Icon(Icons.error_outline, color: error),
          title: Text(l.autoEntryUnauthorized),
        ),
      if (provider.lastSync?.waitingForWifi == true)
        ListTile(
          leading: const Icon(Icons.wifi_off),
          title: Text(l.autoEntryWaitingForWifi),
        ),
    ];
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.provider});

  final AutoEntryProvider provider;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final paused = provider.native.paused;
    final reading = provider.isReading;

    final String title;
    final String detail;
    final IconData icon;
    final Color color;
    if (paused) {
      title = l.autoEntryStatusPaused;
      detail = l.autoEntryStatusPausedDetail;
      icon = Icons.pause_circle_outline;
      color = colorScheme.onSurfaceVariant;
    } else if (reading) {
      title = l.autoEntryStatusReading;
      detail = l.autoEntryStatusReadingDetail;
      icon = Icons.play_circle_outline;
      color = colorScheme.primary;
    } else {
      title = l.autoEntryStatusIdle;
      detail = l.autoEntryStatusIdleDetail;
      icon = Icons.radio_button_unchecked;
      color = colorScheme.onSurfaceVariant;
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: color, size: 32),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      detail,
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.tonal(
                onPressed: () => provider.setPaused(!paused),
                child: Text(paused ? l.autoEntryResume : l.autoEntryPause),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthCounts extends StatelessWidget {
  const _MonthCounts({required this.provider});

  final AutoEntryProvider provider;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final month = provider.month;
    final colorScheme = Theme.of(context).colorScheme;

    Widget count(String label, int value) {
      return Expanded(
        child: Column(
          children: [
            Text(
              '$value',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(l.autoEntrySectionThisMonth),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              count(l.autoEntryCountSent, month.sent),
              count(l.autoEntryCountEntered, month.entered),
              count(l.autoEntryCountQuestions, month.questions),
              count(l.autoEntryCountWaiting, month.waiting),
            ],
          ),
        ),
        if (provider.skippedOtps > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              l.autoEntryOtpsSkipped(provider.skippedOtps),
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _LatestTile extends StatelessWidget {
  const _LatestTile({required this.message, required this.onOpenQuestion});

  final PaymentMessage message;
  final VoidCallback onOpenQuestion;

  String _statusLabel(AppLocalizations l) {
    switch (message.state) {
      case PaymentMessageState.pending:
        return l.autoEntryStatusWaiting;
      case PaymentMessageState.rejected:
        return l.autoEntryStatusRejected;
      case PaymentMessageState.sent:
        break;
    }
    switch (message.status) {
      case PaymentMessageStatus.entered:
        return l.autoEntryStatusEntered;
      case PaymentMessageStatus.merged:
        return l.autoEntryStatusMerged;
      case PaymentMessageStatus.question:
        return l.autoEntryStatusQuestion;
      case PaymentMessageStatus.ignored:
        return l.autoEntryStatusIgnored;
      case PaymentMessageStatus.pending:
        return l.autoEntryStatusReadingOnServer;
      default:
        return l.autoEntryStatusFailed;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final from = message.app ?? message.sender;
    final when = DateFormat.MMMd(l.localeName)
        .add_jm()
        .format(message.receivedAt);
    final title = message.question ??
        message.summary ??
        message.body.split('\n').first;

    return ListTile(
      leading: Icon(
        message.source == PaymentMessageSource.sms
            ? Icons.sms_outlined
            : Icons.notifications_outlined,
      ),
      title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text('$from · $when'),
      trailing: Text(
        _statusLabel(l),
        style: TextStyle(
          color: message.isQuestion
              ? colorScheme.primary
              : colorScheme.onSurfaceVariant,
          fontWeight: message.isQuestion ? FontWeight.w600 : null,
        ),
      ),
      onTap: message.isQuestion ? onOpenQuestion : null,
    );
  }
}
