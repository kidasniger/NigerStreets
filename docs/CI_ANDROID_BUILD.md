# Release Android automatique — GitHub Actions 🤖

Ce dépôt utilise le **même système de release que MusicPro** : chaque push sur `main` produit un APK signé et crée automatiquement une Release GitHub avec l'APK attaché.

---

## 🎯 Ce que fait le workflow (`.github/workflows/android.yml`)

| Déclencheur | Résultat |
|---|---|
| **Push sur `main`** | APK release signé → Release GitHub `v1.0-b{N}` (tag créé + APK attaché) |
| **Run workflow** (manuel) | Identique, à la demande depuis l'onglet Actions |

Détails :

- **Version** : `1.0-b{N}` où `{N}` = numéro de build (`run_number`). `versionCode` = `{N}` — croissant à chaque release, donc chaque APK s'installe en mise à jour par-dessus le précédent.
- **Notes de release** : le **corps du message de commit** est utilisé comme résumé utilisateur. Les commits de release doivent donc rester orientés changements visibles dans le jeu.
- **Artefact** `NigerStreets-release-apk` conservé 90 jours.

---

## 🔐 Secrets requis (configurés ✅)

| Secret | Rôle |
|---|---|
| `KEYSTORE_BASE64` | Keystore release encodé en base64 |
| `KEYSTORE_PASSWORD` | Mot de passe du keystore |
| `KEY_ALIAS` | Alias de la clé (`nigerstreets`) |
| `KEY_PASSWORD` | Mot de passe de la clé (identique au keystore) |

Le workflow décode le keystore vers `$RUNNER_TEMP/release.keystore` puis Godot le consomme via les variables d'environnement officielles de Godot 4.x : `GODOT_ANDROID_KEYSTORE_RELEASE_PATH` / `_USER` / `_PASSWORD` (noms vérifiés dans le code source de Godot).

⚠️ **Sauvegarde le keystore** (`nigerstreets-release.jks`) et son mot de passe **hors GitHub** : sans eux, impossible de signer une future mise à jour. Ne régénère jamais le keystore — les installations existantes refuseraient la mise à jour (signature différente).

---

## 🚀 Publier une mise à jour

1. Commite tes changements avec un **message dont le corps décrit les nouveautés** (il devient le texte de la release).
2. `git push origin main`.
3. Le workflow construit l'APK signé (≈ 5 min) puis crée la Release `v1.0-b{N}` — onglet **Releases** → APK téléchargeable et installable.

Retrouver un APK : onglet **Actions** → run → **Artifacts**, ou **Releases** → **Assets**.

---

## 🛠 Personnalisation

### Changer la version de base
`version/name="X.Y"` dans `export_presets.cfg` — le suffixe `-b{N}` est ajouté automatiquement.

### Changer la version Godot
Édite `env.GODOT_VERSION` et les 2 URLs de téléchargement dans `.github/workflows/android.yml`.

### Architectures
`architectures/arm64-v8a` dans `export_presets.cfg` (ajouter `x86_64` pour les émulateurs).

---

## 🐛 Dépannage

| Erreur | Cause | Solution |
|---|---|---|
| `Could not find release keystore` | Secrets absents ou invalides | Vérifier les 4 secrets |
| `Android build template not installed` | Export AAB (gradle) demandé sans template installé | Le workflow n'exporte pas d'AAB ; pour le Play Store un jour, installer le template depuis l'éditeur (Projet → Installer le template de build Android) |
| Signature différente entre versions | Keystore remplacé | Ne jamais régénérer le keystore — conserver `nigerstreets-release.jks` et son mot de passe |
| `Gradle download timeout` / cache 400 | Service de cache GitHub indisponible | Transitoire — relancer le job |
