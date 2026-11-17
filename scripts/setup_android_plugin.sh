#!/usr/bin/env bash
# Injecte le plugin UpdateInstaller (installation d'APK dans l'appli) dans le
# template gradle Godot (android/build, projet mono-module), généré juste avant
# par la CI. Structure attendue (Godot 4.7) :
#   android/build/build.gradle                          (module app, unique)
#   android/build/src/main/AndroidManifest.xml          (manifeste de l'application)
#   android/build/src/main/java/com/godot/game/GodotApp.java
#   android/build/libs/release/godot-lib.template_release.aar
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/android/build"

MANIFEST="$BUILD_DIR/src/main/AndroidManifest.xml"
APP_GRADLE="$BUILD_DIR/build.gradle"
for f in "$MANIFEST" "$APP_GRADLE"; do
    [ -f "$f" ] || { echo "ERREUR : $f introuvable (template 4.7 attendu)" >&2; exit 1; }
done
GODOT_APP="$(find "$BUILD_DIR/src" -name 'GodotApp.java' | head -n 1)"
[ -n "$GODOT_APP" ] || { echo "ERREUR : GodotApp.java introuvable" >&2; exit 1; }
SRC_DIR="$(dirname "$GODOT_APP")"

# 0) Info de version du template : l'éditeur l'écrit normalement à l'installation
#    au niveau android/ (un cran au-dessus de android/build) — voir export_plugin.cpp :
#    gradle_build_directory.get_base_dir().path_join(".build_version"),
#    contenu = GODOT_VERSION_FULL_CONFIG (ex. « 4.7.2.stable »).
GODOT_VERSION="${GODOT_VERSION:-4.7.2}"
echo "${GODOT_VERSION}.stable" > "$ROOT/android/.build_version"
echo "template marqué : $(cat "$ROOT/android/.build_version")"

# 1) Copie du plugin (Java pur : aucune dépendance Kotlin) dans le package de l'app
PKG="$(grep -m1 -E '^[[:space:]]*package[[:space:]]' "$GODOT_APP" | sed -E 's/^[[:space:]]*package[[:space:]]+//; s/;[[:space:]]*$//; s/[[:space:]]+$//')"
cp "$ROOT/android_plugin/UpdateInstaller.java" "$SRC_DIR/UpdateInstaller.java"
sed -i "s/^package .*/package $PKG;/" "$SRC_DIR/UpdateInstaller.java"
META="$PKG.UpdateInstaller"

# 2) Manifeste : permission installation + meta-data plugin v2 (idempotent)
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

# 3) La lib Godot doit être une dépendance du module (le template l'a déjà)
if grep -q 'godot-lib' "$APP_GRADLE"; then
    echo "dépendance godot-lib présente"
else
    sed -i 's/^dependencies {/dependencies {\n    implementation files("libs\/release\/godot-lib.template_release.aar")/' "$APP_GRADLE"
    echo "dépendance godot-lib ajoutée"
fi

echo "OK : plugin UpdateInstaller injecté ($PKG.UpdateInstaller)"
