package com.godot.game

import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.provider.Settings
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.UsedByGodot
import java.io.File
import java.io.FileInputStream

/**
 * Plugin Godot v2 « UpdateInstaller » : installe un APK déjà téléchargé dans le
 * stockage de l'application, sans navigateur, via PackageInstaller (API Android).
 * Exposé à GDScript sous le nom de singleton « UpdateInstaller ».
 */
class UpdateInstaller(godot: Godot) : GodotPlugin(godot) {

    override fun getPluginName(): String = "UpdateInstaller"

    @UsedByGodot
    fun canRequestInstall(): Boolean {
        val ctx = godot.getActivity() ?: return false
        return ctx.packageManager.canRequestPackageInstalls()
    }

    /** Ouvre l'écran Android « Installer des applications inconnues » pour cette appli. */
    @UsedByGodot
    fun openUnknownSourceSettings(): Boolean {
        val ctx = godot.getActivity() ?: return false
        return try {
            val i = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:" + ctx.packageName))
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            ctx.startActivity(i)
            true
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Lance l'installation de l'APK téléchargé (chemin absolu).
     * La session PackageInstaller affiche la confirmation système Android.
     */
    @UsedByGodot
    fun installApk(path: String): Boolean {
        val ctx = godot.getActivity() ?: return false
        val f = File(path)
        if (!f.exists() || f.length() < 1_000_000L) return false
        return try {
            val installer = ctx.packageManager.packageInstaller
            val sessionId = installer.createSession(PackageInstaller.SessionParams())
            val session = installer.openSession(sessionId)
            FileInputStream(f).use { input ->
                session.openWrite("update", 0, f.length()).use { out ->
                    input.copyTo(out)
                    session.fsync(out)
                }
            }
            val flags = if (Build.VERSION.SDK_INT >= 23) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            val pi = PendingIntent.getActivity(ctx, sessionId, Intent(), flags)
            session.commit(pi.intentSender)
            session.close()
            true
        } catch (e: Exception) {
            false
        }
    }
}
