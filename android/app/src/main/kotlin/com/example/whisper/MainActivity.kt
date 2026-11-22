package cz.josefraz.whisper

import android.database.ContentObserver
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the app and the one piece of it that has to live in the platform:
 * blocking screenshots of a view-once attachment and noticing ones taken of
 * ordinary messages. Android is the only target with an enforceable block.
 */
class MainActivity : FlutterFragmentActivity() {
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val methodChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "whisper/secure_screen")
        channel = methodChannel
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "enableSecure" -> {
                    window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(true)
                }
                "disableSecure" -> {
                    window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        watchScreenshots()
    }

    /** The media store gains a row in Pictures/Screenshots when one is taken. */
    private fun watchScreenshots() {
        val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean, uri: Uri?) {
                super.onChange(selfChange, uri)
                if (uri != null && isScreenshot(uri)) {
                    channel?.invokeMethod("onScreenshot", null)
                }
            }
        }
        contentResolver.registerContentObserver(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            true,
            observer,
        )
    }

    private fun isScreenshot(uri: Uri): Boolean {
        return try {
            contentResolver.query(
                uri,
                arrayOf(MediaStore.Images.Media.RELATIVE_PATH),
                null,
                null,
                null,
            )?.use { cursor ->
                cursor.moveToFirst() &&
                    (cursor.getString(0) ?: "").contains("Screenshot", ignoreCase = true)
            } ?: false
        } catch (_: Exception) {
            // A provider that does not answer is not worth crashing over.
            false
        }
    }
}
