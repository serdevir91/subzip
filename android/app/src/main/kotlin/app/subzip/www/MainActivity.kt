package www.subzip.app

import android.os.Environment
import android.os.StatFs
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val STORAGE_CHANNEL = "app.subzip/storage"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, STORAGE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getStorageStats" -> {
                        try {
                            val storagePath = Environment.getExternalStorageDirectory().absolutePath
                            val statFs = StatFs(storagePath)
                            val totalBytes = statFs.blockSizeLong * statFs.blockCountLong
                            val freeBytes = statFs.blockSizeLong * statFs.availableBlocksLong
                            val usedBytes = (totalBytes - freeBytes).coerceAtLeast(0L)

                            result.success(
                                mapOf(
                                    "path" to storagePath,
                                    "total" to totalBytes,
                                    "free" to freeBytes,
                                    "used" to usedBytes
                                )
                            )
                        } catch (e: Exception) {
                            result.error("storage_error", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
