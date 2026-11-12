# Export Android 📱

Projet configuré pour Godot 4.7.2 — deux presets prêts dans `export_presets.cfg` :

| Preset | Fichier | Usage |
|---|---|---|
| **Android** | `build/NigerStreets.apk` | Tests sur téléphone (install directe) |
| **Android AAB (Play Store)** | `build/NigerStreets.aab` | Upload Google Play |

Identifiant du paquet : `com.nigerstreets.game` — architecture `arm64-v8a` uniquement, textures ETC2/ASTC activées.

## Étapes dans Godot

1. **Android SDK + OpenJDK 17** : `Éditeur > Paramètres d'éditeur > Export > Android`, renseigner le chemin du SDK et du JDK.
2. **Templates d'export** : `Éditeur > Gérer les templates d'export` → installer les templates **4.7.2** correspondant à ta version exacte.
3. **Tester** : `Projet > Export… > Android` → `Exporter le projet` → le `.apk` sort dans `build/`. L'APK est signé avec la clé debug : installable via `adb install build/NigerStreets.apk`.
4. **Play Store** : exporter avec le preset **Android AAB (Play Store)** (gradle build activé, format `.aab`). Il faut un **keystore de release** : `Projet > Export… > Options de keystore` (ou variables `GODOT_ANDROID_KEYSTORE_*`). Un AAB non signé en release sera refusé par la console Play.
5. **Premier export gradle** : long (téléchargement des dépendances gradle) — c'est normal, les suivants sont rapides.

## Notes

- **shader_baker/enabled = false** (les deux presets). C'est voulu pour un premier export sans friction. Si tu constates des **accrocs la première minute** de jeu sur GPU Mali (compilation de shaders à la volée), repasse l'option à `true` : les shaders seront précompilés à l'export (export plus long, package un peu plus gros).
- Le fichier `.godot/` n'est pas requis dans l'archive : Godot le régénère (réimport des assets) à la première ouverture du projet.
- La détection tactile combine `OS.has_feature("mobile")` et l'écran tactile : sur un laptop tactile, l'UI mobile ne s'activera pas.

Référence officielle : documentation Godot 4.x sur l'export Android.
