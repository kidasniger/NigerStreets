package com.godot.game;

import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageInstaller;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;
import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;
import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.io.OutputStream;

/**
 * Plugin Godot v2 « UpdateInstaller » : installe un APK déjà téléchargé dans le
 * stockage de l'application, sans navigateur, via PackageInstaller (API Android).
 * Exposé à GDScript sous le nom de singleton « UpdateInstaller ».
 */
public class UpdateInstaller extends GodotPlugin {

    private final Godot godot;

    public UpdateInstaller(Godot godot) {
        super(godot);
        this.godot = godot;
    }

    @Override
    public String getPluginName() {
        return "UpdateInstaller";
    }

    @UsedByGodot
    public boolean canRequestInstall() {
        Context ctx = godot.getActivity();
        if (ctx == null) return false;
        return ctx.getPackageManager().canRequestPackageInstalls();
    }

    /** Ouvre l'écran Android « Installer des applications inconnues » pour cette appli. */
    @UsedByGodot
    public boolean openUnknownSourceSettings() {
        Context ctx = godot.getActivity();
        if (ctx == null) return false;
        try {
            Intent i = new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:" + ctx.getPackageName()));
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            ctx.startActivity(i);
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    /**
     * Lance l'installation de l'APK téléchargé (chemin absolu).
     * La session PackageInstaller affiche la confirmation système Android.
     */
    @UsedByGodot
    public boolean installApk(String path) {
        Context ctx = godot.getActivity();
        if (ctx == null) return false;
        File f = new File(path);
        if (!f.exists() || f.length() < 1000000L) return false;
        try {
            PackageInstaller installer = ctx.getPackageManager().getPackageInstaller();
            int sessionId = installer.createSession(
                new PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL));
            PackageInstaller.Session session = installer.openSession(sessionId);
            InputStream input = new FileInputStream(f);
            OutputStream out = session.openWrite("update", 0, f.length());
            byte[] buf = new byte[65536];
            int n;
            while ((n = input.read(buf)) > 0) {
                out.write(buf, 0, n);
            }
            session.fsync(out);
            out.close();
            input.close();
            int flags = Build.VERSION.SDK_INT >= 23
                ? PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
                : PendingIntent.FLAG_UPDATE_CURRENT;
            PendingIntent pi = PendingIntent.getActivity(ctx, sessionId, new Intent(), flags);
            session.commit(pi.getIntentSender());
            session.close();
            return true;
        } catch (Exception e) {
            return false;
        }
    }
}
