package com.example.notify

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    private val apkInstallChannel = "com.example.notify/apk_install"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, apkInstallChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installApk" -> {
                        val filePath = call.argument<String>("filePath")
                        if (filePath == null) {
                            result.error("INVALID_ARG", "filePath is required", null)
                            return@setMethodCallHandler
                        }
                        // Android 8+: the app must be granted "Install unknown apps"
                        // permission before the system installer accepts our intent.
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                            !packageManager.canRequestPackageInstalls()
                        ) {
                            // Open the per-app permission page directly so the user
                            // can toggle it without hunting through Settings.
                            try {
                                val settingsIntent = Intent(
                                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:$packageName"),
                                )
                                startActivity(settingsIntent)
                            } catch (_: Exception) {
                                // Some OEMs don't expose this Settings screen.
                                // Fall through — the error code still tells Flutter
                                // to show the permission prompt.
                            }
                            result.error(
                                "INSTALL_PERMISSION_REQUIRED",
                                "Install unknown apps permission is not granted",
                                null,
                            )
                            return@setMethodCallHandler
                        }
                        try {
                            installApk(filePath)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("INSTALL_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun installApk(filePath: String) {
        val file = File(filePath)
        val uri = FileProvider.getUriForFile(
            this,
            "${applicationContext.packageName}.fileprovider",
            file,
        )
        val intent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
            data = uri
            flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK
        }
        startActivity(intent)
    }
}
