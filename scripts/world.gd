extends Node3D
# Ch31 - Environnement avec spawn de véhicules (Godot 4.7.2)

@export_category("Roundabout")
@export var roundabout_scene_path: String = "res://assets/environment/rond-point-elf.glb"
@export var roundabout_scale: float = 6.0
@export var roundabout_radius: float = 4.1
@export var island_radius: float = 3.9
@export var island_height: float = 12.0

@export_category("Roads")
## Goudron à double voie : 2 voies par sens, sans trottoir (24 m = 4 voies larges ; la texture s'adapte à cette largeur)
@export var road_width: float = 24.0
@export var road_length: float = 130.0
@export var road_thickness: float = 0.06
## Grand cercle du rond-point (goudron) autour du monument, avant le départ des routes
@export var ring_outer_radius: float = 30.0
@export var road_y: float = 0.0
@export var sidewalk_width: float = 1.2
@export var build_sidewalks: bool = false
## Textures de goudron (extraites de ta photo, herbes retirées). Si un fichier manque, on garde le goudron uni.
@export var road_texture_path: String = "res://assets/textures/road_arm.png"
@export var asphalt_texture_path: String = "res://assets/textures/asphalt.png"
const ROAD_TEX_BASE_WIDTH: float = 14.42    # largeur réelle représentée par road_arm.png avant mise à l'échelle
var road_texture_length_m: float = 10.236   # longueur de route couverte par une répétition de road_arm.png (recalculée)
var asphalt_tile_m: float = 5.408           # côté d'une tuile asphalt.png (recalculé)
var road_arm_material: StandardMaterial3D
@export var sidewalk_height: float = 0.12

@export_category("Buildings")
## Immeubles supprimés à la demande (garder seulement le rond-point et les routes)
@export var build_buildings: bool = false
@export var build_zinder: bool = true   # zone pilote OSM (zinder_zone.gd)
@export var building_setback: float = 5.0
@export var building_spacing: float = 16.0
@export var building_gap: float = 6.0

@export_category("Décor")
@export var decor_seed: int = 31
## Arbres désactivés (aucun arbre dans la ville)
@export var build_trees: bool = false
## Rochers supprimés à la demande (garder seulement le rond-point et les routes)
@export var build_rocks: bool = false

var _rng := RandomNumberGenerator.new()
var _building_rects: Array[Rect2] = []
var _building_count: int = 0

## Modèles 3D de bâtiments de Zinder (glTF générés) : boutiques 1 étage ×2,
## immeubles 2 étages ×2, Birni ×2. Empreinte (L×P) et hauteur du mur à l'échelle 1.
const BUILDING_SCENE_PATHS: Array[String] = [
        "res://assets/environment/buildings/shop_creme_vert.glb",
        "res://assets/environment/buildings/shop_rose_rouge.glb",
        "res://assets/environment/buildings/etage_sable.glb",
        "res://assets/environment/buildings/etage_blanc.glb",
        "res://assets/environment/buildings/birni_ocre.glb",
        "res://assets/environment/buildings/birni_fonce.glb",
]
const BUILDING_SIZES: Array[Vector2] = [
        Vector2(8.0, 7.0), Vector2(8.0, 7.0), Vector2(8.0, 7.0),
        Vector2(8.0, 7.0), Vector2(7.0, 9.0), Vector2(7.0, 9.0),
]
const BUILDING_HEIGHTS: Array[float] = [4.2, 4.2, 7.2, 7.2, 5.5, 5.5]
var _building_scenes: Array[PackedScene] = []

## Charge les modèles GLB disponibles (chemins manquants ignorés : repli sur les boîtes)
func _load_building_scenes() -> void:
        for p in BUILDING_SCENE_PATHS:
                if ResourceLoader.exists(p):
                        _building_scenes.append(load(p) as PackedScene)
var _low_facades: Array[StandardMaterial3D] = []    # façades 1 étage (boutique + muret)
var _high_facades: Array[StandardMaterial3D] = []   # façades 2 étages (boutique + étage fenêtres)
var _birni_facades: Array[StandardMaterial3D] = []  # façades terre ocre d'inspiration Birni
var _roof_material: StandardMaterial3D
var road_material: StandardMaterial3D
var sidewalk_material: StandardMaterial3D
var line_material: StandardMaterial3D

func _ready() -> void:
        _rng.seed = decor_seed
        GameSettings.load_settings()
        _create_materials()
        _setup_environment()
        _setup_ground()
        _load_roundabout()
        _build_ring_road()
        _build_roads()
        _build_island_collision()
        if build_zinder: _build_zinder_zone()
        elif build_buildings: _build_buildings()
        if build_trees: _build_trees()
        if build_rocks: _build_rocks()   # rochers de granit à l'horizon
        # Spawn des véhicules APRÈS que tout soit dans l'arbre
        call_deferred("_spawn_vehicles")
        _add_ambience()
        call_deferred("_add_pause_menu")   # en dernier enfant : son _input est appelé avant celui du joueur

## Ambiance de ville en boucle (res://assets/audio/ambience_city.ogg ; ignorée si le fichier manque)
func _add_ambience() -> void:
        var path: String = "res://assets/audio/ambience_city.ogg"
        if not ResourceLoader.exists(path): return
        var stream: AudioStream = GameAssets.make_looping(GameAssets.load_resource(path) as AudioStream)
        if stream == null: return
        var player := AudioStreamPlayer.new()
        player.name = "AmbienceCity"
        player.stream = stream
        player.volume_db = -10.0
        add_child(player)
        player.play()

func _create_materials() -> void:
        # Les textures gardent leurs proportions quand on élargit la route
        var tex_scale: float = road_width / ROAD_TEX_BASE_WIDTH
        road_texture_length_m = 10.236 * tex_scale
        asphalt_tile_m = 5.408 * tex_scale
        road_material = StandardMaterial3D.new()
        road_material.albedo_color = Color(0.055, 0.06, 0.065, 1.0)
        road_material.roughness = 0.92
        if ResourceLoader.exists(asphalt_texture_path):
                road_material.albedo_texture = load(asphalt_texture_path) as Texture2D
                road_material.albedo_color = Color(0.75, 0.75, 0.78, 1.0)
                road_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
        if ResourceLoader.exists(road_texture_path):
                road_arm_material = StandardMaterial3D.new()
                road_arm_material.albedo_texture = load(road_texture_path) as Texture2D
                road_arm_material.albedo_color = Color(0.75, 0.75, 0.78, 1.0)
                road_arm_material.roughness = 0.92
                road_arm_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
        sidewalk_material = StandardMaterial3D.new()
        sidewalk_material.albedo_color = Color(0.30, 0.31, 0.32, 1.0)
        sidewalk_material.roughness = 0.88
        line_material = StandardMaterial3D.new()
        line_material.albedo_color = Color(0.88, 0.88, 0.82, 1.0)
        line_material.roughness = 0.72

func _load_roundabout() -> void:
        var packed: PackedScene = GameAssets.load_resource(roundabout_scene_path) as PackedScene
        if packed == null:
                push_error("Ch31 : GLB introuvable : " + roundabout_scene_path)
                return
        var roundabout: Node3D = packed.instantiate() as Node3D
        if roundabout == null:
                push_error("Ch31 : impossible d'instancier le GLB.")
                return
        roundabout.name = "Roundabout_ELF"
        roundabout.scale = Vector3.ONE * roundabout_scale
        roundabout.position = Vector3(0.0, roundabout_scale, 0.0)
        add_child(roundabout)

func _ring_inner() -> float:
        return roundabout_radius + 0.1

func _ring_outer() -> float:
        return maxf(ring_outer_radius, _ring_inner() + road_width)

func _build_ring_road() -> void:
        var segments: int = 128
        var inner: float = _ring_inner()
        var outer: float = _ring_outer()
        var top: float = road_y + road_thickness * 0.5
        var st := SurfaceTool.new()
        st.begin(Mesh.PRIMITIVE_TRIANGLES)
        for i in range(segments):
                var a0: float = TAU * float(i) / float(segments)
                var a1: float = TAU * float(i + 1) / float(segments)
                var i0 := Vector3(cos(a0) * inner, top, sin(a0) * inner)
                var o0 := Vector3(cos(a0) * outer, top, sin(a0) * outer)
                var i1 := Vector3(cos(a1) * inner, top, sin(a1) * inner)
                var o1 := Vector3(cos(a1) * outer, top, sin(a1) * outer)
                for v in [i0, o0, o1, i0, o1, i1]:
                        st.set_normal(Vector3.UP)
                        st.set_uv(Vector2(v.x, v.z) / asphalt_tile_m)
                        st.add_vertex(v)
        var mesh: ArrayMesh = st.commit()
        var body := StaticBody3D.new()
        body.name = "Road_Ring"
        body.collision_layer = 1
        body.collision_mask = 1
        add_child(body)
        var mesh_instance := MeshInstance3D.new()
        mesh_instance.mesh = mesh
        mesh_instance.material_override = road_material
        body.add_child(mesh_instance)
        var collision := CollisionShape3D.new()
        collision.shape = mesh.create_trimesh_shape()
        body.add_child(collision)

func _build_roads() -> void:
        var arms: Dictionary = {
                "North": Vector3(0.0, 0.0, -1.0),
                "South": Vector3(0.0, 0.0, 1.0),
                "East": Vector3(1.0, 0.0, 0.0),
                "West": Vector3(-1.0, 0.0, 0.0),
        }
        for arm_name: String in arms.keys():
                _build_arm(arm_name, arms[arm_name])
        if road_arm_material == null: _build_center_markings()   # sans texture, on dessine les lignes à la main

func _build_arm(arm_name: String, dir: Vector3) -> void:
        var along_z: bool = absf(dir.z) > 0.5
        var side: Vector3 = Vector3(-dir.z, 0.0, dir.x)
        # Les routes partent du bord du grand cercle : les coins de la route (à ±largeur/2) doivent rester dans le cercle, sans trou
        var half_w: float = road_width * 0.5
        var road_start: float = maxf(sqrt(maxf(_ring_outer() * _ring_outer() - half_w * half_w, 0.0)) - 1.0, 1.0)
        var road_len: float = road_length - road_start
        var road_center: Vector3 = dir * (road_start + road_len * 0.5)
        road_center.y = road_y
        var road_size: Vector3 = Vector3(road_width, road_thickness, road_len) if along_z else Vector3(road_len, road_thickness, road_width)
        if road_arm_material != null:
                _create_textured_road("Road_" + arm_name, road_center, road_width, road_len, along_z)
        else:
                _create_road("Road_" + arm_name, road_center, road_size)
        if not build_sidewalks: return
        var lateral: float = road_width * 0.5 + sidewalk_width * 0.5
        var sw_start: float = sqrt(maxf(_ring_outer() * _ring_outer() - lateral * lateral, 0.0)) + 0.05
        var sw_len: float = road_length - sw_start
        var sw_size: Vector3 = Vector3(sidewalk_width, sidewalk_height, sw_len) if along_z else Vector3(sw_len, sidewalk_height, sidewalk_width)
        for lateral_sign: float in [-1.0, 1.0]:
                var sw_pos: Vector3 = dir * (sw_start + sw_len * 0.5) + side * lateral * lateral_sign
                sw_pos.y = sidewalk_height * 0.5
                var suffix: String = "L" if lateral_sign < 0.0 else "R"
                _create_sidewalk_mesh("Sidewalk_%s_%s" % [arm_name, suffix], sw_pos, sw_size)

## Route texturée : un plan avec la photo de goudron (lignes comprises), répétée sur la longueur
func _create_textured_road(node_name: String, position: Vector3, width: float, length: float, along_z: bool) -> void:
        var dimensions: Vector3 = Vector3(width, road_thickness, length) if along_z else Vector3(length, road_thickness, width)
        var body := StaticBody3D.new()
        body.name = node_name
        body.collision_layer = 1
        body.collision_mask = 1
        add_child(body)
        var collision := CollisionShape3D.new()
        collision.name = "Collision"
        var shape := BoxShape3D.new()
        shape.size = dimensions
        collision.shape = shape
        collision.position = position
        body.add_child(collision)
        var mesh_instance := MeshInstance3D.new()
        mesh_instance.name = "RoadMesh"
        var plane := PlaneMesh.new()
        plane.size = Vector2(width, length)
        mesh_instance.mesh = plane
        var material: StandardMaterial3D = road_arm_material.duplicate() as StandardMaterial3D
        material.uv1_scale = Vector3(1.0, length / road_texture_length_m, 1.0)
        mesh_instance.material_override = material
        mesh_instance.position = position + Vector3(0.0, road_thickness * 0.5 + 0.015, 0.0)
        mesh_instance.rotation.y = 0.0 if along_z else PI * 0.5
        add_child(mesh_instance)

func _create_road(node_name: String, position: Vector3, dimensions: Vector3) -> void:
        var body := StaticBody3D.new()
        body.name = node_name
        body.collision_layer = 1
        body.collision_mask = 1
        add_child(body)
        var mesh_instance := MeshInstance3D.new()
        mesh_instance.name = "RoadMesh"
        var mesh := BoxMesh.new()
        mesh.size = dimensions
        mesh_instance.mesh = mesh
        mesh_instance.material_override = road_material
        mesh_instance.position = position
        add_child(mesh_instance)
        var collision := CollisionShape3D.new()
        collision.name = "Collision"
        var shape := BoxShape3D.new()
        shape.size = dimensions
        collision.shape = shape
        collision.position = position
        body.add_child(collision)

func _create_sidewalk_mesh(node_name: String, position: Vector3, dimensions: Vector3) -> void:
        var body := StaticBody3D.new()
        body.name = node_name
        body.collision_layer = 1
        add_child(body)
        var mesh_instance := MeshInstance3D.new()
        var mesh := BoxMesh.new()
        mesh.size = dimensions
        mesh_instance.mesh = mesh
        mesh_instance.material_override = sidewalk_material
        mesh_instance.position = position
        add_child(mesh_instance)
        var collision := CollisionShape3D.new()
        var shape := BoxShape3D.new()
        shape.size = dimensions
        collision.shape = shape
        collision.position = position
        body.add_child(collision)

func _build_center_markings() -> void:
        # Goudron à double voie : double ligne continue au centre, pointillés entre les voies, lignes de rive
        var marking_y: float = road_y + road_thickness * 0.5 + 0.01
        var d0: float = _ring_outer() + 1.0
        var d1: float = road_length - 3.0
        var solid_len: float = d1 - d0
        if solid_len <= 1.0:
                return
        var lane_off: float = road_width * 0.25
        var edge_off: float = road_width * 0.5 - 0.35
        var dash_length: float = 3.0
        var gap: float = 4.0
        for dir_sign: float in [-1.0, 1.0]:
                # lignes continues : centre (x2) et rives (x2)
                for off: float in [-0.12, 0.12, -edge_off, edge_off]:
                        var mid: float = dir_sign * (d0 + solid_len * 0.5)
                        _create_line(Vector3(off, marking_y, mid), Vector3(0.12, 0.015, solid_len))   # bras Nord / Sud
                        _create_line(Vector3(mid, marking_y, off), Vector3(solid_len, 0.015, 0.12))   # bras Est / Ouest
                # pointillés entre les deux voies de chaque sens
                var d: float = d0 + dash_length * 0.5
                while d + dash_length * 0.5 <= d1:
                        for off: float in [-lane_off, lane_off]:
                                _create_line(Vector3(off, marking_y, dir_sign * d), Vector3(0.12, 0.015, dash_length))
                                _create_line(Vector3(dir_sign * d, marking_y, off), Vector3(dash_length, 0.015, 0.12))
                        d += dash_length + gap

func _create_line(position: Vector3, dimensions: Vector3) -> void:
        var mesh_instance := MeshInstance3D.new()
        var mesh := BoxMesh.new()
        mesh.size = dimensions
        mesh_instance.mesh = mesh
        mesh_instance.material_override = line_material
        mesh_instance.position = position
        # LOD : marquage plat et fin, plus dessiné au-delà de 180 m (pop invisible) ;
        # inutile de le faire participer aux ombres
        mesh_instance.visibility_range_end = 180.0
        mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        add_child(mesh_instance)

func _build_island_collision() -> void:
        var body := StaticBody3D.new()
        body.name = "RoundaboutIslandCollision"
        body.collision_layer = 1
        body.collision_mask = 1
        add_child(body)
        var collision := CollisionShape3D.new()
        var shape := CylinderShape3D.new()
        shape.radius = island_radius
        shape.height = island_height
        collision.shape = shape
        collision.position = Vector3(0.0, island_height * 0.5, 0.0)
        body.add_child(collision)

func _make_noise_texture(low: Color, high: Color, frequency: float, tex_size: int = 512) -> NoiseTexture2D:
        var noise := FastNoiseLite.new()
        noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
        noise.frequency = frequency
        noise.seed = decor_seed
        var gradient := Gradient.new()
        gradient.colors = PackedColorArray([low, high])
        gradient.offsets = PackedFloat32Array([0.0, 1.0])
        var tex := NoiseTexture2D.new()
        tex.width = tex_size
        tex.height = tex_size
        tex.seamless = true
        tex.noise = noise
        tex.color_ramp = gradient
        return tex

func _setup_environment() -> void:
        var world_env: WorldEnvironment = get_node_or_null("Environment") as WorldEnvironment
        if world_env == null:
                world_env = WorldEnvironment.new()
                world_env.name = "Environment"
                add_child(world_env)
        if world_env.environment == null:
                world_env.environment = Environment.new()
        var env: Environment = world_env.environment
        var sky_material := ProceduralSkyMaterial.new()
        sky_material.sky_top_color = Color(0.20, 0.42, 0.78)
        sky_material.sky_horizon_color = Color(0.66, 0.78, 0.90)
        sky_material.ground_horizon_color = Color(0.62, 0.68, 0.72)
        sky_material.ground_bottom_color = Color(0.25, 0.28, 0.30)
        var sky := Sky.new()
        sky.sky_material = sky_material
        env.background_mode = Environment.BG_SKY
        env.sky = sky
        env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
        env.ambient_light_energy = 1.0
        env.fog_enabled = true
        env.fog_light_color = Color(0.66, 0.78, 0.90)
        env.fog_density = 0.005
        env.fog_sky_affect = 0.0
        var sun: DirectionalLight3D = get_node_or_null("Sun") as DirectionalLight3D
        if sun == null:
                sun = DirectionalLight3D.new()
                sun.name = "Sun"
                add_child(sun)
        sun.light_energy = 1.2
        GameSettings.apply_sun(sun)   # ombres + distance d'ombre unifiées (splash.gd = world.gd = menu réglages)
        sun.add_to_group("main_sun")   # le menu pause pilote les ombres via ce groupe
        var fill: OmniLight3D = get_node_or_null("Fill") as OmniLight3D
        if fill != null:
                fill.visible = false

func _setup_ground() -> void:
        var ground_size: float = 500.0
        var ground_node: Node3D = get_node_or_null("Ground") as Node3D
        if ground_node == null:
                ground_node = Node3D.new()
                ground_node.name = "Ground"
                add_child(ground_node)
        var mesh_node: MeshInstance3D = ground_node.get_node_or_null("Mesh") as MeshInstance3D
        if mesh_node == null:
                mesh_node = MeshInstance3D.new()
                mesh_node.name = "Mesh"
                mesh_node.mesh = BoxMesh.new()
                ground_node.add_child(mesh_node)
        if mesh_node.mesh is BoxMesh:
                (mesh_node.mesh as BoxMesh).size = Vector3(ground_size, 0.2, ground_size)
                var mat := StandardMaterial3D.new()
                mat.albedo_texture = _make_noise_texture(Color(0.16, 0.30, 0.12), Color(0.38, 0.50, 0.21), 0.02)
                mat.uv1_triplanar = true
                mat.uv1_world_triplanar = true
                mat.uv1_scale = Vector3.ONE * 0.12
                mat.roughness = 1.0
                mesh_node.material_override = mat
        var collision_node: CollisionShape3D = ground_node.get_node_or_null("Collision") as CollisionShape3D
        if collision_node == null:
                collision_node = CollisionShape3D.new()
                collision_node.name = "Collision"
                collision_node.shape = BoxShape3D.new()
                ground_node.add_child(collision_node)
        if collision_node.shape is BoxShape3D:
                (collision_node.shape as BoxShape3D).size = Vector3(ground_size, 0.2, ground_size)

## Mouchetis du plâtre : petites taches claires/sombres pour casser l'aplat des façades
func _mottle(img: Image, base: Color, count: int) -> void:
        for i in range(count):
                var px := _rng.randi_range(0, 248)
                var py := _rng.randi_range(0, 248)
                var sz := _rng.randi_range(4, 10)
                var c := base.darkened(_rng.randf_range(0.03, 0.09)) if _rng.randf() < 0.5 else base.lightened(_rng.randf_range(0.02, 0.07))
                img.fill_rect(Rect2i(px, py, sz, sz), c)

## Façade « boutique de Zinder » : muret en haut, rangée de fenêtres si 2 étages, store rayé,
## vitrine, volet métallique et porte. Mappée par les UV natives du BoxMesh : une texture =
## tout l'étage du bâtiment (haut de l'image = haut du mur).
func _make_shop_facade(wall: Color, awning: Color, two_floors: bool) -> StandardMaterial3D:
        var img := Image.create(256, 256, false, Image.FORMAT_RGB8)
        img.fill(wall)
        _mottle(img, wall, 120)
        var dark: Color = wall.darkened(0.22)
        # muret du toit + corniche
        img.fill_rect(Rect2i(0, 0, 256, 30), wall.lightened(0.10))
        img.fill_rect(Rect2i(0, 30, 256, 6), dark)
        if two_floors:
                # fenêtres de l'étage avec linteaux et reflets
                for wx in range(3):
                        var x0 := 22 + wx * 82
                        img.fill_rect(Rect2i(x0 - 4, 52, 44, 4), dark)
                        img.fill_rect(Rect2i(x0 - 2, 56, 40, 56), dark)
                        img.fill_rect(Rect2i(x0, 58, 36, 52), Color(0.22, 0.30, 0.40))
                        img.fill_rect(Rect2i(x0, 58, 36, 10), Color(0.45, 0.55, 0.62))
                img.fill_rect(Rect2i(0, 122, 256, 8), dark)
        # bandeau d'enseigne puis store rayé
        var aw_y := 138 if two_floors else 66
        img.fill_rect(Rect2i(0, aw_y - 14, 256, 14), wall.darkened(0.12))
        for tx in range(12, 240, 34):
                img.fill_rect(Rect2i(tx, aw_y - 10, 20, 6), Color(0.95, 0.93, 0.88))
        img.fill_rect(Rect2i(0, aw_y, 256, 34), awning)
        for sx in range(0, 256, 32):
                img.fill_rect(Rect2i(sx + 16, aw_y, 16, 34), awning.lightened(0.28))
        # devanture : vitrine + volet + porte
        var shop_y := aw_y + 34
        img.fill_rect(Rect2i(0, shop_y, 256, 256 - shop_y), dark)
        img.fill_rect(Rect2i(10, shop_y + 8, 100, 256 - shop_y - 16), Color(0.20, 0.28, 0.36))
        img.fill_rect(Rect2i(10, shop_y + 8, 100, 12), Color(0.50, 0.58, 0.64))
        var shutter: Color = Color(0.72, 0.70, 0.64)
        img.fill_rect(Rect2i(118, shop_y + 8, 54, 256 - shop_y - 16), shutter)
        for lx in range(120, 170, 7):
                img.fill_rect(Rect2i(lx, shop_y + 8, 2, 256 - shop_y - 16), shutter.darkened(0.18))
        img.fill_rect(Rect2i(182, shop_y + 8, 64, 256 - shop_y - 16), Color(0.14, 0.10, 0.08))
        img.generate_mipmaps()
        var mat := StandardMaterial3D.new()
        mat.albedo_texture = ImageTexture.create_from_image(img)
        mat.roughness = 0.9
        return mat

## Façade « Birni » : terre ocre, poutres saillantes (toron), bande décorative et porte sombre
func _make_birni_facade(ochre: Color) -> StandardMaterial3D:
        var img := Image.create(256, 256, false, Image.FORMAT_RGB8)
        img.fill(ochre)
        _mottle(img, ochre, 160)
        var beam: Color = Color(0.30, 0.19, 0.12)
        for by in [52, 118, 184]:
                img.fill_rect(Rect2i(0, by, 256, 10), beam)
                for bx in range(8, 256, 24):
                        img.fill_rect(Rect2i(bx, by - 2, 6, 14), beam.darkened(0.15))
        # bande décorative en losanges sous la corniche
        var deco: Color = Color(0.58, 0.42, 0.30)
        for dx in range(0, 256, 32):
                img.fill_rect(Rect2i(dx + 12, 18, 8, 8), deco)
                img.fill_rect(Rect2i(dx + 24, 18, 8, 8), Color(0.86, 0.72, 0.55))
        img.fill_rect(Rect2i(0, 28, 256, 4), ochre.darkened(0.20))
        # fenêtres étroites et porte sombre
        for wx in [30, 190]:
                img.fill_rect(Rect2i(wx, 150, 26, 34), Color(0.18, 0.14, 0.12))
        img.fill_rect(Rect2i(108, 216, 40, 40), Color(0.16, 0.11, 0.08))
        img.generate_mipmaps()
        var mat := StandardMaterial3D.new()
        mat.albedo_texture = ImageTexture.create_from_image(img)
        mat.roughness = 1.0
        return mat

func _create_building_materials() -> void:
        # Palette « Zinder » : tons crème / sable / ocre / rose pâle des façades peintes,
        # stores de boutiques vert / rouge / bleu / jaune ocre.
        var awnings: Array[Color] = [
                Color(0.24, 0.52, 0.30), Color(0.72, 0.25, 0.22),
                Color(0.22, 0.42, 0.66), Color(0.82, 0.60, 0.18),
        ]
        var low_walls: Array[Color] = [
                Color(0.92, 0.86, 0.70), Color(0.86, 0.76, 0.60), Color(0.88, 0.70, 0.64),
        ]
        var high_walls: Array[Color] = [
                Color(0.84, 0.66, 0.44), Color(0.90, 0.89, 0.84), Color(0.92, 0.86, 0.70),
        ]
        _low_facades.clear()
        _high_facades.clear()
        _birni_facades.clear()
        for wall in low_walls:
                for awning in awnings:
                        _low_facades.append(_make_shop_facade(wall, awning, false))
        for i in range(high_walls.size()):
                _high_facades.append(_make_shop_facade(high_walls[i], awnings[i % awnings.size()], true))
        _birni_facades.append(_make_birni_facade(Color(0.74, 0.55, 0.38)))
        _birni_facades.append(_make_birni_facade(Color(0.66, 0.49, 0.35)))
        _roof_material = StandardMaterial3D.new()
        _roof_material.albedo_color = Color(0.58, 0.54, 0.48)
        _roof_material.roughness = 0.95

func _add_building(center_xz: Vector2, footprint: Vector2, height: float) -> void:
        _building_count += 1
        var body := StaticBody3D.new()
        body.name = "Building%d" % _building_count   # nom unique (Godot renomme sinon en @StaticBody3D@N)
        body.collision_layer = 1
        body.position = Vector3(center_xz.x, 0.0, center_xz.y)   # origine des modèles au niveau du sol
        add_child(body)
        if _building_scenes.size() > 0:
                _add_model_building(body, footprint)
        else:
                _add_box_building(body, footprint, height)
        _building_rects.append(Rect2(center_xz - footprint * 0.5, footprint))

## Vrai bâtiment 3D (glTF) : orienté au hasard, étiré pour remplir exactement l'empreinte demandée
func _add_model_building(body: StaticBody3D, footprint: Vector2) -> void:
        var idx := _rng.randi() % _building_scenes.size()
        var inst: Node3D = _building_scenes[idx].instantiate()
        var rot_steps := _rng.randi_range(0, 3)
        var model_size: Vector2 = BUILDING_SIZES[idx]
        if rot_steps % 2 == 1:
                model_size = Vector2(model_size.y, model_size.x)   # modèle tourné : axes échangés
        var sx := footprint.x / model_size.x
        var sz := footprint.y / model_size.y
        var sy := (sx + sz) * 0.5
        var h: float = BUILDING_HEIGHTS[idx] * sy
        inst.rotation.y = float(rot_steps) * PI * 0.5
        inst.scale = Vector3(sx, sy, sz)
        body.add_child(inst)
        var shape := BoxShape3D.new()
        shape.size = Vector3(footprint.x, h, footprint.y)
        var collision := CollisionShape3D.new()
        collision.shape = shape
        collision.position = Vector3(0.0, h * 0.5, 0.0)
        body.add_child(collision)

## Bâtiment texturé simple (repli si les modèles GLB sont absents)
func _add_box_building(body: StaticBody3D, footprint: Vector2, height: float) -> void:
        var mat: StandardMaterial3D
        if _rng.randf() < 0.25:
                mat = _birni_facades[_rng.randi() % _birni_facades.size()]   # quartier Birni
        else:
                var pool: Array[StandardMaterial3D] = _low_facades if height < 6.0 else _high_facades
                mat = pool[_rng.randi() % pool.size()]
        body.position.y = height * 0.5
        var wall_mesh := BoxMesh.new()
        wall_mesh.size = Vector3(footprint.x, height, footprint.y)
        var wall_instance := MeshInstance3D.new()
        wall_instance.mesh = wall_mesh
        wall_instance.material_override = mat
        body.add_child(wall_instance)
        var roof_mesh := BoxMesh.new()
        roof_mesh.size = Vector3(footprint.x + 0.3, 0.3, footprint.y + 0.3)
        var roof_instance := MeshInstance3D.new()
        roof_instance.mesh = roof_mesh
        roof_instance.material_override = _roof_material
        roof_instance.position = Vector3(0.0, height * 0.5 + 0.15, 0.0)
        body.add_child(roof_instance)
        # muret tout autour du toit plat (les toits de Zinder ne sont jamais nus)
        var parapet_h: float = 0.5
        var t: float = 0.18
        for i in range(4):
                var par := MeshInstance3D.new()
                var pm := BoxMesh.new()
                if i < 2:
                        pm.size = Vector3(footprint.x + t * 2.0, parapet_h, t)
                        par.position = Vector3(0.0, height * 0.5 + 0.3 + parapet_h * 0.5, (footprint.y * 0.5 + t * 0.5) * (1.0 if i == 0 else -1.0))
                else:
                        pm.size = Vector3(t, parapet_h, footprint.y)
                        par.position = Vector3((footprint.x * 0.5 + t * 0.5) * (1.0 if i == 2 else -1.0), height * 0.5 + 0.3 + parapet_h * 0.5, 0.0)
                par.mesh = pm
                par.material_override = mat
                body.add_child(par)
        var shape := BoxShape3D.new()
        shape.size = Vector3(footprint.x, height, footprint.y)
        var collision := CollisionShape3D.new()
        collision.shape = shape
        body.add_child(collision)

func _build_buildings() -> void:
        _load_building_scenes()
        _create_building_materials()
        var dirs: Array[Vector3] = [
                Vector3(0.0, 0.0, -1.0), Vector3(0.0, 0.0, 1.0),
                Vector3(1.0, 0.0, 0.0), Vector3(-1.0, 0.0, 0.0),
        ]
        var setback: float = road_width * 0.5 + sidewalk_width + building_setback
        for dir in dirs:
                var side: Vector3 = Vector3(-dir.z, 0.0, dir.x)
                for lateral_sign in [-1.0, 1.0]:
                        for i in range(3):
                                var along: float = 20.0 + building_spacing * float(i)
                                var depth: float = _rng.randf_range(7.0, 10.0)
                                var width: float = _rng.randf_range(8.0, 12.0)
                                var height: float = _rng.randf_range(4.0, 7.5)   # 1 à 2 étages, comme à Zinder
                                var lateral: float = setback + depth * 0.5
                                var pos: Vector3 = dir * along + side * lateral * float(lateral_sign)
                                var along_z: bool = absf(dir.z) > 0.5
                                var footprint: Vector2 = Vector2(depth, width) if along_z else Vector2(width, depth)
                                var center2d := Vector2(pos.x, pos.z)
                                if not _overlaps_building(center2d, footprint * 0.5 + Vector2(building_gap, building_gap)):
                                        _add_building(center2d, footprint, height)
        for qx in [-1.0, 1.0]:
                for qz in [-1.0, 1.0]:
                        for i in range(3):
                                var fx: float = _rng.randf_range(28.0, 55.0)
                                var fz: float = _rng.randf_range(28.0, 55.0)
                                var footprint2: Vector2 = Vector2(_rng.randf_range(10.0, 16.0), _rng.randf_range(10.0, 16.0))
                                var center2: Vector2 = Vector2(fx * float(qx), fz * float(qz))
                                if _overlaps_building(center2, footprint2 * 0.5 + Vector2(building_gap, building_gap)):
                                        continue
                                _add_building(center2, footprint2, _rng.randf_range(5.0, 9.0))

func _build_zinder_zone() -> void:
        var zone_script: GDScript = load("res://scripts/zinder_zone.gd")
        var zone: Node3D = zone_script.new()
        zone.name = "ZinderZone"
        add_child(zone)

func _overlaps_building(center_xz: Vector2, half_extent: Vector2) -> bool:
        var probe := Rect2(center_xz - half_extent, half_extent * 2.0)
        for rect in _building_rects:
                if rect.intersects(probe):
                        return true
        return false

## Rochers de granit de Zinder : dômes aplatis posés à l'horizon du plateau (décor lointain)
func _build_rocks() -> void:
        var mat := StandardMaterial3D.new()
        mat.albedo_texture = _make_noise_texture(Color(0.42, 0.40, 0.38), Color(0.58, 0.55, 0.52), 0.03)
        mat.roughness = 1.0
        var spots: Array[Vector2] = [
                Vector2(180.0, 60.0), Vector2(-170.0, -110.0), Vector2(120.0, -190.0),
                Vector2(-130.0, 170.0), Vector2(210.0, -40.0),
        ]
        var rock_idx := 0
        for s in spots:
                for i in range(_rng.randi_range(3, 5)):
                        var body := StaticBody3D.new()
                        rock_idx += 1
                        body.name = "Rock%d" % rock_idx   # nom unique (sinon @StaticBody3D@N)
                        var r := _rng.randf_range(7.0, 16.0)
                        body.position = Vector3(s.x + _rng.randf_range(-12.0, 12.0), r * 0.28, s.y + _rng.randf_range(-12.0, 12.0))
                        add_child(body)
                        var mi := MeshInstance3D.new()
                        var m := SphereMesh.new()
                        m.radius = r
                        m.height = r * 0.62
                        m.radial_segments = 16
                        m.rings = 8
                        mi.mesh = m
                        mi.material_override = mat
                        mi.scale = Vector3(1.0, 1.0, _rng.randf_range(0.8, 1.3))
                        body.add_child(mi)
                        var cs := CollisionShape3D.new()
                        var shape := SphereShape3D.new()
                        shape.radius = r * 0.6
                        cs.shape = shape
                        body.add_child(cs)

func _build_trees() -> void:
        var positions: Array[Vector2] = []
        var dirs: Array[Vector3] = [
                Vector3(0.0, 0.0, -1.0), Vector3(0.0, 0.0, 1.0),
                Vector3(1.0, 0.0, 0.0), Vector3(-1.0, 0.0, 0.0),
        ]
        var tree_lateral: float = road_width * 0.5 + sidewalk_width + 0.8
        for dir in dirs:
                var side: Vector3 = Vector3(-dir.z, 0.0, dir.x)
                for lateral_sign in [-1.0, 1.0]:
                        var along: float = 14.0
                        while along <= 56.0:
                                var p: Vector3 = dir * along + side * tree_lateral * float(lateral_sign)
                                positions.append(Vector2(p.x, p.z))
                                along += 7.0
        for qx in [-1.0, 1.0]:
                for qz in [-1.0, 1.0]:
                        var placed: int = 0
                        var attempts: int = 0
                        while placed < 20 and attempts < 300:
                                attempts += 1
                                var candidate := Vector2(_rng.randf_range(16.0, 70.0) * float(qx), _rng.randf_range(16.0, 70.0) * float(qz))
                                if _overlaps_building(candidate, Vector2(3.0, 3.0)):
                                        continue
                                positions.append(candidate)
                                placed += 1
        var count: int = positions.size()
        if count == 0:
                return
        var trunk_mesh := CylinderMesh.new()
        trunk_mesh.top_radius = 0.16
        trunk_mesh.bottom_radius = 0.24
        trunk_mesh.height = 2.2
        trunk_mesh.radial_segments = 6
        var trunk_mat := StandardMaterial3D.new()
        trunk_mat.albedo_color = Color(0.32, 0.22, 0.13)
        trunk_mat.roughness = 1.0
        trunk_mesh.material = trunk_mat
        var crown_mesh := SphereMesh.new()
        crown_mesh.radius = 1.0
        crown_mesh.height = 2.0
        crown_mesh.radial_segments = 10
        crown_mesh.rings = 6
        var crown_mat := StandardMaterial3D.new()
        crown_mat.vertex_color_use_as_albedo = true
        crown_mat.roughness = 0.95
        crown_mesh.material = crown_mat
        var trunks := MultiMesh.new()
        trunks.transform_format = MultiMesh.TRANSFORM_3D
        trunks.mesh = trunk_mesh
        trunks.instance_count = count
        var crowns := MultiMesh.new()
        crowns.transform_format = MultiMesh.TRANSFORM_3D
        crowns.use_colors = true
        crowns.mesh = crown_mesh
        crowns.instance_count = count
        var collider_body := StaticBody3D.new()
        collider_body.name = "TreeColliders"
        collider_body.collision_layer = 1
        add_child(collider_body)
        var trunk_shape := CylinderShape3D.new()
        trunk_shape.radius = 0.3
        trunk_shape.height = 2.5
        for i in range(count):
                var grow: float = _rng.randf_range(0.85, 1.35)
                var pos2: Vector2 = positions[i]
                trunks.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(grow, grow, grow)), Vector3(pos2.x, 1.1 * grow, pos2.y)))
                var crown_scale: Vector3 = Vector3(1.1, 1.0, 1.1) * grow
                crowns.set_instance_transform(i, Transform3D(Basis().scaled(crown_scale), Vector3(pos2.x, 3.0 * grow, pos2.y)))
                crowns.set_instance_color(i, Color(0.13, 0.36, 0.14).lerp(Color(0.32, 0.52, 0.16), _rng.randf()))
                var collision := CollisionShape3D.new()
                collision.shape = trunk_shape
                collision.position = Vector3(pos2.x, 1.25, pos2.y)
                collider_body.add_child(collision)
        var trunk_instance := MultiMeshInstance3D.new()
        trunk_instance.name = "TreeTrunks"
        trunk_instance.multimesh = trunks
        add_child(trunk_instance)
        var crown_instance := MultiMeshInstance3D.new()
        crown_instance.name = "TreeCrowns"
        crown_instance.multimesh = crowns
        add_child(crown_instance)

# --- SPAWN DE VÉHICULES (corrigé pour Godot 4.7.2) ---
func _spawn_vehicles() -> void:
        var car_script = preload("res://scripts/vehicle.gd")
        # Positions le long des routes
        var spawn_data: Array[Dictionary] = [
                {"pos": Vector3(2.0, 0.6, -22.0), "rot_y": 0.0},
                # Modèle lourd (~99 000 triangles) : une seule voiture pour l'instant. Décommenter pour en ajouter :
                # {"pos": Vector3(-2.0, 0.6, 25.0), "rot_y": 180.0},
        ]
        for data in spawn_data:
                var car_body := VehicleBody3D.new()
                car_body.set_script(car_script)
                # On définit la position ET la rotation AVANT d'ajouter à l'arbre
                car_body.position = data["pos"]
                car_body.rotation_degrees.y = data["rot_y"]
                add_child(car_body)

## Menu pause + réglages (instancié en dernier enfant du monde)
func _add_pause_menu() -> void:
        var menu := PauseMenu.new()
        menu.name = "PauseMenu"
        add_child(menu)
