package com.jnote.app

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import java.time.LocalDate

/**
 * Opens the same jnote.db file the Flutter app uses through sqflite.
 * Keep the schema identical to lib/data/notes_db.dart.
 */
class NoteStore(context: Context) : SQLiteOpenHelper(context, "jnote.db", null, 1) {

    class Reminder(val id: Int, val day: Int, val text: String, val at: Long?)

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            "CREATE TABLE IF NOT EXISTS notes(id INTEGER PRIMARY KEY AUTOINCREMENT, day INTEGER NOT NULL, " +
                "text TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, reminder_at INTEGER)"
        )
        db.execSQL("CREATE INDEX IF NOT EXISTS notes_day ON notes(day)")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit

    fun insert(text: String) {
        val now = System.currentTimeMillis()
        writableDatabase.insertOrThrow("notes", null, ContentValues().apply {
            put("day", today())
            put("text", text)
            put("created_at", now)
            put("updated_at", now)
        })
    }

    fun note(id: Int): Reminder? =
        readableDatabase.rawQuery("SELECT day, text, reminder_at FROM notes WHERE id = ?", arrayOf(id.toString()))
            .use { c -> if (c.moveToFirst()) Reminder(id, c.getInt(0), c.getString(1), if (c.isNull(2)) null else c.getLong(2)) else null }

    fun setReminder(id: Int, at: Long?) {
        writableDatabase.update("notes", ContentValues().apply { put("reminder_at", at) }, "id = ?", arrayOf(id.toString()))
    }

    fun pendingReminders(): List<Pair<Int, Long>> =
        readableDatabase.rawQuery("SELECT id, reminder_at FROM notes WHERE reminder_at IS NOT NULL", null).use { c ->
            buildList { while (c.moveToNext()) add(c.getInt(0) to c.getLong(1)) }
        }

    companion object {
        /** Local date as yyyymmdd, the same day key the Dart side uses. */
        fun today(): Int = LocalDate.now().run { year * 10000 + monthValue * 100 + dayOfMonth }

        /** Opens, runs [block], and closes, so receivers never leak a connection. */
        fun <T> with(context: Context, block: (NoteStore) -> T): T {
            val store = NoteStore(context)
            try {
                return block(store)
            } finally {
                store.close()
            }
        }
    }
}
