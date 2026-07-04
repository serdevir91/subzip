package www.subzip.app

import android.os.Environment
import android.os.StatFs
import com.google.android.play.agesignals.AgeSignalsException
import com.google.android.play.agesignals.AgeSignalsManagerFactory
import com.google.android.play.agesignals.AgeSignalsRequest
import com.google.android.play.agesignals.model.AgeSignalsVerificationStatus
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val STORAGE_CHANNEL = "app.subzip/storage"
        private const val AGE_SIGNALS_CHANNEL = "app.subzip/age_signals"
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AGE_SIGNALS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "checkAgeSignals" -> checkAgeSignals(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun checkAgeSignals(result: MethodChannel.Result) {
        try {
            val ageSignalsManager = AgeSignalsManagerFactory.create(applicationContext)
            ageSignalsManager
                .checkAgeSignals(AgeSignalsRequest.builder().build())
                .addOnSuccessListener { ageSignalsResult ->
                    val userStatus: Int? = ageSignalsResult.userStatus()
                    val approvalDate = ageSignalsResult.mostRecentApprovalDate()

                    result.success(
                        mapOf(
                            "userStatus" to userStatus,
                            "userStatusName" to statusName(userStatus),
                            "ageLower" to ageSignalsResult.ageLower(),
                            "ageUpper" to ageSignalsResult.ageUpper(),
                            "mostRecentApprovalEpochMs" to approvalDate?.time,
                            "installId" to ageSignalsResult.installId(),
                            "checkedAtEpochMs" to System.currentTimeMillis()
                        )
                    )
                }
                .addOnFailureListener { exception ->
                    if (exception is AgeSignalsException) {
                        result.error(
                            "age_signals_error",
                            exception.message,
                            mapOf("errorCode" to exception.getErrorCode())
                        )
                    } else {
                        result.error("age_signals_error", exception.message, null)
                    }
                }
        } catch (exception: Exception) {
            result.error("age_signals_error", exception.message, null)
        }
    }

    private fun statusName(status: Int?): String? {
        return when (status) {
            AgeSignalsVerificationStatus.VERIFIED -> "VERIFIED"
            AgeSignalsVerificationStatus.SUPERVISED -> "SUPERVISED"
            AgeSignalsVerificationStatus.SUPERVISED_APPROVAL_PENDING ->
                "SUPERVISED_APPROVAL_PENDING"
            AgeSignalsVerificationStatus.SUPERVISED_APPROVAL_DENIED ->
                "SUPERVISED_APPROVAL_DENIED"
            AgeSignalsVerificationStatus.UNKNOWN -> "UNKNOWN"
            AgeSignalsVerificationStatus.DECLARED -> "DECLARED"
            else -> null
        }
    }
}
