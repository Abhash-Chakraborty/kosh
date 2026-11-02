package am.sure.mobile.autoentry

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

/**
 * Where the SMS receiver and the notification listener put messages until
 * Dart takes them (masks them and moves them to the sqflite outbox). Lives in
 * the app's private storage and is emptied on every drain.
 */
class AutoEntryInbox private constructor(context: Context) :
    SQLiteOpenHelper(context.applicationContext, "auto_entry_inbox.db", null, 1) {

    companion object {
        const val SOURCE_SMS = "sms"
        const val SOURCE_NOTIFICATION = "notification"

        @Volatile
        private var instance: AutoEntryInbox? = null

        fun get(context: Context): AutoEntryInbox =
            instance ?: synchronized(this) {
                instance ?: AutoEntryInbox(context).also { instance = it }
            }
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            "CREATE TABLE inbox (id INTEGER PRIMARY KEY AUTOINCREMENT, source TEXT NOT NULL, " +
                "sender TEXT NOT NULL, body TEXT NOT NULL, received_at INTEGER NOT NULL)"
        )
        db.execSQL(
            "CREATE TABLE skipped (id INTEGER PRIMARY KEY AUTOINCREMENT, sender TEXT NOT NULL, " +
                "at INTEGER NOT NULL)"
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {}

    @Synchronized
    fun add(source: String, sender: String, body: String, receivedAt: Long) {
        val values = ContentValues().apply {
            put("source", source)
            put("sender", sender)
            put("body", body)
            put("received_at", receivedAt)
        }
        writableDatabase.insert("inbox", null, values)
    }

    /** Records that an OTP from [sender] was dropped. The text itself is not kept. */
    @Synchronized
    fun addSkippedOtp(sender: String, at: Long) {
        val values = ContentValues().apply {
            put("sender", sender)
            put("at", at)
        }
        writableDatabase.insert("skipped", null, values)
    }

    /** Returns everything stored and deletes it, in one transaction. */
    @Synchronized
    fun drain(): Map<String, Any> {
        val db = writableDatabase
        val messages = ArrayList<Map<String, Any>>()
        val skipped = ArrayList<Map<String, Any>>()
        db.beginTransaction()
        try {
            db.rawQuery(
                "SELECT source, sender, body, received_at FROM inbox ORDER BY id",
                null,
            ).use { cursor ->
                while (cursor.moveToNext()) {
                    messages.add(
                        mapOf(
                            "source" to cursor.getString(0),
                            "sender" to cursor.getString(1),
                            "body" to cursor.getString(2),
                            "receivedAt" to cursor.getLong(3),
                        )
                    )
                }
            }
            db.rawQuery("SELECT sender, at FROM skipped ORDER BY id", null).use { cursor ->
                while (cursor.moveToNext()) {
                    skipped.add(mapOf("sender" to cursor.getString(0), "at" to cursor.getLong(1)))
                }
            }
            db.delete("inbox", null, null)
            db.delete("skipped", null, null)
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
        return mapOf("messages" to messages, "skipped" to skipped)
    }
}
