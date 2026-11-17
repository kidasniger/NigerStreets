#!/usr/bin/env bash
# Injecte le plugin UpdateInstaller (installation d'APK dans l'appli) dans le
# template gradle Godot (android/build), généré juste avant par la CI.
# - copie UpdateInstaller.kt à côté de GodotApp (même package)
# - ajoute la permission REQUEST_INSTALL_PACKAGES et le meta-data plugin v2
# - garantit la dépendance du module app vers :godot-library
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/android/build"

MANIFEST="$(find "$BUILD_DIR" -maxdepth 4 -name AndroidManifest.xml | head -n 1)"
if [ -z "$MANIFEST" ]; then
    echo "ERREUR : AndroidManifest.xml introuvable sous $BUILD_DIR" >&2
    exit 1
fi
APP_DIR="$(dirname "$MANIFEST")"
GODOT_APP="$(find "$APP_DIR" -name 'GodotApp.kt' -o -name 'GodotApp.java' | head -n 1)"
if [ -z "$GODOT_APP" ]; then
    echo "ERREUR : GodotApp introuvable sous $APP_DIR" >&2
    exit 1
fi
SRC_DIR="$(dirname "$GODOT_APP")"

# 1) Copie du plugin dans le package de l'application
PKG="$(grep -m1 -E '^[[:space:]]*package[[:space:]]' "$GODOT_APP" | sed -E 's/^[[:space:]]*package[[:space:]]+//; s/[[:space:]]*$//')"
cp "$ROOT/android_plugin/UpdateInstaller.kt" "$SRC_DIR/UpdateInstaller.kt"
sed -i "s/^package .*/package $PKG/" "$SRC_DIR/UpdateInstaller.kt"
META="$PKG.UpdateInstaller"

# 2) Patch du manifeste : permission + meta-data plugin v2 (idempotent)
python3 - "$MANIFEST" "$META" <<'PY'
import re, sys
path, meta = sys.argv[1], sys.argv[2]
xml = open(path, encoding="utf-8").read()
if "REQUEST_INSTALL_PACKAGES" not in xml:
    xml = xml.replace("<application", '<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>\n    <application', 1)
tag = f'<meta-data android:name="org.godotengine.plugin.v2.UpdateInstaller" android:value="{meta}" />'
if "org.godotengine.plugin.v2.UpdateInstaller" not in xml:
    m = re.search(r"<application[^>]*>", xml)
    if m is None:
        sys.exit("balise <application> introuvable")
    xml = xml[:m.end()] + "\n        " + tag + xml[m.end():]
open(path, "w", encoding="utf-8").write(xml)
print("manifeste patché :", meta)
PY

# 3) Dépendance godot-library pour le module app (si absente)
if ! grep -q 'godot-library' "$APP_DIR/build.gradle"; then
    sed -i 's/^dependencies {/dependencies {\n    implementation project(":godot-library")/' "$APP_DIR/build.gradle"
    echo "dépendance :godot-library ajoutée"
fi

echo "OK : plugin UpdateInstaller injecté dans $APP_DIR (package $PKG)"
