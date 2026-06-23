package com.suseoaa.castpigeon.db

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import com.suseoaa.castpigeon.shared.NotificationMessage
import java.util.Calendar

class MessageDatabaseHelper(context: Context) : SQLiteOpenHelper(context, DATABASE_NAME, null, DATABASE_VERSION) {

    companion object {
        private const val DATABASE_NAME = "castpigeon.db"
        private const val DATABASE_VERSION = 1
        private const val TABLE_MESSAGES = "messages"
        
        private const val COL_ID = "id"
        private const val COL_MSG_ID = "msg_id"
        private const val COL_APP_NAME = "app_name"
        private const val COL_TITLE = "title"
        private const val COL_CONTENT = "content"
        private const val COL_TIMESTAMP = "timestamp"
    }

    override fun onCreate(db: SQLiteDatabase) {
        val createTable = """
            CREATE TABLE $TABLE_MESSAGES (
                $COL_ID INTEGER PRIMARY KEY AUTOINCREMENT,
                $COL_MSG_ID TEXT UNIQUE,
                $COL_APP_NAME TEXT,
                $COL_TITLE TEXT,
                $COL_CONTENT TEXT,
                $COL_TIMESTAMP INTEGER
            )
        """.trimIndent()
        db.execSQL(createTable)
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        db.execSQL("DROP TABLE IF EXISTS $TABLE_MESSAGES")
        onCreate(db)
    }

    fun insertMessage(msg: NotificationMessage) {
        val db = this.writableDatabase
        val values = ContentValues().apply {
            put(COL_MSG_ID, msg.id)
            put(COL_APP_NAME, msg.appName)
            put(COL_TITLE, msg.title)
            put(COL_CONTENT, msg.content)
            put(COL_TIMESTAMP, msg.timestamp)
        }
        db.insertWithOnConflict(TABLE_MESSAGES, null, values, SQLiteDatabase.CONFLICT_IGNORE)
        db.close()
    }

    fun getTodayMessageCount(): Int {
        val db = this.readableDatabase
        val calendar = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val startOfDay = calendar.timeInMillis
        
        val cursor = db.rawQuery("SELECT COUNT(*) FROM $TABLE_MESSAGES WHERE $COL_TIMESTAMP >= ?", arrayOf(startOfDay.toString()))
        var count = 0
        if (cursor.moveToFirst()) {
            count = cursor.getInt(0)
        }
        cursor.close()
        db.close()
        return count
    }
}
