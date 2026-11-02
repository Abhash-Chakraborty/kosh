package am.sure.mobile.autoentry

import android.content.Context
import android.content.SharedPreferences

/** Settings the receivers read even when the Flutter UI isn't running. */
object AutoEntrySettings {
    private const val PREFS = "kosh_auto_entry"
    private const val KEY_PAUSED = "paused"
    private const val KEY_SMS = "sms_enabled"
    private const val KEY_PACKAGES = "enabled_packages"
    private const val KEY_MOBILE_DATA = "mobile_data"

    /** Google Pay, slice and Groww are on until the user turns them off. */
    val DEFAULT_PACKAGES = setOf(
        "com.google.android.apps.nbu.paisa.user",
        "indwin.c3.shareapp",
        "com.nextbillion.groww",
    )

    private fun prefs(context: Context): SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun isPaused(context: Context) = prefs(context).getBoolean(KEY_PAUSED, false)

    fun isSmsEnabled(context: Context) = prefs(context).getBoolean(KEY_SMS, true)

    fun mobileDataAllowed(context: Context) = prefs(context).getBoolean(KEY_MOBILE_DATA, true)

    fun enabledPackages(context: Context): Set<String> =
        prefs(context).getStringSet(KEY_PACKAGES, null)?.toSet() ?: DEFAULT_PACKAGES

    fun update(
        context: Context,
        paused: Boolean? = null,
        smsEnabled: Boolean? = null,
        packages: Set<String>? = null,
        mobileData: Boolean? = null,
    ) {
        val editor = prefs(context).edit()
        paused?.let { editor.putBoolean(KEY_PAUSED, it) }
        smsEnabled?.let { editor.putBoolean(KEY_SMS, it) }
        packages?.let { editor.putStringSet(KEY_PACKAGES, HashSet(it)) }
        mobileData?.let { editor.putBoolean(KEY_MOBILE_DATA, it) }
        editor.apply()
    }
}
