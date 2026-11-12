extends CharacterBody3D
class_name PlayerCharacter
# Ch31 - contrôleur avec gestion des véhicules

signal camera_mode_changed(first_person: bool)

const HudScript := preload("res://scripts/hud.gd")

@export_category("Movement")
@export var walk_speed: float = 3.0
@export var run_speed: float = 6.0
@export var acceleration: float = 20.0
@export var air_acceleration: float = 8.0
@export var rotation_speed: float = 11.0
@export var jump_velocity: float = 5.4

@export_category("Camera")
@export var camera_distance: float = 4.4
@export var touch_camera_sensitivity: float = 0.006
@export var mouse_sensitivity: float = 0.0025
@export var gamepad_look_speed: float = 2.8
@export var min_pitch: float = -1.1
@export var max_pitch: float = 0.65
@export var fps_min_pitch: float = -1.45
@export var fps_max_pitch: float = 1.45
@export var start_first_person: bool = false

@export_category("Animation")
@export var animation_fade: float = 0.10

# CORRECTION CRITIQUE : Plus d'espaces dans les clés et les valeurs !
const ANIM_FILES: Dictionary = {
        "Idle": "res://assets/animations/Idle.fbx",
        "Walking": "res://assets/animations/Walking.fbx",
        "Running": "res://assets/animations/Running.fbx",
        "Jump": "res://assets/animations/Jump.fbx",
        # Pack voiture (Mixamo)
        "Driving": "res://assets/animations/car/Driving.fbx",
        "Entering_Car": "res://assets/animations/car/Entering_Car.fbx",
        "Exiting_Car": "res://assets/animations/car/Exiting_Car.fbx",
        "Honking_Horn": "res://assets/animations/car/Honking_Horn.fbx",
}

const LOOPING: Dictionary = {
        "Idle": true, "Walking": true, "Running": true, "Jump": false, "Driving": true,
        "Entering_Car": false, "Exiting_Car": false, "Honking_Horn": false,
}

@onready var visual: Node3D = $Visual
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var mobile_controls: MobileControls = $MobileUI/MobileControls
@onready var camera_rig: Node3D = $CameraRig
@onready var camera_pivot: Node3D = $CameraRig/PitchPivot
@onready var spring_arm: SpringArm3D = $CameraRig/PitchPivot/SpringArm3D
@onready var camera: Camera3D = $CameraRig/PitchPivot/SpringArm3D/Camera3D

var skeleton: Skeleton3D
var hud = null
var animation_ready: bool = false
var current_animation: String = ""
var action_lock: String = ""
var yaw: float = 0.0
var pitch: float = -0.18
var facing_yaw: float = PI
var first_person: bool = false
var fov_base: float = 75.0   # FOV de repos (lu au démarrage), base du FOV dynamique
var spawn_position: Vector3 = Vector3.ZERO

# --- VÉHICULE ---
var is_driving: bool = false
## "" = à pied, "entering" / "driving" / "exiting"
var vehicle_state: String = ""
var _horn_prev: bool = false
var _rig_home: Vector3 = Vector3(0.0, 1.45, 0.0)
var _arm_home: Vector3 = Vector3.ZERO
# --- Sons (fichiers dans res://assets/audio/ ; si un fichier manque, le son est simplement ignoré) ---
const SFX_DIR: String = "res://assets/audio/"
var _sfx_walk: AudioStreamPlayer
var _sfx_run: AudioStreamPlayer
var _sfx_jump: AudioStreamPlayer
var _sfx_land: AudioStreamPlayer
var _sfx_click: AudioStreamPlayer
var _was_on_floor: bool = true
var _step_timer: float = 0.0
var _fp_before_seq: bool = false
var _cam_free_left: float = 0.0
## Animations dont on garde le déplacement du bassin (marche vers la portière, s'asseoir, sortir)
const ROOT_MOTION_ANIMS: Array[String] = []
var _keep_root: bool = false
var _saved_arm_mask: int = 1
var _saved_collision_layer: int = 1
var _saved_collision_mask: int = 9
var current_vehicle: GameVehicle = null
var nearest_vehicle: GameVehicle = null
var enter_distance: float = 4.5

var _mouse_look: Vector2 = Vector2.ZERO
var _mouse_horn_held: bool = false
var _bone_map: Dictionary = {}
var _unmapped_tracks: int = 0

func _ready() -> void:
        _rig_home = camera_rig.position   # hauteur d'origine de la caméra à pied
        _setup_sfx()
        _arm_home = spring_arm.position
        add_to_group("player")
        collision_mask = 1 | 8   # sol/murs (1) et véhicules (8) : on ne traverse pas la voiture
        spawn_position = global_position
        _setup_input_map()
        var touch_ui: bool = OS.has_feature("mobile") or (DisplayServer.is_touchscreen_available() and not OS.has_feature("pc"))
        mobile_controls.visible = touch_ui
        if OS.has_feature("mobile"):
                DisplayServer.screen_set_orientation(DisplayServer.SCREEN_LANDSCAPE)
        else:
                Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
        spring_arm.collision_mask = 1
        spring_arm.add_excluded_object(get_rid())
        fov_base = camera.fov
        camera_pivot.rotation.x = pitch
        camera_pivot.rotation.y = yaw
        visual.rotation.y = facing_yaw
        hud = HudScript.new()
        add_child(hud)
        camera_mode_changed.connect(hud.set_first_person)
        Input.joy_connection_changed.connect(_on_joy_connection_changed)
        _set_first_person(start_first_person, false)
        _disable_nested_animation_players(visual)
        call_deferred("_initialize_character")

func _setup_input_map() -> void:
        _bind_key("move_forward", KEY_W)
        _bind_key("move_forward", KEY_UP)
        _bind_key("move_backward", KEY_S)
        _bind_key("move_backward", KEY_DOWN)
        _bind_key("move_left", KEY_A)
        _bind_key("move_left", KEY_LEFT)
        _bind_key("move_right", KEY_D)
        _bind_key("move_right", KEY_RIGHT)
        _bind_key("run", KEY_SHIFT)
        _bind_key("jump", KEY_SPACE)
        _bind_key("horn", KEY_F)
        _bind_key("toggle_camera", KEY_V)
        _bind_key("toggle_fps", KEY_F3)
        _bind_key("enter_vehicle", KEY_E) # NOUVEAU
        _bind_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
        _bind_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
        _bind_axis("move_forward", JOY_AXIS_LEFT_Y, -1.0)
        _bind_axis("move_backward", JOY_AXIS_LEFT_Y, 1.0)
        _bind_axis("look_left", JOY_AXIS_RIGHT_X, -1.0)
        _bind_axis("look_right", JOY_AXIS_RIGHT_X, 1.0)
        _bind_axis("look_up", JOY_AXIS_RIGHT_Y, -1.0)
        _bind_axis("look_down", JOY_AXIS_RIGHT_Y, 1.0)
        _bind_button("run", JOY_BUTTON_A)
        _bind_button("jump", JOY_BUTTON_X)
        _bind_button("horn", JOY_BUTTON_B)
        _bind_button("toggle_camera", JOY_BUTTON_BACK)
        _bind_button("toggle_fps", JOY_BUTTON_DPAD_DOWN)
        _bind_button("enter_vehicle", JOY_BUTTON_Y) # NOUVEAU

func _ensure_action(action_name: StringName, deadzone: float = 0.2) -> void:
        if not InputMap.has_action(action_name): InputMap.add_action(action_name, deadzone)
func _bind_event(action_name: StringName, event: InputEvent, deadzone: float = 0.2) -> void:
        _ensure_action(action_name, deadzone)
        if not InputMap.action_has_event(action_name, event): InputMap.action_add_event(action_name, event)
func _bind_key(action_name: StringName, keycode: Key) -> void:
        var event := InputEventKey.new(); event.physical_keycode = keycode; _bind_event(action_name, event)
func _bind_mouse_button(action_name: StringName, button: MouseButton) -> void:
        var event := InputEventMouseButton.new(); event.button_index = button; _bind_event(action_name, event)
func _bind_button(action_name: StringName, button: JoyButton) -> void:
        var event := InputEventJoypadButton.new(); event.button_index = button; _bind_event(action_name, event)
func _bind_axis(action_name: StringName, axis: JoyAxis, value: float, deadzone: float = 0.2) -> void:
        var event := InputEventJoypadMotion.new(); event.axis = axis; event.axis_value = value; _bind_event(action_name, event, deadzone)

func _unhandled_input(event: InputEvent) -> void:
        if event.is_action_pressed("toggle_camera"): _set_first_person(not first_person); return
        if event.is_action_pressed("toggle_fps") and hud != null: hud.toggle_fps(); return
        if OS.has_feature("mobile"): return
        if event is InputEventMouseButton:
                var button_event: InputEventMouseButton = event as InputEventMouseButton
                if button_event.button_index == MOUSE_BUTTON_LEFT:
                        if button_event.pressed:
                                if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
                                else: _mouse_horn_held = true
                        else: _mouse_horn_held = false
        elif event is InputEventMouseMotion:
                if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED: _mouse_look += (event as InputEventMouseMotion).screen_relative
        elif event.is_action_pressed("ui_cancel"): Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _notification(what: int) -> void:
        if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not OS.has_feature("mobile"):
                Input.mouse_mode = Input.MOUSE_MODE_VISIBLE; _mouse_horn_held = false

func _on_joy_connection_changed(device: int, connected: bool) -> void:
        if hud == null: return
        if connected: hud.show_message("Manette connectée : " + Input.get_joy_name(device), 2.0)
        else: hud.show_message("Manette déconnectée", 2.0)

func _set_first_person(value: bool, announce: bool = true) -> void:
        first_person = value
        visual.visible = not value
        spring_arm.spring_length = 0.0 if value else camera_distance
        var low: float = fps_min_pitch if value else min_pitch
        var high: float = fps_max_pitch if value else max_pitch
        pitch = clampf(pitch, low, high)
        camera_pivot.rotation.x = pitch
        if announce: _play_sfx(_sfx_click); camera_mode_changed.emit(value)
        elif hud != null: hud.set_first_person(value, false)

func _apply_look(delta: float) -> void:
        var look: Vector2 = Vector2.ZERO
        if is_instance_valid(mobile_controls): look += mobile_controls.consume_look_delta() * touch_camera_sensitivity * GameSettings.camera_sensitivity
        look += _mouse_look * mouse_sensitivity * GameSettings.camera_sensitivity
        _mouse_look = Vector2.ZERO
        look += Input.get_vector("look_left", "look_right", "look_up", "look_down") * gamepad_look_speed * delta
        var low: float = fps_min_pitch if first_person else min_pitch
        var high: float = fps_max_pitch if first_person else max_pitch
        if look.length_squared() > 0.0000001:
                yaw -= look.x; pitch -= look.y; pitch = clampf(pitch, low, high)
        camera_pivot.rotation.y = yaw
        camera_pivot.rotation.x = clampf(pitch, fps_min_pitch, fps_max_pitch)

## Distance de la caméra (3e personne), plus reculée en voiture — lissée à la main :
## Camera3D n'a plus de lissage de position en Godot 4.7, on lisse donc la longueur
## du bras (dolly doux entre « à pied » et « en voiture », caméra collée sinon)
func _update_camera_distance(delta: float) -> void:
        if first_person:
                spring_arm.spring_length = 0.0
        else:
                var target: float = camera_distance + (1.4 if vehicle_state == "driving" else 0.0)
                spring_arm.spring_length = lerpf(spring_arm.spring_length, target, minf(1.0, 8.0 * delta))
        spring_arm.position.x = 0.0

## FOV dynamique : ouvre légèrement le champ avec la vitesse (sensation de vitesse, à pied et en voiture)
func _update_dynamic_fov(delta: float, speed: float) -> void:
        var target: float = fov_base + clampf(speed / 18.0, 0.0, 1.0) * 9.0
        camera.fov = lerpf(camera.fov, target, minf(1.0, 4.0 * delta))

func _initialize_character() -> void:
        skeleton = _find_skeleton(visual)
        if skeleton == null: push_error("Ch31: Skeleton3D introuvable."); return
        animation_player.root_node = NodePath("../Visual")
        _build_animation_library()
        animation_ready = animation_player.has_animation_library(&"mixamo")
        if not animation_ready: push_error("Ch31: bibliothèque d'animations introuvable."); return
        _play_animation("Idle", true)
        if not animation_player.animation_finished.is_connected(_on_animation_finished):
                animation_player.animation_finished.connect(_on_animation_finished)

func _physics_process(delta: float) -> void:
        var jump_pressed: bool = _jump_requested()
        if is_instance_valid(mobile_controls) and mobile_controls.consume_camera_toggle(): _set_first_person(not first_person)

        # --- GESTION VÉHICULE ---
        _check_vehicle_interaction()
        if vehicle_state != "":
                _vehicle_process(delta)
                return
        if is_instance_valid(mobile_controls): mobile_controls.vehicle_mode = false

        var move_input: Vector2 = Vector2.ZERO
        var running: bool = false
        var run_touch: bool = false
        if is_instance_valid(mobile_controls):
                move_input = mobile_controls.move_vector; run_touch = mobile_controls.run_held
        if move_input.length_squared() <= 0.01: move_input = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
        running = run_touch or Input.is_action_pressed("run")
        var has_input: bool = move_input.length_squared() > 0.01
        if not is_on_floor():
                var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
                velocity.y -= gravity * delta
        elif jump_pressed and action_lock.is_empty():
                velocity.y = jump_velocity; action_lock = "Jump"; _play_sfx(_sfx_jump); _play_animation("Jump", true)
        var direction: Vector3 = Vector3.ZERO
        if has_input:
                var yaw_basis: Basis = Basis(Vector3.UP, yaw)
                direction = yaw_basis * Vector3(move_input.x, 0.0, move_input.y); direction.y = 0.0; direction = direction.normalized()
        var speed_scale: float = lerpf(0.6, 1.0, clampf(move_input.length(), 0.0, 1.0))
        var top_speed: float = run_speed if running else walk_speed
        var target_speed: float = top_speed * speed_scale
        var target_velocity: Vector3 = direction * target_speed if has_input else Vector3.ZERO
        var accel: float = acceleration if is_on_floor() else air_acceleration
        velocity.x = move_toward(velocity.x, target_velocity.x, accel * delta)
        velocity.z = move_toward(velocity.z, target_velocity.z, accel * delta)
        _reset_camera_rig()
        var vy_before: float = velocity.y
        move_and_slide()
        _update_landing(vy_before)
        _push_out_of_vehicles()
        _anti_sink()
        _update_footsteps(delta, running)
        if action_lock == "Jump" and is_on_floor() and velocity.y <= 0.0: action_lock = ""
        _apply_look(delta)
        _update_camera_distance(delta)
        _update_dynamic_fov(delta, Vector3(velocity.x, 0.0, velocity.z).length())
        if first_person: facing_yaw = yaw + PI; _apply_facing()
        elif has_input: var target_angle: float = atan2(direction.x, direction.z); facing_yaw = lerp_angle(facing_yaw, target_angle, minf(1.0, rotation_speed * delta)); _apply_facing()
        if not action_lock.is_empty(): return
        if not is_on_floor(): _play_animation("Jump")
        elif has_input: _play_animation("Running" if running else "Walking")
        else: _play_animation("Idle")

# --- INTERACTION VÉHICULE ---
func _check_vehicle_interaction() -> void:
        nearest_vehicle = null
        var pressed: bool = Input.is_action_just_pressed("enter_vehicle") or (is_instance_valid(mobile_controls) and mobile_controls.consume_enter_exit())
        var key: String = "Y" if not Input.get_connected_joypads().is_empty() else ("CAR" if (is_instance_valid(mobile_controls) and DisplayServer.is_touchscreen_available()) else "E")
        match vehicle_state:
                "":
                        var min_dist: float = enter_distance
                        for v in get_tree().get_nodes_in_group("vehicle"):
                                var dist: float = global_position.distance_to(v.global_position)
                                if dist < min_dist: min_dist = dist; nearest_vehicle = v
                        if nearest_vehicle != null:
                                hud.show_prompt("Appuyer sur %s pour monter" % key)
                                if pressed: _start_enter(nearest_vehicle)
                        else:
                                hud.hide_prompt()
                "driving":
                        if current_vehicle != null and absf(current_vehicle.forward_speed) < 4.0:
                                hud.show_prompt("Appuyer sur %s pour descendre" % key)
                                if pressed: _start_exit()
                        else:
                                hud.show_prompt("Ralentis pour descendre")
                _:
                        hud.hide_prompt()

## Vue 1re personne en véhicule : la caméra suit la tête du perso (niveau des yeux), pas le point fixe au-dessus des pieds
func _update_eye_camera() -> void:
        var hidx: int = skeleton.find_bone(String(_bone_map.get("Head", ""))) if skeleton != null else -1
        if hidx < 0:
                _reset_camera_rig()
                return
        # Le pivot de la caméra est la base du crâne (le "cou") ; la caméra est devant le visage, donc elle décrit
        # un arc en tournant la tête et on ne voit plus l'intérieur de la bouche.
        camera_rig.global_position = skeleton.global_transform * skeleton.get_bone_global_pose(hidx).origin
        spring_arm.position = Vector3(0.0, _arm_home.y + 0.15, _arm_home.z - 0.17)

func _reset_camera_rig() -> void:
        camera_rig.position = _rig_home
        spring_arm.position.y = _arm_home.y
        spring_arm.position.z = _arm_home.z

# ---------------------------------------------------------------- sons

## Crée un lecteur de son à partir de assets/audio/<file_name> (ignoré proprement si le fichier n'existe pas)
func _make_sfx(file_name: String, volume_db: float = 0.0, loop: bool = false) -> AudioStreamPlayer:
        var player := AudioStreamPlayer.new()
        player.volume_db = volume_db
        var path: String = SFX_DIR + file_name
        if ResourceLoader.exists(path):
                var stream: AudioStream = GameAssets.load_resource(path) as AudioStream
                if loop and stream != null: stream = GameAssets.make_looping(stream)
                player.stream = stream
        add_child(player)
        return player

func _setup_sfx() -> void:
        _sfx_walk = _make_sfx("walk.ogg", -6.0, true)
        _sfx_run = _make_sfx("run_loop.ogg", -6.0, true)
        _sfx_jump = _make_sfx("jump.ogg", 0.0)
        _sfx_land = _make_sfx("land.ogg", 0.0)
        _sfx_click = _make_sfx("ui_click.ogg", -6.0)

func _play_sfx(player: AudioStreamPlayer) -> void:
        if player != null and player.stream != null: player.play()

func _stop_footsteps() -> void:
        if _sfx_run != null and _sfx_run.playing: _sfx_run.stop()
        if _sfx_walk != null and _sfx_walk.playing: _sfx_walk.stop()
        _step_timer = 0.0

## Bruits de pas : boucle de marche ou boucle de course selon la vitesse
func _update_footsteps(_delta: float, running_input: bool) -> void:
        var hspeed: float = Vector2(velocity.x, velocity.z).length()
        if vehicle_state != "" or not is_on_floor() or hspeed < 0.8:
                _stop_footsteps()
                return
        var run_now: bool = running_input and hspeed > walk_speed * 1.2
        var active: AudioStreamPlayer = _sfx_run if run_now else _sfx_walk
        var other: AudioStreamPlayer = _sfx_walk if run_now else _sfx_run
        if other != null and other.playing: other.stop()
        if active != null and active.stream != null and not active.playing: active.play()

## Atterrissage : joue le son quand on touche le sol après une vraie chute
func _update_landing(vy_before: float) -> void:
        var on_floor: bool = is_on_floor()
        if on_floor and not _was_on_floor and vy_before < -2.5 and vehicle_state == "":
                if _sfx_land != null and _sfx_land.stream != null:
                        _sfx_land.volume_db = lerpf(-8.0, 2.0, clampf((-vy_before - 2.5) / 6.0, 0.0, 1.0))
                        _sfx_land.play()
        _was_on_floor = on_floor

## Le perso ne doit jamais s'enfoncer : on le remonte au niveau du sol/de la route, et on le ramène s'il tombe hors du monde
func _anti_sink() -> void:
        if global_position.y < -3.0:
                global_position = spawn_position
                velocity = Vector3.ZERO
                return
        var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.2, global_position + Vector3.DOWN * 1.5, 1)
        query.exclude = [get_rid()]
        var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
        if hit.is_empty(): return
        var ground_y: float = (hit["position"] as Vector3).y
        if global_position.y < ground_y - 0.04:
                global_position.y = ground_y
                if velocity.y < 0.0: velocity.y = 0.0

## Filet de sécurité : à pied, on ne peut jamais se retrouver dans la carrosserie d'un véhicule
func _push_out_of_vehicles() -> void:
        for node: Node in get_tree().get_nodes_in_group("vehicle"):
                var gv: GameVehicle = node as GameVehicle
                if gv == null: continue
                var local: Vector3 = gv.to_local(global_position)
                var rel: Vector3 = local - gv.body_center
                var r: float = 0.45   # rayon du personnage
                var hx: float = gv.body_half.x + r
                var hz: float = gv.body_half.z + r
                var top: float = gv.body_center.y + gv.body_half.y
                # sur le toit (pieds au-dessus de la carrosserie) ou trop haut/bas : pas de correction
                if local.y > top - 0.1 or local.y + 1.7 < gv.body_center.y - gv.body_half.y: continue
                if absf(rel.x) < hx and absf(rel.z) < hz:
                        var push_x: float = hx - absf(rel.x)
                        var push_z: float = hz - absf(rel.z)
                        if push_x < push_z: local.x += (1.0 if rel.x >= 0.0 else -1.0) * push_x
                        else: local.z += (1.0 if rel.z >= 0.0 else -1.0) * push_z
                        global_position = gv.to_global(local)

func _facing_toward(dir: Vector3) -> void:
        if dir.length_squared() < 0.0001: return
        facing_yaw = atan2(dir.x, dir.z); _apply_facing()

func _anim_length(anim: String) -> float:
        var key := StringName("mixamo/" + anim)
        if animation_ready and animation_player.has_animation(key): return maxf(animation_player.get_animation(key).length, 0.3)
        return 1.5

## Trajectoire du bassin lue dans les FBX Mixamo (cm) : Vector4(temps, x, y, z) dans le repère de l'animation (le perso regarde +Z, sa gauche est +X)
const ENTER_DURATION: float = 5.467
const ENTER_PATH: Array[Vector4] = [Vector4(0.00, 0.1, 95.5, -0.3), Vector4(0.25, 2.1, 95.3, 5.4), Vector4(0.50, -4.2, 90.3, 22.7), Vector4(0.75, -18.1, 90.7, 42.1), Vector4(0.99, -24.5, 92.8, 51.6), Vector4(1.24, -26.7, 93.9, 56.6), Vector4(1.49, -28.2, 94.5, 60.8), Vector4(1.74, -28.4, 94.5, 66.2), Vector4(1.99, -20.7, 92.8, 80.7), Vector4(2.24, -12.0, 95.4, 103.8), Vector4(2.48, -8.8, 97.6, 123.4), Vector4(2.73, -4.4, 93.0, 144.8), Vector4(2.98, -3.9, 85.0, 166.2), Vector4(3.23, -8.6, 83.2, 177.8), Vector4(3.48, -10.0, 83.6, 174.1), Vector4(3.73, -12.5, 83.5, 171.9), Vector4(3.98, -13.7, 82.5, 175.0), Vector4(4.22, -14.3, 82.4, 180.1), Vector4(4.47, -15.6, 81.4, 177.4), Vector4(4.72, -16.7, 80.9, 177.0), Vector4(4.97, -15.8, 81.1, 176.5), Vector4(5.22, -15.2, 81.1, 177.9), Vector4(5.47, -15.4, 80.9, 177.7)]
const EXIT_DURATION: float = 5.8
const EXIT_PATH: Array[Vector4] = [Vector4(0.00, -0.1, 80.9, -1.2), Vector4(0.25, 0.1, 81.1, -1.2), Vector4(0.50, -1.2, 81.0, -1.1), Vector4(0.76, -1.0, 81.0, -1.4), Vector4(1.01, 0.2, 81.0, -1.7), Vector4(1.26, 3.6, 82.2, 1.4), Vector4(1.51, 4.6, 82.5, 2.6), Vector4(1.77, 5.1, 82.8, 4.9), Vector4(2.02, 15.8, 84.8, 11.6), Vector4(2.27, 34.8, 89.7, 8.8), Vector4(2.52, 56.9, 95.4, 3.5), Vector4(2.77, 80.7, 92.9, 0.1), Vector4(3.03, 105.4, 92.9, -0.0), Vector4(3.28, 121.7, 95.9, 0.4), Vector4(3.53, 136.9, 95.2, 2.0), Vector4(3.78, 139.5, 94.0, 2.5), Vector4(4.03, 137.1, 93.8, -0.5), Vector4(4.29, 136.9, 93.7, -5.1), Vector4(4.54, 140.8, 93.8, -8.0), Vector4(4.79, 142.5, 95.7, -10.3), Vector4(5.04, 149.3, 94.9, -6.0), Vector4(5.30, 165.7, 94.9, 2.3), Vector4(5.55, 174.9, 95.3, 10.9), Vector4(5.80, 180.7, 95.5, 19.4)]
const MIXAMO_HIPS_HEIGHT: float = 95.9   # hauteur du bassin au repos dans Mixamo (cm)

var _seq_path: Array[Vector4] = []
var _seq_time: float = 0.0
var _seq_duration: float = 1.0
var _seq_start: Vector3 = Vector3.ZERO
var _seq_basis: Basis = Basis.IDENTITY
var _seq_scale: float = 0.01
var _seq_y0: float = 0.0
var _seq_y1: float = 0.0
var _seq_hip_drop: float = 0.0
var _seq_entering: bool = true

func _path_at(path: Array[Vector4], t: float) -> Vector3:
        if path.is_empty(): return Vector3.ZERO
        if t <= path[0].x: return Vector3(path[0].y, path[0].z, path[0].w)
        for i in range(1, path.size()):
                if t <= path[i].x:
                        var k: float = inverse_lerp(path[i - 1].x, path[i].x, t)
                        return Vector3(lerpf(path[i - 1].y, path[i].y, k), lerpf(path[i - 1].z, path[i].z, k), lerpf(path[i - 1].w, path[i].w, k))
        var last: Vector4 = path[path.size() - 1]
        return Vector3(last.y, last.z, last.w)

## Hauteur du bassin au repos (mètres, le long de l'axe vertical RÉEL). Les os d'un GLB
## Mixamo sont en Y-up (rest.y = hauteur), mais certains exports FBX (Blender) gardent
## les os en Z-up en reportant la compensation sur les nœuds : la hauteur est alors sur
## un autre axe. On mesure donc le long de l'axe du bassin, quelle que soit la convention.
func _hips_rest_height_m() -> float:
        var rest: float = 0.0
        if skeleton != null:
                var idx: int = skeleton.find_bone(String(_bone_map.get("Hips", "")))
                if idx >= 0:
                        var g: Vector3 = skeleton.get_bone_global_rest(idx).origin
                        var up: Vector3 = Vector3.UP
                        if g.length() > 0.001:
                                var dir: Vector3 = g / g.length()
                                if absf(dir.dot(Vector3.UP)) < 0.95: up = dir
                        rest = g.dot(up)
        if rest > 10.0: rest *= 0.01   # squelette en cm
        return rest

## Échelle cm -> m adaptée à la taille du squelette du perso
func _hips_scale() -> float:
        var rest_y: float = _hips_rest_height_m()
        if rest_y < 0.3: return 0.01
        return 0.01 * (rest_y / (MIXAMO_HIPS_HEIGHT * 0.01))

## Siège : les réglages de position ont été faits avec un perso dont le bassin est à 0,959 m ; on compense l'écart pour ce squelette
func _seat_world(vehicle: GameVehicle) -> Vector3:
        var rest: float = _hips_rest_height_m()
        var offset: float = clampf(MIXAMO_HIPS_HEIGHT * 0.01 - rest, -0.3, 0.3) if rest > 0.3 else 0.0
        return vehicle.get_seat_global() + Vector3.UP * offset

## Position de l'origine du perso à l'instant t de la séquence
func _seq_position(t: float) -> Vector3:
        var d: Vector3 = _path_at(_seq_path, t) - _path_at(_seq_path, 0.0)
        var horizontal: Vector3 = _seq_basis * Vector3(d.x, 0.0, d.z) * _seq_scale
        var progress: float = 0.0
        if absf(_seq_hip_drop) > 0.5:
                var hy: float = _path_at(_seq_path, t).y
                var y_start: float = _path_at(_seq_path, 0.0).y
                progress = clampf((y_start - hy) / _seq_hip_drop, 0.0, 1.0) if _seq_entering else clampf((hy - y_start) / -_seq_hip_drop, 0.0, 1.0)
        var y: float = lerpf(_seq_y0, _seq_y1, progress)
        return Vector3(_seq_start.x + horizontal.x, y, _seq_start.z + horizontal.z)

func _later(delay: float, action: Callable) -> void:
        get_tree().create_timer(delay, false).timeout.connect(action)   # false : respecte la pause

## Handlers de portière de la séquence montée/descendue : méthodes nommées plutôt que
## lambdas inline. Les lambdas à corps "if" déclenchent un bug du tokenizer de Godot 4.7
## (« Expected end of file », issue #96228) qui faisait échouer le parse du script et
## colorait tout ce qui référence PlayerCharacter en rouge.
func _enter_seq_door_open() -> void:
        if is_instance_valid(current_vehicle) and vehicle_state == "entering":
                current_vehicle.open_driver_door(true, _seq_duration * 0.165)

func _enter_seq_door_close() -> void:
        if is_instance_valid(current_vehicle) and vehicle_state == "entering":
                current_vehicle.open_driver_door(false, _seq_duration * 0.137)

func _exit_seq_door_open() -> void:
        if is_instance_valid(current_vehicle) and vehicle_state == "exiting":
                current_vehicle.open_driver_door(true, _seq_duration * 0.17)

func _exit_seq_door_close() -> void:
        if is_instance_valid(current_vehicle) and vehicle_state == "exiting":
                current_vehicle.open_driver_door(false, _seq_duration * 0.14)

func _start_enter(vehicle: GameVehicle) -> void:
        _stop_footsteps()
        vehicle_state = "entering"
        current_vehicle = vehicle
        hud.hide_prompt()
        action_lock = ""
        _saved_collision_layer = collision_layer; _saved_collision_mask = collision_mask
        collision_layer = 0; collision_mask = 0
        _saved_arm_mask = spring_arm.collision_mask
        spring_arm.collision_mask = 0   # en voiture la caméra traverse arbres et murs (sinon elle se colle dedans)
        velocity = Vector3.ZERO
        if not vehicle.has_driver_door() and hud != null: hud.show_message("Portière conducteur introuvable dans le modèle", 3.0)
        vehicle.wake_up()
        var seat: Vector3 = _seat_world(vehicle)
        var ground_y: float = vehicle.get_door_global().y
        _facing_toward(vehicle.get_door_inward_dir())   # le perso marche vers la voiture
        # Trajectoire : le départ est placé pour que l'arrivée tombe pile sur le siège
        _seq_entering = true
        _seq_path = ENTER_PATH
        _seq_duration = ENTER_DURATION
        _seq_time = 0.0
        _seq_basis = visual.global_transform.basis.orthonormalized()
        _seq_scale = _hips_scale()
        _seq_y0 = ground_y
        _seq_y1 = seat.y
        _seq_hip_drop = _path_at(_seq_path, 0.0).y - _path_at(_seq_path, _seq_duration).y
        var d_end: Vector3 = _path_at(_seq_path, _seq_duration) - _path_at(_seq_path, 0.0)
        var h_end: Vector3 = _seq_basis * Vector3(d_end.x, 0.0, d_end.z) * _seq_scale
        _seq_start = Vector3(seat.x - h_end.x, ground_y, seat.z - h_end.z)
        global_position = _seq_position(0.0)
        _play_animation("Entering_Car", true)
        # Portière : s'ouvre quand le perso arrive dessus, se referme une fois assis
        # Montée : la main saisit la poignée vers 0,85 s et tire la portière jusqu'à 1,8 s ; il la referme de 3,95 s à 4,7 s
        _later(_seq_duration * 0.155, _enter_seq_door_open)
        _later(_seq_duration * 0.722, _enter_seq_door_close)
        await get_tree().create_timer(_seq_duration, false).timeout   # false : respecte la pause
        if not is_inside_tree() or not is_instance_valid(vehicle) or vehicle_state != "entering" or current_vehicle != vehicle: return
        global_position = seat
        vehicle_state = "driving"
        is_driving = true
        vehicle.wake_up()
        vehicle.is_player_driving = true
        _horn_prev = false
        pitch = -0.22   # caméra légèrement en hauteur derrière le véhicule
        yaw = vehicle.get_heading_yaw()   # caméra pile derrière le véhicule dès le départ
        _play_animation("Driving", true)

func _start_exit() -> void:
        var vehicle: GameVehicle = current_vehicle
        if vehicle == null: return
        vehicle_state = "exiting"
        is_driving = false
        vehicle.is_player_driving = false
        vehicle.horn_active = false
        vehicle.steer_input = 0.0; vehicle.throttle_input = 0.0; vehicle.brake_input = true
        if is_instance_valid(mobile_controls): mobile_controls.vehicle_mode = false
        action_lock = ""
        var seat: Vector3 = _seat_world(vehicle)
        var ground_y: float = vehicle.get_door_global().y
        _facing_toward(vehicle.global_transform.basis.z)   # assis, il regarde vers l'avant de la voiture
        _seq_entering = false
        _seq_path = EXIT_PATH
        _seq_duration = EXIT_DURATION
        _seq_time = 0.0
        _seq_basis = visual.global_transform.basis.orthonormalized()
        _seq_scale = _hips_scale()
        _seq_y0 = seat.y
        _seq_y1 = ground_y
        _seq_hip_drop = _path_at(_seq_path, 0.0).y - _path_at(_seq_path, _seq_duration).y
        _seq_start = Vector3(seat.x, seat.y, seat.z)
        global_position = _seq_position(0.0)
        _play_animation("Exiting_Car", true)
        # Portière : s'ouvre avant que le perso sorte, se referme une fois dehors
        # Descente : la main pousse la portière de 0,9 s à 1,9 s ; il la referme de 4,3 s à 5,1 s
        _later(_seq_duration * 0.155, _exit_seq_door_open)
        _later(_seq_duration * 0.741, _exit_seq_door_close)
        await get_tree().create_timer(_seq_duration, false).timeout   # false : respecte la pause
        if not is_inside_tree() or not is_instance_valid(vehicle) or vehicle_state != "exiting": return
        var end_pos: Vector3 = _seq_position(_seq_duration)
        vehicle_state = ""
        collision_layer = _saved_collision_layer; collision_mask = _saved_collision_mask
        spring_arm.collision_mask = _saved_arm_mask
        global_position = Vector3(end_pos.x, ground_y + 0.05, end_pos.z)
        velocity = Vector3.ZERO
        current_vehicle = null
        _facing_toward(-vehicle.get_door_inward_dir())   # il s'éloigne de la voiture, comme dans l'animation
        visual.visible = not first_person
        _play_animation("Idle", true)

func _vehicle_process(delta: float) -> void:
        if first_person: _update_eye_camera()
        else: _reset_camera_rig()
        if vehicle_state == "entering" or vehicle_state == "exiting":
                _seq_time = minf(_seq_time + delta, _seq_duration)
                global_position = _seq_position(_seq_time)
        visual.visible = true   # en voiture, le corps reste visible même en vue à la première personne (mains sur le volant)
        _apply_look(delta)
        _update_camera_distance(delta)
        if is_instance_valid(mobile_controls):
                mobile_controls.vehicle_mode = vehicle_state == "driving"
        # Pendant la montée, la caméra se place déjà derrière la jeep
        if vehicle_state == "entering" and current_vehicle != null:
                yaw = lerp_angle(yaw, current_vehicle.get_heading_yaw(), minf(1.0, 4.0 * delta))
        if vehicle_state != "driving" or current_vehicle == null: return
        var v: GameVehicle = current_vehicle
        # Le perso suit le siège ; la caméra suit le cap de la jeep quand elle roule
        global_position = _seat_world(v)
        var heading: float = v.get_heading_yaw()
        facing_yaw = heading + PI; _apply_facing()
        _update_dynamic_fov(delta, absf(v.forward_speed))
        # Caméra de poursuite : reste derrière la jeep (même en marche arrière) ; un balayage du doigt la libère 1,5 s
        if is_instance_valid(mobile_controls) and mobile_controls.is_looking(): _cam_free_left = 1.5
        _cam_free_left = maxf(0.0, _cam_free_left - delta)
        if _cam_free_left <= 0.0 and absf(v.forward_speed) > 1.0: yaw = lerp_angle(yaw, heading, minf(1.0, 3.0 * delta))
        # Entrées : boutons de conduite tactiles (ou clavier / manette)
        var steer: float = 0.0
        var throttle: float = 0.0
        var braking: bool = false
        var horn_touch: bool = false
        if is_instance_valid(mobile_controls):
                steer = mobile_controls.drive_steer
                throttle = mobile_controls.drive_throttle
                braking = mobile_controls.drive_brake
                horn_touch = mobile_controls.drive_horn
                var adj: Vector3 = mobile_controls.consume_seat_adjust()
                if adj != Vector3.ZERO: v.seat_local += adj
                if mobile_controls.consume_door_toggle(): v.toggle_driver_door()
                if mobile_controls.show_seat_tuning: mobile_controls.debug_text = "Siège  x=%.2f  y=%.2f  z=%.2f" % [v.seat_local.x, v.seat_local.y, v.seat_local.z]
        # Clavier : ZQSD/WASD ou flèches (lecture directe des touches pour ne pas mélanger avec le stick de la manette)
        var key_steer: float = 0.0
        var key_throttle: float = 0.0
        if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): key_steer += 1.0
        if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): key_steer -= 1.0
        if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): key_throttle += 1.0
        if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): key_throttle -= 1.0
        # Manette Xbox : stick gauche = direction, RT = accélérer, LT = freiner / marche arrière, A (ou X) = frein à main, B = klaxon, Y = descendre
        var pad_steer: float = 0.0
        var pad_throttle: float = 0.0
        for dev: int in Input.get_connected_joypads():
                var lx: float = Input.get_joy_axis(dev, JOY_AXIS_LEFT_X)
                if absf(lx) > 0.12: pad_steer = clampf(signf(lx) * (absf(lx) - 0.12) / 0.88, -1.0, 1.0)
                pad_throttle += Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_RIGHT) - Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_LEFT)
        if absf(steer) < 0.01: steer = key_steer if absf(key_steer) > 0.01 else pad_steer
        if absf(throttle) < 0.01: throttle = key_throttle if absf(key_throttle) > 0.01 else clampf(pad_throttle, -1.0, 1.0)
        braking = braking or Input.is_action_pressed("jump") or Input.is_action_pressed("run")
        v.steer_input = steer
        v.throttle_input = throttle
        v.brake_input = braking
        # Klaxon (bouton HORN, clic, gâchette ou touche F)
        var horn: bool = horn_touch or _mouse_horn_held or Input.is_action_pressed("horn")   # bouton HORN, clic gauche, touche F ou B (manette)
        v.horn_active = horn
        if horn and not _horn_prev and action_lock.is_empty():
                action_lock = "Honking_Horn"; _play_animation("Honking_Horn", true)
        _horn_prev = horn
        if action_lock.is_empty(): _play_animation("Driving")

func _apply_facing() -> void: visual.rotation.y = facing_yaw
func _jump_requested() -> bool:
        var mobile_jump: bool = is_instance_valid(mobile_controls) and mobile_controls.consume_jump()
        return mobile_jump or Input.is_action_just_pressed("jump")

func _on_animation_finished(anim_name: StringName) -> void:
        var name: String = String(anim_name)
        if name.begins_with("mixamo/"): name = name.trim_prefix("mixamo/")
        if name == action_lock and name != "Jump":
                action_lock = ""
                _play_animation("Driving" if vehicle_state == "driving" else "Idle", true)

func _play_animation(name: String, force: bool = false) -> void:
        if not animation_ready: return
        var key := StringName("mixamo/" + name)
        if not animation_player.has_animation(key):
                push_warning("Ch31: animation introuvable: " + String(key))
                if hud != null and (name == "Entering_Car" or name == "Exiting_Car"): hud.show_message("Animation introuvable : " + name, 3.0, 24)
                return
        if not force and current_animation == name: return
        current_animation = name
        animation_player.speed_scale = _jump_speed_scale(key) if name == "Jump" else 1.0
        animation_player.play(key, animation_fade)

# Adapte la vitesse de l'anim de saut à la durée réelle du vol (montée + descente)
# pour qu'elle ne se termine pas avant l'atterrissage.
func _jump_speed_scale(key: StringName) -> float:
        var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
        var airtime: float = maxf(2.0 * jump_velocity / gravity, 0.2)
        var anim_length: float = animation_player.get_animation(key).length
        return clampf(anim_length / (airtime * 0.95), 0.25, 2.0)

func _build_animation_library() -> void:
        var library := AnimationLibrary.new(); _bone_map.clear()
        for bone_index in range(skeleton.get_bone_count()):
                var real_name: String = skeleton.get_bone_name(bone_index); _bone_map[_normalize_bone_name(real_name)] = real_name
        for anim_name in ANIM_FILES.keys():
                var file_path: String = ANIM_FILES[anim_name]; var packed: PackedScene = GameAssets.load_resource(file_path) as PackedScene
                if packed == null: push_error("Ch31: impossible de charger " + file_path); continue
                var source_root := packed.instantiate(); var source_player: AnimationPlayer = _find_animation_player(source_root)
                var source_skeleton: Skeleton3D = _find_skeleton(source_root)
                if source_player == null or source_skeleton == null: push_error("Ch31: " + anim_name + " n'a pas d'AnimationPlayer/Skeleton3D."); source_root.queue_free(); continue
                var source_animation: Animation = _find_clip_animation(source_player)
                if source_animation == null: push_error("Ch31: aucune animation trouvée dans " + anim_name); source_root.queue_free(); continue
                var animation := source_animation.duplicate(true) as Animation; _unmapped_tracks = 0; _keep_root = ROOT_MOTION_ANIMS.has(anim_name)
                var retargeted: int = _retarget_animation(animation, source_player, source_skeleton, skeleton)
                if retargeted > 0: animation.loop_mode = Animation.LOOP_LINEAR if LOOPING.get(anim_name, false) else Animation.LOOP_NONE; library.add_animation(StringName(anim_name), animation)
                else: push_error("Ch31: aucune piste valide pour " + anim_name)
                source_root.queue_free()
        if animation_player.has_animation_library(&"mixamo"): animation_player.remove_animation_library(&"mixamo")
        animation_player.add_animation_library(&"mixamo", library)

func _find_clip_animation(source_player: AnimationPlayer) -> Animation:
        for candidate in source_player.get_animation_list():
                if String(candidate) == "RESET": continue
                var candidate_animation: Animation = source_player.get_animation(candidate)
                if candidate_animation != null and candidate_animation.get_track_count() > 0: return candidate_animation
        return null

func _retarget_animation(animation: Animation, source_player: AnimationPlayer, source_skeleton: Skeleton3D, target_skeleton: Skeleton3D) -> int:
        var source_root: Node = source_player.get_node(source_player.root_node); var target_root: Node = animation_player.get_node(animation_player.root_node)
        if source_root == null or target_root == null: return 0
        var target_skeleton_path: NodePath = target_root.get_path_to(target_skeleton); var count: int = 0
        # Convention d'axes du squelette cible : les os suivent la convention Mixamo/glTF (Y-up)
        # dans les GLB, mais certains exports FBX (Blender) gardent les os en Z-up en reportant
        # la compensation sur les nœuds (Armature). Les VALEURS d'animation, elles, sont toujours
        # en Y-up (elles marchaient sur le GLB). On détecte l'orientation réelle du bassin cible
        # et on convertit ses pistes position + rotation ; pour un squelette Y-up la conversion
        # est l'identité (comportement inchangé).
        var hips_tbone: String = String(_bone_map.get("Hips", ""))
        var axis_to_up := Basis.IDENTITY   # espace réel du squelette cible -> espace Y-up des valeurs
        var k := 1.0                       # échelle du bassin cible / source (hauteurs globales)
        var hips_idx: int = target_skeleton.find_bone(hips_tbone)
        var src_idx: int = -1
        for bone_index in range(source_skeleton.get_bone_count()):
                if _normalize_bone_name(source_skeleton.get_bone_name(bone_index)) == "Hips":
                        src_idx = bone_index
                        break
        if hips_idx >= 0 and src_idx >= 0:
                var tg: Vector3 = target_skeleton.get_bone_global_rest(hips_idx).origin
                var sg: Vector3 = source_skeleton.get_bone_global_rest(src_idx).origin
                var tdir: Vector3 = Vector3.UP if tg.length() < 0.001 else tg.normalized()
                if absf(tdir.dot(Vector3.UP)) < 0.95:
                        axis_to_up = Basis(Quaternion(tdir, Vector3.UP))
                var th: float = (axis_to_up * tg).y
                k = th / sg.y if absf(sg.y) > 0.0001 else 1.0
        var up_to_axis_q: Quaternion = axis_to_up.inverse().get_rotation_quaternion()
        for track_index in range(animation.get_track_count() - 1, -1, -1):
                var track_type: int = animation.track_get_type(track_index)
                if track_type == Animation.TYPE_POSITION_3D:
                        if not _keep_root: animation.remove_track(track_index); continue
                        # On garde uniquement la position du bassin (Hips), mise à l'échelle du squelette cible
                        var ppath: NodePath = animation.track_get_path(track_index)
                        if ppath.get_subname_count() != 1: animation.remove_track(track_index); continue
                        var pnode: Node = source_root.get_node_or_null(NodePath(ppath.get_concatenated_names()))
                        var pbone: String = String(ppath.get_subname(0))
                        var tbone: String = String(_bone_map.get(_normalize_bone_name(pbone), ""))
                        if pnode != source_skeleton or _normalize_bone_name(pbone) != "Hips" or tbone.is_empty() or target_skeleton.find_bone(tbone) < 0:
                                animation.remove_track(track_index); continue
                        for key_index in range(animation.track_get_key_count(track_index)):
                                var v: Vector3 = (animation.track_get_key_value(track_index, key_index) as Vector3) * k
                                animation.track_set_key_value(track_index, key_index, up_to_axis_q * v)
                        animation.track_set_path(track_index, NodePath(String(target_skeleton_path) + ":" + tbone)); count += 1
                        continue
                if not (track_type == Animation.TYPE_ROTATION_3D or track_type == Animation.TYPE_SCALE_3D): animation.remove_track(track_index); continue
                var source_path: NodePath = animation.track_get_path(track_index)
                if source_path.get_subname_count() != 1: animation.remove_track(track_index); continue
                var source_node_path: NodePath = NodePath(source_path.get_concatenated_names()); var source_node: Node = source_root.get_node_or_null(source_node_path)
                if source_node != source_skeleton: animation.remove_track(track_index); continue
                var source_bone: String = String(source_path.get_subname(0)); var target_bone: String = String(_bone_map.get(_normalize_bone_name(source_bone), ""))
                if target_bone.is_empty() or target_skeleton.find_bone(target_bone) < 0: _unmapped_tracks += 1; animation.remove_track(track_index); continue
                var is_hips: bool = target_bone == hips_tbone and track_type == Animation.TYPE_ROTATION_3D
                for key_index in range(animation.track_get_key_count(track_index)):
                        if is_hips:
                                # Les os non racines héritent de la conversion par leur parent ; seul le bassin,
                                # rattaché directement au squelette, doit tourner dans sa frame réelle.
                                var q: Quaternion = animation.track_get_key_value(track_index, key_index) as Quaternion
                                animation.track_set_key_value(track_index, key_index, up_to_axis_q * q)
                animation.track_set_path(track_index, NodePath(String(target_skeleton_path) + ":" + target_bone)); count += 1
        return count

func _normalize_bone_name(bone_name: String) -> String:
        if not bone_name.begins_with("mixamorig"): return bone_name
        var i: int = 9
        while i < bone_name.length() and bone_name.unicode_at(i) >= 48 and bone_name.unicode_at(i) <= 57: i += 1
        if i < bone_name.length() and (bone_name[i] == ":" or bone_name[i] == "_"): i += 1
        return bone_name.substr(i)

func _disable_nested_animation_players(node: Node) -> void:
        for child in node.get_children():
                if child is AnimationPlayer: (child as AnimationPlayer).active = false
                _disable_nested_animation_players(child)

func _find_skeleton(node: Node) -> Skeleton3D:
        if node is Skeleton3D: return node
        for child in node.get_children(): var found := _find_skeleton(child); if found != null: return found
        return null

func _find_animation_player(node: Node) -> AnimationPlayer:
        if node is AnimationPlayer: return node
        for child in node.get_children(): var found := _find_animation_player(child); if found != null: return found
        return null
