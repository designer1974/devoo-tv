package com.designer1974.devoo_tv

import android.content.Intent
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        try { Scheduler.refreshStandby(this) } catch (_: Exception) {}
    }

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
                    // ---- registrazioni (fatte dal servizio, anche ad app chiusa) ----
                    "recStatus" -> result.success(
                        mapOf(
                            "busy" to HlsRecorder.busy,
                            "running" to HlsRecorder.running,
                            "bytes" to HlsRecorder.bytes,
                            "startedAt" to HlsRecorder.startedAt,
                            "error" to HlsRecorder.error,
                            "schedId" to ScheduledRecService.activeId,
                            "schedName" to ScheduledRecService.activeName,
                            "schedEnd" to ScheduledRecService.activeEnd,
                        )
                    )
                    "schedAdd" -> {
                        val m = call.arguments as Map<*, *>
                        val j = org.json.JSONObject()
                        for ((k, v) in m) j.put(k.toString(), v)
                        Scheduler.add(this, j)
                        result.success(null)
                    }
                    "schedList" -> {
                        val a = Scheduler.list(this)
                        result.success((0 until a.length()).map { i ->
                            val o = a.getJSONObject(i)
                            o.keys().asSequence().associateWith { k -> o.get(k) }
                        })
                    }
                    "schedRemove" -> {
                        val id = call.argument<String>("id")!!
                        if (Scheduler.get(this, id)?.optBoolean("running") == true) {
                            try {
                                startService(Intent(this, ScheduledRecService::class.java).setAction(ScheduledRecService.ACTION_STOP))
                            } catch (_: Exception) {}
                        }
                        Scheduler.remove(this, id)
                        result.success(null)
                    }
                    "schedStop" -> {
                        try {
                            startService(Intent(this, ScheduledRecService::class.java).setAction(ScheduledRecService.ACTION_STOP))
                        } catch (_: Exception) {}
                        result.success(null)
                    }
                    "schedExactOk" -> result.success(Scheduler.exactAllowed(this))
                    "schedExactSettings" -> {
                        if (Build.VERSION.SDK_INT >= 31) {
                            try {
                                startActivity(Intent(android.provider.Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                                    Uri.parse("package:$packageName")))
                            } catch (_: Exception) {}
                        }
                        result.success(null)
                    }
                    "batteryOk" -> {
                        val pm = getSystemService(POWER_SERVICE) as android.os.PowerManager
                        result.success(Build.VERSION.SDK_INT < 23 || pm.isIgnoringBatteryOptimizations(packageName))
                    }
                    "batteryAsk" -> {
                        if (Build.VERSION.SDK_INT >= 23) {
                            try {
                                startActivity(Intent(android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                    Uri.parse("package:$packageName")))
                            } catch (_: Exception) {}
                        }
                        result.success(null)
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
