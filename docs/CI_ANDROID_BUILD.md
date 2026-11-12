# Build Android automatisé — GitHub Actions 🤖

Ce dépôt contient un workflow CI/CD (`.github/workflows/android.yml`) qui compile automatiquement l'APK/AAB à chaque push et publication de release.

---

## 🎯 Ce que fait le workflow

| Job | Déclencheur | Sortie | Artefact |
|---|---|---|---|
| **build-apk-debug** | Push sur `main`, PR, workflow_dispatch | `NigerStreets-debug.apk` (signé debug) | Téléchargeable 30 jours |
| **build-aab-release** | Publication d'une **Release GitHub** (`v*`), workflow_dispatch | `NigerStreets-release.aab` (signé release) | Téléchargeable 90 jours + attaché à la Release |
| **build-apk-release** | Publication d'une **Release GitHub** (`v*`), workflow_dispatch | `NigerStreets-release.apk` (signé release) | Téléchargeable 90 jours + attaché à la Release |

> **Note** : Les builds *release* (AAB/APK signés) ne s'exécutent **que** lors de la création d'une Release GitHub ou via "Run workflow" manuel. Cela évite de consommer des minutes CI pour des commits intermédiaires.

---

## 🔐 Configuration des secrets (requis pour builds release)

Pour signer les builds release (AAB/APK), ajoute ces **secrets** dans GitHub :  
`Settings → Secrets and variables → Actions → New repository secret`

| Secret | Description | Comment obtenir |
|---|---|---|
| `KEYSTORE_BASE64` | Keystore Java encodé en base64 | `base64 -w0 mon_keystore.jks` |
| `KEYSTORE_PASSWORD` | Mot de passe du keystore | Ton mot de passe keystore |
| `KEY_ALIAS` | Alias de la clé (ex: `release-key`) | `keytool -list -keystore mon_keystore.jks` |
| `KEY_PASSWORD` | Mot de passe de la clé | Souvent identique au keystore |

### Générer un keystore release (si pas encore fait)
```bash
keytool -genkey -v -keystore release.keystore -alias release-key \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass TON_MOT_DE_PASSE -keypass TON_MOT_DE_PASSE \
  -dname "CN=Niger Streets, OU=Games, O=NigerStreets, L=Niamey, C=NE"

# Encoder en base64 pour le secret
base64 -w0 release.keystore  # → copie le résultat dans KEYSTORE_BASE64
```

⚠️ **Garde le fichier `release.keystore` en sécurité** — il est indispensable pour mettre à jour l'app sur le Play Store.

---

## 🚀 Comment déclencher un build

### Build debug (APK) — automatique
Chaque `git push origin main` lance `build-apk-debug`.  
Récupère l'artefact : onglet **Actions** → run → **Artifacts** → `NigerStreets-debug-apk`.

### Build release (AAB/APK) — via Release GitHub
1. Va sur **Releases** → **Create a new release**
2. Tag version : `v1.0.0` (format `v*` requis)
3. Titre : `Version 1.0.0`
4. **Publish release**
5. Le workflow se lance → artefacts `NigerStreets-release-aab` / `NigerStreets-release-apk` + fichiers attachés à la Release.

### Build manuel (sans tag)
Onglet **Actions** → **Android Build** → **Run workflow** → choisir `main` → **Run workflow**.  
Coche "build-aab-release" / "build-apk-release" si tu veux les versions signées (nécessite les secrets configurés).

---

## 📦 Télécharger les artefacts

| Interface | Comment |
|---|---|
| **GitHub UI** | Actions → run → résumé → **Artifacts** (zip) |
| **CLI (gh)** | `gh run download -R kidasniger/NigerStreets -n NigerStreets-debug-apk` |
| **Release** | Page Releases → Assets (`.aab` / `.apk` release) |

---

## 🛠 Personnalisation

### Changer la version Godot / templates
Édite `env.GODOT_VERSION` dans `.github/workflows/android.yml` (ex: `"4.8"`).

### Ajouter d'architectures (x86_64 pour émulateurs)
Dans `export_presets.cfg`, section `[preset.0.options]` :
```ini
architectures/x86_64=true
```
Puis commit → le workflow utilisera la config mise à jour.

### Activer shader_baker (précompilation shaders)
Dans `export_presets.cfg`, pour les deux presets :
```ini
shader_baker/enabled=true
```
Export plus long, mais pas de lag shader au premier lancement sur Mali/Adreno.

---

## 🐛 Dépannage courant

| Erreur | Cause | Solution |
|---|---|---|
| `Export template not found` | Templates 4.7.2 absents | L'action `firebelley/godot-export` les télécharge auto — vérifier `template_version` |
| `Keystore not found` | Secrets manquants | Ajouter `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD` |
| `AAB rejected by Play Console` | Non signé / versionCode dupliqué | Incrémenter `version/code` dans `export_presets.cfg` + build release |
| `Gradle download timeout` | Premier build gradle lent | C'est normal (5–10 min) — les builds suivants sont mis en cache |
| `Permission denied` sur artefacts | Token GITHUB_TOKEN | L'action `upload-artifact` utilise le token auto — pas de config nécessaire |

---

## 📚 Références

- [firebelley/godot-export](https://github.com/firebelley/godot-export) — action Godot officielle communautaire
- [Godot 4.x Export Android](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_android.html)
- [GitHub Actions Artifacts](https://docs.github.com/en/actions/using-workflows/storing-workflow-data-as-artifacts)
- [softprops/action-gh-release](https://github.com/softprops/action-gh-release) — upload vers Releases