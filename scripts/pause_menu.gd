extends CanvasLayer
class_name PauseMenu
# Ch31 - Menu pause + réglages (refonte M1) : panneau moderne à onglets (Jeu, Image, Son,
# Système), interrupteurs, sélecteurs à segments, curseurs fins, défilement tactile.
# Ouverture : Échap (PC), bouton Android « retour », ou bouton dessiné sous le radar.
# L'ouverture met l'arbre du jeu en pause (get_tree().paused) ; cette couche reste
# active grâce à PROCESS_MODE_ALWAYS. Tout est construit par code (aucun asset).

const SPLASH_SCENE: String = "res://scenes/splash.tscn"
const GOLD: Color = Color(1.0, 0.72, 0.20)
const PANEL_BG: Color = Color(0.055, 0.07, 0.095, 0.96)
const CARD_BG: Color = Color(1.0, 1.0, 1.0, 0.05)
const BTN_BG: Color = Color(0.11, 0.14, 0.19, 1.0)
const TEXT: Color = Color(1.0, 1.0, 1.0, 0.92)
const TEXT_DIM: Color = Color(1.0, 1.0, 1.0, 0.55)
const TAB_NAMES: Array[String] = ["Jeu", "Image", "Son", "Système"]

static var _knob_tex: Texture2D

var open: bool = false
var show_settings: bool = false
var settings_tab: int = 0
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
	var battery_timer := Timer.new()
	battery_timer.wait_time = 20.0
	battery_timer.timeout.connect(_check_battery)
	add_child(battery_timer)
	battery_timer.start()
	_check_battery()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		toggle()   # bouton Android « retour » : ouvre la pause au lieu de quitter l'app

## Ouvre/ferme le menu et met l'arbre du jeu en pause
func toggle() -> void:
	if CarteZinder.is_open():
		CarteZinder.close_current()   # retour Android / Échap : ferme d'abord la carte
		return
	open = not open
	show_settings = false
	get_tree().paused = open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
	overlay.rebuild(true)

func open_settings() -> void:
	show_settings = true
	settings_tab = 0
	overlay.rebuild()

## Vérifie le niveau de batterie (mode batterie automatique)
func _check_battery() -> void:
	GameSettings.update_battery(get_tree(), get_viewport())

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

## Pastille dorée des curseurs, générée une seule fois par code
static func _make_knob() -> Texture2D:
	if _knob_tex != null:
		return _knob_tex
	var d: int = 36
	var img := Image.create_empty(d, d, false, Image.FORMAT_RGBA8)
	var c: float = (d - 1) * 0.5
	var r: float = d * 0.5 - 1.0
	for y in d:
		for x in d:
			var dist: float = Vector2(x - c, y - c).length()
			var a: float = clampf(r - dist + 0.5, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 0.78, 0.30, a))
	_knob_tex = ImageTexture.create_from_image(img)
	return _knob_tex


# ------------------------------------------------------------------ interrupteur

class SwitchControl extends Control:
	signal toggled(value: bool)
	var on: bool = false

	func _init() -> void:
		custom_minimum_size = Vector2(76, 44)

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			accept_event()
			on = not on
			queue_redraw()
			toggled.emit(on)

	func _draw() -> void:
		var w: float = 60.0
		var h: float = 30.0
		var origin := Vector2((size.x - w) * 0.5, (size.y - h) * 0.5)
		var track := StyleBoxFlat.new()
		track.bg_color = Color(1.0, 0.72, 0.20) if on else Color(1.0, 1.0, 1.0, 0.16)
		track.set_corner_radius_all(15)
		draw_style_box(track, Rect2(origin, Vector2(w, h)))
		var kx: float = (origin.x + w - 15.0) if on else (origin.x + 15.0)
		draw_circle(Vector2(kx, origin.y + h * 0.5), 11.5, Color(1.0, 1.0, 1.0, 0.97))


# ------------------------------------------------------------------ overlay

class PauseOverlay extends Control:
	var parent_menu: PauseMenu

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE   # le panneau GUI intercepte lui-même les appuis
		rebuild()

	## Reconstruit le contenu selon l'état (fermé : bouton pause dessiné ; ouvert : panneau GUI)
	func rebuild(fade: bool = false) -> void:
		for child in get_children():
			if child is CanvasItem:
				(child as CanvasItem).hide()
			child.queue_free()
		queue_redraw()
		if parent_menu == null or not parent_menu.open:
			return
		var dim := ColorRect.new()
		dim.color = Color(0.0, 0.0, 0.0, 0.6)
		dim.set_anchors_preset(Control.PRESET_FULL_RECT)
		dim.mouse_filter = Control.MOUSE_FILTER_STOP   # absorbe les appuis hors du panneau
		add_child(dim)
		var center := CenterContainer.new()
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(center)
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", _panel_style())
		center.add_child(panel)
		if parent_menu.show_settings:
			_fill_settings(panel)
		else:
			_fill_main(panel)
		if fade:
			dim.modulate.a = 0.0
			center.modulate.a = 0.0
			var tw := create_tween()
			tw.set_parallel(true)
			tw.tween_property(dim, "modulate:a", 1.0, 0.15)
			tw.tween_property(center, "modulate:a", 1.0, 0.15)

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

	# ---------------------------------------------------- écran principal

	func _fill_main(panel: PanelContainer) -> void:
		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 12)
		vbox.custom_minimum_size = Vector2(440, 0)
		panel.add_child(vbox)
		vbox.add_child(_label("PAUSE", 30, GOLD, true))
		vbox.add_child(_spacer(6))
		var labels: Array[String] = ["Reprendre", "Réglages", "Menu principal", "Quitter l'application"]
		for i in labels.size():
			var b := _button(labels[i], i == 0)
			match i:
				0: b.pressed.connect(parent_menu.toggle)
				1: b.pressed.connect(parent_menu.open_settings)
				2: b.pressed.connect(parent_menu.go_to_menu)
				3: b.pressed.connect(parent_menu.quit_game)
			vbox.add_child(b)
		vbox.add_child(_spacer(4))
		vbox.add_child(_label("Version " + str(ProjectSettings.get_setting("application/config/version", "1.0")), 13, TEXT_DIM, true))
		vbox.add_child(_label("Échap / retour : fermer", 13, TEXT_DIM, true))

	# ---------------------------------------------------- écran réglages (onglets)

	func _fill_settings(panel: PanelContainer) -> void:
		var vp: Vector2 = get_viewport_rect().size
		var panel_w: float = clampf(vp.x * 0.88, 560.0, 920.0)
		var panel_h: float = clampf(vp.y * 0.84, 340.0, 560.0)
		panel.custom_minimum_size = Vector2(panel_w, panel_h)
		var root := HBoxContainer.new()
		root.add_theme_constant_override("separation", 20)
		panel.add_child(root)
		# barre latérale : onglets + retour
		var side := VBoxContainer.new()
		side.add_theme_constant_override("separation", 6)
		side.custom_minimum_size = Vector2(160, 0)
		root.add_child(side)
		side.add_child(_label("RÉGLAGES", 22, GOLD, false))
		side.add_child(_spacer(8))
		for i in TAB_NAMES.size():
			var tb := _tab_button(TAB_NAMES[i], i == parent_menu.settings_tab)
			tb.pressed.connect(_select_tab.bind(i))
			side.add_child(tb)
		var gap := Control.new()
		gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
		side.add_child(gap)
		var back := _button("Retour", false, 48.0)
		back.pressed.connect(_close_settings)
		side.add_child(back)
		# contenu de l'onglet, avec défilement
		var body := VBoxContainer.new()
		body.add_theme_constant_override("separation", 10)
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		root.add_child(body)
		body.add_child(_label(TAB_NAMES[parent_menu.settings_tab], 26, TEXT, false))
		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		body.add_child(scroll)
		var margin := MarginContainer.new()
		margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		margin.add_theme_constant_override("margin_right", 16)   # bande libre pour faire défiler au doigt
		scroll.add_child(margin)
		var list := VBoxContainer.new()
		list.add_theme_constant_override("separation", 10)
		margin.add_child(list)
		match parent_menu.settings_tab:
			0: _tab_game(list)
			1: _tab_image(list)
			2: _tab_sound(list)
			_: _tab_system(list)

	func _tab_game(list: VBoxContainer) -> void:
		_slider_card(list, "Sensibilité caméra", GameSettings.camera_sensitivity, 0.3, 3.0, 0.05,
			true, _set_sensitivity, _save_settings)
		_switch_card(list, "Vibration", "Retour tactile lors des chocs (mobile).",
			GameSettings.vibration_enabled, _set_vibration)

	func _tab_image(list: VBoxContainer) -> void:
		var box := _add_card(list)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 12)
		var name_lbl := _label("Qualité graphique", 20, TEXT, false)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(name_lbl)
		var opts: Array[String] = ["Éco", "Haute"]
		head.add_child(_segmented(opts, 1 if GameSettings.quality_high else 0, _set_quality))
		box.add_child(head)
		box.add_child(_hint("Haute : ombres, anticrénelage et pleine résolution. Éco : plus de FPS, recommandé sur téléphone."))
		var dist_box := _add_card(list)
		dist_box.add_child(_label("Distance d'affichage", 20, TEXT, false))
		var dist_opts: Array[String] = ["Courte", "Normale", "Longue"]
		dist_box.add_child(_segmented(dist_opts, GameSettings.view_distance, _set_view_distance))
		dist_box.add_child(_hint("Courte : plus de FPS. Longue : voit plus loin mais plus lourd, pour téléphones puissants."))
		var fps_box := _add_card(list)
		fps_box.add_child(_label("Limite de FPS", 20, TEXT, false))
		var fps_opts: Array[String] = ["30", "45", "60"]
		fps_box.add_child(_segmented(fps_opts, GameSettings.FPS_CHOICES.find(GameSettings.fps_limit), _set_fps_limit))
		fps_box.add_child(_hint("30 ou 45 économisent la batterie et chauffent moins. 60 est le plus fluide."))
		_switch_card(list, "Mode batterie automatique", _battery_text(), GameSettings.auto_battery, _set_auto_battery)
		_switch_card(list, "Réduire le rendu à grande vitesse", "En voiture au-dessus de 60 km/h, le rendu 3D passe à 70 % (retour à la normale sous 45 km/h).", GameSettings.speed_scale, _set_speed_scale)

	func _tab_sound(list: VBoxContainer) -> void:
		_slider_card(list, "Volume général", GameSettings.master_volume, 0.0, 1.0, 0.01,
			false, _set_volume, _save_settings)

	func _tab_system(list: VBoxContainer) -> void:
		_switch_card(list, "Compteur de performance", "Affiche les FPS, les draw calls et les triangles en haut de l'écran (touche F3 aussi).", GameSettings.show_perf, _set_show_perf)
		var upd_box := _add_card(list)
		upd_box.add_child(_label("Mises à jour", 20, TEXT, false))
		upd_box.add_child(_hint("Vérifie si une nouvelle version du jeu est disponible."))
		var upd := _button("Rechercher les mises à jour", false, 48.0)
		var upd_status := _label("", 15, Color(1.0, 0.85, 0.55), false)
		upd_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		upd_status.custom_minimum_size = Vector2(200, 0)
		upd.pressed.connect(_check_updates.bind(upd, upd_status))
		upd_box.add_child(upd)
		upd_box.add_child(upd_status)
		var reset_box := _add_card(list)
		reset_box.add_child(_label("Réglages par défaut", 20, TEXT, false))
		reset_box.add_child(_hint("Remet tous les réglages à leurs valeurs d'origine."))
		var reset_btn := _button("Réinitialiser", false, 48.0)
		reset_btn.pressed.connect(_reset_settings)
		reset_box.add_child(reset_btn)
		list.add_child(_label("Version " + str(ProjectSettings.get_setting("application/config/version", "1.0")), 14, TEXT_DIM, true))

	# ---------------------------------------------------- actions des réglages

	func _select_tab(index: int) -> void:
		parent_menu.settings_tab = index
		rebuild()

	func _set_sensitivity(v: float) -> void:
		GameSettings.camera_sensitivity = v

	func _set_volume(v: float) -> void:
		GameSettings.master_volume = v
		GameSettings.apply_audio()

	func _save_settings() -> void:
		GameSettings.save_settings()

	func _set_vibration(value: bool) -> void:
		GameSettings.vibration_enabled = value
		GameSettings.save_settings()

	func _on_switch_click(_value: bool) -> void:
		parent_menu._play_click()

	func _set_quality(index: int) -> void:
		GameSettings.quality_high = (index == 1)
		GameSettings.apply_shadows(get_tree())
		GameSettings.apply_viewport(get_viewport())   # MSAA + échelle de rendu 3D
		GameSettings.save_settings()
		rebuild()

	func _set_view_distance(index: int) -> void:
		GameSettings.view_distance = index
		GameSettings.apply_view_distance(get_tree())
		GameSettings.save_settings()
		rebuild()

	func _set_fps_limit(index: int) -> void:
		GameSettings.fps_limit = GameSettings.FPS_CHOICES[clampi(index, 0, 2)]
		GameSettings.apply_fps()
		GameSettings.save_settings()
		rebuild()

	func _battery_text() -> String:
		var pct: int = GameSettings.battery_percent()
		var info: String = "Batterie : indisponible sur cet appareil."
		if pct >= 0:
			info = "Batterie : %d %%." % pct
		if GameSettings.battery_saver_active:
			info += " Économie active : qualité éco, 30 FPS et distance courte appliqués temporairement."
		else:
			info += " Sous 20 %, applique temporairement qualité éco, 30 FPS et distance courte."
		return info

	func _set_auto_battery(value: bool) -> void:
		GameSettings.auto_battery = value
		GameSettings.save_settings()
		GameSettings.update_battery(get_tree(), get_viewport())
		rebuild()

	func _set_show_perf(value: bool) -> void:
		GameSettings.show_perf = value
		GameSettings.save_settings()

	func _set_speed_scale(value: bool) -> void:
		GameSettings.speed_scale = value
		GameSettings.save_settings()
		GameSettings.update_speed(0.0, get_viewport())

	func _reset_settings() -> void:
		GameSettings.reset_defaults()
		GameSettings.update_speed(0.0, get_viewport())
		GameSettings.apply_view_distance(get_tree())
		GameSettings.update_battery(get_tree(), get_viewport())
		GameSettings.apply_shadows(get_tree())
		GameSettings.apply_viewport(get_viewport())   # ombres / MSAA / échelle revenus aux défauts
		rebuild()

	func _close_settings() -> void:
		parent_menu.show_settings = false
		rebuild()

	## Vérification manuelle de mise à jour : appelle l'autoload UpdateChecker ;
	## si une version existe, sa popup d'installation s'ouvre.
	func _check_updates(btn: Button, status: Label) -> void:
		if not is_instance_valid(btn) or not is_instance_valid(status):
			return
		var uc := get_node_or_null("/root/UpdateChecker")
		if uc == null:
			status.text = "Indisponible sur cette version"
			return
		btn.disabled = true
		btn.text = "Vérification…"
		status.text = ""
		uc.check_manual(_on_update_result.bind(btn, status))

	func _on_update_result(msg: String, btn: Button, status: Label) -> void:
		if not is_instance_valid(btn) or not is_instance_valid(status):
			return
		btn.disabled = false
		btn.text = "Rechercher les mises à jour"
		status.text = msg

	# ---------------------------------------------------- fabriques de Controls

	func _flat(color: Color, radius: int, border_color: Color = Color(0, 0, 0, 0), border_w: int = 0) -> StyleBoxFlat:
		var sb := StyleBoxFlat.new()
		sb.bg_color = color
		sb.set_corner_radius_all(radius)
		if border_w > 0:
			sb.border_color = border_color
			sb.set_border_width_all(border_w)
		return sb

	func _panel_style() -> StyleBoxFlat:
		var sb := _flat(PANEL_BG, 20, Color(1, 1, 1, 0.10), 1)
		sb.content_margin_left = 24.0
		sb.content_margin_right = 24.0
		sb.content_margin_top = 20.0
		sb.content_margin_bottom = 18.0
		sb.shadow_color = Color(0, 0, 0, 0.55)
		sb.shadow_size = 24
		return sb

	## Carte arrondie qui regroupe un réglage ; renvoie son conteneur intérieur
	func _add_card(parent: Control) -> VBoxContainer:
		var pc := PanelContainer.new()
		var sb := _flat(CARD_BG, 14)
		sb.content_margin_left = 18.0
		sb.content_margin_right = 18.0
		sb.content_margin_top = 14.0
		sb.content_margin_bottom = 14.0
		pc.add_theme_stylebox_override("panel", sb)
		parent.add_child(pc)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		pc.add_child(box)
		return box

	func _slider_card(parent: Control, label_text: String, value: float, vmin: float, vmax: float,
			step: float, as_mult: bool, on_change: Callable, on_end: Callable) -> void:
		var box := _add_card(parent)
		var head := HBoxContainer.new()
		var name_lbl := _label(label_text, 20, TEXT, false)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(name_lbl)
		var val := _label(_format_value(value, as_mult), 20, GOLD, false)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		head.add_child(val)
		box.add_child(head)
		var slider := HSlider.new()
		slider.min_value = vmin
		slider.max_value = vmax
		slider.step = step
		slider.value = value
		slider.custom_minimum_size = Vector2(0, 36)
		var track := _flat(Color(1, 1, 1, 0.14), 4)
		track.content_margin_top = 3.0
		track.content_margin_bottom = 3.0
		var filled := _flat(GOLD, 4)
		filled.content_margin_top = 3.0
		filled.content_margin_bottom = 3.0
		slider.add_theme_stylebox_override("slider", track)
		slider.add_theme_stylebox_override("grabber_area", filled)
		slider.add_theme_stylebox_override("grabber_area_highlight", filled)
		var knob: Texture2D = PauseMenu._make_knob()
		slider.add_theme_icon_override("grabber", knob)
		slider.add_theme_icon_override("grabber_highlight", knob)
		slider.add_theme_icon_override("grabber_disabled", knob)
		box.add_child(slider)
		slider.value_changed.connect(_on_slider_changed.bind(val, as_mult, on_change))
		slider.drag_ended.connect(_on_slider_drag_ended.bind(on_end))

	func _on_slider_changed(v: float, val: Label, as_mult: bool, on_change: Callable) -> void:
		val.text = _format_value(v, as_mult)
		on_change.call(v)

	func _on_slider_drag_ended(_changed: bool, on_end: Callable) -> void:
		on_end.call()

	func _switch_card(parent: Control, title: String, hint_text: String, value: bool, handler: Callable) -> void:
		var box := _add_card(parent)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var name_lbl := _label(title, 20, TEXT, false)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(name_lbl)
		var sw := SwitchControl.new()
		sw.on = value
		sw.toggled.connect(_on_switch_click)
		sw.toggled.connect(handler)
		row.add_child(sw)
		box.add_child(row)
		box.add_child(_hint(hint_text))

	func _segmented(options: Array[String], selected: int, handler: Callable) -> HBoxContainer:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		for i in options.size():
			var b := _seg_button(options[i], i == selected)
			b.pressed.connect(handler.bind(i))
			row.add_child(b)
		return row

	func _seg_button(text_value: String, selected: bool) -> Button:
		var b := Button.new()
		b.text = text_value
		b.custom_minimum_size = Vector2(92, 44)
		b.add_theme_font_size_override("font_size", 19)
		var normal := _flat(GOLD if selected else Color(1, 1, 1, 0.07), 10)
		var hover := _flat(Color(1.0, 0.78, 0.32) if selected else Color(1, 1, 1, 0.13), 10)
		var pressed := _flat(Color(1.0, 0.62, 0.10) if selected else Color(1, 1, 1, 0.20), 10)
		b.add_theme_stylebox_override("normal", normal)
		b.add_theme_stylebox_override("hover", hover)
		b.add_theme_stylebox_override("pressed", pressed)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		var dark := Color(0.06, 0.07, 0.09)
		b.add_theme_color_override("font_color", dark if selected else TEXT)
		b.add_theme_color_override("font_hover_color", dark if selected else Color(1, 1, 1, 1))
		b.add_theme_color_override("font_pressed_color", dark)
		b.pressed.connect(parent_menu._play_click)   # retour sonore sur chaque appui
		return b

	func _tab_button(text_value: String, selected: bool) -> Button:
		var b := Button.new()
		b.text = text_value
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 48)
		b.add_theme_font_size_override("font_size", 20)
		var normal := _flat(Color(1.0, 0.72, 0.20, 0.18) if selected else Color(0, 0, 0, 0), 10)
		var hover := _flat(Color(1, 1, 1, 0.08), 10)
		var pressed := _flat(Color(1.0, 0.72, 0.20, 0.28), 10)
		normal.content_margin_left = 16.0
		hover.content_margin_left = 16.0
		pressed.content_margin_left = 16.0
		b.add_theme_stylebox_override("normal", normal)
		b.add_theme_stylebox_override("hover", hover)
		b.add_theme_stylebox_override("pressed", pressed)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.add_theme_color_override("font_color", GOLD if selected else TEXT_DIM)
		b.add_theme_color_override("font_hover_color", GOLD if selected else TEXT)
		b.add_theme_color_override("font_pressed_color", GOLD)
		b.pressed.connect(parent_menu._play_click)
		return b

	func _format_value(value: float, as_mult: bool) -> String:
		return ("×%.2f" % value) if as_mult else "%d %%" % int(round(value * 100.0))

	func _button(text_value: String, accent: bool, height: float = 52.0) -> Button:
		var b := Button.new()
		b.text = text_value
		b.custom_minimum_size = Vector2(0, height)
		b.add_theme_font_size_override("font_size", 21)
		var normal := _flat(GOLD if accent else BTN_BG, 12, Color(1, 1, 1, 0.10), 0 if accent else 1)
		var hover := _flat(Color(1.0, 0.78, 0.32) if accent else Color(0.15, 0.19, 0.26, 1.0), 12, Color(1, 1, 1, 0.14), 0 if accent else 1)
		var pressed := _flat(Color(1.0, 0.62, 0.10) if accent else Color(0.19, 0.24, 0.32, 1.0), 12)
		var dark := Color(0.06, 0.07, 0.09)
		b.add_theme_stylebox_override("normal", normal)
		b.add_theme_stylebox_override("hover", hover)
		b.add_theme_stylebox_override("pressed", pressed)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.add_theme_stylebox_override("disabled", normal)
		b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.55))
		b.add_theme_color_override("font_color", dark if accent else TEXT)
		b.add_theme_color_override("font_hover_color", dark if accent else Color(1, 1, 1, 1))
		b.add_theme_color_override("font_pressed_color", dark)
		b.pressed.connect(parent_menu._play_click)   # retour sonore sur chaque appui
		return b

	func _label(text_value: String, font_size: int, color: Color, centered: bool) -> Label:
		var l := Label.new()
		l.text = text_value
		l.add_theme_font_size_override("font_size", font_size)
		l.add_theme_color_override("font_color", color)
		if centered:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		return l

	func _hint(text_value: String) -> Label:
		var l := _label(text_value, 14, TEXT_DIM, false)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(200, 0)
		return l

	func _spacer(height: float) -> Control:
		var c := Control.new()
		c.custom_minimum_size = Vector2(0, height)
		return c
