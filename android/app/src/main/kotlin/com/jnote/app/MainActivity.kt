package com.jnote.app

import android.Manifest
import android.app.NotificationManager
import android.appwidget.AppWidgetManager
import android.content.ClipData
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var launchDay: Int? = null
    private var permissionResult: MethodChannel.Result? = null
    private var exactResult: MethodChannel.Result? = null
    private var fileResult: MethodChannel.Result? = null
    private var textToSave: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        launchDay = dayOf(intent)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "jnote/native").apply {
            setMethodCallHandler { call, result ->
                val id = call.argument<Number>("id")?.toInt() ?: 0
                when (call.method) {
                    "schedule" -> result.success(Reminders.schedule(this@MainActivity, id, call.argument<Number>("at")!!.toLong()))
                    "cancel" -> { Reminders.cancel(this@MainActivity, id); result.success(null) }
                    "resync" -> {
                        // Off the main thread: Flutter's UI runs on it too.
                        Thread { Reminders.resync(applicationContext) }.start()
                        result.success(null)
                    }
                    "notificationsEnabled" -> result.success(Reminders.notificationsOn(this@MainActivity))
                    "requestNotifications" -> requestNotifications(result)
                    "canExact" -> result.success(Reminders.canExact(this@MainActivity))
                    // Replies once the user is back, so a reminder set next already uses the new permission.
                    "openExactSettings" -> {
                        if (Build.VERSION.SDK_INT < 31 || exactResult != null) result.success(null)
                        else try {
                            exactResult = result
                            startActivityForResult(
                                Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:$packageName")),
                                REQUEST_EXACT
                            )
                        } catch (e: Exception) {
                            exactResult = null
                            result.success(null)
                        }
                    }
                    "openNotificationSettings" -> {
                        // When the app is allowed but the Reminders category is off, that category's page is the one to fix.
                        val appAllowed = getSystemService(NotificationManager::class.java).areNotificationsEnabled()
                        startActivity(
                            if (appAllowed) reminderChannelSettings()
                            else Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        )
                        result.success(null)
                    }
                    "openSoundSettings" -> { startActivity(reminderChannelSettings()); result.success(null) }
                    // Asks the launcher to add a widget; false when the launcher can't, so the app explains instead.
                    "pinWidget" -> {
                        val widget = if (call.argument<Boolean>("small") == true) QuickNoteWidgetSmall::class.java else QuickNoteWidget::class.java
                        val manager = getSystemService(AppWidgetManager::class.java)
                        result.success(
                            manager.isRequestPinAppWidgetSupported &&
                                manager.requestPinAppWidget(ComponentName(this@MainActivity, widget), null, null)
                        )
                    }
                    // Android 13+ remembers the splash theme for later launches, so light themes don't start dark.
                    "setSplash" -> {
                        if (Build.VERSION.SDK_INT >= 33) {
                            splashScreen.setSplashScreenTheme(if (call.argument<Boolean>("light") == true) R.style.SplashLight else 0)
                        }
                        result.success(null)
                    }
                    "appVersion" -> result.success(packageManager.getPackageInfo(packageName, 0).versionName)
                    "share" -> try {
                        startActivity(Intent.createChooser(shareIntent(call.argument<String>("text") ?: ""), null))
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("share", e.message, null)
                    }
                    // Android's own picker and save dialog: no storage permission needed.
                    "openText" -> pickFile(
                        result,
                        Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("text/*"),
                        REQUEST_OPEN
                    )
                    "saveText" -> pickFile(
                        result,
                        Intent(Intent.ACTION_CREATE_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE)
                            .setType("text/plain").putExtra(Intent.EXTRA_TITLE, call.argument<String>("name")),
                        REQUEST_SAVE,
                        call.argument<String>("text")
                    )
                    "takeLaunchDay" -> { result.success(launchDay); launchDay = null }
                    else -> result.notImplemented()
                }
            }
        }
        running = channel
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        super.cleanUpFlutterEngine(flutterEngine)
        if (running === channel) running = null
    }

    // A reminder notification tapped while the app is already open.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        dayOf(intent)?.let { channel?.invokeMethod("openDay", it) }
    }

    private fun dayOf(intent: Intent?): Int? = intent?.getIntExtra(EXTRA_DAY, 0)?.takeIf { it > 0 }

    private fun reminderChannelSettings(): Intent {
        Reminders.createChannels(this) // the category must exist to open its page
        return Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
            .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            .putExtra(Settings.EXTRA_CHANNEL_ID, Reminders.RINGING)
    }

    // Large exports are shared as a file: an Intent can only carry about 1 MB.
    private fun shareIntent(text: String): Intent {
        val send = Intent(Intent.ACTION_SEND).setType("text/plain")
        if (text.length < 100_000) return send.putExtra(Intent.EXTRA_TEXT, text)
        val file = File(cacheDir, "exports").apply { mkdirs() }.resolve("jnote-notes.txt")
        file.writeText(text)
        val uri = FileProvider.getUriForFile(this, "$packageName.files", file)
        return send.putExtra(Intent.EXTRA_STREAM, uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION).apply {
            clipData = ClipData.newRawUri(null, uri) // carries the read grant through the chooser
        }
    }

    private fun requestNotifications(result: MethodChannel.Result) {
        when {
            Reminders.notificationsOn(this) -> result.success("granted")
            // Turned off in Settings (the app, or just the Reminders category): only Settings can undo it.
            getSystemService(NotificationManager::class.java).areNotificationsEnabled() || Build.VERSION.SDK_INT < 33 ->
                result.success("blocked")
            permissionResult != null -> result.success("denied") // the system prompt is already showing
            else -> {
                permissionResult = result
                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATIONS)
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_NOTIFICATIONS) return
        val canAskAgain = Build.VERSION.SDK_INT >= 33 && shouldShowRequestPermissionRationale(Manifest.permission.POST_NOTIFICATIONS)
        val answer = when {
            Reminders.notificationsOn(this) -> "granted"
            grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED -> "blocked" // allowed, but the category is off
            canAskAgain -> "denied"
            else -> "blocked"
        }
        permissionResult?.success(answer)
        permissionResult = null
    }

    private fun pickFile(result: MethodChannel.Result, intent: Intent, request: Int, text: String? = null) {
        if (fileResult != null) return result.success(null) // a second tap while the picker opens: ignore it
        try {
            startActivityForResult(intent, request)
            fileResult = result
            textToSave = text
        } catch (e: Exception) {
            result.error("no_picker", e.message, null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            REQUEST_EXACT -> {
                exactResult?.success(null)
                exactResult = null
            }
            REQUEST_OPEN, REQUEST_SAVE -> {
                val result = fileResult ?: return
                val text = textToSave
                fileResult = null
                textToSave = null
                val uri = data?.data
                if (resultCode != RESULT_OK || uri == null) return result.success(null) // cancelled
                // Off the main thread: the file may live on a slow or network-backed provider.
                Thread {
                    try {
                        val value: Any = if (requestCode == REQUEST_OPEN) readText(uri) else {
                            (contentResolver.openOutputStream(uri) ?: throw IOException("no stream"))
                                .use { it.write((text ?: "").toByteArray()) }
                            true
                        }
                        runOnUiThread { result.success(value) }
                    } catch (e: Exception) {
                        runOnUiThread { result.error(if (e.message == TOO_LARGE) TOO_LARGE else "io", e.message, null) }
                    }
                }.start()
            }
        }
    }

    // Reads at most MAX_TEXT_BYTES, so a wrong pick can't exhaust memory.
    private fun readText(uri: Uri): String {
        val out = ByteArrayOutputStream()
        (contentResolver.openInputStream(uri) ?: throw IOException("no stream")).use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val n = input.read(buffer)
                if (n < 0) break
                out.write(buffer, 0, n)
                if (out.size() > MAX_TEXT_BYTES) throw IOException(TOO_LARGE)
            }
        }
        return out.toString("UTF-8")
    }

    companion object {
        const val EXTRA_DAY = "day"
        private const val REQUEST_NOTIFICATIONS = 7
        private const val REQUEST_EXACT = 8
        private const val REQUEST_OPEN = 9
        private const val REQUEST_SAVE = 10
        private const val MAX_TEXT_BYTES = 20 * 1024 * 1024
        private const val TOO_LARGE = "too_large"

        // The open app, if any, so a reminder that rings or is snoozed or dismissed shows at once.
        private var running: MethodChannel? = null

        fun remindersChanged() {
            running?.invokeMethod("changed", null)
        }
    }
}
