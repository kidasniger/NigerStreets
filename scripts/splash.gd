extends Control
# Niger Streets - Écran titre
# Décor 3D réel (monument texturé, asphalte, silhouettes de ville, coucher de soleil, brume, glow)
# en caméra orbitale + logo avec reflet + braises lumineuses + vignette + barre de chargement.
# Le monde est chargé en arrière-plan PENDANT l'animation, puis fondu vers le jeu.

const NEXT_SCENE := "res://scenes/world.tscn"
const ROUNDABOUT := "res://assets/environment/rond-point-elf.glb"
const LOGO := "res://assets/branding/logo.png"
const ASPHALT := "res://assets/textures/asphalt.png"
const BG_COLOR := Color(0.025, 0.035, 0.06, 1.0)
const GOLD := Color(1.0, 0.72, 0.20, 1.0)

## true = attend un toucher/clic sur « Touchez pour commencer » ; false = enchaîne tout seul
@export var wait_for_tap: bool = true
## Pause (en secondes) entre « Prêt » et le fondu vers le jeu (si wait_for_tap = false)
@export var hold_after_loaded: float = 0.6
@export var roundabout_scale: float = 6.0
@export var orbit_radius: float = 17.0
@export var orbit_height: float = 3.4
@export var orbit_speed: float = 0.07

const SHINE_SHADER := """
shader_type canvas_item;
uniform float sweep = -0.5;
void fragment() {
        float band = smoothstep(0.14, 0.0, abs((UV.x + UV.y * 0.35) - sweep));
        COLOR.rgb += vec3(1.0, 0.92, 0.72) * band * 0.6 * COLOR.a;
}
"""

class LoadBar extends Control:
        const BAR_GOLD := Color(1.0, 0.72, 0.20, 1.0)
        var progress: float = 0.0

        func _draw() -> void:
                var y: float = size.y * 0.5
                draw_line(Vector2(0.0, y), Vector2(size.x, y), Color(1.0, 1.0, 1.0, 0.16), 5.0, true)
                var w: float = size.x * clampf(progress, 0.0, 1.0)
                if w > 0.0:
                        draw_line(Vector2(0.0, y), Vector2(w, y), BAR_GOLD, 5.0, true)
                        draw_circle(Vector2(w, y), 7.0, Color(1.0, 0.95, 0.8))

# ------------------------------------------------------------------ état

var view: SubViewportContainer
var vp: SubViewport
var cam: Camera3D
var shade: TextureRect
var vignette: TextureRect
var embers: CPUParticles2D
var logo: TextureRect
var shine_mat: ShaderMaterial
var loadbar: LoadBar
var status: Label
var prompt: Label
var version_label: Label
var fade: ColorRect

var _tween: Tween
var _packed: PackedScene = null
var _loaded: bool = false
var _target: float = 0.0
var _intro_done: bool = false
var _tapped: bool = false
var _leaving: bool = false
var _ready_time: float = 0.0
var _t: float = 0.0
var _orbit: float = 0.6
var _dolly: float = 0.0
var _portrait: bool = false
var _mon_done: bool = false


func _ready() -> void:
        GameSettings.load_settings()   # le splash est la scène initiale : charge les réglages au lancement
        if OS.has_feature("mobile"):
                DisplayServer.screen_set_orientation(DisplayServer.SCREEN_LANDSCAPE)
        # Chargements en arrière-plan : monument (pour le décor) + jeu complet
        ResourceLoader.load_threaded_request(ROUNDABOUT)
        ResourceLoader.load_threaded_request(NEXT_SCENE)
        # Préchargement des gros assets du monde (modèle voiture + animations Mixamo) pendant l'intro :
        # plus d'accroc au démarrage de la partie (GameAssets.load_resource consommera le cache).
        for model_path: String in GameVehicle.MODEL_CANDIDATES:
                if ResourceLoader.exists(model_path):
                        ResourceLoader.load_threaded_request(model_path)
        for anim_path: String in PlayerCharacter.ANIM_FILES.values():
                if ResourceLoader.exists(anim_path):
                        ResourceLoader.load_threaded_request(anim_path)
        _build()
        _layout()
        resized.connect(_layout)
        _play_intro()


func _add(node: Control) -> void:
        node.mouse_filter = Control.MOUSE_FILTER_IGNORE
        add_child(node)


func _make_label(color: Color) -> Label:
        var label := Label.new()
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        label.add_theme_color_override("font_color", color)
        label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
        label.add_theme_constant_override("outline_size", 6)
        return label


func _radial_tex(inner: Color, outer: Color, size_px: int, mid: float = 0.5, mid_color: Color = Color(0, 0, 0, 0)) -> GradientTexture2D:
        var g := Gradient.new()
        g.offsets = PackedFloat32Array([0.0, mid, 1.0])
        g.colors = PackedColorArray([inner, mid_color, outer])
        var gt := GradientTexture2D.new()
        gt.gradient = g
        gt.fill = GradientTexture2D.FILL_RADIAL
        gt.fill_from = Vector2(0.5, 0.5)
        gt.fill_to = Vector2(1.0, 1.0)
        gt.width = size_px
        gt.height = size_px
        return gt


func _build() -> void:
        var bg := ColorRect.new()
        bg.color = BG_COLOR
        bg.set_anchors_preset(Control.PRESET_FULL_RECT)
        _add(bg)

        _build_3d()

        # Dégradé bas d'écran (lisibilité de la barre / du texte)
        var g := Gradient.new()
        g.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
        g.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0.01, 0.015, 0.03, 0.8)])
        var gt := GradientTexture2D.new()
        gt.gradient = g
        gt.fill = GradientTexture2D.FILL_LINEAR
        gt.fill_from = Vector2(0.0, 0.0)
        gt.fill_to = Vector2(0.0, 1.0)
        gt.width = 4
        gt.height = 256
        shade = TextureRect.new()
        shade.texture = gt
        shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        shade.stretch_mode = TextureRect.STRETCH_SCALE
        shade.set_anchors_preset(Control.PRESET_FULL_RECT)
        _add(shade)

        # Vignette
        vignette = TextureRect.new()
        vignette.texture = _radial_tex(Color(0, 0, 0, 0), Color(0, 0, 0, 0.9), 256, 0.45)
        vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        vignette.stretch_mode = TextureRect.STRETCH_SCALE
        vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
        _add(vignette)

        # Braises lumineuses qui montent
        embers = CPUParticles2D.new()
        embers.amount = 40
        embers.lifetime = 9.0
        embers.preprocess = 9.0
        embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
        embers.emission_rect_extents = Vector2(640.0, 8.0)
        embers.direction = Vector2(0.25, -1.0)
        embers.spread = 22.0
        embers.gravity = Vector2.ZERO
        embers.initial_velocity_min = 26.0
        embers.initial_velocity_max = 70.0
        embers.scale_amount_min = 0.35
        embers.scale_amount_max = 1.0
        embers.texture = _radial_tex(Color(1, 1, 1, 1), Color(1, 1, 1, 0), 32, 0.4, Color(1, 1, 1, 0.5))
        embers.color = Color(1.0, 0.72, 0.30, 0.9)
        var ramp := Gradient.new()
        ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
        ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
        embers.color_ramp = ramp
        var add_mat := CanvasItemMaterial.new()
        add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
        embers.material = add_mat
        add_child(embers)

        # Logo + reflet
        logo = TextureRect.new()
        if ResourceLoader.exists(LOGO):
                logo.texture = load(LOGO) as Texture2D
        logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        logo.modulate.a = 0.0
        var sh := Shader.new()
        sh.code = SHINE_SHADER
        shine_mat = ShaderMaterial.new()
        shine_mat.shader = sh
        shine_mat.set_shader_parameter("sweep", -0.5)
        logo.material = shine_mat
        _add(logo)

        loadbar = LoadBar.new()
        loadbar.modulate.a = 0.0
        _add(loadbar)

        status = _make_label(Color(1.0, 1.0, 1.0, 0.8))
        status.modulate.a = 0.0
        _add(status)

        prompt = _make_label(Color(1.0, 0.9, 0.65, 1.0))
        prompt.text = "TOUCHEZ POUR COMMENCER" if DisplayServer.is_touchscreen_available() else "CLIQUEZ OU APPUYEZ SUR UNE TOUCHE"
        prompt.visible = false
        _add(prompt)

        version_label = _make_label(Color(1.0, 1.0, 1.0, 0.45))
        version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
        version_label.text = "v" + str(ProjectSettings.get_setting("application/config/version", "1.0"))
        _add(version_label)

        fade = ColorRect.new()
        fade.color = Color(0.0, 0.0, 0.0, 1.0)
        fade.set_anchors_preset(Control.PRESET_FULL_RECT)
        _add(fade)


func _build_3d() -> void:
        view = SubViewportContainer.new()
        view.stretch = true
        view.set_anchors_preset(Control.PRESET_FULL_RECT)
        _add(view)

        vp = SubViewport.new()
        vp.own_world_3d = true
        GameSettings.apply_viewport(vp)   # MSAA + échelle de rendu 3D selon la case qualité
        vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
        view.add_child(vp)

        # Ciel de coucher de soleil + brume chaude + glow
        var sky_mat := ProceduralSkyMaterial.new()
        sky_mat.sky_top_color = Color(0.05, 0.09, 0.24)
        sky_mat.sky_horizon_color = Color(0.98, 0.55, 0.24)
        sky_mat.ground_horizon_color = Color(0.70, 0.38, 0.22)
        sky_mat.ground_bottom_color = Color(0.08, 0.06, 0.08)
        var sky := Sky.new()
        sky.sky_material = sky_mat
        var env := Environment.new()
        env.background_mode = Environment.BG_SKY
        env.sky = sky
        env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
        env.ambient_light_energy = 0.85
        env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
        env.tonemap_exposure = 1.05
        env.fog_enabled = true
        env.fog_light_color = Color(0.95, 0.56, 0.30)
        env.fog_density = 0.018
        env.fog_sky_affect = 0.3
        env.glow_enabled = true
        env.glow_intensity = 0.7
        env.glow_bloom = 0.08
        var we := WorldEnvironment.new()
        we.environment = env
        vp.add_child(we)

        # Soleil bas, lumière dorée + ombres
        var sun := DirectionalLight3D.new()
        sun.rotation_degrees = Vector3(-13.0, -38.0, 0.0)
        sun.light_color = Color(1.0, 0.70, 0.42)
        sun.light_energy = 2.0
        GameSettings.apply_sun(sun)   # ombres + distance d'ombre unifiées avec world.gd et le menu réglages
        vp.add_child(sun)

        # Sol en asphalte texturé
        var ground := MeshInstance3D.new()
        var pm := PlaneMesh.new()
        pm.size = Vector2(600.0, 600.0)
        ground.mesh = pm
        var gm := StandardMaterial3D.new()
        gm.albedo_color = Color(0.16, 0.16, 0.18)
        gm.roughness = 0.92
        if ResourceLoader.exists(ASPHALT):
                gm.albedo_texture = load(ASPHALT) as Texture2D
                gm.albedo_color = Color(0.72, 0.72, 0.76)
                gm.uv1_scale = Vector3(110.0, 110.0, 1.0)
                gm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
        ground.material_override = gm
        vp.add_child(ground)

        # Socle (îlot) du monument
        var base := MeshInstance3D.new()
        var cyl := CylinderMesh.new()
        cyl.top_radius = 4.3
        cyl.bottom_radius = 4.5
        cyl.height = 0.3
        cyl.radial_segments = 48
        base.mesh = cyl
        var bmat := StandardMaterial3D.new()
        bmat.albedo_color = Color(0.42, 0.42, 0.44)
        bmat.roughness = 0.85
        base.material_override = bmat
        base.position = Vector3(0.0, 0.15, 0.0)
        vp.add_child(base)

        # Marquage au sol : tirets blancs circulaires (MultiMesh = 1 seul draw call)
        var dash_mesh := BoxMesh.new()
        dash_mesh.size = Vector3(1.6, 0.02, 0.22)
        var dash_mat := StandardMaterial3D.new()
        dash_mat.albedo_color = Color(0.9, 0.88, 0.8)
        dash_mat.roughness = 0.7
        dash_mesh.material = dash_mat
        var dashes := MultiMesh.new()
        dashes.transform_format = MultiMesh.TRANSFORM_3D
        dashes.mesh = dash_mesh
        dashes.instance_count = 56
        for i in 56:
                var a: float = TAU * float(i) / 56.0
                dashes.set_instance_transform(i, Transform3D(Basis(Vector3.UP, -(a + PI * 0.5)), Vector3(cos(a) * 12.0, 0.015, sin(a) * 12.0)))
        var dash_instance := MultiMeshInstance3D.new()
        dash_instance.multimesh = dashes
        dash_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        vp.add_child(dash_instance)

        # Silhouettes de ville à l'horizon (noyées dans la brume) - MultiMesh = 1 seul draw call
        var rng := RandomNumberGenerator.new()
        rng.seed = 227
        var city_mat := StandardMaterial3D.new()
        city_mat.albedo_color = Color(0.10, 0.10, 0.13)
        city_mat.roughness = 0.9
        var unit_box := BoxMesh.new()
        unit_box.size = Vector3.ONE
        var buildings := MultiMesh.new()
        buildings.transform_format = MultiMesh.TRANSFORM_3D
        buildings.mesh = unit_box
        buildings.instance_count = 64
        for i in 64:
                var a2: float = rng.randf() * TAU
                var d: float = rng.randf_range(55.0, 125.0)
                var h: float = rng.randf_range(7.0, 34.0)
                var sx: float = rng.randf_range(6.0, 16.0)
                var sz: float = rng.randf_range(6.0, 16.0)
                var b_basis := Basis(Vector3.UP, a2 + rng.randf_range(-0.3, 0.3)).scaled(Vector3(sx, h, sz))
                buildings.set_instance_transform(i, Transform3D(b_basis, Vector3(cos(a2) * d, h * 0.5, sin(a2) * d)))
        var city_instance := MultiMeshInstance3D.new()
        city_instance.multimesh = buildings
        city_instance.material_override = city_mat
        city_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        vp.add_child(city_instance)

        cam = Camera3D.new()
        cam.fov = 52.0
        cam.near = 0.1
        cam.far = 500.0
        vp.add_child(cam)
        cam.current = true
        _update_camera(0.0)


func _poll_monument() -> void:
        if _mon_done:
                return
        var st: int = ResourceLoader.load_threaded_get_status(ROUNDABOUT)
        if st == ResourceLoader.THREAD_LOAD_LOADED:
                var packed: PackedScene = ResourceLoader.load_threaded_get(ROUNDABOUT) as PackedScene
                if packed != null:
                        var node: Node3D = packed.instantiate() as Node3D
                        if node != null:
                                # Même placement que dans le jeu
                                node.scale = Vector3.ONE * roundabout_scale
                                node.position = Vector3(0.0, roundabout_scale, 0.0)
                                vp.add_child(node)
                _mon_done = true
        elif st != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
                _mon_done = true


func _update_camera(delta: float) -> void:
        if cam == null:
                return
        _orbit += delta * orbit_speed
        var r: float = orbit_radius - 3.0 * _dolly
        var pos := Vector3(cos(_orbit) * r, orbit_height + sin(_t * 0.45) * 0.12, sin(_orbit) * r)
        cam.position = pos
        var center := Vector3(0.0, 5.0, 0.0)
        var fwd: Vector3 = (center - pos).normalized()
        var right: Vector3 = fwd.cross(Vector3.UP).normalized()
        var vs: Vector2 = get_viewport_rect().size
        var aspect: float = vs.x / maxf(vs.y, 1.0)
        var half_w: float = tan(deg_to_rad(cam.fov * 0.5)) * r * aspect
        # Paysage : le monument passe à droite pour laisser la place au logo ; portrait : il descend
        var shift: float = 0.0 if _portrait else 0.36 * half_w
        var up_off: float = 3.5 if _portrait else 0.0
        cam.look_at(center - right * shift + Vector3(0.0, up_off, 0.0), Vector3.UP)


func _layout() -> void:
        var vs: Vector2 = get_viewport_rect().size
        _portrait = vs.x < vs.y * 1.1
        var ls: float
        var c: Vector2
        if _portrait:
                ls = minf(vs.x * 0.86, vs.y * 0.5)
                c = Vector2(vs.x * 0.5, vs.y * 0.30)
        else:
                ls = minf(vs.y * 0.80, vs.x * 0.46)
                c = Vector2(vs.x * 0.27, vs.y * 0.46)
        logo.size = Vector2(ls, ls)
        logo.position = c - logo.size * 0.5
        logo.pivot_offset = logo.size * 0.5

        var u: float = minf(vs.y, vs.x * 0.5625)
        loadbar.size = Vector2(vs.x * 0.34, 20.0)
        loadbar.position = Vector2((vs.x - loadbar.size.x) * 0.5, vs.y * 0.92)
        status.add_theme_font_size_override("font_size", int(u * 0.032))
        status.size = Vector2(vs.x, 28.0)
        status.position = Vector2(0.0, vs.y * 0.92 + 20.0)
        prompt.add_theme_font_size_override("font_size", int(u * 0.045))
        prompt.size = Vector2(vs.x, 48.0)
        prompt.position = Vector2(0.0, vs.y * 0.88)
        version_label.add_theme_font_size_override("font_size", int(u * 0.028))
        version_label.size = Vector2(vs.x * 0.2, 28.0)
        version_label.position = Vector2(vs.x * 0.8 - 16.0, vs.y - 40.0)

        embers.position = Vector2(vs.x * 0.5, vs.y * 1.03)
        embers.emission_rect_extents = Vector2(vs.x * 0.5, 8.0)


func _play_intro() -> void:
        _tween = create_tween().set_parallel(true)
        var tw: Tween = _tween
        tw.tween_property(fade, "color:a", 0.0, 1.0)
        tw.tween_property(self, "_dolly", 1.0, 7.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
        logo.scale = Vector2(0.88, 0.88)
        tw.tween_property(logo, "modulate:a", 1.0, 0.9).set_delay(0.7)
        tw.tween_property(logo, "scale", Vector2.ONE, 1.1).set_delay(0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
        tw.tween_property(shine_mat, "shader_parameter/sweep", 1.5, 1.2).set_delay(1.9)
        tw.tween_property(loadbar, "modulate:a", 1.0, 0.5).set_delay(1.2)
        tw.tween_property(status, "modulate:a", 1.0, 0.5).set_delay(1.2)
        tw.tween_callback(func() -> void: _intro_done = true).set_delay(2.6)


func _process(delta: float) -> void:
        _t += delta
        _poll_monument()
        _update_camera(delta)
        if _intro_done and logo.modulate.a >= 0.99:
                var pulse: float = 1.0 + 0.012 * sin(_t * 1.6)
                logo.scale = Vector2(pulse, pulse)

        # Progression du chargement en arrière-plan
        if not _loaded:
                var info: Array = []
                var st: int = ResourceLoader.load_threaded_get_status(NEXT_SCENE, info)
                if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
                        if info.size() > 0:
                                _target = float(info[0])
                elif st == ResourceLoader.THREAD_LOAD_LOADED:
                        _packed = ResourceLoader.load_threaded_get(NEXT_SCENE) as PackedScene
                        _loaded = true
                        _target = 1.0
                else:
                        # Échec : change_scene_to_file affichera l'erreur précise
                        _loaded = true
                        _target = 1.0
        loadbar.progress = move_toward(loadbar.progress, _target, delta * 0.9)
        loadbar.queue_redraw()
        var done: bool = _loaded and loadbar.progress >= 0.999
        status.text = "Prêt" if done else "Chargement…  %d %%" % int(loadbar.progress * 100.0)

        if _leaving or not (_intro_done and done):
                return
        _ready_time += delta
        if wait_for_tap:
                status.visible = false
                loadbar.visible = false
                prompt.visible = true
                prompt.modulate.a = 0.55 + 0.45 * sin(_t * 4.0)
                if _tapped:
                        _leave()
        elif _ready_time >= hold_after_loaded or _tapped:
                _leave()


func _input(event: InputEvent) -> void:
        var pressed: bool = false
        if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
                pressed = true
        elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
                pressed = true
        elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
                pressed = true
        elif event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
                pressed = true
        if not pressed or _leaving:
                return
        if not _intro_done:
                # Un toucher pendant l'intro = on saute directement à la fin de l'animation
                if _tween != null and _tween.is_valid():
                        _tween.custom_step(10.0)
                _intro_done = true
                if not wait_for_tap:
                        _tapped = true
        else:
                _tapped = true


func _leave() -> void:
        if _leaving:
                return
        _leaving = true
        var tw: Tween = create_tween()
        tw.tween_property(fade, "color:a", 1.0, 0.45)
        tw.tween_callback(_change_scene)


func _change_scene() -> void:
        if _packed != null:
                get_tree().change_scene_to_packed(_packed)
        else:
                get_tree().change_scene_to_file(NEXT_SCENE)
