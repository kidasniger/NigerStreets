extends Control
class_name MobileControls
# Ch31 - Commandes tactiles avec bouton CAR

var move_vector: Vector2 = Vector2.ZERO
var run_held: bool = false
var vehicle_mode: bool = false:
        set(value):
                if value == vehicle_mode: return
                vehicle_mode = value
                _reset_all_inputs()
# --- Mode conduite : sorties lues par le joueur ---
var drive_steer: float = 0.0      # -1 gauche, +1 droite
var drive_throttle: float = 0.0   # +1 accélère, -1 marche arrière
var drive_brake: bool = false
var drive_horn: bool = false
## Boutons temporaires pour régler la position assise (à mettre à false quand c'est réglé)
var show_seat_tuning: bool = false
var debug_text: String = ""
var _seat_adjust: Vector3 = Vector3.ZERO
var _door_toggle_requested: bool = false
var _drive_fingers: Dictionary = {}
var _btn_centers: Dictionary = {}
var _btn_radii: Dictionary = {}
var _tune_buttons: Array[Dictionary] = []
var _jump_requested: bool = false
var _camera_toggle_requested: bool = false
var enter_exit_requested: bool = false
var _look_delta: Vector2 = Vector2.ZERO
var _move_finger: int = -1
var _look_finger: int = -1
var _run_finger: int = -1

var _joy_radius: float = 92.0
var _joy_home: Vector2 = Vector2.ZERO
var _joy_center: Vector2 = Vector2.ZERO
var _jump_center: Vector2 = Vector2.ZERO
var _gas_center: Vector2 = Vector2.ZERO
var _run_center: Vector2 = Vector2.ZERO
var _cam_center: Vector2 = Vector2.ZERO
var _horn_center: Vector2 = Vector2.ZERO
var _enter_center: Vector2 = Vector2.ZERO
var _jump_r: float = 58.0
var _gas_r: float = 70.0
var _run_r: float = 46.0
var _cam_r: float = 36.0
var _horn_r: float = 50.0
var _enter_r: float = 40.0
var _scale: float = 1.0
var _move_zone_x: float = 500.0

func _ready() -> void:
        mouse_filter = Control.MOUSE_FILTER_IGNORE
        resized.connect(_update_layout)
        _update_layout()
        queue_redraw()

func _update_layout() -> void:
        var w: float = size.x
        var h: float = size.y
        if w <= 0.0 or h <= 0.0:
                return
        _scale = clampf(h / 720.0, 0.6, 1.6)
        var s: float = _scale
        var inset_left: float = 0.0
        var inset_right: float = 0.0
        var inset_bottom: float = 0.0
        if OS.has_feature("mobile"):
                var window_size: Vector2i = DisplayServer.window_get_size()
                if window_size.x > 0 and window_size.y > 0:
                        var safe: Rect2i = DisplayServer.get_display_safe_area()
                        var factor: float = h / float(window_size.y)
                        inset_left = clampf(float(safe.position.x) * factor, 0.0, 160.0)
                        inset_right = clampf(float(window_size.x - safe.end.x) * factor, 0.0, 160.0)
                        inset_bottom = clampf(float(window_size.y - safe.end.y) * factor, 0.0, 120.0)
        var margin: float = 36.0 * s
        var right_edge: float = w - inset_right - margin
        var bottom_edge: float = h - inset_bottom - margin
        _joy_radius = 92.0 * s
        _gas_r = 70.0 * s
        _jump_r = 58.0 * s
        _run_r = 46.0 * s
        _cam_r = 36.0 * s
        _horn_r = 50.0 * s
        _enter_r = 40.0 * s
        _joy_home = Vector2(inset_left + margin + _joy_radius, bottom_edge - _joy_radius)
        _joy_center = _joy_home
        _gas_center = Vector2(right_edge - _gas_r, bottom_edge - _gas_r)
        _jump_center = Vector2(_gas_center.x, _gas_center.y - _gas_r - _jump_r - 14.0 * s)
        _horn_center = Vector2(_jump_center.x - _jump_r - _horn_r - 22.0 * s, _jump_center.y)
        _run_center = Vector2(_gas_center.x - _gas_r - _run_r - 22.0 * s, bottom_edge - _run_r)
        _enter_center = Vector2(_run_center.x - _run_r - _enter_r - 22.0 * s, _run_center.y)
        _cam_center = Vector2(w - inset_right - 24.0 * s - _cam_r, 24.0 * s + _cam_r)
        _move_zone_x = w * 0.42
        # --- Boutons du mode conduite ---
        var steer_r: float = 66.0 * s
        var left_c := Vector2(inset_left + margin + steer_r, bottom_edge - steer_r)
        _btn_centers = {
                "left": left_c,
                "right": Vector2(left_c.x + steer_r * 2.0 + 26.0 * s, left_c.y),
                "gas": _gas_center,
                "rev": _jump_center,
                "brake": _run_center,
                "horn": _horn_center,
        }
        _btn_radii = {
                "left": steer_r, "right": steer_r, "gas": 74.0 * s,
                "rev": 50.0 * s, "brake": 52.0 * s, "horn": 44.0 * s,
        }
        _tune_buttons.clear()
        var tr: float = 21.0 * s
        var tx: float = _cam_center.x - _cam_r - 14.0 * s - tr
        var labels: Array[String] = ["Z-", "Z+", "Y-", "Y+", "X-", "X+", "DOOR"]
        var deltas: Array[Vector3] = [Vector3(0.0, 0.0, -0.05), Vector3(0.0, 0.0, 0.05), Vector3(0.0, -0.05, 0.0), Vector3(0.0, 0.05, 0.0), Vector3(-0.05, 0.0, 0.0), Vector3(0.05, 0.0, 0.0), Vector3.ZERO]
        for i in range(7):
                _tune_buttons.append({"label": labels[i], "door": i == 6, "delta": deltas[i], "center": Vector2(tx - float(i) * (tr * 2.0 + 6.0 * s), _cam_center.y), "r": tr})
        queue_redraw()

func _draw() -> void:
        if vehicle_mode:
                _draw_vehicle_controls()
                return
        var s: float = _scale
        var moving: bool = _move_finger != -1
        var ring_center: Vector2 = _joy_center if moving else _joy_home
        var knob: Vector2 = ring_center + move_vector * _joy_radius
        var idle_alpha: float = 1.0 if moving else 0.55
        draw_circle(ring_center, _joy_radius, Color(0.08, 0.10, 0.14, 0.34 * idle_alpha))
        draw_arc(ring_center, _joy_radius - 4.0 * s, 0.0, TAU, 48, Color(1.0, 1.0, 1.0, 0.25 * idle_alpha), 4.0 * s)
        draw_circle(knob, 42.0 * s, Color(0.09, 0.12, 0.18, 0.62 * idle_alpha))
        var run_alpha: float = 0.62 if run_held else 0.38
        draw_circle(_run_center, _run_r, Color(0.10, 0.13, 0.18, run_alpha))
        _draw_text_centered(_run_center, "RUN", int(20.0 * s))
        draw_circle(_jump_center, _jump_r, Color(0.12, 0.15, 0.22, 0.48))
        _draw_text_centered(_jump_center, "JUMP", int(20.0 * s))
        draw_circle(_cam_center, _cam_r, Color(0.10, 0.13, 0.18, 0.42))
        _draw_text_centered(_cam_center, "CAM", int(16.0 * s))
        draw_circle(_enter_center, _enter_r, Color(0.15, 0.40, 0.15, 0.60))
        _draw_text_centered(_enter_center, "CAR", int(18.0 * s))

func _draw_vehicle_controls() -> void:
        var s: float = _scale
        var info: Dictionary = {
                "left": ["<", 40, Color(0.10, 0.16, 0.26)],
                "right": [">", 40, Color(0.10, 0.16, 0.26)],
                "gas": ["GAS", 26, Color(0.10, 0.30, 0.12)],
                "rev": ["REV", 17, Color(0.22, 0.18, 0.08)],
                "brake": ["BRAKE", 15, Color(0.34, 0.10, 0.08)],
                "horn": ["HORN", 15, Color(0.10, 0.20, 0.26)],
        }
        var down: Array = _drive_fingers.values()
        for key: String in info.keys():
                var c: Vector2 = _btn_centers[key]
                var r: float = _btn_radii[key]
                var col: Color = info[key][2]
                col.a = 0.80 if down.has(key) else 0.50
                draw_circle(c, r, col)
                draw_arc(c, r - 3.0 * s, 0.0, TAU, 40, Color(1.0, 1.0, 1.0, 0.28), 3.0 * s)
                _draw_text_centered(c, info[key][0], int(float(info[key][1]) * s))
        draw_circle(_cam_center, _cam_r, Color(0.10, 0.13, 0.18, 0.42))
        _draw_text_centered(_cam_center, "CAM", int(16.0 * s))
        draw_circle(_enter_center, _enter_r, Color(0.15, 0.40, 0.15, 0.60))
        _draw_text_centered(_enter_center, "EXIT", int(16.0 * s))
        if show_seat_tuning:
                for b: Dictionary in _tune_buttons:
                        draw_circle(b["center"], b["r"], Color(0.35, 0.30, 0.05, 0.60))
                        _draw_text_centered(b["center"], b["label"], int((11.0 if b["door"] else 15.0) * s))
                if not debug_text.is_empty():
                        var font: Font = ThemeDB.fallback_font
                        draw_string(font, Vector2(_cam_center.x - 420.0 * s, _cam_center.y + 56.0 * s), debug_text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(18.0 * s), Color(1.0, 0.95, 0.5, 0.95))

func _draw_text_centered(center: Vector2, value: String, font_size: int) -> void:
        var font: Font = ThemeDB.fallback_font
        var width: float = font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
        var position_text: Vector2 = center + Vector2(-width * 0.5, float(font_size) * 0.35)
        draw_string(font, position_text, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1.0, 1.0, 1.0, 0.92))

func _input(event: InputEvent) -> void:
        if not visible:
                return
        if event is InputEventScreenTouch:
                var touch: InputEventScreenTouch = event as InputEventScreenTouch
                if touch.pressed:
                        _handle_touch_down(touch.position, touch.index)
                else:
                        _handle_touch_up(touch.index)
        elif event is InputEventScreenDrag:
                _handle_touch_drag(event as InputEventScreenDrag)

func _handle_touch_down(position_touch: Vector2, finger: int) -> void:
        queue_redraw()   # tout appui peut changer l'affichage (joystick, bouton enfoncé)
        var tolerance: float = 6.0 * _scale
        if vehicle_mode:
                _handle_vehicle_touch_down(position_touch, finger, tolerance)
                return
        if position_touch.distance_to(_jump_center) <= _jump_r + tolerance:
                _jump_requested = true
                return
        if position_touch.distance_to(_cam_center) <= _cam_r + tolerance:
                _camera_toggle_requested = true
                return
        if position_touch.distance_to(_run_center) <= _run_r + tolerance:
                run_held = true
                _run_finger = finger
                return
        if position_touch.distance_to(_enter_center) <= _enter_r + tolerance:
                enter_exit_requested = true
                return
        if position_touch.x < _move_zone_x and position_touch.y > size.y * 0.2 and _move_finger == -1:
                _move_finger = finger
                var pad: float = _joy_radius + 8.0 * _scale
                _joy_center = Vector2(
                        clampf(position_touch.x, pad, maxf(_move_zone_x, pad)),
                        clampf(position_touch.y, pad, maxf(size.y - pad, pad))
                )
                _update_move(position_touch)
                return
        if position_touch.x >= _move_zone_x and _look_finger == -1:
                _look_finger = finger

func _handle_vehicle_touch_down(position_touch: Vector2, finger: int, tolerance: float) -> void:
        if position_touch.distance_to(_enter_center) <= _enter_r + tolerance:
                enter_exit_requested = true
                return
        if position_touch.distance_to(_cam_center) <= _cam_r + tolerance:
                _camera_toggle_requested = true
                return
        if show_seat_tuning:
                for b: Dictionary in _tune_buttons:
                        if position_touch.distance_to(b["center"]) <= float(b["r"]) + tolerance:
                                if b["door"]: _door_toggle_requested = true
                                else: _seat_adjust += b["delta"]
                                return
        var btn: String = _drive_button_at(position_touch, tolerance)
        if not btn.is_empty():
                _drive_fingers[finger] = btn
                _recompute_drive_state()
                return
        if _look_finger == -1:
                _look_finger = finger

func _drive_button_at(position_touch: Vector2, tolerance: float) -> String:
        for key: String in _btn_centers.keys():
                var c: Vector2 = _btn_centers[key]
                if position_touch.distance_to(c) <= float(_btn_radii[key]) + tolerance:
                        return key
        return ""

func _recompute_drive_state() -> void:
        var steer: float = 0.0
        var throttle: float = 0.0
        var brake: bool = false
        var horn: bool = false
        for btn: String in _drive_fingers.values():
                match btn:
                        "left": steer -= 1.0
                        "right": steer += 1.0
                        "gas": throttle += 1.0
                        "rev": throttle -= 1.0
                        "brake": brake = true
                        "horn": horn = true
        drive_steer = clampf(steer, -1.0, 1.0)
        drive_throttle = clampf(throttle, -1.0, 1.0)
        drive_brake = brake
        drive_horn = horn

func _reset_all_inputs() -> void:
        queue_redraw()
        _drive_fingers.clear()
        drive_steer = 0.0; drive_throttle = 0.0; drive_brake = false; drive_horn = false
        _move_finger = -1; _look_finger = -1; _run_finger = -1
        move_vector = Vector2.ZERO; run_held = false
        _joy_center = _joy_home

func _update_move(position_touch: Vector2) -> void:
        var offset: Vector2 = position_touch - _joy_center
        if offset.length() > _joy_radius:
                _joy_center += offset.normalized() * (offset.length() - _joy_radius)
                offset = position_touch - _joy_center
        move_vector = offset.limit_length(_joy_radius) / _joy_radius

func _handle_touch_drag(event: InputEventScreenDrag) -> void:
        queue_redraw()
        if vehicle_mode and _drive_fingers.has(event.index):
                # Glisser d'un bouton à l'autre (ex. de gauche à droite)
                var btn: String = _drive_button_at(event.position, 6.0 * _scale)
                if btn.is_empty(): _drive_fingers.erase(event.index)
                else: _drive_fingers[event.index] = btn
                _recompute_drive_state()
                return
        if event.index == _move_finger:
                _update_move(event.position)
        elif event.index == _look_finger:
                _look_delta += event.screen_relative

func _handle_touch_up(finger: int) -> void:
        queue_redraw()
        if _drive_fingers.has(finger):
                _drive_fingers.erase(finger)
                _recompute_drive_state()
        if finger == _move_finger:
                _move_finger = -1
                move_vector = Vector2.ZERO
                _joy_center = _joy_home
        if finger == _look_finger:
                _look_finger = -1
        if finger == _run_finger:
                _run_finger = -1
                run_held = false

func consume_jump() -> bool:
        var value: bool = _jump_requested
        _jump_requested = false
        return value
func consume_camera_toggle() -> bool:
        var value: bool = _camera_toggle_requested
        _camera_toggle_requested = false
        return value
func consume_enter_exit() -> bool:
        var value: bool = enter_exit_requested
        enter_exit_requested = false
        return value
func is_looking() -> bool:
        return _look_finger != -1
func consume_door_toggle() -> bool:
        var value: bool = _door_toggle_requested
        _door_toggle_requested = false
        return value
func consume_seat_adjust() -> Vector3:
        var value: Vector3 = _seat_adjust
        _seat_adjust = Vector3.ZERO
        return value
func consume_look_delta() -> Vector2:
        var value: Vector2 = _look_delta
        _look_delta = Vector2.ZERO
        return value
