extends Node
# Niger Streets - Vérification automatique de mise à jour (autoload).
# Au lancement (après CHECK_DELAY), interroge la dernière release GitHub et compare
# le numéro de build (bNN) avec la version installée (config/version, remplie par la CI).
# Si une version plus récente existe : popup dorée « Télécharger la mise à jour » qui
# ouvre le navigateur sur l'APK signé (Android propose ensuite l'installation).
# Silencieux en cas d'absence de réseau, d'erreur API ou de version d'éditeur (sans bNN).

const API_URL: String = "https://api.github.com/repos/kidasniger/NigerStreets/releases/latest"
const CHECK_DELAY: float = 4.0

## true tant qu'une popup de mise à jour est affichée (le splash ne doit pas démarrer le jeu)
var popup_open: bool = false

var _http: HTTPRequest = null
var _popup_layer: CanvasLayer = null

func _ready() -> void:
	get_tree().create_timer(CHECK_DELAY).timeout.connect(_check)

func _check() -> void:
	var local_build: int = _build_number(str(ProjectSettings.get_setting("application/config/version", "1.0")))
	if local_build <= 0:
		return   # version d'éditeur sans numéro de build : rien à vérifier
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	_http.request_completed.connect(_on_response)
	add_child(_http)
	var headers: PackedStringArray = PackedStringArray([
		"Accept: application/vnd.github+json",
		"User-Agent: NigerStreets-UpdateCheck",
	])
	if _http.request(API_URL, headers) != OK:
		_cleanup()

func _on_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var remote_build: int = 0
	var apk_url: String = ""
	var tag: String = ""
	var size_mb: int = 0
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var data: Variant = JSON.parse_string(body.get_string_from_utf8())
		if data is Dictionary:
			tag = str(data.get("tag_name", ""))
			remote_build = _build_number(tag)
			var assets: Variant = data.get("assets", [])
			if assets is Array:
				for a: Variant in assets:
					if a is Dictionary and str(a.get("name", "")).ends_with(".apk"):
						apk_url = str(a.get("browser_download_url", ""))
						size_mb = int(float(a.get("size", 0.0)) / 1048576.0)
						break
			if apk_url.is_empty():
				apk_url = str(data.get("html_url", ""))
	var local_build: int = _build_number(str(ProjectSettings.get_setting("application/config/version", "1.0")))
	if remote_build > local_build and not apk_url.is_empty():
		_show_popup(tag, apk_url, local_build, size_mb)
	_cleanup()

## Extrait le numéro de build d'une chaîne « 1.0-b12 » ou « v1.0-b12 » (0 si absent/invalide)
func _build_number(version: String) -> int:
	var idx := version.rfind("b")
	if idx < 0:
		return 0
	var suffix := version.substr(idx + 1)
	return int(suffix) if suffix.is_valid_int() else 0

func _cleanup() -> void:
	if _http != null:
		_http.queue_free()
		_http = null

# ------------------------------------------------------------------ popup

func _show_popup(tag: String, apk_url: String, local_build: int, size_mb: int) -> void:
	if popup_open:
		return
	popup_open = true
	_popup_layer = CanvasLayer.new()
	_popup_layer.layer = 20
	add_child(_popup_layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP   # bloque les appuis derrière la popup
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	_popup_layer.add_child(root)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.08, 0.12, 0.97)
	sb.border_color = Color(1.0, 0.72, 0.20)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 30.0
	sb.content_margin_right = 30.0
	sb.content_margin_top = 24.0
	sb.content_margin_bottom = 22.0
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.custom_minimum_size = Vector2(520, 0)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Nouvelle mise à jour disponible"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1.0, 0.72, 0.20))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	title.add_theme_constant_override("outline_size", 4)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var size_txt: String = "" if size_mb <= 0 else ", %d Mo" % size_mb
	var body := Label.new()
	body.text = "Version %s disponible (installée : b%d%s).\n\nTélécharger et installer maintenant ?" % [tag, local_build, size_txt]
	body.add_theme_font_size_override("font_size", 17)
	body.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(body)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(buttons)

	var dl := Button.new()
	dl.text = "Télécharger la mise à jour"
	dl.custom_minimum_size = Vector2(0, 52)
	dl.add_theme_font_size_override("font_size", 20)
	_style_button(dl, true)
	dl.pressed.connect(_install.bind(apk_url))
	buttons.add_child(dl)

	var later := Button.new()
	later.text = "Plus tard"
	later.custom_minimum_size = Vector2(0, 52)
	later.add_theme_font_size_override("font_size", 20)
	_style_button(later, false)
	later.pressed.connect(_close_popup)
	buttons.add_child(later)

## Ouvre le navigateur sur l'APK signé : Android télécharge puis propose l'installation
func _install(url: String) -> void:
	OS.shell_open(url)
	_close_popup()

func _close_popup() -> void:
	popup_open = false
	if _popup_layer != null:
		_popup_layer.queue_free()
		_popup_layer = null

func _style_button(b: Button, accent: bool) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(1.0, 0.72, 0.20) if accent else Color(0.10, 0.13, 0.18, 0.98)
	normal.set_corner_radius_all(8)
	if not accent:
		normal.border_color = Color(1, 1, 1, 0.22)
		normal.set_border_width_all(2)
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(1.0, 0.62, 0.10) if accent else Color(0.18, 0.22, 0.30, 0.98)
	pressed.set_corner_radius_all(8)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(1.0, 0.78, 0.32) if accent else Color(0.14, 0.18, 0.25, 0.98)
	hover.set_corner_radius_all(8)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color(0.06, 0.07, 0.09) if accent else Color(1, 1, 1, 0.95))
	b.add_theme_color_override("font_hover_color", Color(0.06, 0.07, 0.09) if accent else Color(1, 1, 0.9, 1))
	b.add_theme_color_override("font_pressed_color", Color(0.06, 0.07, 0.09))
