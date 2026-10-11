package com.example.vellum

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.provider.Settings
import android.view.KeyEvent
import android.view.WindowManager
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import java.io.File

class MainActivity : AudioServiceActivity() {
    private val channelName = "vellum/device"
    private var channel: MethodChannel? = null
    private var localBookScanner: LocalBookScanner? = null

    /** Volume buttons turn pages instead of changing the volume. */
    private var volumeKeyPaging = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val scanner = LocalBookScanner(this)
        localBookScanner = scanner
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vellum/local_books")
            .setMethodCallHandler(scanner::handle)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "vellum/local_books/scan")
            .setStreamHandler(scanner)
        val methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel = methodChannel
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "batteryLevel" -> batteryLevel(result)
                "supportedAbis" -> result.success(Build.SUPPORTED_ABIS.toList())
                "canRequestInstall" -> result.success(canRequestInstall())
                "openInstallSettings" -> openInstallSettings(result)
                "installApk" -> installApk(call.argument<String>("path"), result)
                "updateWidgetShelf" -> updateWidgetShelf(
                    call.argument<String>("snapshot"),
                    result,
                )
                "setScreenBrightness" -> setScreenBrightness(
                    call.argument<Double>("value") ?: -1.0,
                    result,
                )
                "setKeepScreenOn" -> setKeepScreenOn(
                    call.argument<Boolean>("enabled") ?: false,
                    result,
                )
                "setVolumeKeyPaging" -> {
                    volumeKeyPaging = call.argument<Boolean>("enabled") ?: false
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (localBookScanner?.activityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        localBookScanner?.close()
        super.onDestroy()
    }

    /**
     * Only the current window is affected and `-1` restores the system
     * brightness, so nothing is written to user settings.
     */
    private fun setScreenBrightness(value: Double, result: MethodChannel.Result) {
        window.attributes = window.attributes.apply {
            screenBrightness = value.toFloat().coerceIn(-1f, 1f)
        }
        result.success(true)
    }

    private fun setKeepScreenOn(enabled: Boolean, result: MethodChannel.Result) {
        if (enabled) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
        result.success(true)
    }

    /**
     * Stores only the small widget metadata snapshot. The widget never reads
     * book bodies or the app's backup/state files directly.
     */
    private fun updateWidgetShelf(snapshot: String?, result: MethodChannel.Result) {
        if (snapshot.isNullOrBlank() || snapshot.length > 32 * 1024) {
            result.error("BAD_SNAPSHOT", "widget snapshot is empty or too large", null)
            return
        }
        try {
            val target = File(filesDir, VellumWidgetProvider.SNAPSHOT_FILE)
            val temporary = File(filesDir, "${VellumWidgetProvider.SNAPSHOT_FILE}.tmp")
            temporary.writeText(snapshot, Charsets.UTF_8)
            if (target.exists() && !target.delete()) {
                result.error("SNAPSHOT_WRITE_FAILED", "cannot replace widget snapshot", null)
                return
            }
            if (!temporary.renameTo(target)) {
                result.error("SNAPSHOT_WRITE_FAILED", "cannot commit widget snapshot", null)
                return
            }
            VellumWidgetProvider.refreshAll(this)
            result.success(true)
        } catch (error: Exception) {
            result.error("SNAPSHOT_WRITE_FAILED", error.message, null)
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (volumeKeyPaging) {
            when (keyCode) {
                KeyEvent.KEYCODE_VOLUME_UP -> {
                    channel?.invokeMethod("volumeKey", -1)
                    return true
                }
                KeyEvent.KEYCODE_VOLUME_DOWN -> {
                    channel?.invokeMethod("volumeKey", 1)
                    return true
                }
            }
        }
        return super.onKeyDown(keyCode, event)
    }

    private fun batteryLevel(result: MethodChannel.Result) {
        val batteryManager = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        val level = batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        if (level >= 0) {
            result.success(level)
        } else {
            result.error("UNAVAILABLE", "Battery level unavailable", null)
        }
    }

    /** Older releases cannot restrict per-source installs, so they count as allowed. */
    private fun canRequestInstall(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }

    private fun openInstallSettings(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.success(false)
            return
        }
        try {
            startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                    .setData(Uri.fromParts("package", packageName, null))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            result.success(true)
        } catch (error: Exception) {
            result.error("SETTINGS_UNAVAILABLE", error.message, null)
        }
    }

    /**
     * Hands a downloaded APK to the system package installer. The file must live
     * under a root declared in res/xml/file_paths.xml, which is why the APK is
     * downloaded into the app's files directory.
     */
    private fun installApk(path: String?, result: MethodChannel.Result) {
        if (path.isNullOrEmpty()) {
            result.error("BAD_ARGS", "path is required", null)
            return
        }
        val file = File(path)
        if (!file.exists()) {
            result.error("MISSING_FILE", "APK not found at $path", null)
            return
        }
        try {
            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
            val intent = Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            startActivity(intent)
            result.success(true)
        } catch (error: Exception) {
            result.error("INSTALL_FAILED", error.message, null)
        }
    }
}
