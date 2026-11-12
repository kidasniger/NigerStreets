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
## Immeubles désactivés : la vraie ville (Zinder) est basse et ouverte. Mettre à true pour les remettre.
@export var build_buildings: bool = false
@export var building_setback: float = 5.0
@export var building_spacing: float = 16.0
@export var building_gap: float = 6.0

@export_category("Décor")
@export var decor_seed: int = 31
## Arbres désactivés (aucun arbre dans la ville)
@export var build_trees: bool = false

var _rng := RandomNumberGenerator.new()
var _building_rects: Array[Rect2] = []
var _wall_materials: Array[StandardMaterial3D] = []
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
        if build_buildings: _build_buildings()
        if build_trees: _build_trees()
        # Spawn des véhicules APRÈS que tout soit dans l'arbre
        call_deferred("_spawn_vehicles")
        _add_credits()
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

## Crédits CC-BY affichés en petit en haut de l'écran
func _add_credits() -> void:
        var layer := CanvasLayer.new()
        layer.name = "Credits"
        layer.layer = 5
        add_child(layer)
        var label := Label.new()
        label.text = "Hennessy Vehnom GT 2010 - Eyasu Biyaylgn (CC-BY 4.0)"
        label.add_theme_font_size_override("font_size", 11)
        label.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
        label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
        label.add_theme_constant_override("outline_size", 3)
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        label.set_anchors_preset(Control.PRESET_TOP_WIDE)
        label.offset_top = 40.0
        label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        layer.add_child(label)

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

func _make_facade_texture(wall: Color) -> ImageTexture:
        var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
        img.fill(wall)
        var frame: Color = wall.darkened(0.25)
        var glass: Color = Color(0.20, 0.30, 0.42)
        for y in range(14, 48):
                for x in range(16, 48):
                        var on_frame: bool = x < 18 or x >= 46 or y < 16 or y >= 46
                        img.set_pixel(x, y, frame if on_frame else glass)
        img.generate_mipmaps()
        return ImageTexture.create_from_image(img)

func _create_building_materials() -> void:
        var walls: Array[Color] = [
                Color(0.82, 0.74, 0.62), Color(0.70, 0.72, 0.76),
                Color(0.80, 0.55, 0.42), Color(0.86, 0.84, 0.78),
        ]
        for wall in walls:
                var mat := StandardMaterial3D.new()
                mat.albedo_texture = _make_facade_texture(wall)
                mat.uv1_triplanar = true
                mat.uv1_world_triplanar = true
                mat.uv1_scale = Vector3.ONE / 3.0
                mat.roughness = 0.9
                _wall_materials.append(mat)
        _roof_material = StandardMaterial3D.new()
        _roof_material.albedo_color = Color(0.22, 0.22, 0.24)
        _roof_material.roughness = 0.95

func _add_building(center_xz: Vector2, footprint: Vector2, height: float) -> void:
        var mat: StandardMaterial3D = _wall_materials[_rng.randi() % _wall_materials.size()]
        var body := StaticBody3D.new()
        body.name = "Building"
        body.collision_layer = 1
        body.position = Vector3(center_xz.x, height * 0.5, center_xz.y)
        add_child(body)
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
        var shape := BoxShape3D.new()
        shape.size = Vector3(footprint.x, height, footprint.y)
        var collision := CollisionShape3D.new()
        collision.shape = shape
        body.add_child(collision)
        _building_rects.append(Rect2(center_xz - footprint * 0.5, footprint))

func _build_buildings() -> void:
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
                                var height: float = _rng.randf_range(8.0, 18.0)
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
                                _add_building(center2, footprint2, _rng.randf_range(12.0, 25.0))

func _overlaps_building(center_xz: Vector2, half_extent: Vector2) -> bool:
        var probe := Rect2(center_xz - half_extent, half_extent * 2.0)
        for rect in _building_rects:
                if rect.intersects(probe):
                        return true
        return false

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
