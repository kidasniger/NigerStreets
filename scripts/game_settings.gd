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

static var loaded: bool = false
## Multiplicateur appliqué à la sensibilité caméra (souris et tactile)
static var camera_sensitivity: float = 1.0
## Volume général (bus Master), de 0 à 1
static var master_volume: float = 1.0
## Qualité graphique : haute = ombres + MSAA 2x + rendu 3D pleine résolution ;
## éco = sans ombres, MSAA off, rendu 3D à RENDER_SCALE_ECO. Remplace l'ancien
## réglage « ombres » (l'ancienne clé de sauvegarde est relue pour la compatibilité).
static var quality_high: bool = false

static func load_settings() -> void:
        if loaded:
                return
        loaded = true
        quality_high = not OS.has_feature("mobile")   # même défaut qu'avant le menu : pas d'ombres sur mobile
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
        apply_audio()

static func save_settings() -> void:
        var cf := ConfigFile.new()
        cf.set_value("game", "camera_sensitivity", camera_sensitivity)
        cf.set_value("audio", "master_volume", master_volume)
        cf.set_value("video", "quality_high", quality_high)
        cf.save(SAVE_PATH)

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
        sun.shadow_enabled = quality_high
        sun.directional_shadow_max_distance = SUN_SHADOW_DISTANCE

## Applique la qualité au viewport : MSAA 2x + pleine résolution en « haute »,
## MSAA off + rendu 3D réduit en « éco » (l'interface 2D reste à la résolution native)
static func apply_viewport(vp: Viewport) -> void:
        if quality_high:
                vp.msaa_3d = Viewport.MSAA_2X
                vp.scaling_3d_scale = 1.0
        else:
                vp.msaa_3d = Viewport.MSAA_DISABLED
                vp.scaling_3d_scale = RENDER_SCALE_ECO
