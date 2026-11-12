extends CanvasLayer
# Ch31 - HUD avec Radar et prompt d'interaction

const RadarScript = preload("res://scripts/radar.gd")

@export var show_fps_on_start: bool = true

var _fps_label: Label
var _message: Label
var _hint: Label
var _prompt_label: Label
var _radar: Radar
var _message_tween: Tween
var _fps_timer: float = 0.0

func _ready() -> void:
        layer = 5
        var mobile: bool = OS.has_feature("mobile")
        var left: float = 56.0 if mobile else 14.0
        
        # --- RADAR ---
        _radar = RadarScript.new()
        _radar.custom_minimum_size = Vector2(160, 160)
        _radar.size = Vector2(160, 160)
        _radar.position = Vector2(left, 10.0)
        add_child(_radar)
        
        # --- FPS ---
        _fps_label = _make_label(18)
        _fps_label.position = Vector2(left + 170.0, 10.0)
        _fps_label.visible = show_fps_on_start
        add_child(_fps_label)
        
        # --- MESSAGES ---
        _message = _make_label(40)
        _message.set_anchors_preset(Control.PRESET_FULL_RECT)
        _message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        _message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        _message.modulate.a = 0.0
        add_child(_message)
        
        # --- PROMPT (Entrer dans véhicule) ---
        _prompt_label = _make_label(26)
        _prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
        _prompt_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
        _prompt_label.offset_bottom = -120.0
        _prompt_label.visible = false
        add_child(_prompt_label)
        
        if not mobile:
                _hint = _make_label(15)
                _hint.text = "ZQSD : bouger   Souris : caméra   E : Entrer/Sortir voiture   Espace : sauter   Maj : courir\nEn voiture : ZQSD conduire   Clic/F : klaxon   Espace : frein à main   V : 1re/3e personne   F3 : FPS   Échap : pause"
                _hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
                _hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
                _hint.offset_left = 14.0
                _hint.offset_bottom = -12.0
                add_child(_hint)
                var fade: Tween = create_tween()
                fade.tween_interval(12.0)
                fade.tween_property(_hint, "modulate:a", 0.0, 1.5)

func _make_label(font_size: int) -> Label:
        var label: Label = Label.new()
        label.add_theme_font_size_override("font_size", font_size)
        label.add_theme_color_override("font_color", Color.WHITE)
        label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
        label.add_theme_constant_override("outline_size", 5)
        label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        return label

func _process(delta: float) -> void:
        if _radar != null and get_parent() != null:
                var player = get_parent()
                if "yaw" in player:
                        _radar.set_player_yaw(player.yaw)
        if not _fps_label.visible:
                return
        _fps_timer -= delta
        if _fps_timer > 0.0:
                return
        _fps_timer = 0.25
        var fps: float = Engine.get_frames_per_second()
        var frame_ms: float = 1000.0 / maxf(fps, 1.0)
        _fps_label.text = "FPS %d  (%.1f ms)" % [int(fps), frame_ms]

func toggle_fps() -> void:
        _fps_label.visible = not _fps_label.visible

func set_first_person(value: bool, announce: bool = true) -> void:
        if announce:
                show_message("Vue 1re personne" if value else "Vue 3e personne", 1.0, 24)

func show_message(text: String, duration: float = 1.5, font_size: int = 40) -> void:
        _message.text = text
        _message.add_theme_font_size_override("font_size", font_size)
        if _message_tween != null and _message_tween.is_valid():
                _message_tween.kill()
        _message.modulate.a = 1.0
        _message_tween = create_tween()
        _message_tween.tween_interval(maxf(duration - 0.4, 0.1))
        _message_tween.tween_property(_message, "modulate:a", 0.0, 0.4)

func show_prompt(text: String) -> void:
        _prompt_label.text = text
        _prompt_label.visible = true

func hide_prompt() -> void:
        _prompt_label.visible = false
