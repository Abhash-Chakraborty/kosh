package am.sure.mobile.autoentry

import android.Manifest
import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.provider.Telephony
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * The `sure/auto_entry` channel. Attached to the UI engine by MainActivity
 * (with a [Host] for permission prompts) and to the headless engine by
 * [AutoEntryWorker] (no host; reports the end of a run via [onBackgroundDone]).
 */
class AutoEntryChannel(
    private val context: Context,
    private val host: Host?,
    private val onBackgroundDone: ((Boolean) -> Unit)? = null,
) : MethodChannel.MethodCallHandler {

    interface Host {
        fun askPermissions(permissions: Array<String>, callback: (Boolean) -> Unit)
        fun openSystemScreen(intent: Intent)
        fun takeLaunchAction(): String?
    }

    private var channel: MethodChannel? = null
    private val main = Handler(Looper.getMainLooper())

    fun attach(messenger: BinaryMessenger): AutoEntryChannel {
        channel = MethodChannel(messenger, NAME).also { it.setMethodCallHandler(this) }
        return this
    }

    /** Tells Dart a question notification was tapped while the app was open. */
    fun sendLaunchAction(action: String) {
        channel?.invokeMethod("launchAction", action)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "getState" -> {
                    if (isAvailable()) AutoEntryWorker.schedulePeriodic(context)
                    result.success(state())
                }
                "setSettings" -> {
                    @Suppress("UNCHECKED_CAST")
                    val packages = (call.argument<List<String>>("enabledPackages"))?.toSet()
                    val mobileData = call.argument<Boolean>("mobileData")
                    AutoEntrySettings.update(
                        context,
                        paused = call.argument<Boolean>("paused"),
                        smsEnabled = call.argument<Boolean>("smsEnabled"),
                        packages = packages,
                        mobileData = mobileData,
                    )
                    if (mobileData != null && isAvailable()) AutoEntryWorker.schedulePeriodic(context)
                    result.success(null)
                }
                "requestSmsPermission" -> ask(
                    arrayOf(Manifest.permission.RECEIVE_SMS, Manifest.permission.READ_SMS),
                    result,
                )
                "requestPostNotifications" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        ask(arrayOf(Manifest.permission.POST_NOTIFICATIONS), result)
                    } else {
                        result.success(notificationsEnabled())
                    }
                }
                "openNotificationAccess" -> {
                    openNotificationAccess()
                    result.success(null)
                }
                "drainInbox" -> runInBackground(result) { AutoEntryInbox.get(context).drain() }
                "readOlderSms" -> {
                    val days = call.argument<Int>("days") ?: 90
                    runInBackground(result) { readOlderSms(days) }
                }
                "scheduleFlush" -> {
                    AutoEntryWorker.enqueue(context)
                    result.success(null)
                }
                "showQuestion" -> {
                    QuestionNotifier.show(
                        context,
                        call.argument<String>("id") ?: "question",
                        call.argument<String>("title") ?: "",
                        call.argument<String>("text") ?: "",
                    )
                    result.success(null)
                }
                "takeLaunchAction" -> result.success(host?.takeLaunchAction())
                "backgroundDone" -> {
                    result.success(null)
                    onBackgroundDone?.invoke(call.argument<Boolean>("retry") ?: false)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            Log.w(TAG, "${call.method} failed: ${e.javaClass.simpleName}")
            result.error("auto_entry", e.javaClass.simpleName, null)
        }
    }

    private fun ask(permissions: Array<String>, result: MethodChannel.Result) {
        if (permissions.all { granted(it) }) {
            result.success(true)
            return
        }
        val askHost = host
        if (askHost == null) {
            result.success(false)
            return
        }
        askHost.askPermissions(permissions) { allGranted -> result.success(allGranted) }
    }

    private fun runInBackground(result: MethodChannel.Result, work: () -> Any?) {
        IO.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: Exception) {
                Log.w(TAG, "Background call failed: ${e.javaClass.simpleName}")
                main.post { result.error("auto_entry", e.javaClass.simpleName, null) }
            }
        }
    }

    private fun granted(permission: String) =
        context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    @Suppress("DEPRECATION")
    private fun smsDeclared(): Boolean = try {
        val info = context.packageManager.getPackageInfo(
            context.packageName,
            PackageManager.GET_PERMISSIONS,
        )
        info.requestedPermissions?.contains(Manifest.permission.READ_SMS) == true
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }

    private fun listenerDeclared(): Boolean = try {
        context.packageManager.getServiceInfo(listenerComponent(), 0)
        true
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }

    private fun isAvailable() = smsDeclared() || listenerDeclared()

    private fun listenerComponent() = ComponentName(context, PaymentNotificationListener::class.java)

    private fun notificationAccess(): Boolean {
        val enabled = Settings.Secure.getString(
            context.contentResolver,
            "enabled_notification_listeners",
        ) ?: return false
        return enabled.split(':').any {
            ComponentName.unflattenFromString(it)?.packageName == context.packageName
        }
    }

    private fun notificationsEnabled(): Boolean {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (!manager.areNotificationsEnabled()) return false
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            granted(Manifest.permission.POST_NOTIFICATIONS)
    }

    private fun state(): Map<String, Any> {
        val smsSupported = smsDeclared()
        return mapOf(
            "available" to (smsSupported || listenerDeclared()),
            "smsSupported" to smsSupported,
            "smsPermission" to (smsSupported &&
                granted(Manifest.permission.READ_SMS) &&
                granted(Manifest.permission.RECEIVE_SMS)),
            "notificationAccess" to notificationAccess(),
            "canPostNotifications" to notificationsEnabled(),
            "paused" to AutoEntrySettings.isPaused(context),
            "smsEnabled" to AutoEntrySettings.isSmsEnabled(context),
            "enabledPackages" to AutoEntrySettings.enabledPackages(context).toList(),
            "mobileData" to AutoEntrySettings.mobileDataAllowed(context),
        )
    }

    private fun openNotificationAccess() {
        val askHost = host ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val detail = Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS).putExtra(
                Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME,
                listenerComponent().flattenToString(),
            )
            try {
                askHost.openSystemScreen(detail)
                return
            } catch (e: ActivityNotFoundException) {
                // Some vendors drop the detail page; fall back to the list.
            }
        }
        askHost.openSystemScreen(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
    }

    /**
     * Texts from the last [days] days from transactional bank senders. OTPs
     * are counted as skipped and their text is not returned.
     */
    private fun readOlderSms(days: Int): Map<String, Any> {
        val messages = ArrayList<Map<String, Any>>()
        val skipped = ArrayList<Map<String, Any>>()
        if (!granted(Manifest.permission.READ_SMS)) {
            return mapOf("messages" to messages, "skipped" to skipped)
        }
        val since = System.currentTimeMillis() - days * 24L * 60 * 60 * 1000
        context.contentResolver.query(
            Telephony.Sms.Inbox.CONTENT_URI,
            arrayOf(Telephony.Sms.ADDRESS, Telephony.Sms.BODY, Telephony.Sms.DATE),
            "${Telephony.Sms.DATE} >= ?",
            arrayOf(since.toString()),
            "${Telephony.Sms.DATE} ASC",
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val sender = cursor.getString(0) ?: continue
                val body = cursor.getString(1) ?: continue
                val date = cursor.getLong(2)
                if (!AutoEntryRules.isTransactionalSender(sender)) continue
                if (AutoEntryRules.isOtp(body)) {
                    skipped.add(mapOf("sender" to sender, "at" to date))
                    continue
                }
                messages.add(
                    mapOf(
                        "source" to AutoEntryInbox.SOURCE_SMS,
                        "sender" to sender,
                        "body" to body,
                        "receivedAt" to date,
                    )
                )
            }
        }
        return mapOf("messages" to messages, "skipped" to skipped)
    }

    companion object {
        const val NAME = "sure/auto_entry"
        private const val TAG = "SureAutoEntry"
        private val IO = Executors.newSingleThreadExecutor()
    }
}
