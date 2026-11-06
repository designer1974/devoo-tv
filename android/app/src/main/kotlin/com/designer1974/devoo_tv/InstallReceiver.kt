package com.designer1974.devoo_tv

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.util.Log

/** Risposta di Android all'installazione dell'aggiornamento: apre la conferma "Installa". */
class InstallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, -999)
        // l'app legge l'esito e, se non è andata, propone di riprovare
        try {
            context.getSharedPreferences("tv_update", Context.MODE_PRIVATE).edit()
                .putInt("status", status)
                .putString("msg", intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE) ?: "")
                .apply()
        } catch (_: Exception) {}
        if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
            @Suppress("DEPRECATION")
            val confirm = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT) ?: return
            confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try { context.startActivity(confirm) } catch (e: Exception) { Log.e("Install", "conferma", e) }
        }
    }
}
