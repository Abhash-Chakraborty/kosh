package am.sure.mobile

import android.content.Intent
import android.os.Bundle
import androidx.activity.result.contract.ActivityResultContracts
import am.sure.mobile.autoentry.AutoEntryChannel
import am.sure.mobile.autoentry.QuestionNotifier
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity(), AutoEntryChannel.Host {
    private var permissionCallback: ((Boolean) -> Unit)? = null
    private val permissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { grants ->
            val callback = permissionCallback
            permissionCallback = null
            callback?.invoke(grants.isNotEmpty() && grants.values.all { it })
        }

    private var launchAction: String? = null
    private var autoEntry: AutoEntryChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        launchAction = autoEntryAction(intent)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        autoEntry = AutoEntryChannel(applicationContext, this)
            .attach(flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val action = autoEntryAction(intent) ?: return
        val channel = autoEntry
        if (channel != null) channel.sendLaunchAction(action) else launchAction = action
    }

    override fun askPermissions(permissions: Array<String>, callback: (Boolean) -> Unit) {
        if (permissionCallback != null) {
            callback(false)
            return
        }
        permissionCallback = callback
        permissionLauncher.launch(permissions)
    }

    override fun openSystemScreen(intent: Intent) {
        startActivity(intent)
    }

    override fun takeLaunchAction(): String? {
        val action = launchAction
        launchAction = null
        return action
    }

    private fun autoEntryAction(intent: Intent?): String? =
        intent?.getStringExtra(QuestionNotifier.EXTRA_ACTION)
}
