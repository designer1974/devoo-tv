package com.designer1974.devoo_tv

import android.content.Intent
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tv/app").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "is64" -> result.success(Build.SUPPORTED_64_BIT_ABIS.isNotEmpty())
                    "openUrl" -> {
                        val ok = try {
                            startActivity(
                                Intent(Intent.ACTION_VIEW, Uri.parse(call.argument<String>("url")!!))
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            )
                            true
                        } catch (_: Exception) {
                            false
                        }
                        result.success(ok)
                    }
                    "installStatus" -> {
                        val p = getSharedPreferences("tv_update", MODE_PRIVATE)
                        result.success(mapOf("status" to p.getInt("status", -100), "msg" to (p.getString("msg", "") ?: "")))
                    }
                    "installApk" -> {
                        val path = call.argument<String>("path")!!
                        Thread {
                            val r = try { installApk(path); "ok" } catch (e: Exception) { e.message ?: "errore" }
                            runOnUiThread { result.success(r) }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("TV", e.message ?: "Errore", null)
            }
        }
    }

    /** Aggiornamento: passa l'APK scaricato all'installatore di Android, che chiede "Installa". */
    private fun installApk(path: String) {
        val f = java.io.File(path)
        getSharedPreferences("tv_update", MODE_PRIVATE).edit().putInt("status", -100).putString("msg", "").commit()
        val pi = packageManager.packageInstaller
        val params = android.content.pm.PackageInstaller.SessionParams(
            android.content.pm.PackageInstaller.SessionParams.MODE_FULL_INSTALL
        )
        val id = pi.createSession(params)
        pi.openSession(id).use { s ->
            f.inputStream().use { input ->
                s.openWrite("update.apk", 0, f.length()).use { out ->
                    input.copyTo(out, 256 * 1024)
                    s.fsync(out)
                }
            }
            val flags = android.app.PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= 31) android.app.PendingIntent.FLAG_MUTABLE else 0)
            val sender = android.app.PendingIntent.getBroadcast(
                this, id, Intent(this, InstallReceiver::class.java), flags
            ).intentSender
            s.commit(sender)
        }
    }
}
