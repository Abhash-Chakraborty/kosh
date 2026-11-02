package am.sure.mobile.autoentry

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.util.Log

/**
 * Receives incoming texts (SMS_RECEIVED, declared in the sideload manifest).
 * Keeps transactional bank senders only, drops OTPs on the spot, stores the
 * rest in [AutoEntryInbox] and asks WorkManager to deliver them.
 */
class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        if (AutoEntrySettings.isPaused(context) || !AutoEntrySettings.isSmsEnabled(context)) return

        val parts = try {
            Telephony.Sms.Intents.getMessagesFromIntent(intent)?.filterNotNull().orEmpty()
        } catch (e: Exception) {
            Log.w(TAG, "Could not read the incoming text: ${e.javaClass.simpleName}")
            return
        }
        if (parts.isEmpty()) return

        // A long text arrives in several parts from the same sender.
        val bodies = LinkedHashMap<String, StringBuilder>()
        val times = HashMap<String, Long>()
        for (part in parts) {
            val sender = part.displayOriginatingAddress ?: part.originatingAddress ?: continue
            bodies.getOrPut(sender) { StringBuilder() }.append(part.displayMessageBody ?: "")
            if (!times.containsKey(sender)) {
                times[sender] = if (part.timestampMillis > 0) part.timestampMillis else System.currentTimeMillis()
            }
        }

        val pending = goAsync()
        val appContext = context.applicationContext
        Thread {
            try {
                val inbox = AutoEntryInbox.get(appContext)
                var stored = false
                for ((sender, builder) in bodies) {
                    if (!AutoEntryRules.isTransactionalSender(sender)) continue
                    val body = builder.toString()
                    val at = times[sender] ?: System.currentTimeMillis()
                    if (AutoEntryRules.isOtp(body)) {
                        inbox.addSkippedOtp(sender, at)
                        Log.i(TAG, "Skipped OTP from $sender")
                        stored = true
                        continue
                    }
                    inbox.add(AutoEntryInbox.SOURCE_SMS, sender, body, at)
                    stored = true
                }
                if (stored) AutoEntryWorker.enqueue(appContext)
            } catch (e: Exception) {
                Log.w(TAG, "Storing a text failed: ${e.javaClass.simpleName}")
            } finally {
                pending.finish()
            }
        }.start()
    }

    companion object {
        private const val TAG = "KoshAutoEntry"
    }
}
