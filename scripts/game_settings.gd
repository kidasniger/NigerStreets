extends RefCounted
class_name GameSettings
# Ch31 - Réglages persistants du menu pause : sensibilité caméra, volume, qualité graphique.
# Stockés dans user://settings.cfg, appliqués au bus Master, aux soleils du groupe "main_sun"
# et au viewport (MSAA + échelle de rendu 3D).

const SAVE_PATH: String = "user://settings.cfg"
## Distance d'ombre unifiée du soleil (avant : 55.0 dans splash.gd, 70.0 dans world.gd)
const SUN_SHADOW_DISTANCE: float = 65.0
## Échelle de rendu 3D en mode « éco » : 85 % de la résolution, perte quasi invisible, FPS en plus
const RENDER_SCALE_ECO: float = 0.85
## Distance d'affichage du streamer : [rayon de chargement, rayon de déchargement] en mètres.
## 0 = courte, 1 = normale (valeurs d'origine), 2 = longue.
const VIEW_DISTANCES: Array = [[300.0, 450.0], [450.0, 650.0], [600.0, 850.0]]

static var loaded: bool = false
## Multiplicateur appliqué à la sensibilité caméra (souris et tactile)
static var camera_sensitivity: float = 1.0
## Volume général (bus Master), de 0 à 1
static var master_volume: float = 1.0
## Qualité graphique : haute = ombres + MSAA 2x + rendu 3D pleine résolution ;
## éco = sans ombres, MSAA off, rendu 3D à RENDER_SCALE_ECO. Remplace l'ancien
## réglage « ombres » (l'ancienne clé de sauvegarde est relue pour la compatibilité).
static var quality_high: bool = false
## Vibration aux chocs (mobile) : activée/désactivée dans le menu pause
static var vibration_enabled: bool = true
## Distance d'affichage : 0 courte, 1 normale, 2 longue (voir VIEW_DISTANCES)
static var view_distance: int = 1
## Choix autorisés pour la limite de FPS
const FPS_CHOICES: Array[int] = [30, 45, 60]
## Limite de FPS (Engine.max_fps) : 30, 45 ou 60 (défaut : 60, comme project.godot)
static var fps_limit: int = 60
## Mode batterie : seuils d'activation / de retour (hystérésis) et limite de FPS imposée
const BATTERY_LOW_PERCENT: int = 20
const BATTERY_OK_PERCENT: int = 25
const BATTERY_FPS: int = 30
## Mode batterie automatique : sous 20 % (hors charge), qualité éco + 30 FPS + distance courte
static var auto_battery: bool = true
## État temporaire (jamais sauvegardé) : vrai quand l'économie d'énergie est appliquée
static var battery_saver_active: bool = false
## Compteur de performance (FPS, draw calls, triangles) affiché à l'écran
static var show_perf: bool = false
## Rendu réduit à grande vitesse en voiture : seuils (km/h), échelle de rendu 3D, délai minimum entre deux changements
const SPEED_ON_KMH: float = 60.0
const SPEED_OFF_KMH: float = 45.0
const SPEED_RENDER_SCALE: float = 0.7
const SPEED_MIN_INTERVAL_MS: int = 2000
## Réglage « Réduire le rendu à grande vitesse » (activé par défaut sur mobile)
static var speed_scale: bool = true
## État temporaire (jamais sauvegardé) : vrai quand le rendu est réduit à cause de la vitesse
static var speed_reduced: bool = false
static var _speed_changed_ms: int = 0

static func load_settings() -> void:
        if loaded:
                return
        loaded = true
        quality_high = not OS.has_feature("mobile")   # même défaut qu'avant le menu : pas d'ombres sur mobile
        speed_scale = OS.has_feature("mobile")
        var cf := ConfigFile.new()
        if cf.load(SAVE_PATH) == OK:
                camera_sensitivity = clampf(float(cf.get_value("game", "camera_sensitivity", 1.0)), 0.3, 3.0)
                master_volume = clampf(float(cf.get_value("audio", "master_volume", 1.0)), 0.0, 1.0)
                # Godot 4.7 : get_value(...) avec un défaut null ERREUR si la clé manque.
                # On teste donc les clés avant lecture (has_section_key ne renvoie jamais d'erreur).
                if cf.has_section_key("video", "quality_high"):
                        quality_high = bool(cf.get_value("video", "quality_high", quality_high))
                elif cf.has_section_key("video", "shadows_enabled"):   # ancienne clé (sauvegardes d'avant la case « Qualité »)
                        quality_high = bool(cf.get_value("video", "shadows_enabled", quality_high))
                if cf.has_section_key("game", "vibration"):
                        vibration_enabled = bool(cf.get_value("game", "vibration", true))
                if cf.has_section_key("game", "view_distance"):
                        view_distance = clampi(int(cf.get_value("game", "view_distance", 1)), 0, 2)
                if cf.has_section_key("video", "fps_limit"):
                        fps_limit = sanitize_fps(int(cf.get_value("video", "fps_limit", 60)))
                if cf.has_section_key("video", "auto_battery"):
                        auto_battery = bool(cf.get_value("video", "auto_battery", true))
                if cf.has_section_key("video", "show_perf"):
                        show_perf = bool(cf.get_value("video", "show_perf", false))
                if cf.has_section_key("video", "speed_scale"):
                        speed_scale = bool(cf.get_value("video", "speed_scale", true))
        apply_audio()
        apply_fps()

static func save_settings() -> void:
        var cf := ConfigFile.new()
        cf.set_value("game", "camera_sensitivity", camera_sensitivity)
        cf.set_value("audio", "master_volume", master_volume)
        cf.set_value("video", "quality_high", quality_high)
        cf.set_value("game", "vibration", vibration_enabled)
        cf.set_value("game", "view_distance", view_distance)
        cf.set_value("video", "fps_limit", fps_limit)
        cf.set_value("video", "auto_battery", auto_battery)
        cf.set_value("video", "show_perf", show_perf)
        cf.set_value("video", "speed_scale", speed_scale)
        cf.save(SAVE_PATH)

## Remet tous les réglages à leurs valeurs par défaut (bouton « Réglages par défaut » du menu pause)
static func reset_defaults() -> void:
        camera_sensitivity = 1.0
        master_volume = 1.0
        quality_high = not OS.has_feature("mobile")   # même défaut qu'au premier lancement
        speed_scale = OS.has_feature("mobile")
        vibration_enabled = true
        view_distance = 1
        fps_limit = 60
        auto_battery = true
        show_perf = false
        save_settings()
        apply_audio()
        apply_fps()

static func apply_audio() -> void:
        var bus: int = AudioServer.get_bus_index("Master")
        AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(master_volume, 0.0001)))
        AudioServer.set_bus_mute(bus, master_volume <= 0.001)

## Applique la qualité à tous les soleils enregistrés dans le groupe "main_sun"
static func apply_shadows(tree: SceneTree) -> void:
        for node in tree.get_nodes_in_group("main_sun"):
                var sun := node as DirectionalLight3D
                if sun != null:
                        apply_sun(sun)

## Configure un soleil : ombres + distance d'ombre identiques partout
## (le menu pause pilote les soleils du groupe "main_sun" via apply_shadows)
static func apply_sun(sun: DirectionalLight3D) -> void:
        sun.shadow_enabled = is_high_quality()
        sun.directional_shadow_max_distance = SUN_SHADOW_DISTANCE

## Applique la qualité au viewport : MSAA 2x + pleine résolution en « haute »,
## MSAA off + rendu 3D réduit en « éco » (l'interface 2D reste à la résolution native)
static func apply_viewport(vp: Viewport) -> void:
        if is_high_quality():
                vp.msaa_3d = Viewport.MSAA_2X
                vp.scaling_3d_scale = 1.0
        else:
                vp.msaa_3d = Viewport.MSAA_DISABLED
                vp.scaling_3d_scale = RENDER_SCALE_ECO
        if speed_reduced:
                vp.scaling_3d_scale = minf(vp.scaling_3d_scale, SPEED_RENDER_SCALE)

## Applique la distance d'affichage aux streamers du groupe "zinder_streamer"
static func apply_view_distance(tree: SceneTree) -> void:
        for node in tree.get_nodes_in_group("zinder_streamer"):
                set_streamer_radii(node)

## Règle les rayons de chargement/déchargement d'un streamer (il les relit toutes les 0,4 s)
static func set_streamer_radii(streamer: Node) -> void:
        var level: int = 0 if battery_saver_active else view_distance
        var pair: Array = VIEW_DISTANCES[clampi(level, 0, 2)]
        streamer.set("load_radius", float(pair[0]))
        streamer.set("unload_radius", float(pair[1]))

## Ramène une valeur lue du fichier à un choix autorisé (60 par défaut)
static func sanitize_fps(value: int) -> int:
        return value if FPS_CHOICES.has(value) else 60

## Applique la limite de FPS (Engine.max_fps)
static func apply_fps() -> void:
        Engine.max_fps = mini(BATTERY_FPS, fps_limit) if battery_saver_active else fps_limit

## Qualité réellement appliquée : le réglage de l'utilisateur, sauf en mode batterie (éco forcé)
static func is_high_quality() -> bool:
        return quality_high and not battery_saver_active

## Lit la batterie Android (Intent BATTERY_CHANGED, sans permission) : renvoie [pourcentage, en_charge],
## ou [-1, false] si indisponible (PC, éditeur, erreur). Godot 4 n'a pas d'API batterie native.
static func read_battery() -> Array:
        if not OS.has_feature("android") or not Engine.has_singleton("AndroidRuntime"):
                return [-1, false]
        var runtime = Engine.get_singleton("AndroidRuntime")
        var filter_class = JavaClassWrapper.wrap("android.content.IntentFilter")
        if runtime == null or filter_class == null:
                return [-1, false]
        var context = runtime.getApplicationContext()
        if context == null:
                return [-1, false]
        var filter = filter_class.IntentFilter("android.intent.action.BATTERY_CHANGED")
        var intent = context.registerReceiver(null, filter)
        if intent == null:
                return [-1, false]
        var level: int = int(intent.getIntExtra("level", -1))
        var scale: int = int(intent.getIntExtra("scale", 100))
        var plugged: int = int(intent.getIntExtra("plugged", 0))
        if level < 0 or scale <= 0:
                return [-1, false]
        return [level * 100 / scale, plugged > 0]

## Niveau de batterie en % (0-100), ou -1 si indisponible
static func battery_percent() -> int:
        return int(read_battery()[0])

## Vrai si l'appareil est en charge (ou chargé)
static func battery_charging() -> bool:
        return bool(read_battery()[1])

## Met à jour le mode batterie (hystérésis 20 % / 25 %) ; réapplique ombres, rendu, FPS et distance si l'état change
static func update_battery(tree: SceneTree, vp: Viewport) -> void:
        var want: bool = false
        if auto_battery:
                var info: Array = read_battery()
                var pct: int = int(info[0])
                if pct >= 0 and not bool(info[1]):
                        if battery_saver_active:
                                want = pct < BATTERY_OK_PERCENT
                        else:
                                want = pct < BATTERY_LOW_PERCENT
        if want == battery_saver_active:
                return
        battery_saver_active = want
        apply_shadows(tree)
        apply_viewport(vp)
        apply_fps()
        apply_view_distance(tree)

## Réduit le rendu 3D à grande vitesse (hystérésis 60 / 45 km/h, au plus un changement toutes les 2 s)
static func update_speed(kmh: float, vp: Viewport) -> void:
        var want: bool = speed_reduced
        if not speed_scale:
                want = false
        elif kmh >= SPEED_ON_KMH:
                want = true
        elif kmh < SPEED_OFF_KMH:
                want = false
        if want == speed_reduced:
                return
        var now: int = Time.get_ticks_msec()
        if speed_scale and now - _speed_changed_ms < SPEED_MIN_INTERVAL_MS:
                return
        _speed_changed_ms = now
        speed_reduced = want
        apply_viewport(vp)
