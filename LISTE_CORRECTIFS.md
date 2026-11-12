# Correctifs appliqués — revue de code « Niger Streets »

Tous les correctifs de la revue (R1–R3, B1–B7, P1–P11) sont appliqués. Références = fichiers après correction.

## Configuration export / projet

| ID | Correctif | Fichier |
|---|---|---|
| R1 | Package `com.example.$genname` → `com.nigerstreets.game` (les 2 presets) | `export_presets.cfg` l.46, l.273 |
| R2 | `export_path` défini → `build/NigerStreets.apk` | `export_presets.cfg` l.14 |
| R3 | Preset dédié **Android AAB (Play Store)** : `use_gradle_build=true`, `export_format=1`, `build/NigerStreets.aab` | `export_presets.cfg` l.231+ |
| P11 | `log_path="D:\Downloads\godot.log"` supprimé (logs → `user://` par défaut) | `project.godot` |

## Bugs corrigés (B)

| ID | Correctif | Fichier |
|---|---|---|
| B1 | Rotation radar inversée → `diff.rotated(player_yaw)` et nord `Vector2(0,-1).rotated(player_yaw)` | `radar.gd` l.57, l.73 |
| B2 | Course splash/world sur le GLB → `GameAssets.load_resource()` consomme le chargement threadé s'il existe, sinon charge en synchrone | `asset_loader.gd` l.8–14, `world.gd` l.122–134 |
| B3 | Garde après `await` d'entrée/sortie véhicule : `if not is_inside_tree() or not is_instance_valid(vehicle) or vehicle_state != … : return` | `player_controller.gd` l.527–528, l.568–569 |
| B4 | Lambdas sur timers protégés : `is_instance_valid(self)` (portière), `is_instance_valid(vehicle) and vehicle_state == …` | `vehicle.gd` l.387, `player_controller.gd` l.525–526, l.566–567 |
| B5 | Lambdas portières uniformisées avec garde d'état (`entering`/`exiting`) | `player_controller.gd` l.525, l.566 |
| B6 | Détection tactile : `OS.has_feature("mobile") or (tactile and not OS.has_feature("pc"))` — plus de faux positif sur laptop tactile | `player_controller.gd` l.109 |
| B7 | `LOOPING[anim_name]` → `LOOPING.get(anim_name, false)` (plus de KeyError) | `player_controller.gd` l.693 |

## Qualité / perfs mobile (P)

| ID | Correctif | Fichier |
|---|---|---|
| P1 | Tout l'audio converti **WAV → OGG Vorbis** (16 fichiers, ~11 Mo → ~1,1 Mo). Boucles gérées à l'exécution pour OGG | `assets/audio/*.ogg`, `asset_loader.gd` l.16–29 |
| P2 | Préchargement threadé pendant l'intro : voiture (`GameVehicle.MODEL_CANDIDATES`) + animations (`PlayerCharacter.ANIM_FILES`) — plus d'accroc au démarrage | `splash.gd` l.79–88 |
| P3 | `queue_redraw()` conditionnel : radar redessiné seulement si position/yaw changés ; contrôles tactiles redessinés sur événements, plus de boucle par frame | `radar.gd` l.29–37, `mobile_controls.gd` |
| P4 | Klaxon : lit `horn.ogg` à l'appui/relâchement ; le générateur temps réel n'est créé qu'en fichier audio absent | `vehicle.gd` l.492–503, l.520–522, l.560–563 |
| P5 | `debug_text` écrit et dessiné seulement si `show_seat_tuning` | `player_controller.gd` l.618, `mobile_controls.gd` l.164–170 |
| P6 | Ombres coupées sur mobile dans les deux scènes : `sun.shadow_enabled = not OS.has_feature("mobile")` | `splash.gd` l.265, `world.gd` l.373 |
| P7 | Décors du splash en **MultiMesh** (tirets + silhouettes de ville) : ~120 draw calls → 2 | `splash.gd` l.300–343 |
| P8 | Couple anti-tonneau proportionnel à la masse : `9000.0 * car_mass / 1400.0` | `vehicle.gd` l.447 |
| P9 | Fallback box : `body_center`/`body_half` recalculés cohérents avec la boîte de secours | `vehicle.gd` l.359–360 |
| P10 | Crédit asset nettoyé et centré : « Hennessy Vehnom GT 2010 – Eyasu Biyaylgn (CC-BY 4.0) » | `world.gd` l.80–95 |

## Non modifié (à valider sur appareil)

- **`shader_baker/enabled=false`** : volontairement laissé. Si accrocs la 1ʳᵉ minute sur GPU Mali → passer à `true` (voir `docs/ANDROID_EXPORT.md`).
- Le dossier `.godot/` (cache d'import) est exclu de l'archive livrée : Godot le régénère à la première ouverture.

---

## Ajout post-revue : menu pause + réglages (proposition 3)

| Élément | Fichier |
|---|---|
| Menu pause (Reprendre / Réglages / Menu principal / Quitter), ouverture par **Échap**, **bouton Android « retour »** ou **bouton à l'écran** sous le radar ; arbre du jeu en pause, couche en `PROCESS_MODE_ALWAYS` | `scripts/pause_menu.gd` (nouveau) |
| Réglages persistants dans `user://settings.cfg` : sensibilité caméra (×0,3–×3), volume général (bus Master), ombres on/off | `scripts/game_settings.gd` (nouveau) |
| Sensibilité appliquée à la souris **et** au tactile | `player_controller.gd` l.209–210 |
| Ombres pilotées par les réglages (soleils dans le groupe « main_sun »), défauts inchangés (mobile : off, PC : on) | `world.gd` l.375–376, `splash.gd` l.266 |
| Chargement des réglages au lancement (le splash est la scène initiale) | `splash.gd` l.76 |
| Menu instancié en dernier enfant du monde → son `_input` est appelé avant celui du joueur/hud | `world.gd` l.66 et l.609–613 |
| Bouton Android « retour » ouvre la pause au lieu de quitter l'app | `project.godot` l.23 (`config/quit_on_go_back=false`) |
| Timers des séquences (entrée/sortie véhicule, portière) respectent la pause — plus de téléportation si on met en pause pendant une montée | `player_controller.gd` l.490, l.527, l.568, `vehicle.gd` l.387 |
| Aide clavier mise à jour (« Échap : pause ») | `hud.gd` l.52 |

---

## Améliorations A1–A8 (pass « perfs & ressenti », rien de nouveau à jouer)

| # | Amélioration | Fichiers |
|---|---|---|
| A1 | Textures 3D en **VRAM compressée** (`compress/mode=2`) **+ mipmaps** : mémoire ÷4, chargement plus rapide, fini le scintillement au loin. Godot réimporte à la 1ʳᵉ ouverture de l'éditeur | `assets/textures/asphalt.png.import`, `road_arm.png.import` |
| A2 | **LOD** : au-delà de 240 m les meshes du véhicule ne sont plus dessinés (`visibility_range_end`) ; marquages au sol coupés à 180 m et exclus des ombres | `vehicle.gd` (`_apply_lod`, l.192–200, l.325, l.356), `world.gd` l.313–316 |
| A3 | **Plafond à 60 FPS** : sur écran 120 Hz le jeu ne chauffe plus la batterie pour rien | `project.godot` l.24 (`run/max_fps=60`) |
| A4 | **MSAA 2×** en qualité « haute » (avant : désactivé en dur) | `game_settings.gd` (`apply_viewport`), `splash.gd` l.231 |
| A5 | **FOV dynamique** : jusqu'à +9° avec la vitesse, à pied comme en voiture + **dolly lissé** de la longueur du bras entre « à pied » et « en voiture » (le lissage de position de `Camera3D` n'existe plus en Godot 4.7 → lissage manuel sur `spring_length`) | `player_controller.gd` l.66, l.222–236, l.293–294, l.602, l.614 |
| A6 | **Vibration aux chocs** sur mobile : 60–140 ms dosés par la violence de l'impact + permission `VIBRATE` activée dans les 2 presets | `vehicle.gd` l.567–568, `export_presets.cfg` l.214, l.441 |
| A7 | **Config soleil unifiée** : `GameSettings.apply_sun()` — ombres + `directional_shadow_max_distance = 65.0` partout (avant : 55.0 dans splash, 70.0 dans world) | `game_settings.gd` l.59–61, `splash.gd` l.266, `world.gd` l.375 |
| A8 | **Échelle de rendu 3D** : 85 % en mode « éco » (UI 2D toujours nette), 100 % en « haute » | `game_settings.gd` l.65–71 (`RENDER_SCALE_ECO`) |

Le bouton **« Ombres »** du menu pause devient **« Qualité : haute / éco »** et pilote A4 + A6/A7 (ombres) + A8 d'un seul toggle — `pause_menu.gd` (`_toggle_quality`, l.135–141, label l.220). L'ancienne clé de sauvegarde `video/shadows_enabled` est relue une dernière fois pour ne pas perdre le réglage déjà sauvegardé ; la nouvelle clé est `video/quality_high`.

**Réglages par défaut** : mobile → éco (pas d'ombres, MSAA off, rendu 85 %) ; PC → haute. Inchangés par rapport à avant.

---

## Correctifs Godot 4.7.2 (2 erreurs rouges du débogueur, retours de test)

| Erreur en rouge | Cause | Correctif |
|---|---|---|
| `PlayerCharacter._ready: Invalid assignment of property or key 'position_smoothing_speed' with value of type 'float' on a base object of type 'Camera3D'` | Godot 4.7 a **retiré** `position_smoothing_enabled`/`position_smoothing_speed` de `Camera3D` (vérifié dans la doc officielle de la branche 4.7) | Les 2 lignes supprimées ; lissage refait à la main : `_update_camera_distance(delta)` lisse `spring_arm.spring_length` (dolly doux entre à pied et en voiture). `fov_base = camera.fov` conservé | 
| `game_settings.gd:32 @ load_settings(): Couldn't find the given section "video" and key "quality_high", and no default was given.` | En Godot 4.7, `ConfigFile.get_value()` **provoque une erreur** quand la section/clé est absente et que le défaut est `null` | Lecture protégée par `has_section_key()` (jamais d'erreur) avant chaque `get_value` |

Non touché (warnings jaunes, sans impact) : shadowing des paramètres `position` / `name` dans `world.gd` et `player_controller.gd` — demandé tel quel.

---

## Correctif 2 erreurs « Impossible de résoudre la classe » (éditeur Godot 4.7.2)

Symptômes dans l'éditeur : `Erreur à (84, 35) : Impossible de résoudre la classe "GameVehicle", à cause d'une erreur d'analyse` (×2, la 2ᵉ sur `PlayerCharacter`) — alors même que le projet tournait.

| Cause | Correctif |
|---|---|
| Bug tokenizer de Godot 4.7 (**issue #96228** — reproduit et confirmé sur 4.7.2) : un fichier contenant une **lambda inline à corps `if`** peut faire échouer l'analyse du script ; tout script référençant la classe passe alors en rouge (`vehicle.gd` → GameVehicle, `player_controller.gd` → PlayerCharacter) | Les 5 lambdas à corps `if` remplacées par des **méthodes nommées** équivalentes (comportement identique) : `vehicle.gd` l.401 (`connect(_play_door_close)`, la connexion d'un objet libéré est retirée automatiquement par Godot) et `player_controller.gd` l.509–523 (`_enter_seq_door_open/_close`, `_exit_seq_door_open/_close` pilotées via `current_vehicle`) |
| Même famille de bug : fichier **sans saut de ligne final** + lambda | Saut de ligne final ajouté à `player_controller.gd`, `hud.gd`, `mobile_controls.gd`, `world.gd` (1 octet, sans effet sur le code) |

Vérifié sur Godot 4.7.2 exact (headless) : import complet OK, les 10 scripts chargent et instancient (`can_instantiate`), lancement du jeu 120 frames sans aucune erreur de script.

**Important — si des erreurs rouges restent affichées après mise à jour** : elles proviennent alors d'un cache d'analyse périmé dans le dossier du projet (extractions successives qui mélangent les versions). Procédure : 1) fermer Godot ; 2) supprimer le dossier caché `.godot` du projet (ou extraire ce zip dans un dossier **neuf**) ; 3) rouvrir le projet. Les erreurs fantômes disparaissent.

---

## Nouveau modèle du personnage : kidas_rigged_fbx_textures.fbx

Le personnage jouable utilise désormais l'export Mixamo **« with skin » + textures** fourni (FBX réexporté via Blender 4.2, texture **2048×2048 intégrée** contre l'ancienne 1024).

| Élément | Détail |
|---|---|
| Fichier | `assets/character/kidas_rigged_fbx_textures.fbx` (+ texture extraite `kidas_rigged_fbx_textures_0.png` par l'import) |
| Branchement | `scenes/player.tscn` — l'ext_resource `2_model` pointe vers le FBX (uid `uid://cl07xi4o7qlmo`) |
| Ancien modèle | `kidas_rigged.glb` + `kidas_rigged_0.jpg` **supprimés** du projet (non référencés, ils auraient alourdi l'APK) |
| Motion embarquée | Le FBX contient une motion « FreeRunning » dans son propre AnimationPlayer : il est mis `active = false` au démarrage par `_disable_nested_animation_players()` — vérifié en jeu (`active=false, playing=false`), aucune double animation |

### Correctif indispensable venu avec ce modèle : conversion d'axes du retargeting

Le FBX (export Blender) ne stocke pas son squelette comme l'ancien GLB :

| | Ancien GLB | Nouveau FBX |
|---|---|---|
| Os du bassin au repos | `(0 ; 0,870 ; −0,009)` — **Y-up** | `(0 ; 0,009 ; 0,870)` — **Z-up** |
| Compensation d'orientation | dans les os mêmes | sur le nœud `Armature` (rotation −90° X) |

Or les pistes d'animation Mixamo (Idle, Walking, …) sont exprimées en convention **Y-up** (celle qui marchait sur le GLB). Appliquées telles quelles aux os Z-up du FBX, elles faussent le bassin et le personnage se déforme.

Correction dans `player_controller.gd` :

1. **`_retarget_animation()`** : détection de l'orientation réelle du bassin cible (`get_bone_global_rest`) ; si elle n'est pas Y-up, les pistes **position** du bassin sont multipliées par l'échelle puis tournées dans la frame réelle de l'os (`up_to_axis_q * (v * k)`), et sa piste **rotation** est pré-multipliée pareil. Les os non racines n'ont pas besoin de conversion (ils héritent de la rotation par leur parent). Pour un squelette Y-up comme l'ancien GLB, la conversion vaut l'**identité** : comportement inchangé.
2. **`_hips_rest_height_m()`** (nouveau, remplace la lecture brute de `rest.y` dans `_hips_rest_m`/`_hips_scale`) : mesure la hauteur du bassin **le long de l'axe vertical réel**, quelle que soit la convention. Utilisée par le positionnement du siège de voiture et l'échelle cm→m des séquences d'entrée/sortie — sinon le perso s'asseyait ~9 cm trop bas et la séquence était décalée de ~10 %.

Vérifié sur Godot 4.7.2 exact (headless), **dans le vrai monde** (sol + physique), en comparant au build GLB validé sur téléphone :

| Mesure (perso immobile, Idle) | GLB (ancien build) | FBX + correctif |
|---|---|---|
| AABB du mesh | 0,03 → 1,78 m | 0,03 → 1,78 m |
| Hauteur du bassin | 0,900 m | 0,900 m |
| Pied gauche | 0,153–0,159 m | 0,153–0,159 m |
| Cycle de marche (amplitude du pied) | 0,162 m (σ 0,043) | 0,159 m (σ 0,043) |
| Les 8 animations (dont Jump, Driving, Entering/Exiting_Car) | — | aucune pose aberrante |
| Parse des 10 scripts / lancement complet du jeu | 0 erreur | 0 erreur |

**Pour revenir à l'ancien modèle** : il reste disponible dans le zip précédent (`NigerStreets_erreurs_corrigees.zip`), il suffit de le remettre dans `assets/character/` et de repointer l'ext_resource `2_model` de `player.tscn` — le code corrigé fonctionne avec les deux (conversion à l'identité pour le GLB).

---

## Filets de sécurité voiture : plus jamais de voiture « en l'air » ou sur le toit

Constat sur appareil (capture du 31/10) : une voiture peut se retrouver **en l'air** ou **retournée** après un choc ou une manip', et y rester (posée sur un obstacle, sur le joueur, ou figée). En jeu propre, la voiture se pose normalement (vérifié : spawn à y=0,6 → posée à h≈0 en 1 s, puis endormie).

| Filet | Comportement | Fichier |
|---|---|---|
| Anti-flottement | Voiture **inoccupée** immobile (< 1,2 m/s) flottant à **plus de 0,9 m** au-dessus du premier support solide pendant **2,5 s** → reposée sur ce support (x/z conservés). Le rayon exclut la voiture elle-même et ignore le joueur (CharacterBody3D) comme support | `vehicle.gd` (`_anti_stuck`, `_ground_below`) |
| Anti-retournement | Voiture inoccupée **sur le toit ou sur le côté** (upness < 0,35) immobile pendant **3 s** → redressée sur ses roues en conservant son cap (`_re_right`) | `vehicle.gd` (`_anti_stuck`, `_re_right`) |
| Conduite préservée | Tant que `is_player_driving` est vrai, **rien ne bouge** : sauts, rampes et décollages pendant la conduite ne sont jamais corrigés de force | `vehicle.gd` |

Tests sur Godot 4.7.2 exact (headless) :

- Voiture garée au spawn : posée, endormie, **aucun filet déclenché** en 600 frames (pas de faux positif) ;
- Voiture forcée de flotter à 2,5 m (gravité coupée) : reposée au sol **exactement après 2,5 s** ;
- Voiture retournée sur le toit : redressée (upness −1,00 → 1,00) **exactement après 3 s**, posée à h≈0 ;
- Lâchée de 3 m au-dessus du joueur : glisse et se pose normalement (la voiture ne reste pas sur le joueur) ;
- Parse des 10 scripts : 0 erreur.

