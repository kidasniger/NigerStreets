extends CanvasLayer
class_name PauseMenu
# Ch31 - Menu pause + réglages (sensibilité caméra, volume, vibration, qualité graphique :
# ombres + MSAA + échelle de rendu 3D).
# Ouverture : Échap (PC), bouton Android « retour », ou bouton dessiné sous le radar.
# L'ouverture met l'arbre du jeu en pause (get_tree().paused) ; cette couche reste
# active grâce à PROCESS_MODE_ALWAYS.
# Refonte v1.0-b13 : le panneau utilise de VRAIS Controls Godot (Button, HSlider) au lieu
# du hit-test manuel — chaque appui a un retour visuel immédiat (état pressé) et les
# coordonnées tactiles sont gérées par le moteur, donc fiables sur tous les téléphones.

const SPLASH_SCENE: String = "res://scenes/splash.tscn"
const GOLD: Color = Color(1.0, 0.72, 0.20)
const PANEL_BG: Color = Color(0.05, 0.08, 0.12, 0.97)
const BTN_BG: Color = Color(0.10, 0.13, 0.18, 0.98)

var open: bool = false
var show_settings: bool = false
var overlay: PauseOverlay
var _click_sfx: AudioStreamPlayer

func _ready() -> void:
	layer = 8
	process_mode = Node.PROCESS_MODE_ALWAYS   # reste actif quand le jeu est en pause
	overlay = PauseOverlay.new()
	overlay.parent_menu = self
	add_child(overlay)
	_click_sfx = AudioStreamPlayer.new()
	var sfx_path: String = "res://assets/audio/ui_click.ogg"
	if ResourceLoader.exists(sfx_path):
		_click_sfx.stream = load(sfx_path) as AudioStream
	add_child(_click_sfx)
	GameSettings.load_settings()
	GameSettings.apply_audio()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		toggle()   # bouton Android « retour » : ouvre la pause au lieu de quitter l'app

## Ouvre/ferme le menu et met l'arbre du jeu en pause
func toggle() -> void:
	open = not open
	show_settings = false
	get_tree().paused = open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
	overlay.rebuild()

func open_settings() -> void:
	show_settings = true
	overlay.rebuild()

func _play_click() -> void:
	if _click_sfx.stream != null:
		_click_sfx.play()

## Retour à l'écran titre (appelé par un bouton du panneau)
func go_to_menu() -> void:
	GameSettings.save_settings()
	get_tree().paused = false
	get_tree().change_scene_to_file(SPLASH_SCENE)

func quit_game() -> void:
	GameSettings.save_settings()
	get_tree().quit()


# ------------------------------------------------------------------ overlay

class PauseOverlay extends Control:
	var parent_menu: PauseMenu

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE   # le panneau GUI intercepte lui-même les appuis
		rebuild()

	## Reconstruit le contenu selon l'état (fermé : bouton pause dessiné ; ouvert : panneau GUI)
	func rebuild() -> void:
		for child in get_children():
			child.queue_free()
		queue_redraw()
		if parent_menu == null or not parent_menu.open:
			return
		var dim := ColorRect.new()
		dim.color = Color(0.0, 0.0, 0.0, 0.55)
		dim.set_anchors_preset(Control.PRESET_FULL_RECT)
		dim.mouse_filter = Control.MOUSE_FILTER_STOP   # absorbe les appuis hors du panneau
		add_child(dim)
		var center := CenterContainer.new()
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(center)
		var panel := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = PANEL_BG
		sb.border_color = GOLD
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(10)
		sb.content_margin_left = 28.0
		sb.content_margin_right = 28.0
		sb.content_margin_top = 20.0
		sb.content_margin_bottom = 16.0
		panel.add_theme_stylebox_override("panel", sb)
		center.add_child(panel)
		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 12)
		vbox.custom_minimum_size = Vector2(504, 0)
		panel.add_child(vbox)
		if parent_menu.show_settings:
			_fill_settings(vbox)
		else:
			_fill_main(vbox)

	# ---------------------------------------------------- _input (hors panneau GUI)

	## Échap : bascule la pause. Menu fermé : le bouton dessiné sous le radar ouvre la pause.
	## _input passe AVANT les commandes tactiles du jeu : set_input_as_handled évite de réveiller
	## le joystick quand on vise le bouton pause.
	func _input(event: InputEvent) -> void:
		var menu := parent_menu
		if menu == null:
			return
		if event.is_action("ui_cancel") and event.is_pressed() and not event.is_echo():
			get_viewport().set_input_as_handled()
			menu.toggle()
			return
		if menu.open:
			return   # menu ouvert : tous les appuis sont gérés par les boutons GUI
		var pos := Vector2.ZERO
		var is_press := false
		var touch := event as InputEventScreenTouch
		if touch != null and touch.pressed:
			pos = touch.position
			is_press = true
		else:
			var click := event as InputEventMouseButton
			if click != null and click.button_index == MOUSE_BUTTON_LEFT and click.pressed:
				pos = click.position
				is_press = true
		if is_press and pos.distance_to(_pause_btn_center()) <= 34.0:
			get_viewport().set_input_as_handled()
			menu.toggle()

	func _pause_btn_center() -> Vector2:
		var left: float = 56.0 if OS.has_feature("mobile") else 14.0
		return Vector2(left + 22.0, 200.0)

	func _draw() -> void:
		if parent_menu != null and parent_menu.open:
			return   # le panneau couvre l'écran, le bouton pause n'est pas dessiné
		var c := _pause_btn_center()
		draw_circle(c, 22.0, Color(0.08, 0.10, 0.14, 0.78))
		draw_arc(c, 22.0, 0.0, TAU, 40, Color(1, 1, 1, 0.35), 2.5)
		draw_rect(Rect2(c + Vector2(-7.5, -9.0), Vector2(5.5, 18.0)), Color(1, 1, 1, 0.92))
		draw_rect(Rect2(c + Vector2(2.0, -9.0), Vector2(5.5, 18.0)), Color(1, 1, 1, 0.92))

	# ---------------------------------------------------- construction du panneau

	func _fill_main(vbox: VBoxContainer) -> void:
		vbox.add_child(_label("PAUSE", 30, GOLD, true))
		vbox.add_child(_spacer(8))
		var labels: Array[String] = ["Reprendre", "Réglages", "Menu principal", "Quitter l'application"]
		for i in labels.size():
			var b := _button(labels[i], i == 0)
			match i:
				0: b.pressed.connect(parent_menu.toggle)
				1: b.pressed.connect(parent_menu.open_settings)
				2: b.pressed.connect(parent_menu.go_to_menu)
				3: b.pressed.connect(parent_menu.quit_game)
			vbox.add_child(b)
		vbox.add_child(_spacer(6))
		vbox.add_child(_label("Version " + str(ProjectSettings.get_setting("application/config/version", "1.0")), 13, Color(1, 1, 1, 0.40), true))
		vbox.add_child(_label("Échap / retour : fermer", 13, Color(1, 1, 1, 0.45), true))

	func _fill_settings(vbox: VBoxContainer) -> void:
		vbox.add_child(_label("RÉGLAGES", 30, GOLD, true))
		vbox.add_child(_spacer(10))
		vbox.add_child(_slider_row("Sensibilité caméra", GameSettings.camera_sensitivity, 0.3, 3.0, 0.05,
			true, _set_sensitivity, _save_settings))
		vbox.add_child(_slider_row("Volume général", GameSettings.master_volume, 0.0, 1.0, 0.01,
			false, _set_volume, _save_settings))
		vbox.add_child(_spacer(4))
		var vib := _button("Vibration : %s" % ("activée" if GameSettings.vibration_enabled else "désactivée"), GameSettings.vibration_enabled)
		vib.pressed.connect(_toggle_vibration)
		vbox.add_child(vib)
		var qual := _button("Qualité : %s" % ("haute" if GameSettings.quality_high else "éco"), GameSettings.quality_high)
		qual.pressed.connect(_toggle_quality)
		vbox.add_child(qual)
		var def := _button("Réglages par défaut", false)
		def.pressed.connect(_reset_settings)
		vbox.add_child(def)
		var back := _button("Retour", false)
		back.pressed.connect(_close_settings)
		vbox.add_child(back)

	# ---------------------------------------------------- actions des réglages

	func _set_sensitivity(v: float) -> void:
		GameSettings.camera_sensitivity = v

	func _set_volume(v: float) -> void:
		GameSettings.master_volume = v
		GameSettings.apply_audio()

	func _save_settings() -> void:
		GameSettings.save_settings()

	func _toggle_vibration() -> void:
		GameSettings.vibration_enabled = not GameSettings.vibration_enabled
		GameSettings.save_settings()
		parent_menu._play_click()
		rebuild()

	func _toggle_quality() -> void:
		GameSettings.quality_high = not GameSettings.quality_high
		GameSettings.apply_shadows(get_tree())
		GameSettings.apply_viewport(get_viewport())   # MSAA + échelle de rendu 3D
		GameSettings.save_settings()
		parent_menu._play_click()
		rebuild()

	func _reset_settings() -> void:
		GameSettings.reset_defaults()
		GameSettings.apply_shadows(get_tree())
		GameSettings.apply_viewport(get_viewport())   # ombres / MSAA / échelle revenus aux défauts
		parent_menu._play_click()
		rebuild()

	func _close_settings() -> void:
		parent_menu.show_settings = false
		parent_menu._play_click()
		rebuild()

	# ---------------------------------------------------- fabriques de Controls

	func _slider_row(label_text: String, value: float, vmin: float, vmax: float, step: float,
			as_mult: bool, on_change: Callable, on_end: Callable) -> VBoxContainer:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		box.add_child(_label(label_text, 16, Color(1, 1, 1, 0.9), false))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var slider := HSlider.new()
		slider.min_value = vmin
		slider.max_value = vmax
		slider.step = step
		slider.value = value
		slider.custom_minimum_size = Vector2(300, 32)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(slider)
		var val := _label(_format_value(value, as_mult), 16, GOLD, false)
		val.custom_minimum_size = Vector2(88, 0)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(val)
		box.add_child(row)
		slider.value_changed.connect(func(v: float) -> void:
			val.text = _format_value(v, as_mult)
			on_change.call(v))
		slider.drag_ended.connect(func(_changed: bool) -> void:
			on_end.call())
		return box

	func _format_value(value: float, as_mult: bool) -> String:
		return ("×%.2f" % value) if as_mult else "%d %%" % int(round(value * 100.0))

	func _button(text_value: String, accent: bool) -> Button:
		var b := Button.new()
		b.text = text_value
		b.custom_minimum_size = Vector2(0, 52)
		b.add_theme_font_size_override("font_size", 22)
		var normal := StyleBoxFlat.new()
		normal.bg_color = GOLD if accent else BTN_BG
		normal.set_corner_radius_all(8)
		if not accent:
			normal.border_color = Color(1, 1, 1, 0.22)
			normal.set_border_width_all(2)
		var hover := StyleBoxFlat.new()
		hover.bg_color = Color(1.0, 0.78, 0.32) if accent else Color(0.14, 0.18, 0.25, 0.98)
		hover.set_corner_radius_all(8)
		var pressed := StyleBoxFlat.new()
		pressed.bg_color = Color(1.0, 0.62, 0.10) if accent else Color(0.18, 0.22, 0.30, 0.98)
		pressed.set_corner_radius_all(8)
		b.add_theme_stylebox_override("normal", normal)
		b.add_theme_stylebox_override("hover", hover)
		b.add_theme_stylebox_override("pressed", pressed)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.add_theme_color_override("font_color", Color(0.06, 0.07, 0.09) if accent else Color(1, 1, 1, 0.95))
		b.add_theme_color_override("font_hover_color", Color(0.06, 0.07, 0.09) if accent else Color(1, 1, 0.9, 1))
		b.add_theme_color_override("font_pressed_color", Color(0.06, 0.07, 0.09))
		b.pressed.connect(parent_menu._play_click)   # retour sonore sur chaque appui
		return b

	func _label(text_value: String, font_size: int, color: Color, centered: bool) -> Label:
		var l := Label.new()
		l.text = text_value
		l.add_theme_font_size_override("font_size", font_size)
		l.add_theme_color_override("font_color", color)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		l.add_theme_constant_override("outline_size", 4)
		if centered:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		return l

	func _spacer(height: float) -> Control:
		var c := Control.new()
		c.custom_minimum_size = Vector2(0, height)
		return c
