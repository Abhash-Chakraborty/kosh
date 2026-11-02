package am.sure.mobile.autoentry

/**
 * The first, cheap filter applied where messages arrive. The full rules
 * (money and action words, masking) run in Dart; these two checks only keep
 * personal texts and one-time passwords from ever being written to disk.
 */
object AutoEntryRules {
    private val DLT_SENDER = Regex("^[A-Z]{2}-[A-Z0-9]{6}(-[STGP])?$")
    private val OTP = Regex(
        "\\b(otp|one[\\s-]?time[\\s-]?password|verification[\\s-]?code|passcode)\\b",
        RegexOption.IGNORE_CASE,
    )

    fun isTransactionalSender(sender: String): Boolean {
        val normalized = sender.trim().uppercase()
        return DLT_SENDER.matches(normalized) && !normalized.endsWith("-P")
    }

    fun isOtp(text: String): Boolean = OTP.containsMatchIn(text)
}
