package am.sure.mobile.autoentry

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequest
import androidx.work.PeriodicWorkRequest
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/**
 * Delivers the auto-entry queue when the app isn't open. It starts a headless
 * Flutter engine running `autoEntryBackgroundMain` (lib/main.dart), which
 * drains [AutoEntryInbox], masks and queues the messages, sends them with the
 * app's stored credentials and reports back through `backgroundDone`.
 *
 * WorkManager is used because it survives process death and reboots, runs
 * under Doze with deferral, and waits for the right network on its own
 * (any network, or unmetered only when mobile data is off).
 */
class AutoEntryWorker(context: Context, params: WorkerParameters) : Worker(context, params) {

    override fun doWork(): Result {
        if (runAttemptCount > MAX_ATTEMPTS) return Result.success()

        val done = CountDownLatch(1)
        val retry = AtomicBoolean(false)
        val engineRef = AtomicReference<FlutterEngine?>(null)
        val main = Handler(Looper.getMainLooper())

        main.post {
            try {
                val loader = FlutterInjector.instance().flutterLoader()
                loader.startInitialization(applicationContext)
                loader.ensureInitializationComplete(applicationContext, null)
                val engine = FlutterEngine(applicationContext)
                engineRef.set(engine)
                AutoEntryChannel(applicationContext, null) { shouldRetry ->
                    retry.set(shouldRetry)
                    done.countDown()
                }.attach(engine.dartExecutor.binaryMessenger)
                engine.dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint(loader.findAppBundlePath(), ENTRYPOINT)
                )
            } catch (e: Throwable) {
                Log.w(TAG, "Could not start the background engine: ${e.javaClass.simpleName}")
                retry.set(true)
                done.countDown()
            }
        }

        val finished = done.await(TIMEOUT_MINUTES, TimeUnit.MINUTES)
        main.post { engineRef.getAndSet(null)?.destroy() }

        return if (!finished || retry.get()) Result.retry() else Result.success()
    }

    companion object {
        private const val TAG = "KoshAutoEntry"
        private const val ENTRYPOINT = "autoEntryBackgroundMain"
        private const val UNIQUE_FLUSH = "kosh_auto_entry_flush"
        private const val UNIQUE_PERIODIC = "kosh_auto_entry_periodic"
        private const val TIMEOUT_MINUTES = 4L
        private const val MAX_ATTEMPTS = 25

        private fun constraints(context: Context): Constraints {
            val network = if (AutoEntrySettings.mobileDataAllowed(context)) {
                NetworkType.CONNECTED
            } else {
                NetworkType.UNMETERED
            }
            return Constraints.Builder().setRequiredNetworkType(network).build()
        }

        /** Deliver soon: called whenever a text or notification is stored. */
        fun enqueue(context: Context) {
            val request = OneTimeWorkRequest.Builder(AutoEntryWorker::class.java)
                .setConstraints(constraints(context))
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
                .build()
            WorkManager.getInstance(context.applicationContext)
                .enqueueUniqueWork(UNIQUE_FLUSH, ExistingWorkPolicy.APPEND_OR_REPLACE, request)
        }

        /** Safety net that retries whatever is left every few hours. */
        fun schedulePeriodic(context: Context) {
            val request = PeriodicWorkRequest.Builder(
                AutoEntryWorker::class.java,
                4,
                TimeUnit.HOURS,
            )
                .setConstraints(constraints(context))
                .build()
            WorkManager.getInstance(context.applicationContext).enqueueUniquePeriodicWork(
                UNIQUE_PERIODIC,
                ExistingPeriodicWorkPolicy.UPDATE,
                request,
            )
        }
    }
}
