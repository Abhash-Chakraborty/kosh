package am.sure.mobile.autoentry

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import am.sure.mobile.MainActivity
import am.sure.mobile.R

/** Local notification for a question from the server. No push service. */
object QuestionNotifier {
    const val EXTRA_ACTION = "kosh_auto_entry_action"
    const val ACTION_QUESTIONS = "questions"
    private const val CHANNEL_ID = "kosh_auto_entry_questions"
    private const val TAG = "kosh_question"

    fun show(context: Context, id: String, title: String, text: String) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    context.getString(R.string.auto_entry_questions_channel),
                    NotificationManager.IMPORTANCE_DEFAULT,
                )
            )
        }

        val open = Intent(context, MainActivity::class.java).apply {
            putExtra(EXTRA_ACTION, ACTION_QUESTIONS)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pending = PendingIntent.getActivity(
            context,
            id.hashCode(),
            open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            Notification.Builder(context)
        }
        val notification = builder
            .setSmallIcon(R.drawable.ic_stat_auto_entry)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setAutoCancel(true)
            .setContentIntent(pending)
            .build()
        manager.notify(TAG, id.hashCode(), notification)
    }
}
