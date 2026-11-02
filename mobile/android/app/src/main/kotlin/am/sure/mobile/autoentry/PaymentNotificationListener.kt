package am.sure.mobile.autoentry

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log

/**
 * Reads notifications from the payment apps the user turned on. The user
 * grants "Notification access" once in system settings.
 */
class PaymentNotificationListener : NotificationListenerService() {
    private val recent = LinkedHashMap<String, Long>()

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        val context = applicationContext
        try {
            if (AutoEntrySettings.isPaused(context)) return
            val pkg = sbn.packageName ?: return
            if (pkg !in AutoEntrySettings.enabledPackages(context)) return

            val notification = sbn.notification ?: return
            if (sbn.isOngoing || (notification.flags and Notification.FLAG_ONGOING_EVENT) != 0) return
            if ((notification.flags and Notification.FLAG_GROUP_SUMMARY) != 0) return
            val extras = notification.extras ?: return
            if (extras.getInt(Notification.EXTRA_PROGRESS_MAX, 0) > 0 ||
                extras.getBoolean(Notification.EXTRA_PROGRESS_INDETERMINATE, false)
            ) return

            val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()
            val text = (extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
                ?: extras.getCharSequence(Notification.EXTRA_TEXT))?.toString()
            val body = listOfNotNull(title, text)
                .map { it.trim() }
                .filter { it.isNotEmpty() }
                .joinToString("\n")
            if (body.isEmpty()) return

            val now = System.currentTimeMillis()
            if (isDuplicate("$pkg\n$body", now)) return

            val inbox = AutoEntryInbox.get(context)
            if (AutoEntryRules.isOtp(body)) {
                inbox.addSkippedOtp(pkg, now)
                Log.i(TAG, "Skipped OTP from $pkg")
            } else {
                val postedAt = if (sbn.postTime > 0) sbn.postTime else now
                inbox.add(AutoEntryInbox.SOURCE_NOTIFICATION, pkg, body, postedAt)
            }
            AutoEntryWorker.enqueue(context)
        } catch (e: Exception) {
            Log.w(TAG, "Reading a notification failed: ${e.javaClass.simpleName}")
        }
    }

    /** Same package and text within 60 seconds counts once. */
    private fun isDuplicate(key: String, now: Long): Boolean = synchronized(recent) {
        val iterator = recent.entries.iterator()
        while (iterator.hasNext()) {
            if (now - iterator.next().value > DUPLICATE_WINDOW_MS) iterator.remove()
        }
        val seen = recent[key]
        recent[key] = now
        seen != null
    }

    companion object {
        private const val TAG = "KoshAutoEntry"
        private const val DUPLICATE_WINDOW_MS = 60_000L
    }
}
