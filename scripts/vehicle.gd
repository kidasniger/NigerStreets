extends VehicleBody3D
class_name GameVehicle
# Ch31 - Véhicule générique : charge n'importe quel modèle glTF/GLB, trouve seul les roues, les freins et les portières,
# monte de vraies roues physiques et anime la portière conducteur.
# Repère Godot : l'AVANT d'un VehicleBody3D est +Z.
# Modèle actuel : Hennessy Vehnom GT 2010 par Eyasu Biyaylgn (CC-BY-4.0) - voir assets/vehicles/VEHNOM_CREDIT.txt

@export_category("Modèle")
## Vide = recherche automatique d'un .gltf/.glb dans res://assets/vehicles (hors ancienne jeep).
@export var model_path: String = ""
@export var model_scale: float = 1.0
## true = le capot du modèle est vers +Z (aucune rotation). false = le modèle est retourné de 180°.
@export var front_is_positive_z: bool = true
@export var wheel_keywords: PackedStringArray = ["wheel", "tire", "tyre", "roue"]
@export var wheel_exclude: PackedStringArray = ["brake", "caliper", "disc", "frein"]
@export var door_keywords: PackedStringArray = ["door", "porte", "portiere"]
@export var door_open_angle_deg: float = 62.0
## Opacité des vitres (0 = invisible, 1 = opaque) : plus bas = on voit mieux le conducteur de l'extérieur.
@export var glass_alpha: float = 0.28

@export_category("Conducteur")
## Position de l'ORIGINE du personnage (ses pieds) quand il est assis, dans le repère du véhicule.
## x > 0 = côté gauche (volant à gauche). Réglable en jeu avec les boutons Y/Z (show_seat_tuning dans mobile_controls.gd).
@export var seat_local: Vector3 = Vector3(0.20, -0.65, 1.70)
## Distance entre la carrosserie et l'endroit où le perso se tient pour monter/descendre.
@export var door_stand_margin: float = 0.9

@export_category("Conduite")
@export var engine_force_per_wheel: float = 2200.0
@export var max_speed: float = 30.0            # m/s (~108 km/h)
@export var reverse_factor: float = 0.5
@export var brake_force: float = 35.0
@export var parking_brake_force: float = 10.0
@export var steer_limit: float = 0.42          # radians
@export var steer_speed: float = 3.0
@export var car_mass: float = 1400.0
## Garée, la voiture est beaucoup plus lourde : un piéton ne peut pas la déplacer.

# Entrées envoyées par le joueur
var steer_input: float = 0.0     # -1 gauche, +1 droite
var throttle_input: float = 0.0  # +1 avance, -1 recule
var brake_input: bool = false
var horn_active: bool = false

var is_player_driving: bool = false
var forward_speed: float = 0.0
var wheels: Array[VehicleWheel3D] = []

var _model: Node3D
## Boîte de collision du châssis (repère du véhicule) : sert à empêcher le joueur de traverser la voiture
var body_center: Vector3 = Vector3(0.0, 0.8, 1.6)
var body_half: Vector3 = Vector3(0.95, 0.5, 2.3)
var _parked_timer: float = 0.0
var _float_timer: float = 0.0    # filet anti-flottement : temps passé immobile en l'air
var _flipped_timer: float = 0.0  # filet anti-retournement : temps passé sur le toit/côté
var _door_stand_local: Vector3 = Vector3(2.0, 0.05, 1.8)
var _rest_length: float = 0.1
# Visuels des roues : pivot de braquage -> pivot de rotation -> pneu
var _steer_pivots: Array[Node3D] = []
var _spin_pivots: Array[Node3D] = []
var _tire_radius: Array[float] = []
var _tire_spin: Array[float] = []
var _hardpoints: Array[Vector3] = []
# Portières : {node, rest, hinge, dir, side, amount}
var _doors: Array[Dictionary] = []
var _driver_door: Dictionary = {}
var _horn_player: AudioStreamPlayer3D
# --- Sons du véhicule (res://assets/audio/ ; un fichier manquant est simplement ignoré) ---
const SFX_DIR: String = "res://assets/audio/"
var _snd_horn: AudioStreamPlayer3D
var _snd_start: AudioStreamPlayer3D
var _snd_rev: AudioStreamPlayer3D
var _snd_door_open: AudioStreamPlayer3D
var _snd_door_close: AudioStreamPlayer3D
var _snd_hit: AudioStreamPlayer3D
var _prev_velocity: Vector3 = Vector3.ZERO
var _hit_cooldown: float = 0.0
var _snd_skid: AudioStreamPlayer3D
var _eng_idle: AudioStreamPlayer3D
var _eng_cruise: AudioStreamPlayer3D
var _eng_high: AudioStreamPlayer3D
var _engine_on: bool = false
var _engine_delay: float = 0.0
var _rev_cooldown: float = 0.0
var _horn_was_active: bool = false
var _use_horn_sample: bool = false
var _horn_playback: AudioStreamGeneratorPlayback
var _horn_phase: float = 0.0
const HORN_RATE: float = 22050.0
const MODEL_CANDIDATES: Array[String] = [
        "res://assets/vehicles/scene.gltf",
        "res://assets/vehicles/hennessy_vehnom_gt_2010_fully_rigged_free/scene.gltf",
        "res://assets/vehicles/vehnom/scene.gltf",
        "res://assets/vehicles/car/scene.gltf",
]

func _ready() -> void:
        add_to_group("vehicle")
        collision_layer = 8   # couche "véhicules" : la caméra (masque 1) ne bute pas dessus
        collision_mask = 1
        mass = car_mass
        angular_damp = 1.2   # moins de balancement
        linear_damp = 0.05
        _build_from_model()
        _setup_audio()
        _setup_horn()

# ---------------------------------------------------------------- recherche du modèle

func _find_model_scene() -> PackedScene:
        var paths: Array[String] = []
        if not model_path.is_empty(): paths.append(model_path)
        paths.append_array(MODEL_CANDIDATES)
        paths.append_array(_scan_for_models("res://assets/vehicles", 3))
        for p: String in paths:
                if ResourceLoader.exists(p):
                        var scene: PackedScene = GameAssets.load_resource(p) as PackedScene
                        if scene != null:
                                print("Ch31: véhicule chargé depuis ", p)
                                return scene
        return null

func _scan_for_models(dir_path: String, depth: int) -> Array[String]:
        var out: Array[String] = []
        var da: DirAccess = DirAccess.open(dir_path)
        if da == null: return out
        for f: String in da.get_files():
                var fname: String = f.trim_suffix(".remap").trim_suffix(".import")
                var ext: String = fname.get_extension().to_lower()
                if (ext == "gltf" or ext == "glb") and not fname.to_lower().contains("jeep"):
                        var full: String = dir_path.path_join(fname)
                        if not out.has(full): out.append(full)
        if depth > 0:
                for d: String in da.get_directories():
                        out.append_array(_scan_for_models(dir_path.path_join(d), depth - 1))
        return out

# ---------------------------------------------------------------- outils de recherche dans le modèle

func _all_nodes(root: Node) -> Array[Node]:
        var out: Array[Node] = []
        var stack: Array[Node] = [root]
        while not stack.is_empty():
                var n: Node = stack.pop_back()
                out.append(n)
                for c: Node in n.get_children(): stack.append(c)
        return out

func _name_has(n: Node, keys: PackedStringArray) -> bool:
        var s: String = String(n.name).to_lower()
        for k: String in keys:
                if s.contains(k): return true
        return false

func _has_mesh(n: Node) -> bool:
        for m: Node in _all_nodes(n):
                if m is MeshInstance3D: return true
        return false

## Nœuds portant un des mots-clés (et aucun mot exclu), contenant des meshes, sans ancêtre déjà retenu.
func _topmost_matches(root: Node, keys: PackedStringArray, excludes: PackedStringArray) -> Array[Node3D]:
        var cands: Array[Node3D] = []
        for n: Node in _all_nodes(root):
                if n == root or not (n is Node3D): continue
                if _name_has(n, keys) and not _name_has(n, excludes) and _has_mesh(n):
                        cands.append(n as Node3D)
        var out: Array[Node3D] = []
        for c: Node3D in cands:
                var nested: bool = false
                for o: Node3D in cands:
                        if o != c and o.is_ancestor_of(c):
                                nested = true
                                break
                if not nested: out.append(c)
        return out

## Boîte englobante d'un nœud (tous ses meshes) dans le repère du véhicule.
func _node_aabb(n: Node3D) -> AABB:
        var inv: Transform3D = global_transform.affine_inverse()
        var result: AABB = AABB()
        var first: bool = true
        for m: Node in _all_nodes(n):
                if m is MeshInstance3D:
                        var mi: MeshInstance3D = m as MeshInstance3D
                        var box: AABB = inv * mi.global_transform * mi.get_aabb()
                        if first:
                                result = box; first = false
                        else:
                                result = result.merge(box)
        return result

# ---------------------------------------------------------------- construction

## Au-delà de cette distance les meshes du véhicule ne sont plus dessinés (LOD ;
## rentable dès qu'il y a plusieurs voitures garées ou roulantes)
const VISIBILITY_RANGE_M: float = 240.0

## LOD : coupe le dessin des meshes du véhicule au-delà de VISIBILITY_RANGE_M
func _apply_lod(root: Node) -> void:
        for n: Node in _all_nodes(root):
                if n is MeshInstance3D:
                        (n as MeshInstance3D).visibility_range_end = VISIBILITY_RANGE_M

func _build_from_model() -> void:
        var packed: PackedScene = _find_model_scene()
        if packed == null:
                push_error("Ch31: aucun modèle de véhicule trouvé dans res://assets/vehicles (voir model_path)")
                _build_fallback_box()
                return
        _model = packed.instantiate() as Node3D
        _model.name = "VehicleModel"
        _model.scale = Vector3.ONE * model_scale
        if not front_is_positive_z:
                _model.rotation.y = PI
        add_child(_model)

        var wheel_nodes: Array[Node3D] = _topmost_matches(_model, wheel_keywords, wheel_exclude)
        if wheel_nodes.size() > 4:
                wheel_nodes.sort_custom(func(a: Node3D, b: Node3D) -> bool: return _node_aabb(a).position.y < _node_aabb(b).position.y)
                wheel_nodes = wheel_nodes.slice(0, 4)
        if wheel_nodes.size() != 4:
                push_error("Ch31: 4 roues attendues, trouvées : %d (adapter wheel_keywords)" % wheel_nodes.size())
                _build_fallback_box()
                return

        # 1) Poser le véhicule sur le sol : le bas des roues passe à y = 0
        var lowest: float = INF
        for wn: Node3D in wheel_nodes:
                lowest = minf(lowest, _node_aabb(wn).position.y)
        _model.position.y -= lowest

        # 2) Mesures (après décalage, avant tout déplacement de nœud)
        var wheel_boxes: Array[AABB] = []
        var mean_z: float = 0.0
        for wn: Node3D in wheel_nodes:
                var b: AABB = _node_aabb(wn)
                wheel_boxes.append(b)
                mean_z += b.get_center().z / 4.0
        var brakes: Array[Node3D] = _topmost_matches(_model, PackedStringArray(["brake"]), PackedStringArray())
        var door_nodes: Array[Node3D] = _topmost_matches(_model, door_keywords, PackedStringArray())
        var whole: AABB = _node_aabb(_model)

        # 3) Roues physiques + pivots visuels
        for i in range(4):
                var wn: Node3D = wheel_nodes[i]
                var box: AABB = wheel_boxes[i]
                var center: Vector3 = box.get_center()
                var radius: float = maxf(box.size.y, box.size.z) * 0.5
                _rest_length = clampf(radius * 0.35, 0.08, 0.2)
                var wheel := VehicleWheel3D.new()
                wheel.name = "Wheel_%d" % i
                wheel.position = center + Vector3(0.0, _rest_length, 0.0)
                wheel.wheel_radius = radius
                wheel.wheel_rest_length = _rest_length
                wheel.suspension_travel = radius * 0.8
                wheel.suspension_stiffness = 45.0
                wheel.suspension_max_force = 14000.0
                wheel.wheel_friction_slip = 4.5
                wheel.wheel_roll_influence = 0.03
                wheel.use_as_traction = true
                wheel.use_as_steering = center.z > mean_z    # l'avant est vers +Z
                add_child(wheel)
                wheels.append(wheel)
                var steer_pivot := Node3D.new()
                steer_pivot.name = "SteerPivot_%d" % i
                steer_pivot.position = center
                add_child(steer_pivot)
                var spin_pivot := Node3D.new()
                spin_pivot.name = "SpinPivot"
                steer_pivot.add_child(spin_pivot)
                wn.reparent(spin_pivot, true)
                _steer_pivots.append(steer_pivot)
                _spin_pivots.append(spin_pivot)
                _tire_radius.append(maxf(radius, 0.05))
                _tire_spin.append(0.0)
                _hardpoints.append(wheel.position)

        # Disques de frein : suivent le braquage de leur roue mais ne tournent pas
        for br: Node3D in brakes:
                var bc: Vector3 = _node_aabb(br).get_center()
                var best: int = 0
                var best_d: float = INF
                for i in range(4):
                        var d: float = bc.distance_to(wheel_boxes[i].get_center())
                        if d < best_d: best_d = d; best = i
                if best_d < 0.6:
                        br.reparent(_steer_pivots[best], true)

        # 4) Portières : charnière = origine du nœud, ouverture vers l'extérieur
        var inv: Transform3D = global_transform.affine_inverse()
        var driver_side: float = 1.0 if seat_local.x >= 0.0 else -1.0
        var driver_door_z: float = seat_local.z
        for dn: Node3D in door_nodes:
                var dbox: AABB = _node_aabb(dn)
                var dcenter: Vector3 = dbox.get_center()
                if absf(dcenter.x) < 0.3: continue
                var rest: Transform3D = inv * dn.global_transform
                var hinge: Vector3 = rest.origin
                var side: float = 1.0 if dcenter.x > 0.0 else -1.0
                var dz: float = dcenter.z - hinge.z
                var zsign: float = 1.0 if absf(dz) < 0.05 else signf(dz)
                var door: Dictionary = {"node": dn, "rest": rest, "hinge": hinge, "dir": side * zsign, "side": side, "amount": 0.0}
                _doors.append(door)
                if side == driver_side and _driver_door.is_empty():
                        _driver_door = door
                        driver_door_z = dcenter.z
        var half_w: float = maxf(absf(whole.position.x), absf(whole.end.x))
        _door_stand_local = Vector3(driver_side * (half_w + door_stand_margin), 0.05, driver_door_z)

        # 5) Collision du châssis : une boîte à hauteur des essieux jusqu'au toit
        var low_y: float = wheel_boxes[0].get_center().y
        var size := Vector3(whole.size.x * 0.92, maxf(whole.end.y - low_y, 0.5), whole.size.z * 0.95)
        var col := CollisionShape3D.new()
        col.name = "ChassisCollision"
        var shape := BoxShape3D.new()
        shape.size = size
        col.shape = shape
        col.position = Vector3(whole.get_center().x, low_y + size.y * 0.5, whole.get_center().z)
        add_child(col)
        body_center = col.position
        body_half = size * 0.5

        # 6) Centre de gravité bas pour éviter les tonneaux
        center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
        center_of_mass = Vector3(0.0, low_y - 0.05, whole.get_center().z)
        _tune_glass()
        _apply_lod(_model)
        print("Ch31: véhicule prêt - roues %d, portières %d (conducteur : %s)" % [wheels.size(), _doors.size(), "oui" if not _driver_door.is_empty() else "non"])

## Rend les vitres plus transparentes pour que le conducteur soit visible de l'extérieur.
func _tune_glass() -> void:
        for n: Node in _all_nodes(_model):
                if not (n is MeshInstance3D): continue
                var mi: MeshInstance3D = n as MeshInstance3D
                for s in range(mi.get_surface_override_material_count()):
                        var mat: Material = mi.get_active_material(s)
                        var is_glass: bool = false
                        if mat is BaseMaterial3D:
                                var bm: BaseMaterial3D = mat as BaseMaterial3D
                                var rn: String = bm.resource_name.to_lower()
                                is_glass = rn.contains("window") or rn.contains("glass") or (bm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and bm.albedo_color.a < 0.95)
                        if is_glass:
                                var glass: BaseMaterial3D = (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
                                var c: Color = glass.albedo_color
                                c.a = minf(c.a, glass_alpha)
                                glass.albedo_color = c
                                glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
                                mi.set_surface_override_material(s, glass)

func _build_fallback_box() -> void:
        # Secours si le modèle manque ou n'a pas 4 roues : une boîte qui roule.
        var mi := MeshInstance3D.new()
        var bm := BoxMesh.new()
        bm.size = Vector3(2.0, 1.0, 4.4)
        mi.mesh = bm
        mi.position.y = 1.0
        add_child(mi)
        _apply_lod(mi)
        var col := CollisionShape3D.new()
        var shape := BoxShape3D.new()
        shape.size = bm.size
        col.shape = shape
        col.position.y = 1.0
        add_child(col)
        for p: Vector3 in [Vector3(-1, 0.4, -1.5), Vector3(1, 0.4, -1.5), Vector3(-1, 0.4, 1.5), Vector3(1, 0.4, 1.5)]:
                var w := VehicleWheel3D.new()
                w.position = p
                w.wheel_radius = 0.4
                w.use_as_traction = true
                w.use_as_steering = p.z > 0.0
                add_child(w)
                wheels.append(w)
        body_center = Vector3(0.0, 1.0, 0.0)   # cohérent avec la boîte de secours (2 × 1 × 4,4 à y = 1)
        body_half = Vector3(1.0, 0.5, 2.2)

# ---------------------------------------------------------------- portière conducteur

var _door_target_open: bool = false

func toggle_driver_door() -> void:
        _door_target_open = not _door_target_open
        open_driver_door(_door_target_open)

## À appeler quand quelqu'un monte : la voiture redevient mobile
func wake_up() -> void:
        freeze = false
        sleeping = false

func _play_door_close() -> void:
        if _snd_door_close != null and _snd_door_close.stream != null: _snd_door_close.play()

func has_driver_door() -> bool:
        return not _driver_door.is_empty()

func open_driver_door(open: bool, duration: float = 0.6) -> void:
        if _driver_door.is_empty(): return
        if open:
                if _snd_door_open != null and _snd_door_open.stream != null: _snd_door_open.play()
        else:
                # le claquement arrive quand la portière est presque fermée
                # Connecte directement la méthode (pas de lambda inline) : si le véhicule est libéré
                # avant la fin du délai, Godot retire tout seul la connexion d'un objet supprimé.
                get_tree().create_timer(duration * 0.85, false).timeout.connect(_play_door_close)   # false : respecte la pause
        var tw: Tween = create_tween()
        var from_v: float = float(_driver_door["amount"])
        tw.tween_method(_set_door_amount.bind(_driver_door), from_v, 1.0 if open else 0.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _set_door_amount(amount: float, door: Dictionary) -> void:
        door["amount"] = amount
        var node: Node3D = door["node"]
        if not is_instance_valid(node): return
        var theta: float = deg_to_rad(door_open_angle_deg) * amount * float(door["dir"])
        var h: Vector3 = door["hinge"]
        var rot: Basis = Basis(Vector3.UP, theta)
        var rest: Transform3D = door["rest"]
        node.global_transform = global_transform * (Transform3D(rot, h - rot * h) * rest)

# ---------------------------------------------------------------- repères pour le joueur

func get_seat_global() -> Vector3:
        return to_global(seat_local)

## -1 = portière à droite, +1 = à gauche (du côté du siège conducteur, x > 0 = gauche)
func _door_side() -> float:
        return 1.0 if seat_local.x >= 0.0 else -1.0

func get_door_global() -> Vector3:
        return to_global(Vector3(_door_side() * absf(_door_stand_local.x), _door_stand_local.y, _door_stand_local.z))

## Direction monde allant de la portière vers l'intérieur du véhicule.
func get_door_inward_dir() -> Vector3:
        var d: Vector3 = global_transform.basis.x * -_door_side()
        d.y = 0.0
        return d.normalized()

func get_heading_yaw() -> float:
        var fwd: Vector3 = global_transform.basis.z   # avant = +Z
        return atan2(-fwd.x, -fwd.z)   # yaw "caméra" : la caméra regarde vers l'avant du véhicule

# ---------------------------------------------------------------- physique

func _physics_process(delta: float) -> void:
        forward_speed = global_transform.basis.z.dot(linear_velocity)   # avant = +Z
        if wheels.is_empty():
                return
        _update_audio(delta)
        _prev_velocity = linear_velocity
        _update_tires(delta)
        _anti_stuck(delta)

        if not is_player_driving:
                # À l'arrêt : frein de parking, plus de moteur, roues droites
                for w: VehicleWheel3D in wheels:
                        w.engine_force = 0.0
                        w.brake = parking_brake_force
                        w.steering = move_toward(w.steering, 0.0, steer_speed * delta)
                horn_active = false
                return

        # Stabilité : appui aérodynamique + couple de redressement si la voiture penche trop
        apply_central_force(-global_transform.basis.y * 2.5 * linear_velocity.length_squared())
        var tilt_axis: Vector3 = global_transform.basis.y.cross(Vector3.UP)
        if tilt_axis.length() > 0.45:
                apply_torque(tilt_axis.normalized() * (tilt_axis.length() - 0.4) * 9000.0 * car_mass / 1400.0)   # couple proportionnel à la masse

        # Direction (moins braquée à haute vitesse)
        var speed_ratio: float = clampf(absf(forward_speed) / max_speed, 0.0, 1.0)
        var target_steer: float = -steer_input * steer_limit * lerpf(1.0, 0.10, pow(speed_ratio, 0.6))   # très peu de braquage à haute vitesse (sinon la voiture se retourne)
        for w: VehicleWheel3D in wheels:
                if w.use_as_steering:
                        w.steering = move_toward(w.steering, target_steer, steer_speed * delta)

        # Moteur / frein
        var engine: float = 0.0
        var brake: float = 0.0
        if brake_input:
                brake = brake_force
        elif throttle_input > 0.05:
                if forward_speed < -1.0:
                        brake = brake_force * throttle_input   # on roule en arrière : freiner d'abord
                elif forward_speed < max_speed:
                        engine = engine_force_per_wheel * throttle_input * (1.0 - 0.55 * speed_ratio)   # moins de poussée à haute vitesse
        elif throttle_input < -0.05:
                if forward_speed > 1.5:
                        brake = brake_force * -throttle_input  # on roule en avant : freiner
                elif forward_speed > -max_speed * 0.4:
                        engine = engine_force_per_wheel * reverse_factor * throttle_input
        else:
                brake = 2.0   # léger frein moteur
        for w: VehicleWheel3D in wheels:
                w.engine_force = engine
                w.brake = brake

# --------------------------------------------- filets de sécurité (voiture bloquée)

## Une voiture inoccupée ne doit jamais rester coincée en l'air (posée sur le joueur,
## sur un obstacle disparu, projetée puis figée par un choc) ni rester sur le toit.
## Tant que le joueur conduit, on ne touche à rien (les sauts et décollages sont légitimes).
func _anti_stuck(delta: float) -> void:
        if is_player_driving:
                _float_timer = 0.0
                _flipped_timer = 0.0
                return
        var slow: bool = Vector3(linear_velocity.x, 0.0, linear_velocity.z).length() < 1.2 and absf(linear_velocity.y) < 1.2
        var upness: float = global_transform.basis.y.dot(Vector3.UP)
        # Cas 1 : sur le toit ou sur le côté, immobile depuis 3 s -> on la redresse.
        # Prioritaire : on ne doit pas l'enfoncer dans le sol avant de l'avoir remise droite.
        if upness < 0.35:
                _float_timer = 0.0
                if slow:
                        _flipped_timer += delta
                        if _flipped_timer > 3.0:
                                _re_right()
                else:
                        _flipped_timer = 0.0
                return
        _flipped_timer = 0.0
        # Cas 2 : flotte de plus de 0,9 m au-dessus du premier support solide, immobile
        # depuis 2,5 s -> on la repose dessus (x/z conservés).
        var ground_y := _ground_below()
        if ground_y != INF:
                var height: float = global_position.y - ground_y
                if height > 0.9 and slow:
                        _float_timer += delta
                        if _float_timer > 2.5:
                                global_position = Vector3(global_position.x, ground_y + 0.02, global_position.z)
                                linear_velocity.y = 0.0
                                sleeping = false
                                _float_timer = 0.0
                else:
                        _float_timer = 0.0

## Hauteur du premier support solide sous la voiture (INF = rien trouvé en 6 m).
## La voiture elle-même est exclue du rayon ; le joueur (CharacterBody3D) n'est pas un
## support fiable : si le rayon le touche, on continue en dessous de lui.
func _ground_below() -> float:
        var space := get_world_3d().direct_space_state
        var from: Vector3 = global_position + Vector3.UP * 0.5
        var to: Vector3 = global_position + Vector3.DOWN * 6.0
        var params := PhysicsRayQueryParameters3D.create(from, to)
        var exclude: Array[RID] = [get_rid()]
        params.exclude = exclude
        var hit := space.intersect_ray(params)
        for _i in 4:
                if hit.is_empty() or not (hit["collider"] is CharacterBody3D):
                        break
                params.from = hit["position"] + Vector3.DOWN * 0.05
                hit = space.intersect_ray(params)
        if hit.is_empty():
                return INF
        return hit["position"].y

## Redresse la voiture sur ses roues en conservant son cap, posée sur ce qui se trouve dessous.
func _re_right() -> void:
        var yaw: float = global_transform.basis.get_euler().y
        var ground_y := _ground_below()
        var y: float = (ground_y if ground_y != INF else global_position.y) + 0.05
        global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(global_position.x, y, global_position.z))
        linear_velocity = Vector3(linear_velocity.x * 0.3, 0.0, linear_velocity.z * 0.3)
        angular_velocity = Vector3.ZERO
        sleeping = false
        _flipped_timer = 0.0
        _float_timer = 0.0

# ---------------------------------------------------------------- pneus visuels

func _update_tires(delta: float) -> void:
        for i in range(mini(wheels.size(), _steer_pivots.size())):
                var w: VehicleWheel3D = wheels[i]
                # Position : suit la roue physique (suspension) ; sinon hauteur de repos
                var moved: bool = w.position.distance_to(_hardpoints[i]) > 0.002
                _steer_pivots[i].position = w.position if moved else _hardpoints[i] - Vector3(0.0, _rest_length, 0.0)
                _steer_pivots[i].basis = Basis(Vector3.UP, w.steering)
                # Rotation : le véhicule avance vers +Z, le haut du pneu tourne vers +Z (angle positif autour de X)
                _tire_spin[i] = fmod(_tire_spin[i] + forward_speed * delta / _tire_radius[i], TAU)
                _spin_pivots[i].basis = Basis(Vector3.RIGHT, _tire_spin[i])

# ---------------------------------------------------------------- klaxon

func _setup_horn() -> void:
        if _use_horn_sample:
                return   # klaxon fourni en fichier audio : le générateur temps réel est inutile (économie CPU/batterie)
        var gen := AudioStreamGenerator.new()
        gen.mix_rate = HORN_RATE
        gen.buffer_length = 0.15
        _horn_player = AudioStreamPlayer3D.new()
        _horn_player.stream = gen
        _horn_player.unit_size = 12.0
        add_child(_horn_player)
        _horn_player.play()
        _horn_playback = _horn_player.get_stream_playback() as AudioStreamGeneratorPlayback

# ---------------------------------------------------------------- sons

func _make_sfx3d(file_name: String, volume_db: float, loop: bool = false, max_dist: float = 90.0) -> AudioStreamPlayer3D:
        var player := AudioStreamPlayer3D.new()
        player.volume_db = volume_db
        player.unit_size = 14.0
        player.max_distance = max_dist
        var path: String = SFX_DIR + file_name
        if ResourceLoader.exists(path):
                var stream: AudioStream = GameAssets.load_resource(path) as AudioStream
                if loop and stream != null: stream = GameAssets.make_looping(stream)
                player.stream = stream
        add_child(player)
        return player

func _setup_audio() -> void:
        _snd_horn = _make_sfx3d("horn.ogg", 2.0)
        _use_horn_sample = _snd_horn.stream != null
        _snd_start = _make_sfx3d("engine_start.ogg", 0.0)
        _snd_rev = _make_sfx3d("engine_rev.ogg", -2.0)
        _snd_door_open = _make_sfx3d("door_open.ogg", 2.0, false, 40.0)
        _snd_door_close = _make_sfx3d("door_close.ogg", 3.0, false, 40.0)
        _snd_hit = _make_sfx3d("car_hit.ogg", 2.0, false, 120.0)
        contact_monitor = true
        max_contacts_reported = 4
        body_entered.connect(_on_body_hit)
        _snd_skid = _make_sfx3d("tire_skid.ogg", -80.0, true)
        _eng_idle = _make_sfx3d("engine_idle.ogg", -80.0, true)
        _eng_cruise = _make_sfx3d("engine_cruise.ogg", -80.0, true)
        _eng_high = _make_sfx3d("engine_high.ogg", -80.0, true)

func _set_loop_volume(player: AudioStreamPlayer3D, weight: float, base_db: float) -> void:
        if player == null or player.stream == null: return
        if weight <= 0.01:
                if player.playing: player.stop()
                return
        player.volume_db = base_db + linear_to_db(weight)
        if not player.playing: player.play()

func _stop_engine_sounds() -> void:
        for p: AudioStreamPlayer3D in [_eng_idle, _eng_cruise, _eng_high, _snd_skid]:
                if p != null and p.playing: p.stop()

## Choc de carrosserie : on compare la vitesse avant/après le contact (le sol ne déclenche rien : choc < 6 m/s)
func _on_body_hit(_body: Node) -> void:
        if _hit_cooldown > 0.0 or _snd_hit == null or _snd_hit.stream == null: return
        var impact: float = (_prev_velocity - linear_velocity).length()
        if impact < 6.0: return
        _snd_hit.volume_db = lerpf(-6.0, 6.0, clampf((impact - 6.0) / 14.0, 0.0, 1.0))
        _snd_hit.play()
        if OS.has_feature("mobile"):
                Input.vibrate_handheld(60 + int(clampf((impact - 6.0) / 14.0, 0.0, 1.0) * 80.0))   # retour tactile dosé par la violence du choc (60-140 ms)
        _hit_cooldown = 0.6

func _update_audio(delta: float) -> void:
        _hit_cooldown = maxf(0.0, _hit_cooldown - delta)
        # Klaxon (vrai son) : démarre à l'appui, coupe au relâchement
        if _use_horn_sample:
                if horn_active and not _horn_was_active: _snd_horn.volume_db = 2.0; _snd_horn.play()
                elif not horn_active and _horn_was_active and _snd_horn.playing: _snd_horn.stop()
                _horn_was_active = horn_active
        # Moteur : seulement quand quelqu'un conduit
        if not is_player_driving:
                if _engine_on:
                        _engine_on = false
                        _stop_engine_sounds()
                return
        if not _engine_on:
                _engine_on = true
                _engine_delay = 1.4   # le temps du bruit de démarrage
                _rev_cooldown = 0.0
                if _snd_start.stream != null: _snd_start.play()
        _rev_cooldown = maxf(0.0, _rev_cooldown - delta)
        if _engine_delay > 0.0:
                _engine_delay -= delta
                return
        var speed: float = absf(forward_speed)
        var throttle: float = clampf(absf(throttle_input), 0.0, 1.0)
        # Trois couches qui se fondent selon la vitesse : ralenti, croisière, haut régime
        var w_idle: float = clampf(1.0 - speed / 5.0, 0.0, 1.0)
        var w_cruise: float = clampf(1.0 - absf(speed - 12.0) / 11.0, 0.0, 1.0)
        var w_high: float = clampf((speed - 12.0) / 14.0, 0.0, 1.0)
        var load_db: float = throttle * 2.0
        if _eng_idle != null: _eng_idle.pitch_scale = 0.92 + 0.16 * throttle
        if _eng_cruise != null: _eng_cruise.pitch_scale = lerpf(0.85, 1.25, clampf((speed - 4.0) / 14.0, 0.0, 1.0))
        if _eng_high != null: _eng_high.pitch_scale = lerpf(0.9, 1.2, clampf((speed - 12.0) / 18.0, 0.0, 1.0))
        _set_loop_volume(_eng_idle, w_idle, -3.0 + load_db)
        _set_loop_volume(_eng_cruise, w_cruise, -4.0 + load_db)
        _set_loop_volume(_eng_high, w_high, -4.0 + load_db)
        # Coup d'accélérateur à l'arrêt
        if throttle > 0.6 and speed < 2.0 and _rev_cooldown <= 0.0 and _snd_rev.stream != null:
                _snd_rev.play()
                _rev_cooldown = 6.0
        # Crissement de pneus : glissement latéral ou gros freinage à vitesse élevée
        var lateral: float = absf(global_transform.basis.x.dot(linear_velocity))
        var skid: float = clampf((lateral - 2.5) / 5.0, 0.0, 1.0)
        if (brake_input or (throttle_input < -0.05 and forward_speed > 8.0)) and speed > 10.0:
                skid = maxf(skid, clampf((speed - 10.0) / 14.0, 0.25, 0.8))
        _set_loop_volume(_snd_skid, skid, -2.0)

func _process(_delta: float) -> void:
        if _horn_playback == null:
                return
        var frames: int = _horn_playback.get_frames_available()
        if frames <= 0:
                return
        var buf := PackedVector2Array()
        buf.resize(frames)   # silence par défaut
        if horn_active and not _use_horn_sample:
                for i in range(frames):
                        _horn_phase = fmod(_horn_phase + 1.0 / HORN_RATE, 1.0)
                        var v: float = (sin(TAU * 420.0 * _horn_phase) + sin(TAU * 530.0 * _horn_phase)) * 0.14
                        buf[i] = Vector2(v, v)
        _horn_playback.push_buffer(buf)
